//
//  OutputVolume.swift
//  holzBar
//

import AudioToolbox
import CoreAudio
import Foundation

/// The Mac's sound output, read and set through public CoreAudio.
///
/// This is the only file of the Display controls module that calls CoreAudio. It never uses the
/// deprecated hardware-service functions of AudioToolbox: the virtual main volume is an
/// ordinary property read and written with `AudioObjectGetPropertyData` and
/// `AudioObjectSetPropertyData`. Which property serves an output is decided by the tested
/// ``OutputVolumePlan`` from what the system says the output has and accepts, so nothing is
/// written to a property the system did not offer. Every call checks its status and answers
/// `nil` or `false` on a failure; nothing traps and nothing is logged with a name.
nonisolated enum OutputVolume {
    /// The default output device with what the system says it can do and the plan that follows.
    nonisolated struct Output: Equatable, Sendable {
        let device: AudioObjectID
        let capabilities: OutputVolumePlan.Capabilities
        let plan: OutputVolumePlan
    }

    /// The channels (elements 1 and above) whose volume is looked at. Stereo outputs have two;
    /// the rest cover multichannel interfaces.
    private static let channelElements: [UInt32] = Array(1...8)

    // MARK: Device

    /// The default output device, or `nil` when there is none.
    static func defaultOutputDevice() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else {
            return nil
        }
        return device
    }

    /// The default output device with its capabilities, resolved into a plan before any value is
    /// read or written.
    static func current() -> Output? {
        guard let device = defaultOutputDevice() else {
            return nil
        }
        let capabilities = capabilities(of: device)
        return Output(device: device, capabilities: capabilities, plan: OutputVolumePlan.resolve(capabilities))
    }

    /// What an output has and accepts: the virtual main volume, the main channel's scalar
    /// volume, the scalar volume of each channel and the mute, each only when the property
    /// exists and the system says it can be set.
    static func capabilities(of device: AudioObjectID) -> OutputVolumePlan.Capabilities {
        OutputVolumePlan.Capabilities(
            virtualMainSettable: isSettable(device, selector: virtualMainVolume, element: mainElement),
            mainScalarSettable: isSettable(device, selector: kAudioDevicePropertyVolumeScalar, element: mainElement),
            settableChannels: channelElements.filter {
                isSettable(device, selector: kAudioDevicePropertyVolumeScalar, element: $0)
            },
            muteSettable: isSettable(device, selector: kAudioDevicePropertyMute, element: mainElement)
        )
    }

    // MARK: Volume

    /// The output's level from 0 to 1, or `nil` when it cannot be read. For channels it is the
    /// average of the channels that can be read.
    static func volume(of device: AudioObjectID, plan: OutputVolumePlan) -> Double? {
        switch plan {
        case .virtualMain:
            return readFloat(device, selector: virtualMainVolume, element: mainElement)
        case .mainScalar:
            return readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: mainElement)
        case let .channels(elements):
            let values = elements.compactMap {
                readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: $0)
            }
            return OutputVolumePlan.combined(values)
        case .unsupported:
            return nil
        }
    }

    /// Sets the output's level. The value is kept between 0 and 1 first. Answers whether every
    /// write was accepted.
    @discardableResult
    static func setVolume(_ value: Double, of device: AudioObjectID, plan: OutputVolumePlan) -> Bool {
        let level = DisplayControlsLevel.clamped(value)
        switch plan {
        case .virtualMain:
            return writeFloat(level, device, selector: virtualMainVolume, element: mainElement)
        case .mainScalar:
            return writeFloat(level, device, selector: kAudioDevicePropertyVolumeScalar, element: mainElement)
        case let .channels(elements):
            var accepted = true
            for element in elements where !writeFloat(level, device, selector: kAudioDevicePropertyVolumeScalar, element: element) {
                accepted = false
            }
            return accepted
        case .unsupported:
            return false
        }
    }

    // MARK: Mute and name

    /// Whether the output is muted, or `nil` when it has no mute or it cannot be read.
    static func isMuted(_ device: AudioObjectID) -> Bool? {
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else {
            return nil
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value != 0
    }

    /// Mutes or unmutes the output where the mute can be set. Answers whether the write was
    /// accepted.
    @discardableResult
    static func setMuted(_ muted: Bool, _ device: AudioObjectID) -> Bool {
        guard isSettable(device, selector: kAudioDevicePropertyMute, element: mainElement) else {
            return false
        }
        var address = address(kAudioDevicePropertyMute)
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// The device's name, such as "MacBook Pro Speakers". It is personal when it is a person's
    /// headphones: it is read for the open tab only, kept in memory and never logged.
    static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }

    // MARK: Properties

    /// The main element of a property (element 0).
    fileprivate static let mainElement = UInt32(kAudioObjectPropertyElementMain)

    /// The virtual main volume: the one constant of AudioToolbox's hardware-service header that
    /// is used. Its functions are deprecated; the property is not.
    fileprivate static let virtualMainVolume = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)

    /// The address of a property of an output.
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeOutput),
        element: UInt32 = UInt32(kAudioObjectPropertyElementMain)
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// Whether the property exists and the system says it can be set.
    private static func isSettable(_ device: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = address(selector, element: element)
        guard AudioObjectHasProperty(device, &address) else {
            return false
        }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func readFloat(_ device: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32) -> Double? {
        var address = address(selector, element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite else {
            return nil
        }
        return DisplayControlsLevel.clamped(Double(value))
    }

    private static func writeFloat(_ value: Double, _ device: AudioObjectID, selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = address(selector, element: element)
        var level = Float32(value)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level) == noErr
    }
}

