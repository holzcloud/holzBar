//
//  BrightnessKeyController.swift
//  holzBar
//

import AppKit
import CoreGraphics
import Foundation
import Observation

/// Performs a taken brightness key on the display under the pointer (Phase 96, D-06, D-20, D-21,
/// D-22, DISP-03).
///
/// It owns no private interface. The built-in display is changed through
/// ``DisplayServicesBrightness`` and an external monitor through ``DDCBus``, both existing
/// Display controls wrappers that this plan left unchanged; each part has a ``PrivateFeatureGate``
/// of its own that follows the module's matching switch and the three-failures rule. Nothing here
/// loads a framework or looks a symbol up. While the Display controls module or the matching
/// switch is off nothing is loaded and the keys pass; an external monitor is never written while
/// External monitors (DDC) is off.
///
/// The key is already consumed when ``step(_:display:quarter:)`` runs, so a failed step shows
/// nothing and counts against its gate; the third failure in a row switches the part off for the
/// session, the snapshot of the tap is built again and the keys pass from then on.
///
/// An external monitor is asked once per session, after the user's own brightness key (that first
/// key passes to macOS): every external monitor is surveyed together so that two identical
/// monitors are told apart (and never written), and what each answered is kept in memory until a
/// wake or a display change, which forgets it. No transfer is sent in the wake wait (D-20). A
/// write is read first (the bus refuses otherwise), coalesced so one transfer is in flight and
/// the latest value wins, and read back one settle time after the last write. The controller lives
/// only while the media-key tap does, keeps nothing about a display but numbers and logs nothing.
@MainActor
@Observable
final class BrightnessKeyController {
    /// The writes of one monitor's brightness.
    private struct Channel {
        var coalescer = DDCWriteCoalescer()
        var writer: Task<Void, Never>?
        var settle: Task<Void, Never>?
    }

    /// Whether the built-in display's part may run: follows the Brightness switch, the result of
    /// loading the wrapper and the failures counted here.
    private(set) var builtInGate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// Whether the external monitors part may run: follows the External monitors switch, the
    /// result of loading the interface and the failures counted here.
    private(set) var externalGate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// Called when what the tap may take changed (a gate switched itself off, an answer arrived).
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private weak var appState: AppState?

    /// The bus, created on the first survey and dropped when the part goes off.
    @ObservationIgnored private var bus: DDCBus?
    /// What counts against the external gate.
    @ObservationIgnored private var policy = DDCFailurePolicy()
    /// Whether each external monitor answered a DDC brightness read in this session; a monitor
    /// that is not in it was not asked yet.
    @ObservationIgnored private var answers = [CGDirectDisplayID: Bool]()
    /// The brightness each answering monitor reported last.
    @ObservationIgnored private var values = [CGDirectDisplayID: DDCControlValue]()
    /// The level asked for while writes are pending, until the read-back after the last one.
    @ObservationIgnored private var requested = [CGDirectDisplayID: Double]()
    @ObservationIgnored private var channels = [CGDirectDisplayID: Channel]()
    @ObservationIgnored private var surveyTask: Task<Void, Never>?
    /// Counts the resets (a wake, a display change, the switch going off); work that started
    /// before one is dropped.
    @ObservationIgnored private var generation = 0
    /// Counts the surveys: the bus reads each monitor's capabilities afresh for a new number.
    @ObservationIgnored private var surveyCount = 0

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: Switches

    /// Whether the Display controls module is on.
    var isDisplayControlsOn: Bool {
        appState?.modules.isEnabled(DisplayControlsRuntime.identifier) ?? false
    }

    /// Whether Display controls' Brightness switch is on and the module with it.
    var isBuiltInSwitchOn: Bool {
        isDisplayControlsOn && appState?.settings.displayControls.showsBrightness == true
    }

    /// Whether Display controls' External monitors (DDC) switch is on and the module with it, on
    /// a Mac that can use the bus at all.
    var isExternalSwitchOn: Bool {
        isDisplayControlsOn && DDCBus.supportsThisMac
            && appState?.settings.displayControls.showsExternalMonitors == true
    }

    /// Whether an external monitor may be asked and written: the switch is on and the part did
    /// not switch itself off. Before the interface is loaded the gate still says "off", which is
    /// not a failure.
    var canUseExternal: Bool {
        guard isExternalSwitchOn else {
            return false
        }
        if case .unavailable(let reason) = externalGate.state {
            return reason == .switchedOff
        }
        return true
    }

