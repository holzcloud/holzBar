//
//  DisplayControlsRuntime.swift
//  holzBar
//

import AppKit
import CoreAudio
import Foundation
import Observation
import SwiftUI

/// The running part of the Display controls module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It reads the volume
/// of the default sound output when the hub opens and when its tab appears, and sets it; the
/// level it shows is always the one read back from the system, never the one requested. While
/// the hub is open, CoreAudio listeners tell it of a change made elsewhere (a volume key, the
/// menu bar, another device becoming the default); they are removed the moment the hub closes.
/// Nothing is polled. The output's name is read for the open tab only; it is kept in memory and
/// never logged, and the tile does not carry it.
///
/// The brightness of each display macOS can change is read when the hub opens and after each
/// own change; no change notification is registered and nothing is polled. That part uses a
/// private macOS interface behind one wrapper. It runs only while the module's Brightness
/// setting is on, and ``gate`` switches it off by itself when the interface is missing or fails
/// three calls in a row; the volume is unaffected either way. Display names live in memory for
/// the open tab and are never logged.
///
/// External monitors are a separate part, behind their own setting (External monitors, off by
/// default) and their own ``ddcGate``. A monitor's card shows only the controls it lists in its
/// capabilities string and confirms by a value read; the string is read once per hub opening,
/// at the first survey of it. It talks DDC/CI to a monitor through the private interface of
/// ``IOAVServiceBridge``, on the ``DDCBus``'s own queue, so no transfer ever blocks the main
/// actor. The state of each monitor is read when the Display tab appears, or when the hub opens
/// on the Overview with the brightness line of a monitor (an opening where no monitor's value is
/// shown, a hover pass included, sends nothing to a monitor), and once after a change; nothing
/// is polled, and the CoreAudio listener refreshes only the Mac's volume. Closing the hub cancels every read, write and wait of this part, and a result of an
/// earlier opening is dropped by its generation number. One deliberate deviation from "the level
/// shown is the one read back": while a DDC slider moves it shows the level requested, because a
/// transfer takes about 100 ms. The writes are coalesced (the latest value wins) and about 0.3 s
/// after the last change one read-back sets the level shown to what the monitor reports.
@MainActor
@Observable
final class DisplayControlsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "display-controls"

    let moduleID = DisplayControlsRuntime.identifier
    let tint = HubTint.amber
    let offersTab = true

    /// The default output's level from 0 to 1, or `nil` when it has none or it cannot be read.
    private(set) var volume: Double?

    /// How the default output's volume is reached.
    private(set) var plan = OutputVolumePlan.unsupported

    /// Whether the output is muted. `false` when it has no mute.
    private(set) var isMuted = false

    /// Whether the output has a mute that can be set.
    private(set) var canMute = false

    /// The output's name, for the open tab only.
    private(set) var outputName: String?

    /// The outputs the picker lists, for the open tab only: the names are kept in memory and
    /// emptied when the hub closes. Empty while the hub is closed.
    private(set) var outputs: [AudioOutputRow] = []

    /// The switch of the default output that was asked for and the system has not confirmed
    /// yet (the picker shows a spinner on its row). It ends when the default read back equals
    /// the target or after ``AudioOutputList/switchTimeout``.
    private(set) var outputSwitch: AudioOutputSwitch?

    /// One display and what the module knows of its brightness.
    struct DisplayBrightness: Identifiable {
        let id: CGDirectDisplayID
        /// The display's name, for the open tab only.
        let name: String
        let isBuiltIn: Bool
        /// Whether macOS can change this display's brightness from here.
        let canChange: Bool
        /// The brightness from 0 to 1, or `nil` when the display cannot be changed or read.
        var value: Double?
    }

    /// The displays and their brightness, in the order of the screens. Empty while the setting
    /// is off or the brightness part is unavailable.
    private(set) var displays: [DisplayBrightness] = []

    /// Whether the Brightness setting was on when the brightness was last read.
    private(set) var showsBrightness = false

    /// Whether the brightness part may run. It starts switched off and follows the setting and
    /// the result of loading the brightness wrapper.
    private(set) var gate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// The displays in the order the tab shows them: the one the hub opened on first, then the
    /// others in the order of the screens, each identifier once.
    private(set) var displayOrder: [CGDirectDisplayID] = []

    /// One external monitor macOS cannot change itself, and what the module knows of it.
    struct ExternalMonitor: Identifiable {
        /// What the module knows of the monitor.
        enum State: Equatable {
            /// A survey is running.
            case reading
            /// The monitor answered and its controls are in ``values``.
            case ready
            /// The monitor was asked and gave no answer.
            case doesNotAnswer
            /// No DDC channel could be paired with the monitor, so it was never asked: turning
            /// DDC/CI on in its menu would change nothing.
            case notPaired
            /// The monitor cannot be told from an identical one, so it is never read or written.
            case indistinguishable
            /// The part switched itself off, or this Mac cannot run it.
            case unavailable
            /// The External monitors setting is off: the card only says how to turn it on.
            case switchedOff
        }

        let id: CGDirectDisplayID
        /// The monitor's name, for the open tab only.
        var name: String
        var state: State
        /// Whether the card shows its reading indicator: a first read without values has lasted
        /// longer than ``DDCTiming/readingIndicatorDelay``.
        var showsReadingIndicator = false
        /// The controls the monitor reported, with the raw value and the maximum of each.
        var values: [DDCControl: DDCControlValue]
    }

    /// The external monitors, in no particular order. Empty while the External monitors setting
    /// is off.
    private(set) var externals: [ExternalMonitor] = []

    /// Whether the external monitors part may run. It starts switched off and follows the setting,
    /// the result of loading the interface and the failures the part counts.
    private(set) var ddcGate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// The level requested while a DDC slider moves, until the read-back after its last change.
    private(set) var requestedLevels: [ExternalControl: Double] = [:]

    /// The mute state requested while a monitor's mute write is pending, until the read-back.
    private(set) var requestedMutes: [CGDirectDisplayID: Bool] = [:]

    /// A control of one external monitor.
    struct ExternalControl: Hashable, Sendable {
        let display: CGDirectDisplayID
        let control: DDCControl
    }

    /// The writes of one control of one monitor.
    private struct Channel {
        var coalescer = DDCWriteCoalescer()
        var writer: Task<Void, Never>?
        var settle: Task<Void, Never>?
    }

    /// What counts against the gate. It remembers which monitors answered in this session.
    @ObservationIgnored private var ddcPolicy = DDCFailurePolicy()

    /// The bus, created when the part first runs and dropped with it.
    @ObservationIgnored private var bus: DDCBus?

    /// The number of hub openings so far. The bus reads each monitor's capabilities once per
    /// opening: a survey of the same opening (the tab appearing again) reuses them, a new
    /// opening reads them afresh.
    private(set) var hubOpening = 0

    /// Counts the openings and surveys; a result with another number is dropped.
    @ObservationIgnored private var ddcGeneration = 0

    /// The survey of the current opening, while it runs.
    @ObservationIgnored private var surveyTask: Task<Void, Never>?

    /// The one-shot wait before a first read shows its spinner, while it runs.
    @ObservationIgnored private var indicatorTask: Task<Void, Never>?

    @ObservationIgnored private var channels: [ExternalControl: Channel] = [:]

    /// Whether the hub is open. While it is closed nothing of the external part talks to a monitor.
    @ObservationIgnored private var isHubOpen = false

    /// Follows the External monitors setting for as long as the runtime exists, so switching it
    /// off and on starts the part afresh even while the hub is closed.
    @ObservationIgnored private var externalSettingLoop: ObservationLoop?

    /// The app state, for the Brightness setting.
    @ObservationIgnored private weak var appState: AppState?

    /// The device the volume was read from.
    @ObservationIgnored private var device: AudioObjectID?

    /// The CoreAudio listeners, added while the hub is open.
    @ObservationIgnored private let listener = OutputVolume.Listener()

    /// Follows the wake gate while the hub is open: a wake or a display change asks for the
    /// monitors to be read again once the wait is over.
    @ObservationIgnored private var wakeLoop: ObservationLoop?

    /// The one-shot wait that ends an output switch the system never confirmed, while it runs.
    @ObservationIgnored private var outputSwitchTask: Task<Void, Never>?

    /// Creates the runtime. It has nothing to start: the state is read when the hub opens. It
    /// only follows the External monitors setting, which costs nothing while the setting stays.
    init(appState: AppState) {
        self.appState = appState
        externalSettingLoop = ObservationLoop.observe { [weak self] in
            self?.appState?.settings.displayControls.showsExternalMonitors ?? false
        } onChange: { [weak self] _ in
            self?.externalMonitorsSettingDidChange()
        }
    }

    /// Reads the brightness, the external monitors and the default output's plan, level, mute and
    /// name again. The Display tab calls it when it appears, so this is where the monitors are
    /// surveyed once the hub is open.
    func refresh() {
        refreshBrightness()
        refreshDisplayOrder()
        refreshExternalMonitors()
        refreshVolume()
    }

    /// Reads the default output's plan, level, mute and name again. Nothing of the displays is
    /// touched, so a volume change made elsewhere never starts a transfer to a monitor.
    func refreshVolume() {
        refreshOutputs()
        guard let output = OutputVolume.current() else {
            clear()
            return
        }
        device = output.device
        plan = output.plan
        volume = OutputVolume.volume(of: output.device, plan: output.plan)
        canMute = output.capabilities.muteSettable
        isMuted = canMute ? OutputVolume.isMuted(output.device) ?? false : false
        outputName = OutputVolume.name(of: output.device)
    }

    /// Builds the picker's list from what the system reports and ends a switch the read-back
    /// has settled, either way (``AudioOutputSwitch``): the check is always on the default the
    /// system reports.
    private func refreshOutputs() {
        let currentUID = OutputVolume.defaultOutputDevice().flatMap(OutputVolume.uid(of:))
        outputs = AudioOutputList.rows(OutputVolume.outputDevices(), currentUID: currentUID)
        if let outputSwitch, outputSwitch.state(currentUID: currentUID, now: .now) != .pending {
            clearOutputSwitch()
        }
    }

    /// Asks the system to make the device with this UID the default output (never the output of
    /// system sounds). The row shows a spinner until the default read back equals it, at most
    /// ``AudioOutputList/switchTimeout``; when the system refuses, or the default changes by
    /// itself, the check stays on, or returns to, the default the system reports and nothing is
    /// said (D-16). holzBar stores no choice of its own.
    func selectOutput(uid: String) {
        let currentUID = OutputVolume.defaultOutputDevice().flatMap(OutputVolume.uid(of:))
        guard uid != currentUID else {
            return
        }
        outputSwitch = AudioOutputSwitch(targetUID: uid, startedAt: .now)
        guard OutputVolume.setDefaultOutput(uid: uid) else {
            clearOutputSwitch()
            return
        }
        outputSwitchTask?.cancel()
        outputSwitchTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AudioOutputList.switchTimeout))
            guard !Task.isCancelled, let self else {
                return
            }
            self.outputSwitchTask = nil
            self.clearOutputSwitch()
            self.refreshVolume()
        }
        refreshVolume()
    }

    private func clearOutputSwitch() {
        outputSwitchTask?.cancel()
        outputSwitchTask = nil
        outputSwitch = nil
    }

    /// Empties the picker's list and drops a pending switch: the device names leave memory.
    private func clearOutputs() {
        clearOutputSwitch()
        outputs = []
    }

    /// Sets the level. The level shown afterwards is the one read back, not the argument.
    func setVolume(_ value: Double) {
        guard let device, plan != .unsupported else {
            return
        }
        OutputVolume.setVolume(value, of: device, plan: plan)
        volume = OutputVolume.volume(of: device, plan: plan)
    }

    /// Reads the brightness of every display macOS can change. With the Brightness setting off
    /// nothing is loaded and no private symbol is touched. Otherwise the brightness wrapper is
    /// loaded here, the first time and never before; a failed read counts against the gate.
    func refreshBrightness() {
        let isEnabled = appState?.settings.displayControls.showsBrightness ?? false
        showsBrightness = isEnabled
        guard PrivateFeatureGate.shouldLoad(isEnabled: isEnabled) else {
            gate.setEnabled(false, load: .loaded)
            displays = []
            return
        }
        // Loading happens once; asking again returns the same result and changes nothing.
        gate.setEnabled(true, load: DisplayServicesBrightness.load())
        guard gate.isAvailable else {
            displays = []
            return
        }
        var found: [DisplayBrightness] = []
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard seen.insert(id).inserted else {
                continue
            }
            let canChange = DisplayServicesBrightness.canChange(id)
            var value: Double?
            if canChange {
                value = DisplayServicesBrightness.read(id)
                if value == nil {
                    gate.recordFailure()
                } else {
                    gate.recordSuccess()
                }
            }
            found.append(DisplayBrightness(
                id: id,
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                canChange: canChange,
                value: value
            ))
        }
        displays = gate.isAvailable ? found : []
    }

    /// Sets the brightness of a display. The level shown afterwards is the one read back, not
    /// the argument.
    func setBrightness(_ value: Double, for id: CGDirectDisplayID) {
        guard gate.isAvailable, let index = displays.firstIndex(where: { $0.id == id && $0.canChange }) else {
            return
        }
        guard DisplayServicesBrightness.write(value, to: id),
              let readBack = DisplayServicesBrightness.read(id)
        else {
            gate.recordFailure()
            if !gate.isAvailable {
                displays = []
            }
            return
        }
        displays[index].value = readBack
        gate.recordSuccess()
    }

    /// Moves a display's brightness by steps of 5 percent, for the keyboard and VoiceOver.
    func adjustBrightness(by steps: Int, for id: CGDirectDisplayID) {
        guard let value = displays.first(where: { $0.id == id })?.value else {
            return
        }
        setBrightness(DisplayControlsLevel.stepped(value, by: steps), for: id)
    }

    /// Moves the level by steps of 5 percent, for the keyboard and VoiceOver.
    func adjustVolume(by steps: Int) {
        guard let volume else {
            return
        }
        setVolume(DisplayControlsLevel.stepped(volume, by: steps))
    }

    /// Mutes or unmutes the output. The state shown afterwards is the one read back.
    func setMuted(_ muted: Bool) {
        guard let device, canMute else {
            return
        }
        OutputVolume.setMuted(muted, device)
        isMuted = OutputVolume.isMuted(device) ?? false
    }

    // MARK: External monitors

    /// Works out the order of the tab's cards: the display the hub opened on first, then the
    /// others in the order macOS lists the screens. The built-in display is not forced to the top.
    private func refreshDisplayOrder() {
        displayOrder = DisplayControlsOrder.ordered(
            NSScreen.screens.map(\.displayID),
            first: appState?.notchHub.screenID
        )
    }

    /// The External monitors setting changed. Switching it off drops the gate's count of failures,
    /// what the policy remembers and the bus, so switching it on again starts afresh whether or
    /// not the hub was open in between. Switching it on while the hub is closed changes nothing
    /// and sends nothing to a monitor: the next opening reads them.
    private func externalMonitorsSettingDidChange() {
        let isEnabled = appState?.settings.displayControls.showsExternalMonitors ?? false
        if !isEnabled || isHubOpen {
            refreshExternalMonitors()
        }
    }

    /// Reads the controls of every external monitor macOS cannot change itself. With the External
    /// monitors setting off nothing is looked up and nothing is created. With it on and
    /// `surveying` true, one survey runs on the bus; a survey of this opening that is still
    /// running is left alone. With `surveying` false nothing is sent to a monitor: the hub
    /// opened where no monitor's value is shown.
    func refreshExternalMonitors(surveying: Bool = true) {
        let isEnabled = appState?.settings.displayControls.showsExternalMonitors ?? false
        let names = Dictionary(
            NSScreen.screens.map { ($0.displayID, $0.localizedName) },
            uniquingKeysWith: { first, _ in first }
        )
        guard PrivateFeatureGate.shouldLoad(isEnabled: isEnabled) else {
            ddcGate.setEnabled(false, load: .loaded)
            ddcPolicy = DDCFailurePolicy()
            cancelExternalWork()
            bus = nil
            // Only names and screen identifiers are read: nothing of the DDC part is created or
            // looked up, the cards just say how to turn the part on. With the hub closed there is
            // no tab, so no card and no name is kept.
            externals = isHubOpen ? externalCandidates().map {
                ExternalMonitor(id: $0.id, name: names[$0.id] ?? "", state: .switchedOff, values: [:])
            } : []
            return
        }
        let candidates = externalCandidates()
        // Once switched off by itself the part stays off until the user switches it off and on;
        // the cards of the monitors say so.
        if case .unavailable(let reason) = ddcGate.state, reason != .switchedOff {
            cancelExternalWork()
            externals = candidates.map {
                ExternalMonitor(id: $0.id, name: names[$0.id] ?? "", state: .unavailable, values: [:])
            }
            return
        }
        guard surveying, surveyTask == nil else {
            return
        }
        guard !candidates.isEmpty else {
            cancelExternalWork()
            externals = []
            return
        }
        cancelExternalWork(flushingPendingWrites: true)
        let generation = ddcGeneration
        externals = candidates.map { candidate in
            var monitor = externals.first { $0.id == candidate.id }
                ?? ExternalMonitor(id: candidate.id, name: "", state: .reading, values: [:])
            monitor.name = names[candidate.id] ?? ""
            monitor.state = .reading
            return monitor
        }
        let bus = bus ?? DDCBus()
        self.bus = bus
        let opening = hubOpening
        // While the wake gate is closed every card shows its reading state, with a spinner too.
        startReadingIndicatorWait(generation: generation, includingKnownValues: wakeWaitEnd() != nil)
        surveyTask = Task { [weak self] in
            // No transfer for ``DDCTiming/wakeWait`` after a wake or a display change (D-20).
            guard let self, await self.waitForWakeGate(), self.ddcGeneration == generation else {
                return
            }
            let load = await bus.load()
            guard !Task.isCancelled, self.ddcGeneration == generation else {
                return
            }
            self.ddcGate.setEnabled(true, load: load)
            guard self.ddcGate.isAvailable else {
                self.markExternalsUnavailable()
                return
            }
            let reports = await bus.survey(candidates, opening: opening)
            guard !Task.isCancelled, self.ddcGeneration == generation else {
                return
            }
            self.surveyTask = nil
            self.apply(reports)
        }
    }

    /// The displays macOS cannot change itself, as the matcher wants them: every screen that is
    /// not built in, without those the brightness part changes through DisplayServices.
    private func externalCandidates() -> [DDCDisplayMatch.Display] {
        var seen = Set<CGDirectDisplayID>()
        var candidates: [DDCDisplayMatch.Display] = []
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard seen.insert(id).inserted, CGDisplayIsBuiltin(id) == 0 else {
                continue
            }
            if displays.first(where: { $0.id == id })?.canChange == true {
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

    /// Takes the reports of a survey into ``externals`` and tells the gate what happened. A
    /// monitor that gave no answer says so on its card and never counts on its own; the survey
    /// counts as one failure only when no monitor answered and one of the monitors it asked had
    /// answered earlier in this session (``DDCFailurePolicy``).
    private func apply(_ reports: [DDCDisplayReport]) {
        var tried = Set<UInt32>()
        var answered = Set<UInt32>()
        for report in reports {
            switch report.outcome {
            case .answered:
                tried.insert(report.id)
                answered.insert(report.id)
            case .noAnswer(tried: true):
                tried.insert(report.id)
            case .noAnswer, .indistinguishable:
                break
            }
        }
        indicatorTask?.cancel()
        indicatorTask = nil
        record(ddcPolicy.surveyEnded(tried: tried, answered: answered))
        guard ddcGate.isAvailable else {
            markExternalsUnavailable()
            return
        }
        externals = externals.compactMap { monitor in
            guard let report = reports.first(where: { $0.id == monitor.id }) else {
                return nil
            }
            var updated = monitor
            updated.showsReadingIndicator = false
            switch report.outcome {
            case .answered(let controls):
                updated.state = .ready
                updated.values = Dictionary(uniqueKeysWithValues: controls.map { ($0.control, $0) })
            case .noAnswer(tried: true):
                updated.state = .doesNotAnswer
                updated.values = [:]
            case .noAnswer(tried: false):
                updated.state = .notPaired
                updated.values = [:]
            case .indistinguishable:
                updated.state = .indistinguishable
                updated.values = [:]
            }
            return updated
        }
    }

    /// Records an event on the gate.
    private func record(_ event: DDCFailurePolicy.Event) {
        switch event {
        case .success: ddcGate.recordSuccess()
        case .failure: ddcGate.recordFailure()
        case .none: break
        }
    }

    /// Records one write or read-back and, when it switched the part off, says so on every card.
    private func recordTransfer(display: CGDirectDisplayID, succeeded: Bool) {
        record(ddcPolicy.transferEnded(display: display, succeeded: succeeded))
        if !ddcGate.isAvailable {
            markExternalsUnavailable()
        }
    }

    /// Stops everything the part does and shows every external monitor as unavailable, with
    /// nothing left to set. Nothing of the part runs again until the user switches it off and on.
    private func markExternalsUnavailable() {
        cancelExternalWork()
        externals = externals.map { monitor in
            var updated = monitor
            updated.state = .unavailable
            updated.values = [:]
            return updated
        }
    }

    /// The level of a control as the slider shows it: the level requested while one is pending,
    /// else the level the monitor reported. `nil` when the monitor did not report the control.
    func externalLevel(control: DDCControl, display: CGDirectDisplayID) -> Double? {
        if let requested = requestedLevels[ExternalControl(display: display, control: control)] {
            return requested
        }
        guard let value = externals.first(where: { $0.id == display })?.values[control] else {
            return nil
        }
        return DDCLevel.level(raw: value.current, maximum: value.maximum)
    }

    /// Asks for a level of a control of an external monitor. The slider shows the level at once;
    /// the writes are coalesced so the latest value wins, and about 0.3 s after the last change
    /// one read-back sets the level shown to what the monitor reports.
    func setExternalLevel(_ level: Double, control: DDCControl, display: CGDirectDisplayID) {
        guard
            control != .mute,
            ddcGate.isAvailable,
            let bus,
            let value = externals.first(where: { $0.id == display && $0.state == .ready })?.values[control]
        else {
            return
        }
        let key = ExternalControl(display: display, control: control)
        let floor = DDCLevel.floor(for: control)
        let kept = max(DisplayControlsLevel.clamped(level), floor)
        requestedLevels[key] = kept
        let raw = DDCLevel.raw(fromLevel: kept, maximum: value.maximum, floor: floor)
        var channel = channels[key] ?? Channel()
        channel.settle?.cancel()
        channel.settle = nil
        let startsWriter = channel.coalescer.submit(raw)
        channels[key] = channel
        if startsWriter {
            let generation = ddcGeneration
            channels[key]?.writer = Task { [weak self] in
                await self?.runWriter(key, on: bus, generation: generation)
            }
        }
    }

    /// Whether an external monitor is muted as the button shows it: the state requested while a
    /// write is pending, else the one the monitor reported.
    func isExternalMuted(display: CGDirectDisplayID) -> Bool {
        if let requested = requestedMutes[display] {
            return requested
        }
        guard let value = externals.first(where: { $0.id == display })?.values[.mute] else {
            return false
        }
        return DDCLevel.isMuted(raw: value.current)
    }

    /// Mutes or unmutes an external monitor. Only a monitor that confirmed mute by a value read
    /// is written (the bus refuses any other). The button shows the request at once; the write
    /// goes through the control's coalescer, and about 0.3 s later the mute is read back and the
    /// state shown becomes what the monitor reports.
    func setExternalMuted(_ muted: Bool, display: CGDirectDisplayID) {
        guard
            ddcGate.isAvailable,
            let bus,
            externals.first(where: { $0.id == display && $0.state == .ready })?.values[.mute] != nil
        else {
            return
        }
        let key = ExternalControl(display: display, control: .mute)
        requestedMutes[display] = muted
        var channel = channels[key] ?? Channel()
        channel.settle?.cancel()
        channel.settle = nil
        let startsWriter = channel.coalescer.submit(DDCLevel.muteRaw(muted))
        channels[key] = channel
        if startsWriter {
            let generation = ddcGeneration
            channels[key]?.writer = Task { [weak self] in
                await self?.runWriter(key, on: bus, generation: generation)
            }
        }
    }

    /// Moves the level shown by steps of 5 percent, for the keyboard and VoiceOver.
    func adjustExternalLevel(by steps: Int, control: DDCControl, display: CGDirectDisplayID) {
        guard let shown = externalLevel(control: control, display: display) else {
            return
        }
        setExternalLevel(DisplayControlsLevel.stepped(shown, by: steps), control: control, display: display)
    }

    /// The writer of one control: writes the latest value until none is left, then waits for the
    /// monitor to settle and reads the control back once.
    private func runWriter(_ key: ExternalControl, on bus: DDCBus, generation: Int) async {
        while ddcGeneration == generation, !Task.isCancelled {
            // The wait comes before the value is taken, so a newer value still coalesces into it.
            guard await waitForWakeGate(), ddcGeneration == generation else {
                return
            }
            guard let raw = channels[key]?.coalescer.next() else {
                break
            }
            let succeeded = await bus.write(key.control, raw: raw, to: key.display)
            guard ddcGeneration == generation, !Task.isCancelled else {
                return
            }
            recordTransfer(display: key.display, succeeded: succeeded)
            guard ddcGate.isAvailable else {
                return
            }
        }
        guard ddcGeneration == generation, !Task.isCancelled else {
            return
        }
        channels[key]?.writer = nil
        channels[key]?.settle = Task { [weak self] in
            try? await Task.sleep(for: DDCTiming.settle)
            guard !Task.isCancelled, let self, await self.waitForWakeGate(), self.ddcGeneration == generation else {
                return
            }
            let value = await bus.readBack(key.control, of: key.display)
            guard !Task.isCancelled, self.ddcGeneration == generation else {
                return
            }
            self.channels[key]?.settle = nil
            self.recordTransfer(display: key.display, succeeded: value != nil)
            // The request is dropped whether or not the read-back worked: the level shown is the
            // one the monitor confirmed, so a failed read-back falls back to the last confirmed
            // value instead of showing a request the monitor never confirmed.
            self.requestedLevels[key] = nil
            if key.control == .mute {
                self.requestedMutes[key.display] = nil
            }
            if let value, self.ddcGate.isAvailable, let index = self.externals.firstIndex(where: { $0.id == key.display }) {
                self.externals[index].values[key.control] = value
            }
        }
    }

    // MARK: Wake wait

    /// When the wake gate opens, or `nil` when it is open now: no wake or display change was seen
    /// in the last ``DDCTiming/wakeWait``.
    private func wakeWaitEnd() -> ContinuousClock.Instant? {
        guard let gate = appState?.systemActivityMonitor.ddcWakeGate, !gate.isOpen(at: .now) else {
            return nil
        }
        return gate.opensAt
    }

    /// Waits until no DDC transfer is held back by a wake or a display change (D-20, DISP-02).
    /// A later event moves the end, so the gate is asked again after every wait. Answers `false`
    /// when the task was cancelled, which every caller treats as "stop".
    private func waitForWakeGate() async -> Bool {
        while let end = wakeWaitEnd() {
            try? await Task.sleep(until: end, clock: .continuous)
            if Task.isCancelled {
                return false
            }
        }
        return !Task.isCancelled
    }

    /// A wake or a display change while the hub is open: the monitors are read again once the
    /// wait is over, where their values are shown. The cards show their reading state until then.
    private func wakeGateDidChange() {
        guard isHubOpen, appState?.settings.displayControls.showsExternalMonitors == true else {
            return
        }
        refreshExternalMonitors(surveying: showsExternalValues)
    }

    /// Starts the one wait that lets a first read show its spinner: a monitor with no values to
    /// show waits ``DDCTiming/readingIndicatorDelay`` and, if its survey still runs then, shows
    /// the indicator. A monitor with values shows them at once and never a spinner.
    ///
    /// While the wake gate holds the transfers back (`includingKnownValues`), every card in its
    /// reading state shows the spinner, also one that has values, because nothing can be set
    /// until the wait is over.
    private func startReadingIndicatorWait(generation: Int, includingKnownValues: Bool = false) {
        func needsIndicator(_ monitor: ExternalMonitor) -> Bool {
            monitor.state == .reading && (includingKnownValues || monitor.values.isEmpty)
        }
        guard externals.contains(where: needsIndicator) else {
            return
        }
        indicatorTask = Task { [weak self] in
            try? await Task.sleep(for: DDCTiming.readingIndicatorDelay)
            guard !Task.isCancelled, let self, self.ddcGeneration == generation else {
                return
            }
            for index in self.externals.indices where needsIndicator(self.externals[index]) {
                self.externals[index].showsReadingIndicator = true
            }
            self.indicatorTask = nil
        }
    }

    /// Cancels every survey, write and wait of the external part, drops what they would have
    /// delivered and clears the levels requested. With `flushingPendingWrites` the last value a
    /// slider asked for, which no writer had taken yet, is still written once: closing the hub or
    /// asking again must not drop the position the slider showed. The part switching off or going
    /// unavailable never writes.
    private func cancelExternalWork(flushingPendingWrites: Bool = false) {
        ddcGeneration += 1
        surveyTask?.cancel()
        surveyTask = nil
        indicatorTask?.cancel()
        indicatorTask = nil
        for index in externals.indices where externals[index].showsReadingIndicator {
            externals[index].showsReadingIndicator = false
        }
        let flushBus = flushingPendingWrites && ddcGate.isAvailable ? bus : nil
        for (key, var channel) in channels {
            channel.writer?.cancel()
            channel.settle?.cancel()
            if let flushBus, let raw = channel.coalescer.next() {
                // The last position a slider showed is still written, after the wake wait when one
                // is on: a monitor coming back from sleep drops it otherwise.
                Task { [weak self] in
                    _ = await self?.waitForWakeGate()
                    _ = await flushBus.write(key.control, raw: raw, to: key.display)
                }
            }
        }
        channels = [:]
        requestedLevels = [:]
        requestedMutes = [:]
    }

    private func clear() {
        device = nil
        plan = .unsupported
        volume = nil
        isMuted = false
        canMute = false
        outputName = nil
    }

    // MARK: Hub

    /// Reads the state once more and starts the listeners when the hub opens, and stops them
    /// when it closes.
    func hubVisibilityDidChange(isOpen: Bool) {
        isHubOpen = isOpen
        if isOpen {
            hubOpening += 1
            // The monitors are asked only where their values are shown: on the Display tab, or on
            // the Overview where the brightness line of the display the hub opened on is one.
            // Every other opening, a hover pass included, sends nothing to a monitor; the tab
            // asks when it appears.
            refreshBrightness()
            refreshDisplayOrder()
            refreshExternalMonitors(surveying: showsExternalValues)
            refreshVolume()
            listener.start(followsDeviceList: true) { [weak self] in
                self?.refreshVolume()
            }
            wakeLoop = ObservationLoop.observe { [weak self] in
                self?.appState?.systemActivityMonitor.ddcWakeGate.lastEvent
            } onChange: { [weak self] _ in
                self?.wakeGateDidChange()
            }
        } else {
            wakeLoop?.cancel()
            wakeLoop = nil
            listener.stop()
            clearOutputs()
            cancelExternalWork(flushingPendingWrites: true)
        }
    }

    /// Whether the hub, as it opens, shows a value of an external monitor: the Display tab is in
    /// front, or the Overview is and the display the hub opened on is a monitor the module
    /// controls over DDC (its brightness line). Anything else needs no survey.
    private var showsExternalValues: Bool {
        guard let hub = appState?.notchHub else {
            return false
        }
        if let selected = hub.model.selectedRuntime {
            return selected.moduleID == Self.identifier
        }
        guard let id = hub.screenID else {
            return false
        }
        return externalCandidates().contains { $0.id == id }
    }

    /// The tab cannot grow with its cards, so while an external monitor's card shows it asks for
    /// the island's largest content height and scrolls above it. It reads ``externals``, so the
    /// open hub follows a card that appears or goes.
    var preferredContentHeight: Double? {
        externals.isEmpty ? nil : DesignTokens.Island.maximumContentHeight
    }

    /// The brightness of the display the hub opened on, from 0 to 1: through DisplayServices where
    /// macOS can change it, else over DDC while that part runs and the monitor answered. `nil`
    /// where there is none.
    private var openedDisplayBrightness: Double? {
        guard let id = appState?.notchHub.screenID else {
            return nil
        }
        if let display = displays.first(where: { $0.id == id }), display.canChange {
            return display.value
        }
        guard
            ddcGate.isAvailable,
            externals.first(where: { $0.id == id })?.state == .ready
        else {
            return nil
        }
        return externalLevel(control: .brightness, display: id)
    }

    /// The Overview card: the volume as a ring, or the word "Muted" while muted, and the quiet
    /// line with the brightness of the display the hub opened on. No name and no badge.
    var tile: HubTile? {
        guard let volume else {
            return nil
        }
        func tile(detail: Text?) -> HubTile {
            if isMuted {
                return HubTile(
                    symbol: "speaker.slash.fill",
                    title: Text("Volume"),
                    value: String(localized: "Muted"),
                    detail: detail
                )
            }
            return HubTile(
                symbol: "speaker.wave.2.fill",
                title: Text("Volume"),
                value: String(DisplayControlsLevel.percent(volume)),
                unit: Text(verbatim: "%"),
                detail: detail,
                fraction: volume
            )
        }
        guard let brightness = openedDisplayBrightness else {
            return tile(detail: nil)
        }
        // The formatted percent is one argument, so the catalogue key is "Brightness %@".
        let percent = "\(DisplayControlsLevel.percent(brightness)) %"
        return tile(detail: Text("Brightness \(percent)"))
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(DisplayControlsBodyView(runtime: self, host: host))
    }

    /// Stops the listeners and every transfer, and releases the state and the bus.
    func shutDown() {
        externalSettingLoop?.cancel()
        externalSettingLoop = nil
        wakeLoop?.cancel()
        wakeLoop = nil
        listener.stop()
        clearOutputs()
        cancelExternalWork()
        bus = nil
        externals = []
        displayOrder = []
        clear()
        displays = []
    }
}
