import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var name: String
}

/// Lists and switches the system's default audio output device via CoreAudio.
enum AudioOutput {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func devices() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutput(id), let name = name(of: id) else { return nil }
            return AudioDevice(id: id, name: name)
        }
    }

    static func currentDefault() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &dev) == noErr else { return nil }
        return dev
    }

    static func setDefault(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = id
        AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
    }

    // MARK: Volume / mute (default output device)

    static func volume() -> Float? {
        guard let dev = currentDefault() else { return nil }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float) {
        guard let dev = currentDefault() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var v = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    static func isMuted() -> Bool {
        guard let dev = currentDefault() else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let dev = currentDefault() else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var v: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }

    // MARK: Helpers

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr else { return nil }
        return name as String
    }
}