    /// Follows the switches. The built-in wrapper is loaded the first time its switch is on while
    /// the keys replace the system's, never before and never with the switch off; switching the
    /// external part off drops everything it held.
    func refreshGates() {
        var gate = builtInGate
        if PrivateFeatureGate.shouldLoad(isEnabled: isBuiltInSwitchOn) {
            gate.setEnabled(true, load: DisplayServicesBrightness.load())
        } else {
            gate.setEnabled(false, load: .loaded)
        }
        if gate != builtInGate {
            builtInGate = gate
        }
        if !isExternalSwitchOn {
            if bus != nil || surveyTask != nil || !answers.isEmpty || !channels.isEmpty {
                resetExternal()
                bus = nil
                policy = DDCFailurePolicy()
            }
            var external = externalGate
            external.setEnabled(false, load: .loaded)
            if external != externalGate {
                externalGate = external
            }
        }
    }

    /// Whether every part the user's switches leave on has switched itself off: the framework or a
    /// function is missing, or three calls failed in a row. `false` while a part is simply off.
    var hasSwitchedItselfOff: Bool {
        func switchedOff(_ gate: PrivateFeatureGate) -> Bool {
            if case .unavailable(let reason) = gate.state {
                return reason != .switchedOff
            }
            return false
        }
        let parts = [
            isBuiltInSwitchOn ? switchedOff(builtInGate) : nil,
            isExternalSwitchOn ? switchedOff(externalGate) : nil,
        ].compactMap(\.self)
        return !parts.isEmpty && !parts.contains(false)
    }

    // MARK: Targets

    /// What a brightness key would change on a display, for the snapshot of the tap.
    func target(for display: CGDirectDisplayID) -> MediaKeyRule.Target {
        if isBuiltInSwitchOn, builtInGate.isAvailable, DisplayServicesBrightness.canChange(display) {
            return .builtIn(canChange: true)
        }
        if CGDisplayIsBuiltin(display) != 0 {
            return .builtIn(canChange: false)
        }
        return .external(answersBrightness: answers[display])
    }

    /// Whether a display is dimmed by software only: it has a dim level and is known not to
    /// answer DDC brightness, so its brightness keys belong to macOS (D-19, D-25).
    func isSoftwareDimmedOnly(_ display: CGDirectDisplayID) -> Bool {
        guard let dimmer = appState?.softwareDimmer else {
            return false
        }
        return dimmer.level(for: display) > 0 && answers[display] == false
    }

    // MARK: Steps

    /// Moves the brightness of a display by one step of a taken key and returns the level the
    /// display then reports (an external monitor: the level asked for while writes are pending),
    /// from 0 to 1, or `nil` when nothing changed (nothing is shown then).
    ///
    /// While the hub is open the Display controls runtime's own setters do it, so one writer talks
    /// to a display and the open tab follows; otherwise the controller's own path does.
    func step(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) async -> Double? {
        guard code == .brightnessUp || code == .brightnessDown else {
            return nil
        }
        if let level = stepThroughOpenHub(code, display: display, quarter: quarter) {
            return level
        }
        if let level = stepBuiltIn(code, display: display, quarter: quarter) {
            return level
        }
        return stepExternal(code, display: display, quarter: quarter)
    }

    /// Stops everything: nothing is kept.
    func shutDown() {
        onChange = nil
        resetExternal()
        bus = nil
    }

    /// The Display controls runtime is running with its tab open: its setters move the display.
    private func stepThroughOpenHub(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) -> Double? {
        guard
            let hub = appState?.notchHub,
            hub.isOpen,
            let runtime = hub.runtime(DisplayControlsRuntime.self)
        else {
            return nil
        }
        if let shown = runtime.displays.first(where: { $0.id == display && $0.canChange })?.value {
            runtime.setBrightness(MediaKeyRule.next(level: shown, code: code, quarter: quarter), for: display)
            return runtime.displays.first { $0.id == display }?.value
        }
        guard
            runtime.externals.contains(where: { $0.id == display && $0.state == .ready }),
            let shown = runtime.externalLevel(control: .brightness, display: display)
        else {
            return nil
        }
        runtime.setExternalLevel(MediaKeyRule.next(level: shown, code: code, quarter: quarter), control: .brightness, display: display)
        return runtime.externalLevel(control: .brightness, display: display)
    }

