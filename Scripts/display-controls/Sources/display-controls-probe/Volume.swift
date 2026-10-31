//
//  Volume.swift
//  display-controls
//
//  The default output device's volume and mute through public CoreAudio only:
//  `AudioObjectGetPropertyData` and `AudioObjectSetPropertyData`, never the deprecated
//  hardware-service functions. The output device is described by its transport type; its
//  name is read only with `--show-values`.
//

import AudioToolbox
import CoreAudio
import DisplayProbeCore
import Foundation

enum Volume {
    // MARK: Addresses

    static func address(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: element
        )
    }

    static let virtualMain = address(AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
    static let mainScalar = address(AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar))
    static let channelOne = address(AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar), element: 1)
    static let channelTwo = address(AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar), element: 2)
    static let mute = address(AudioObjectPropertySelector(kAudioDevicePropertyMute))

    // MARK: Device

    /// The default output device, or nil when there is none.
    static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != AudioObjectID(kAudioObjectUnknown) ? device : nil
    }

    /// How the device is connected, as a word.
    static func transport(of device: AudioObjectID) -> Verdict.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyTransportType),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return .other
        }
        switch value {
        case UInt32(kAudioDeviceTransportTypeBuiltIn): return .builtIn
        case UInt32(kAudioDeviceTransportTypeUSB): return .usb
        case UInt32(kAudioDeviceTransportTypeBluetooth), UInt32(kAudioDeviceTransportTypeBluetoothLE): return .bluetooth
        case UInt32(kAudioDeviceTransportTypeHDMI): return .hdmi
        case UInt32(kAudioDeviceTransportTypeDisplayPort): return .displayPort
        default: return .other
        }
    }

    /// The device's name. Read only with `--show-values`.
    static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioObjectPropertyName),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr, let name else {
            return nil
        }
        return name.takeRetainedValue() as String
    }

    // MARK: Properties

    static func isSettable(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        guard AudioObjectHasProperty(device, &address) else {
            return false
        }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static func has(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(device, &address)
    }

    private static func readLevel(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Double? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, value.isFinite else {
            return nil
        }
        return Double(value)
    }

    private static func writeLevel(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ level: Double) -> OSStatus {
        var address = address
        var value = Float32(min(1, max(0, level)))
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    // MARK: Plan

    /// How the volume of one device is reached: the word and the addresses to read and write.
    struct Plan: Sendable {
        var word: Verdict.VolumePlan
        var addresses: [AudioObjectPropertyAddress]
        var virtualMainState: String
        var settableChannels: Int
        var muteSettable: Bool

        /// The level, averaged over the addresses.
        func read(_ device: AudioObjectID) -> Double? {
            let levels = addresses.compactMap { Volume.readLevel(device, $0) }
            guard !levels.isEmpty else { return nil }
            return levels.reduce(0, +) / Double(levels.count)
        }

        /// Writes every address; the status is noErr or the first error.
        func write(_ device: AudioObjectID, _ level: Double) -> OSStatus {
            var result: OSStatus = noErr
            for address in addresses {
                let status = Volume.writeLevel(device, address, level)
                if status != noErr, result == noErr {
                    result = status
                }
            }
            return result
        }
    }

    static func plan(for device: AudioObjectID) -> Plan {
        let virtualSettable = isSettable(device, virtualMain)
        let mainSettable = isSettable(device, mainScalar)
        let channels = [channelOne, channelTwo].filter { isSettable(device, $0) }
        let word = Verdict.VolumePlan.choose(
            virtualMainSettable: virtualSettable,
            mainScalarSettable: mainSettable,
            settableChannels: channels.count
        )
        let addresses: [AudioObjectPropertyAddress]
        switch word {
        case .virtualMain: addresses = [virtualMain]
        case .mainScalar: addresses = [mainScalar]
        case .channels: addresses = channels
        case .none: addresses = []
        }
        return Plan(
            word: word,
            addresses: addresses,
            virtualMainState: virtualSettable ? "settable" : (has(device, virtualMain) ? "fixed" : "absent"),
            settableChannels: channels.count,
            muteSettable: isSettable(device, mute)
        )
    }

    // MARK: Change test

    /// How often the listener is polled while waiting for it, in seconds.
    private static let pollInterval = 0.01

    /// Counts the events a listener reports.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func bump() {
            lock.lock()
            count += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    struct ChangeOutcome: Sendable {
        var original: Double?
        var target: Double?
        var setStatus: OSStatus?
        var readBack: Double?
        var restored: Double?
        var listener: Verdict.ListenerState = .notRun
    }

    /// Moves the level by 0.05, reads it back after 300 ms, restores it and reads it again.
    /// A listener on the first address of the plan reports whether the change was announced
    /// within one second. The original is registered for a restore on interrupt.
    static func changeTest(_ device: AudioObjectID, plan: Plan) -> ChangeOutcome {
        var outcome = ChangeOutcome()
        guard plan.word != .none, var listenAddress = plan.addresses.first, let original = plan.read(device) else {
            return outcome
        }
        let target = Verdict.target(from: original)
        outcome.original = original
        outcome.target = target

        PrivateBrightness.Restore.shared.remember(action: "volume") { _ = plan.write(device, original) }
        defer { PrivateBrightness.Restore.shared.forget(action: "volume") }

        let counter = Counter()
        let queue = DispatchQueue(label: "display-controls-probe.volume")
        let block: AudioObjectPropertyListenerBlock = { _, _ in counter.bump() }
        let listening = AudioObjectAddPropertyListenerBlock(device, &listenAddress, queue, block) == noErr
        defer {
            if listening {
                AudioObjectRemovePropertyListenerBlock(device, &listenAddress, queue, block)
            }
        }

        let setAt = DispatchTime.now()
        outcome.setStatus = plan.write(device, target)
        Thread.sleep(forTimeInterval: 0.3)
        outcome.readBack = plan.read(device)
        if listening {
            while counter.value == 0, DispatchTime.now().uptimeNanoseconds - setAt.uptimeNanoseconds < 1_000_000_000 {
                Thread.sleep(forTimeInterval: pollInterval)
            }
            outcome.listener = counter.value > 0 ? .fired : .silent
        }
        _ = plan.write(device, original)
        Thread.sleep(forTimeInterval: 0.3)
        outcome.restored = plan.read(device)
        return outcome
    }
}
