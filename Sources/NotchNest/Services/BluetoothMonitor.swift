import Foundation

/// Polls `system_profiler` for connected Bluetooth devices and their battery.
enum BluetoothMonitor {
    static func connectedDevices(completion: @escaping ([BTDevice]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let devices = run()
            DispatchQueue.main.async { completion(devices) }
        }
    }

    private static func run() -> [BTDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var result: [BTDevice] = []
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    result.append(BTDevice(
                        address: info["device_address"] as? String ?? name,
                        name: name,
                        batteryMain: percent(info["device_batteryLevelMain"]),
                        batteryLeft: percent(info["device_batteryLevelLeft"]),
                        batteryRight: percent(info["device_batteryLevelRight"]),
                        batteryCase: percent(info["device_batteryLevelCase"]),
                        minorType: info["device_minorType"] as? String
                    ))
                }
            }
        }
        return result
    }

    private static func percent(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }
}