    /// The built-in display: read, write the step, read back; never below the 2 % floor.
    private func stepBuiltIn(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) -> Double? {
        guard isBuiltInSwitchOn, builtInGate.isAvailable, DisplayServicesBrightness.canChange(display) else {
            return nil
        }
        guard let current = DisplayServicesBrightness.read(display) else {
            recordBuiltInFailure()
            return nil
        }
        let next = MediaKeyRule.next(level: current, code: code, quarter: quarter)
        guard DisplayServicesBrightness.write(next, to: display), let readBack = DisplayServicesBrightness.read(display) else {
            recordBuiltInFailure()
            return nil
        }
        var gate = builtInGate
        gate.recordSuccess()
        if gate != builtInGate {
            builtInGate = gate
        }
        return readBack
    }

    /// Counts a failed call. The third in a row switches the part off for the session, and the
    /// tap's snapshot is built again so the keys pass.
    private func recordBuiltInFailure() {
        builtInGate.recordFailure()
        if !builtInGate.isAvailable {
            onChange?()
        }
    }

    // MARK: External monitors

    /// Whether the wake gate lets a transfer through: no wake or display change in the last
    /// ``DDCTiming/wakeWait`` (D-20). Without the app state nothing is sent.
    private var wakeGateIsOpen: Bool {
        appState?.systemActivityMonitor.ddcWakeGate.isOpen(at: .now) ?? false
    }

    /// An external monitor: only a monitor that answered, only with the switch on, never in the
    /// wake wait. The level is the one asked for, from the last value read (or the last one asked
    /// for while writes are pending), and the transfer follows from the coalescer.
    private func stepExternal(_ code: MediaKeyCode, display: CGDirectDisplayID, quarter: Bool) -> Double? {
        guard
            canUseExternal,
            externalGate.isAvailable,
            answers[display] == true,
            let bus,
            let value = values[display],
            wakeGateIsOpen
        else {
            return nil
        }
        guard let current = requested[display] ?? DDCLevel.level(raw: value.current, maximum: value.maximum) else {
            return nil
        }
        let floor = DDCLevel.floor(for: .brightness)
        let kept = max(DisplayControlsLevel.clamped(MediaKeyRule.next(level: current, code: code, quarter: quarter)), floor)
        requested[display] = kept
        let raw = DDCLevel.raw(fromLevel: kept, maximum: value.maximum, floor: floor)
        var channel = channels[display] ?? Channel()
        channel.settle?.cancel()
        channel.settle = nil
        let startsWriter = channel.coalescer.submit(raw)
        channels[display] = channel
        if startsWriter {
            let generation = generation
            channels[display]?.writer = Task { [weak self] in
                await self?.runWriter(display, on: bus, generation: generation)
            }
        }
        return kept
    }

    /// The writer of one monitor: writes the latest value until none is left (one transfer in
    /// flight), then waits for the monitor to settle and reads the brightness back once. A wake or
    /// display change in between drops the work: nothing is sent in the wake wait.
    private func runWriter(_ display: CGDirectDisplayID, on bus: DDCBus, generation: Int) async {
        while self.generation == generation, !Task.isCancelled {
            guard wakeGateIsOpen else {
                dropChannel(display)
                return
            }
            guard let raw = channels[display]?.coalescer.next() else {
                break
            }
            let succeeded = await bus.write(.brightness, raw: raw, to: display)
            guard self.generation == generation, !Task.isCancelled else {
                return
            }
            recordTransfer(display: display, succeeded: succeeded)
            guard externalGate.isAvailable else {
                return
            }
        }
        guard self.generation == generation, !Task.isCancelled else {
            return
        }
        channels[display]?.writer = nil
        channels[display]?.settle = Task { [weak self] in
            try? await Task.sleep(for: DDCTiming.settle)
            guard !Task.isCancelled, let self, self.generation == generation else {
                return
            }
            guard self.wakeGateIsOpen else {
                self.dropChannel(display)
                return
            }
            let value = await bus.readBack(.brightness, of: display)
            guard !Task.isCancelled, self.generation == generation else {
                return
            }
            self.channels[display]?.settle = nil
            self.recordTransfer(display: display, succeeded: value != nil)
            // The request is dropped whether or not the read-back worked: what counts is the
            // level the monitor confirmed.
            self.requested[display] = nil
            if let value, self.externalGate.isAvailable {
                self.values[display] = value
            }
        }
    }

    /// Forgets what one monitor was asked for and stops its work.
    private func dropChannel(_ display: CGDirectDisplayID) {
        channels[display]?.writer?.cancel()
        channels[display]?.settle?.cancel()
        channels[display] = nil
        requested[display] = nil
    }