extension OutputVolume {
    /// Tells the module that something about the default output changed, while the hub is open.
    ///
    /// It listens to the default output device, and on the current device to the volume property
    /// the plan chose (each channel for a channel plan) and to the mute. When the default device
    /// changes, the device's listeners are replaced by those of the new device. Every block runs
    /// on the main queue. ``stop()`` removes every block it added with the same object, address
    /// and queue; nothing outlives it, and nothing is polled.
    @MainActor
    final class Listener {
        /// One block added to CoreAudio, with what removes it again.
        private struct Registration {
            let object: AudioObjectID
            let address: AudioObjectPropertyAddress
            let block: AudioObjectPropertyListenerBlock
        }

        private var systemRegistration: Registration?
        private var deviceRegistrations = [Registration]()
        private var onChange: (@MainActor () -> Void)?

        /// Whether the listeners are added.
        var isRunning: Bool {
            onChange != nil
        }

        /// Adds the listeners. Does nothing when they are already added.
        func start(onChange: @escaping @MainActor () -> Void) {
            guard !isRunning else {
                return
            }
            self.onChange = onChange
            let system = AudioObjectID(kAudioObjectSystemObject)
            let address = OutputVolume.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            systemRegistration = register(system, address) { listener in
                listener.defaultDeviceChanged()
            }
            addDeviceListeners()
        }

        /// Removes every listener. Does nothing when none is added.
        func stop() {
            removeDeviceListeners()
            if let systemRegistration {
                unregister(systemRegistration)
            }
            systemRegistration = nil
            onChange = nil
        }

        private func defaultDeviceChanged() {
            removeDeviceListeners()
            addDeviceListeners()
            onChange?()
        }

        private func valueChanged() {
            onChange?()
        }

        private func addDeviceListeners() {
            guard let output = OutputVolume.current() else {
                return
            }
            var addresses = [AudioObjectPropertyAddress]()
            switch output.plan {
            case .virtualMain:
                addresses.append(OutputVolume.address(OutputVolume.virtualMainVolume))
            case .mainScalar:
                addresses.append(OutputVolume.address(kAudioDevicePropertyVolumeScalar))
            case let .channels(elements):
                addresses += elements.map { OutputVolume.address(kAudioDevicePropertyVolumeScalar, element: $0) }
            case .unsupported:
                break
            }
            if output.capabilities.muteSettable {
                addresses.append(OutputVolume.address(kAudioDevicePropertyMute))
            }
            for address in addresses {
                if let registration = register(output.device, address, { $0.valueChanged() }) {
                    deviceRegistrations.append(registration)
                }
            }
        }

        private func removeDeviceListeners() {
            for registration in deviceRegistrations {
                unregister(registration)
            }
            deviceRegistrations.removeAll()
        }

        /// Adds one block on the main queue. A block that CoreAudio refused is not kept.
        private func register(
            _ object: AudioObjectID,
            _ address: AudioObjectPropertyAddress,
            _ action: @escaping @MainActor (Listener) -> Void
        ) -> Registration? {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    if let self {
                        action(self)
                    }
                }
            }
            var address = address
            guard AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else {
                return nil
            }
            return Registration(object: object, address: address, block: block)
        }

        private func unregister(_ registration: Registration) {
            var address = registration.address
            AudioObjectRemovePropertyListenerBlock(registration.object, &address, DispatchQueue.main, registration.block)
        }
    }
}
