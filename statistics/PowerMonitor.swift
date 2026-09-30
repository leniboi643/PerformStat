import Foundation
import IOKit.ps

/// Battery + AC status via public IOKit power-source APIs (empty on desktops).
struct PowerSample {
    let hasBattery: Bool
    let percent: Int
    let isCharging: Bool
    let onAC: Bool
    let timeToEmpty: Int   // minutes, -1 unknown
}

enum PowerMonitor {
    static func sample() -> PowerSample? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any],
                  let type = desc["Type"] as? String, type == "IOPSBatteryType" else { continue }
            let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let ac = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let time = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            return PowerSample(hasBattery: true, percent: capacity, isCharging: charging, onAC: ac, timeToEmpty: time)
        }
        return nil
    }
}

/// Kernel thermal pressure state (public, efficient — no sensor polling).
enum ThermalState {
    static func label() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
