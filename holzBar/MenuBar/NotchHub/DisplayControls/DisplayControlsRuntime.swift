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
/// default) and their own ``ddcGate``. It talks DDC/CI to a monitor through the private
/// interface of ``IOAVServiceBridge``, on the ``DDCBus``'s own queue, so no transfer ever blocks
/// the main actor. The state of each monitor is read when the hub opens or the tab appears and
/// once after a change; nothing is polled, and the CoreAudio listener refreshes only the Mac's
/// volume. Closing the hub cancels every read, write and wait of this part, and a result of an
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

    /// The displays and their brightness, the built-in one first. Empty while the setting is off
    /// or the brightness part is unavailable.
    private(set) var displays: [DisplayBrightness] = []

    /// Whether the Brightness setting was on when the brightness was last read.
    private(set) var showsBrightness = false

    /// Whether the brightness part may run. It starts switched off and follows the setting and
    /// the result of loading the brightness wrapper.
    private(set) var gate = PrivateFeatureGate(isEnabled: false, load: .loaded)

    /// The displays in the order the tab shows them: the built-in one first, then the others in
    /// the order of the screens, each identifier once.
    private(set) var displayOrder: [CGDirectDisplayID] = []

    /// One external monitor macOS cannot change itself, and what the module knows of it.
    struct ExternalMonitor: Identifiable {
        /// What the module knows of the monitor.
        enum State: Equatable {
            /// A survey is running.
            case reading
            /// The monitor answered and its controls are in ``values``.
            case ready
        }

        let id: CGDirectDisplayID
        /// The monitor's name, for the open tab only.
        var name: String
        var state: State
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

    /// The bus, created when the part first runs and dropped with it.
    @ObservationIgnored private var bus: DDCBus?

    /// Counts the openings and surveys; a result with another number is dropped.
    @ObservationIgnored private var ddcGeneration = 0

    /// The survey of the current opening, while it runs.
    @ObservationIgnored private var surveyTask: Task<Void, Never>?

    @ObservationIgnored private var channels: [ExternalControl: Channel] = [:]

    /// The app state, for the Brightness setting.
    @ObservationIgnored private weak var appState: AppState?

    /// The device the volume was read from.
    @ObservationIgnored private var device: AudioObjectID?

    /// The CoreAudio listeners, added while the hub is open.
    @ObservationIgnored private let listener = OutputVolume.Listener()

    /// Creates the runtime. It has nothing to start: the state is read when the hub opens.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Reads the brightness, the external monitors and the default output's plan, level, mute and
    /// name again.
    func refresh() {
        refreshBrightness()
        refreshDisplayOrder()
        refreshExternalMonitors()
        refreshVolume()
    }

    /// Reads the default output's plan, level, mute and name again. Nothing of the displays is
    /// touched, so a volume change made elsewhere never starts a transfer to a monitor.
    func refreshVolume() {
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
        // The built-in display first, the others in the order of the screens.
        let ordered = found.filter(\.isBuiltIn) + found.filter { !$0.isBuiltIn }
        displays = gate.isAvailable ? ordered : []
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

    /// Works out the order of the tab's cards: the built-in display first, then the others.
    private func refreshDisplayOrder() {
        var seen = Set<CGDirectDisplayID>()
        let ids = NSScreen.screens.map(\.displayID).filter { seen.insert($0).inserted }
        displayOrder = ids.filter { CGDisplayIsBuiltin($0) != 0 } + ids.filter { CGDisplayIsBuiltin($0) == 0 }
    }

    /// Reads the controls of every external monitor macOS cannot change itself. With the External
    /// monitors setting off nothing is looked up and nothing is created. With it on, one survey
    /// runs on the bus; a survey of this opening that is still running is left alone.
    func refreshExternalMonitors() {
        let isEnabled = appState?.settings.displayControls.showsExternalMonitors ?? false
        guard PrivateFeatureGate.shouldLoad(isEnabled: isEnabled) else {
            ddcGate.setEnabled(false, load: .loaded)
            cancelExternalWork()
            bus = nil
            externals = []
            return
        }
        // Once switched off by itself the part stays off until the user switches it off and on.
        if case .unavailable(let reason) = ddcGate.state, reason != .switchedOff {
            return
        }
        guard surveyTask == nil else {
            return
        }
        let candidates = externalCandidates()
        guard !candidates.isEmpty else {
            cancelExternalWork()
            externals = []
            return
        }
        cancelExternalWork()
        let generation = ddcGeneration
        let names = Dictionary(
            NSScreen.screens.map { ($0.displayID, $0.localizedName) },
            uniquingKeysWith: { first, _ in first }
        )
        externals = candidates.map { candidate in
            var monitor = externals.first { $0.id == candidate.id }
                ?? ExternalMonitor(id: candidate.id, name: "", state: .reading, values: [:])
            monitor.name = names[candidate.id] ?? ""
            monitor.state = .reading
            return monitor
        }
        let bus = bus ?? DDCBus()
        self.bus = bus
        surveyTask = Task { [weak self] in
            let load = await bus.load()
            guard !Task.isCancelled, let self, self.ddcGeneration == generation else {
                return
            }
            self.ddcGate.setEnabled(true, load: load)
            guard self.ddcGate.isAvailable else {
                self.surveyTask = nil
                self.externals = []
                return
            }
            let reports = await bus.survey(candidates)
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

    /// Takes the reports of a survey into ``externals``. A monitor that did not answer is left out,
    /// so the tab keeps its ordinary row for it.
    private func apply(_ reports: [DDCDisplayReport]) {
        var kept: [ExternalMonitor] = []
        for monitor in externals {
            guard let report = reports.first(where: { $0.id == monitor.id }) else {
                continue
            }
            if case .answered(let controls) = report.outcome {
                var ready = monitor
                ready.state = .ready
                ready.values = Dictionary(uniqueKeysWithValues: controls.map { ($0.control, $0) })
                kept.append(ready)
                ddcGate.recordSuccess()
            }
        }
        externals = kept
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
            ddcGate.isAvailable,
            let bus,
            let value = externals.first(where: { $0.id == display && $0.state == .ready })?.values[control]
        else {
            return
        }
        let key = ExternalControl(display: display, control: control)
        let floor = control == .brightness ? DDCLevel.brightnessFloor : 0
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
        while ddcGeneration == generation, !Task.isCancelled, let raw = channels[key]?.coalescer.next() {
            _ = await bus.write(key.control, raw: raw, to: key.display)
        }
        guard ddcGeneration == generation, !Task.isCancelled else {
            return
        }
        channels[key]?.writer = nil
        channels[key]?.settle = Task { [weak self] in
            try? await Task.sleep(for: DDCTiming.settle)
            guard !Task.isCancelled, let self, self.ddcGeneration == generation else {
                return
            }
            let value = await bus.read(key.control, of: key.display)
            guard !Task.isCancelled, self.ddcGeneration == generation else {
                return
            }
            self.channels[key]?.settle = nil
            if let value, let index = self.externals.firstIndex(where: { $0.id == key.display }) {
                self.externals[index].values[key.control] = value
                self.requestedLevels[key] = nil
            }
        }
    }

    /// Cancels every survey, write and wait of the external part, drops what they would have
    /// delivered and clears the levels requested.
    private func cancelExternalWork() {
        ddcGeneration += 1
        surveyTask?.cancel()
        surveyTask = nil
        for channel in channels.values {
            channel.writer?.cancel()
            channel.settle?.cancel()
        }
        channels = [:]
        requestedLevels = [:]
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
        if isOpen {
            refresh()
            listener.start { [weak self] in
                self?.refreshVolume()
            }
        } else {
            listener.stop()
            cancelExternalWork()
        }
    }

    /// The Overview card: the volume as a ring, or the word "Muted" while muted. No name.
    var tile: HubTile? {
        guard let volume else {
            return nil
        }
        if isMuted {
            return HubTile(
                symbol: "speaker.slash.fill",
                title: Text("Volume"),
                value: String(localized: "Muted")
            )
        }
        return HubTile(
            symbol: "speaker.wave.2.fill",
            title: Text("Volume"),
            value: String(DisplayControlsLevel.percent(volume)),
            unit: Text(verbatim: "%"),
            fraction: volume
        )
    }

    func makeBody(host _: any HubHost) -> AnyView {
        AnyView(DisplayControlsBodyView(runtime: self))
    }

    /// Stops the listeners and every transfer, and releases the state and the bus.
    func shutDown() {
        listener.stop()
        cancelExternalWork()
        bus = nil
        externals = []
        displayOrder = []
        clear()
        displays = []
    }
}
