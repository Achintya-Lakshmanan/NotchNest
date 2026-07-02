import Foundation
import IOKit
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
            let iopsTimeToFull = desc[kIOPSTimeToFullChargeKey] as? Int
            let timeToFull: Int? = {
                if let mins = iopsTimeToFull, mins >= 0 { return mins }
                if charging, let fallback = smartBatteryTimeRemaining() { return fallback }
                return nil
            }()

            return BatteryInfo(
                level: max > 0 ? Double(cur) / Double(max) : 1,
                isCharging: charging,
                isPluggedIn: plugged,
                hasBattery: true,
                timeToFullChargeMinutes: timeToFull
            )
        }

        return BatteryInfo(level: 1, isCharging: false, isPluggedIn: true, hasBattery: false)
    }

    /// Minutes-to-full from AppleSmartBattery when IOPS has no estimate.
    private static func smartBatteryTimeRemaining() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard
            let value = IORegistryEntryCreateCFProperty(
                service, "TimeRemaining" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue()
        else { return nil }

        let minutes: Int
        if let intVal = value as? Int {
            minutes = intVal
        } else if let numVal = value as? NSNumber {
            minutes = numVal.intValue
        } else {
            return nil
        }

        guard minutes > 0, minutes != 65535 else { return nil }
        return minutes
    }
}
