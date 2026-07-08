import Foundation
import IOBluetooth

/// Event-driven connect/disconnect detection via IOBluetooth (source of truth for toasts).
final class BluetoothEventMonitor: NSObject {
    typealias EventHandler = @MainActor (_ name: String, _ address: String, _ connected: Bool) -> Void

    @MainActor private(set) var connectedAddresses: Set<String> = []

    @MainActor private var onEvent: EventHandler?
    /// Last delivered event kind per address (true = connected).
    @MainActor private var lastEventKind: [String: Bool] = [:]
    /// Pending disconnect toasts — cancelled if a reconnect flap occurs within the window.
    @MainActor private var pendingDisconnect: [String: DispatchWorkItem] = [:]

    private let flapWindow: TimeInterval = 0.6

    @MainActor
    func start(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent

        IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:moreComing:))
        )

        seedInitialState()
    }

    /// Seed connected devices at launch without firing toasts.
    @MainActor
    private func seedInitialState() {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in paired where device.isConnected() {
            guard let address = device.addressString, !address.isEmpty else { continue }
            connectedAddresses.insert(address)
            lastEventKind[address] = true
            registerDisconnect(for: device)
        }
    }

    // MARK: - IOBluetooth callbacks (may arrive on CoreBluetooth's background queue)

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice,
        moreComing: Bool
    ) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let name = Self.displayName(for: device)
        registerDisconnect(for: device)

        Task { @MainActor [weak self] in
            self?.handleConnect(name: name, address: address)
        }
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let name = Self.displayName(for: device)

        Task { @MainActor [weak self] in
            self?.handleDisconnect(name: name, address: address)
        }
    }

    @MainActor
    private func handleConnect(name: String, address: String) {
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

    @MainActor
    private func handleDisconnect(name: String, address: String) {
        // Ignore duplicate disconnect notifications.
        if lastEventKind[address] == false { return }

        lastEventKind[address] = false
        connectedAddresses.remove(address)

        // Delay disconnect toast so rapid disconnect→connect flaps show nothing.
        pendingDisconnect[address]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingDisconnect.removeValue(forKey: address)
                guard self.lastEventKind[address] == false else { return }
                self.onEvent?(name, address, false)
            }
        }
        pendingDisconnect[address] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flapWindow, execute: work)
    }

    // MARK: - Helpers

    private func registerDisconnect(for device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
    }

    private static func displayName(for device: IOBluetoothDevice) -> String {
        if let name = device.name, !name.isEmpty { return name }
        if let name = device.nameOrAddress as String?, !name.isEmpty { return name }
        return device.addressString ?? "Bluetooth Device"
    }
}
