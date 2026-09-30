import Foundation
import Darwin

/// Static host facts, computed once at startup.
struct HostFacts {
    let chipModel: String
    let cpuCoreCount: Int
    let totalMemory: UInt64
    let osVersion: String
    let bootTime: Date
}

enum SystemMonitor {
    /// Cached host port. mach_host_self() leaks a send right per call;
    /// take one reference for the process lifetime instead.
    static let hostPort: host_t = mach_host_self()

    static let facts: HostFacts = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = String(cString: buf)

        var cores: Int32 = 0
        var clen = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.physicalcpu", &cores, &clen, nil, 0)
        let pCores = Int(cores)
        sysctlbyname("hw.perflevel1.physicalcpu", &cores, &clen, nil, 0)
        let eCores = Int(cores)
        let totalCores = pCores + eCores

        var memsize: UInt64 = 0
        var mlen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memsize, &mlen, nil, 0)

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "macOS \(os.majorVersion).\(os.minorVersion)"

        var tv = timeval()
        var tlen = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        sysctl(&mib, 2, &tv, &tlen, nil, 0)

        return HostFacts(
            chipModel: brand.isEmpty ? "apple silicon" : brand,
            cpuCoreCount: totalCores > 0 ? totalCores : ProcessInfo.processInfo.activeProcessorCount,
            totalMemory: memsize,
            osVersion: osVersion,
            bootTime: Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        )
    }()

    static var uptime: TimeInterval { Date().timeIntervalSince(facts.bootTime) }

    /// Process-wide snapshots for the CPU load calculation.
    private struct CPUContext {
        var count: Int32 = 0
        var ticks: [Int32] = []
    }
    private static var cpuContext = CPUContext()

    /// Returns mean CPU load across all logical cores, 0.0...1.0.
    /// One Mach call per invocation; allocations kept to two arrays.
    static func cpuLoad() -> Double? {
        var numCPU: natural_t = 0
        var info: processor_info_array_t? = nil
        var msgCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &msgCount)
        guard kr == KERN_SUCCESS, let info = info else { return nil }
        defer {
            let size = Int(msgCount) * MemoryLayout<integer_t>.stride
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(size))
        }

        let n = Int(numCPU)
        let prev = cpuContext.ticks
        var totalDelta: Int64 = 0
        var busyDelta: Int64 = 0
        let stride = Int(CPU_STATE_MAX)

        for i in 0..<n {
            let base = i * stride
            if base + 2 < prev.count {
                let user = Int64(info[base + Int(CPU_STATE_USER)]) - Int64(prev[base + Int(CPU_STATE_USER)])
                let sys = Int64(info[base + Int(CPU_STATE_SYSTEM)]) - Int64(prev[base + Int(CPU_STATE_SYSTEM)])
                let nice = Int64(info[base + Int(CPU_STATE_NICE)]) - Int64(prev[base + Int(CPU_STATE_NICE)])
                let idle = Int64(info[base + Int(CPU_STATE_IDLE)]) - Int64(prev[base + Int(CPU_STATE_IDLE)])
                let total = user + sys + nice + idle
                if total > 0 {
                    busyDelta += user + sys + nice
                    totalDelta += total
                }
            }
        }

        // stash raw ticks for next delta
        var raw = [Int32](repeating: 0, count: n * stride)
        for i in 0..<n {
            let base = i * stride
            for s in 0..<Int(CPU_STATE_MAX) {
                raw[base + s] = info[base + s]
            }
        }
        cpuContext.count = Int32(numCPU)
        cpuContext.ticks = raw

        guard totalDelta > 0 else { return nil }   // first call primes the baseline
        return Double(busyDelta) / Double(totalDelta)
    }
}

extension String {
    /// Formats a byte count as a human-readable rate or size string.
    static func bytes(_ value: Double) -> String {
        if value >= 1_048_576_000 { return String(format: "%.1f gb", value / 1_073_741_824) }
        if value >= 1_048_576 { return String(format: "%.1f mb", value / 1_048_576) }
        if value >= 1_000 { return String(format: "%.1f kb", value / 1_024) }
        return String(format: "%.0f b", value)
    }
}
