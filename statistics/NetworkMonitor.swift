import Foundation
import Darwin

/// Cumulative network byte counters from sysctl NET_RT_IFLIST2 (excludes loopback).
struct NetSample {
    let bytesIn: UInt64
    let bytesOut: UInt64
    let timestamp: Date
}

enum NetworkMonitor {
    static func sample() -> NetSample? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr2>.size <= len {
                let msg = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if msg.ifm_data.ifi_type != 0 && Int(msg.ifm_data.ifi_type) != 0x18 /* loopback */ {
                    totalIn &+= msg.ifm_data.ifi_ibytes
                    totalOut &+= msg.ifm_data.ifi_obytes
                }
                offset += Int(msg.ifm_msglen)
                if msg.ifm_msglen == 0 { break }
            }
        }
        return NetSample(bytesIn: totalIn, bytesOut: totalOut, timestamp: Date())
    }
}

/// GPU utilization from the IOAccelerator registry entry ("Device Utilization %"),
/// refreshed at most every ~500 ms since the registry updates lazily.
enum GPUMonitor {
    private static var cachedEntry: io_registry_entry_t = 0
    private static var cachedValue: Double?
    private static var lastFetch = Date.distantPast

    static func utilization() -> Double? {
        let now = Date()
        if now.timeIntervalSince(lastFetch) < 0.4 { return cachedValue }
        lastFetch = now

        var entry = cachedEntry
        if entry == 0 {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return cachedValue }
            entry = IOIteratorNext(iter)
            IOObjectRelease(iter)
            guard entry != 0 else { return cachedValue }
            cachedEntry = entry
        }

        guard let perf = IORegistryEntrySearchCFProperty(entry, kIOServicePlane, "PerformanceStatistics" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)) as? [String: Any] else {
            return cachedValue
        }
        if let util = perf["Device Utilization %"] as? UInt32 {
            cachedValue = Double(util)
        } else if let util = perf["Device Utilization %"] as? Int {
            cachedValue = Double(util)
        } else if let util = perf["Device Utilization %"] as? Double {
            cachedValue = util
        }
        return cachedValue
    }
}
