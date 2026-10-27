//
//  MediaActivityMonitor.swift
//  holzBar
//

import CoreAudio
import Foundation

/// Reads whether some process runs the default sound output device.
nonisolated enum MediaOutputDevice {
    /// The default output device, or `nil` when there is none.
    static func defaultDevice() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != kAudioObjectUnknown
        else {
            return nil
        }
        return device
    }

    /// Whether any process runs the device now. It opens no audio and needs no permission.
    static func isRunning(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else {
            return false
        }
        return running != 0
    }

    /// Calls `handler` on the main queue each time the device starts or stops running for some
    /// process, until the returned token is passed to ``stopListening(_:)``.
    static func listen(to device: AudioObjectID, _ handler: @escaping @Sendable () -> Void) -> Listener {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        return Listener(device: device, block: block)
    }

    static func stopListening(_ listener: Listener) {
        var address = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(listener.device, &address, .main, listener.block)
    }

    /// A registered listener.
    struct Listener: @unchecked Sendable {
        fileprivate let device: AudioObjectID
        fileprivate let block: AudioObjectPropertyListenerBlock
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

/// Follows whether sound plays, for the media item that shows only while it does.
///
/// It is two property listeners of Core Audio, one on the default output device and one on
/// whether that device runs: nothing polls, no audio is opened and no permission is needed. It
/// exists only while a media item with that setting is in the menu bar. It cannot tell a
/// paused player from a closed one, and it cannot name what plays (no public API does, without
/// the private MediaRemote framework); ``MediaVisibility`` keeps the item for a while after the
/// sound stops for that reason.
@MainActor
final class MediaActivityMonitor {
    /// Called after the answer changed.
    var onChange: (() -> Void)?

    /// Whether some process runs the default output device now.
    private(set) var isActive = false

    /// When the answer last changed to or from active; `nil` until the sound played once while
    /// the monitor was running.
    private(set) var lastActive: Date?

    private var deviceListener: AudioOutputDevices.Listener?
    private var runningListener: MediaOutputDevice.Listener?

    var isRunning: Bool {
        deviceListener != nil
    }

    func start() {
        guard deviceListener == nil else {
            return
        }
        deviceListener = AudioOutputDevices.listen { [weak self] in
            // The listener runs on the main queue.
            MainActor.assumeIsolated {
                self?.attach()
            }
        }
        attach()
    }

    func stop() {
        if let deviceListener {
            AudioOutputDevices.stopListening(deviceListener)
        }
        deviceListener = nil
        detach()
        isActive = false
        lastActive = nil
    }

    /// Follows the current default output device.
    private func attach() {
        detach()
        if let device = MediaOutputDevice.defaultDevice() {
            runningListener = MediaOutputDevice.listen(to: device) { [weak self] in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
        }
        refresh()
    }

    private func detach() {
        if let runningListener {
            MediaOutputDevice.stopListening(runningListener)
        }
        runningListener = nil
    }

    private func refresh() {
        let running = MediaOutputDevice.defaultDevice().map(MediaOutputDevice.isRunning) ?? false
        guard running != isActive else {
            return
        }
        isActive = running
        lastActive = Date()
        onChange?()
    }
}
