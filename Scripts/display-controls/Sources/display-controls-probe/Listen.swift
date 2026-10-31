//
//  Listen.swift
//  display-controls
//
//  Reports changes of the default output device, its volume and its mute for a number of
//  seconds, one LISTEN line per event. Nothing is polled: CoreAudio announces the changes.
//  When the default device changes, the volume and mute listeners move to the new device.
//

import CoreAudio
import DisplayProbeCore
import Foundation

/// All state is touched on `queue` only, which is also the queue CoreAudio calls back on.
private final class OutputListener: @unchecked Sendable {
    private struct Registration {
        var object: AudioObjectID
        var address: AudioObjectPropertyAddress
        var block: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "display-controls-probe.listen")
    private var count = 0
    private var deviceRegistration: Registration?
    private var propertyRegistrations: [Registration] = []

    var events: Int { queue.sync { count } }

    func start() {
        queue.sync {
            var address = AudioObjectPropertyAddress(
                mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
                mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
                mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
            )
            let system = AudioObjectID(kAudioObjectSystemObject)
            let block: AudioObjectPropertyListenerBlock = { [self] _, _ in
                event("device")
                bindToDefaultDevice()
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, queue, block) == noErr {
                deviceRegistration = Registration(object: system, address: address, block: block)
            }
            bindToDefaultDevice()
        }
    }

    func stop() {
        queue.sync {
            removeProperties()
            if var registration = deviceRegistration {
                AudioObjectRemovePropertyListenerBlock(registration.object, &registration.address, queue, registration.block)
            }
            deviceRegistration = nil
        }
    }

    private func event(_ what: String) {
        count += 1
        Out.emit(ProbeLine.line("LISTEN", [("n", String(count)), ("what", what)]))
    }

    private func removeProperties() {
        for var registration in propertyRegistrations {
            AudioObjectRemovePropertyListenerBlock(registration.object, &registration.address, queue, registration.block)
        }
        propertyRegistrations.removeAll()
    }

    /// Listens to the volume (the properties the plan chose) and the mute of the current
    /// default output device.
    private func bindToDefaultDevice() {
        removeProperties()
        guard let device = Volume.defaultOutputDevice() else {
            return
        }
        let plan = Volume.plan(for: device)
        var targets = plan.addresses.map { (what: "volume", address: $0) }
        if Volume.has(device, Volume.mute) {
            targets.append((what: "mute", address: Volume.mute))
        }
        for target in targets {
            var address = target.address
            let what = target.what
            let block: AudioObjectPropertyListenerBlock = { [self] _, _ in event(what) }
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                propertyRegistrations.append(Registration(object: device, address: address, block: block))
            }
        }
    }
}

enum Listen {
    /// Listens for `seconds` and says whether any event arrived.
    static func run(seconds: Int) -> Verdict.ListenerState {
        Out.emit("STEP press the volume keys, mute and unmute, and change the output device; listening for \(seconds) seconds")
        let listener = OutputListener()
        listener.start()
        Thread.sleep(forTimeInterval: Double(seconds))
        listener.stop()
        return listener.events > 0 ? .fired : .silent
    }
}
