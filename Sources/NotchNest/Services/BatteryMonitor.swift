import Foundation
import IOKit.ps

enum BatteryMonitor {
    static func current() -> BatteryInfo {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryInfo(level: 1, isCharging: false, isPluggedIn: true, hasBattery: false)
        }

        for source in sources {
            guard
                let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }

            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let plugged = (state == kIOPSACPowerValue)

            return BatteryInfo(
                level: max > 0 ? Double(cur) / Double(max) : 1,
                isCharging: charging,
                isPluggedIn: plugged,
                hasBattery: true
            )
        }

        return BatteryInfo(level: 1, isCharging: false, isPluggedIn: true, hasBattery: false)
    }
}
