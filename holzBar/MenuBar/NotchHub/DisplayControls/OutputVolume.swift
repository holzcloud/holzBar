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
        readString(device, selector: kAudioObjectPropertyName)
    }

    // MARK: Outputs

    /// Every sound device the system reports, as the output list wants it. A device whose UID
    /// cannot be read is skipped, and a failure to read the list gives an empty list. Names are
    /// kept in memory for the open tab only and are never logged.
    static func outputDevices() -> [AudioOutputDevice] {
        deviceIDs().compactMap { device in
            guard let uid = uid(of: device) else {
                return nil
            }
            return AudioOutputDevice(
                uid: uid,
                name: name(of: device) ?? uid,
                outputChannels: outputChannelCount(of: device),
                isHidden: readUInt32(device, selector: kAudioDevicePropertyIsHidden) == 1,
                transport: transport(of: device)
            )
        }
    }

    /// The device's UID, which stays the same when a device leaves and returns (the object
    /// identifier does not).
    static func uid(of device: AudioObjectID) -> String? {
        readString(device, selector: kAudioDevicePropertyDeviceUID)
    }

    /// Makes the device with this UID the default output, and only the default output: the output
    /// of system sounds stays as the user set it in System Settings. The system decides; the
    /// caller reads the default back. Answers whether the system accepted the call.
    @discardableResult
    static func setDefaultOutput(uid: String) -> Bool {
        guard
            let device = deviceIDs().first(where: { self.uid(of: $0) == uid && outputChannelCount(of: $0) > 0 })
        else {
            return false
        }
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var value = device
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &value
        ) == noErr
    }

    /// The identifiers of every audio device.
    private static func deviceIDs() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    /// The number of output channels of a device, 0 for a microphone or when it cannot be read.
    private static func outputChannelCount(of device: AudioObjectID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// How the device is connected.
    private static func transport(of device: AudioObjectID) -> AudioTransport {
        guard let value = readUInt32(device, selector: kAudioDevicePropertyTransportType) else {
            return .other
        }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        case kAudioDeviceTransportTypeVirtual: return .virtual
        default: return .other
        }
    }

    /// A string property of a device in the global scope, or `nil` when it cannot be read.
    private static func readString(_ device: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    /// A 32-bit integer property of a device in the global scope, or `nil` when it cannot be read.
    private static func readUInt32(_ device: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectHasProperty(device, &address) else {
            return nil
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
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
    /// It listens to the default output device, with `followsDeviceList` to the list of devices
    /// too (a device that appears or leaves), and on the current device to the volume property
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
        private var deviceListRegistration: Registration?
        private var deviceRegistrations = [Registration]()
        private var onChange: (@MainActor () -> Void)?
        private var onValueChange: (@MainActor () -> Void)?

        /// Whether the listeners are added.
        var isRunning: Bool {
            onChange != nil
        }

        /// Adds the listeners. Does nothing when they are already added. With `followsDeviceList`
        /// a device that appears or leaves is reported as well. With `onValueChange` a change of the
        /// level or the mute of the default output goes there instead of to `onChange`, so an owner
        /// that rebuilds more on a change of devices need not do so for every step of the level.
        func start(
            followsDeviceList: Bool = false,
            onValueChange: (@MainActor () -> Void)? = nil,
            onChange: @escaping @MainActor () -> Void
        ) {
            guard !isRunning else {
                return
            }
            self.onChange = onChange
            self.onValueChange = onValueChange
            let system = AudioObjectID(kAudioObjectSystemObject)
            let address = OutputVolume.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
            systemRegistration = register(system, address) { listener in
                listener.defaultDeviceChanged()
            }
            if followsDeviceList {
                let listAddress = OutputVolume.address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
                deviceListRegistration = register(system, listAddress) { listener in
                    listener.onChange?()
                }
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
            if let deviceListRegistration {
                unregister(deviceListRegistration)
            }
            deviceListRegistration = nil
            onChange = nil
            onValueChange = nil
        }

        private func defaultDeviceChanged() {
            removeDeviceListeners()
            addDeviceListeners()
            onChange?()
        }

        private func valueChanged() {
            (onValueChange ?? onChange)?()
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
