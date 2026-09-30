import Foundation
import Darwin

/// RAM and swap sampling from mach and sysctl interfaces.
enum MemoryMonitor {
    /// vm_statistics64 via host_statistics64 — one Mach call, no allocation.
    static func sample() -> (usedGB: Double, totalGB: Double, swapGB: Double)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutableBytes(of: &stats) { raw -> kern_return_t in
            host_statistics64(SystemMonitor.hostPort, HOST_VM_INFO64, raw.bindMemory(to: integer_t.self).baseAddress!, &count)
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let total = SystemMonitor.facts.totalMemory

        // pages actively counted toward usage; includes compressed pages
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
                    + UInt64(stats.speculative_count)) * pageSize
        let swapEncoded = stats.swapins + stats.swapouts
        var swapGB = 0.0
        // swap level from sysctl; vm_statistics64 fields are counters not levels
        var slen: Int = 0
        sysctlbyname("vm.swapusage", nil, &slen, nil, 0)
        var swapBuf = [CChar](repeating: 0, count: max(slen, 64))
        if slen > 0, sysctlbyname("vm.swapusage", &swapBuf, &slen, nil, 0) == 0 {
            let s = String(cString: swapBuf)  // format: "total = 0.00M  used = 0.00M  free = 0.00M (encrypted)"
            let comps = s.components(separatedBy: " ")
            if let ui = comps.firstIndex(of: "used"), ui + 2 < comps.count {
                let numStr = comps[ui + 2]
                let value = Double(numStr.dropLast()) ?? 0
                let unit = numStr.last ?? "M"
                swapGB = unit == "G" ? value : value / 1024.0
            }
        }
        _ = swapEncoded

        return (Double(used) / 1_073_741_824.0,
                Double(total) / 1_073_741_824.0,
                swapGB)
    }
}

/// One 128-byte sysctl read; rates derived by the caller from consecutive samples.
struct DiskSample {
    let bytesRead: UInt64
    let bytesWritten: UInt64
    let timestamp: Date
}

enum DiskMonitor {
    static func sample() -> DiskSample? {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["Statistics"] as? [String: Any] else {
                entry = IOIteratorNext(iter)
                continue
            }
            if let r = stats["Bytes (Read)"] as? UInt64 { totalRead += r }
            if let w = stats["Bytes (Write)"] as? UInt64 { totalWrite += w }
            entry = IOIteratorNext(iter)
        }
        return DiskSample(bytesRead: totalRead, bytesWritten: totalWrite, timestamp: Date())
    }
}
