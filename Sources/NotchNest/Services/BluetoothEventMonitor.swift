import Foundation
import IOBluetooth

/// Event-driven connect/disconnect detection via IOBluetooth (source of truth for toasts).
@MainActor
final class BluetoothEventMonitor: NSObject {
    typealias EventHandler = (_ name: String, _ address: String, _ connected: Bool) -> Void

    private(set) var connectedAddresses: Set<String> = []

    private var onEvent: EventHandler?
    /// Last delivered event kind per address (true = connected).
    private var lastEventKind: [String: Bool] = [:]
    /// Pending disconnect toasts — cancelled if a reconnect flap occurs within the window.
    private var pendingDisconnect: [String: DispatchWorkItem] = [:]

    private let flapWindow: TimeInterval = 0.6

    func start(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent

        IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:moreComing:))
        )

        seedInitialState()
    }

    /// Seed connected devices at launch without firing toasts.
    private func seedInitialState() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in paired where device.isConnected() {
            guard let address = device.addressString, !address.isEmpty else { continue }
            connectedAddresses.insert(address)
            lastEventKind[address] = true
            registerDisconnect(for: device)
        }
    }

    // MARK: - IOBluetooth callbacks

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice,
        moreComing: Bool
    ) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let name = deviceDisplayName(device)

        registerDisconnect(for: device)

        // Flap: reconnect shortly after disconnect — suppress both toasts.
        if let pending = pendingDisconnect.removeValue(forKey: address) {
            pending.cancel()
            lastEventKind[address] = true
            connectedAddresses.insert(address)
            return
        }

        // Ignore duplicate connect notifications for the same address.
        if lastEventKind[address] == true { return }

        lastEventKind[address] = true
        connectedAddresses.insert(address)
        onEvent?(name, address, true)
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let name = deviceDisplayName(device)

        // Ignore duplicate disconnect notifications.
        if lastEventKind[address] == false { return }

        lastEventKind[address] = false
        connectedAddresses.remove(address)

        // Delay disconnect toast so rapid disconnect→connect flaps show nothing.
        pendingDisconnect[address]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingDisconnect.removeValue(forKey: address)
            guard self.lastEventKind[address] == false else { return }
            self.onEvent?(name, address, false)
        }
        pendingDisconnect[address] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flapWindow, execute: work)
    }

    // MARK: - Helpers

    private func registerDisconnect(for device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    private func deviceDisplayName(_ device: IOBluetoothDevice) -> String {
        if let name = device.name, !name.isEmpty { return name }
        if let name = device.nameOrAddress as String?, !name.isEmpty { return name }
        return device.addressString ?? "Bluetooth Device"
    }
}