    /// Records one write or read-back on the gate.
    private func recordTransfer(display: CGDirectDisplayID, succeeded: Bool) {
        record(policy.transferEnded(display: display, succeeded: succeeded))
    }

    /// Records an event on the external gate and, when it switched the part off, forgets the
    /// answers so the keys pass.
    private func record(_ event: DDCFailurePolicy.Event) {
        switch event {
        case .success: externalGate.recordSuccess()
        case .failure: externalGate.recordFailure()
        case .none: break
        }
        if !externalGate.isAvailable {
            resetExternal()
            onChange?()
        }
    }

    /// A wake or a display change: what each monitor answered is forgotten (the next first key
    /// asks again, after the wake wait), and work in flight is dropped.
    func displaysDidChange() {
        guard !answers.isEmpty || surveyTask != nil || !channels.isEmpty else {
            return
        }
        resetExternal()
        onChange?()
    }

    /// Stops every task of the external part and forgets what it knows of the monitors.
    private func resetExternal() {
        generation += 1
        surveyTask?.cancel()
        surveyTask = nil
        for key in Array(channels.keys) {
            dropChannel(key)
        }
        answers = [:]
        values = [:]
        requested = [:]
    }

    /// Asks every external monitor once, after the user's own first brightness key on one whose
    /// answer is not known: the key passed to macOS, this is the asking. Nothing happens in the
    /// wake wait, with the switch off, while a survey runs or for a monitor that was asked.
    func survey(_ display: CGDirectDisplayID) {
        guard
            canUseExternal,
            answers[display] == nil,
            surveyTask == nil,
            wakeGateIsOpen
        else {
            return
        }
        let candidates = externalCandidates()
        guard candidates.contains(where: { $0.id == display }) else {
            return
        }
        surveyCount += 1
        let opening = surveyCount
        let generation = generation
        let bus = bus ?? DDCBus()
        self.bus = bus
        surveyTask = Task { [weak self] in
            let load = await bus.load()
            guard !Task.isCancelled, let self, self.generation == generation else {
                return
            }
            self.externalGate.setEnabled(true, load: load)
            guard self.externalGate.isAvailable else {
                self.surveyTask = nil
                self.onChange?()
                return
            }
            let reports = await bus.survey(candidates, opening: opening)
            guard !Task.isCancelled, self.generation == generation else {
                return
            }
            self.surveyTask = nil
            self.apply(reports)
        }
    }

    /// The displays macOS cannot change itself, as the matcher wants them: every screen that is
    /// not built in, without those the brightness part changes through DisplayServices. Only
    /// numbers are read, never a display name.
    private func externalCandidates() -> [DDCDisplayMatch.Display] {
        var seen = Set<CGDirectDisplayID>()
        var candidates = [DDCDisplayMatch.Display]()
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard seen.insert(id).inserted, CGDisplayIsBuiltin(id) == 0 else {
                continue
            }
            if isBuiltInSwitchOn, builtInGate.isAvailable, DisplayServicesBrightness.canChange(id) {
                continue
            }
            candidates.append(DDCDisplayMatch.Display(
                id: id,
                vendor: CGDisplayVendorNumber(id),
                model: CGDisplayModelNumber(id),
                serial: CGDisplaySerialNumber(id),
                isBuiltIn: false
            ))
        }
        return candidates
    }

    /// Takes the reports of a survey: a monitor answers brightness only when its brightness read
    /// gave a value; every other outcome (no answer, never paired, indistinguishable, answered
    /// without brightness) is "no" and is never written. The survey counts on the gate on the same
    /// terms as in the Display controls tab (``DDCFailurePolicy``).
    private func apply(_ reports: [DDCDisplayReport]) {
        var tried = Set<UInt32>()
        var answered = Set<UInt32>()
        for report in reports {
            switch report.outcome {
            case .answered(let controls):
                tried.insert(report.id)
                answered.insert(report.id)
                if let brightness = controls.first(where: { $0.control == .brightness }) {
                    answers[report.id] = true
                    values[report.id] = brightness
                    // The monitor has its own brightness now: a stored dim level would outlive
                    // the dim row that could remove it, so it is cleared (CR-01).
                    appState?.softwareDimmer.releaseToHardware(report.id)
                } else {
                    answers[report.id] = false
                }
            case .noAnswer(let wasTried):
                if wasTried {
                    tried.insert(report.id)
                }
                answers[report.id] = false
            case .indistinguishable:
                answers[report.id] = false
            }
        }
        record(policy.surveyEnded(tried: tried, answered: answered))
        if externalGate.isAvailable {
            onChange?()
        }
    }
}
