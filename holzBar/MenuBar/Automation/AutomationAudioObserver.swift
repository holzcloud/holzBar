//
//  AutomationAudioObserver.swift
//  holzBar
//

import CoreAudio
import Foundation

/// The sound output devices of the Mac, by name.
nonisolated enum AudioOutputDevices {
    /// The name of the default output device, or `nil` when there is none.
    static func defaultOutputName() -> String? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != kAudioObjectUnknown
        else {
            return nil
        }
        return name(of: device)
    }

    /// The names of the devices that can play sound, without duplicates.
    static func outputNames() -> [String] {
        var address = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        var names = [String]()
        for device in devices where hasOutput(device) {
            if let name = name(of: device), !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeOutput)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    /// Calls `handler` on the main queue each time the default output device changes, until
    /// the returned token is passed to ``stopListening(_:)``.
    static func listen(_ handler: @escaping @Sendable () -> Void) -> Listener {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        return Listener(block: block)
    }

    static func stopListening(_ listener: Listener) {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener.block)
    }

    /// A registered listener.
    struct Listener: @unchecked Sendable {
        fileprivate let block: AudioObjectPropertyListenerBlock
    }
}

/// Follows the default sound output device, for the automation condition "the Mac plays sound
/// through …". It is one property listener of Core Audio: nothing polls, no audio is opened and
/// no permission is needed. It exists only while an enabled rule has the condition.
@MainActor
final class AutomationAudioObserver {
    /// Called after each change of the default output device.
    var onChange: (() -> Void)?

    private var listener: AudioOutputDevices.Listener?

    func start() {
        guard listener == nil else {
            return
        }
        listener = AudioOutputDevices.listen { [weak self] in
            // The listener runs on the main queue.
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    func stop() {
        if let listener {
            AudioOutputDevices.stopListening(listener)
        }
        listener = nil
    }
}
