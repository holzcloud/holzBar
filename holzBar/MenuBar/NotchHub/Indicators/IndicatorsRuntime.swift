//
//  IndicatorsRuntime.swift
//  holzBar
//

import AppKit
import CoreAudio
import Observation
import SwiftUI

/// The Indicators module in the Notch hub: no tab and no tile, it flashes in the closed notch.
///
/// The first indicator is the input source (D-09). While the Input source switch is on, the
/// runtime listens to the system's input source notifications through an ``InputSourceObserver``
/// and to app activations, and nothing else; with the switch off it holds no observer and no task.
/// Every change is read once, offered to ``IndicatorPolicy`` (the activation quiet, the repeat of
/// the shown source and the rate limit are decided there, nowhere else) and, where the policy says
/// so, published as one flash activity of ``IndicatorLook``: the source's icon, its short code and
/// its name, held for the Show for duration. A deferred change is offered again, with the source
/// read at that moment, when its window ends, so a quick second switch still shows.
///
/// The second is the volume (D-10), observe only: while the Volume and brightness switch is on, the
/// runtime has its own ``OutputVolume/Listener`` (Display controls keeps its own), reads the
/// default output's level and mute on every callback and lets ``VolumeSteps`` decide whether it is
/// a key-sized step, a mute change or an end of the range. A change is shown as one flash with the
/// speaker symbol and the level the output reads back, or "Muted". holzBar takes no key here, so
/// macOS's own display shows too. With the switch off the listener does not exist.
///
/// The runtime exists only while the hub and the module are both on. While the hub is open it makes
/// no flash (the open hub has its own surface and never lists a flash). VoiceOver hears "Input
/// source" and the name once, a moment after the last change of a burst. Names stay in memory, are
/// dropped when the flash is, and are never logged.
@MainActor
@Observable
final class IndicatorsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = IndicatorLook.moduleID

    let moduleID = IndicatorsRuntime.identifier
    let offersTab = false

    /// The flashes on show: at most one per kind, which a second change of that kind replaces.
    private var flashes = [LiveActivity]()

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var policy = IndicatorPolicy()
    @ObservationIgnored private let observer = InputSourceObserver()
    @ObservationIgnored private var switchLoop: ObservationLoop?
    @ObservationIgnored private var volumeSwitchLoop: ObservationLoop?
    @ObservationIgnored private let volumeListener = OutputVolume.Listener()
    @ObservationIgnored private var volumeSteps = VolumeSteps()
    @ObservationIgnored private var volumeDevice: AudioObjectID?
    @ObservationIgnored private var pendingVolume: VolumeSteps.Change?
    @ObservationIgnored private var volumeDeferredTask: Task<Void, Never>?
    @ObservationIgnored private var isObservingVolume = false
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var deferredTask: Task<Void, Never>?
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private var enabledCount = 0
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var isHubOpen = false

    init(appState: AppState) {
        self.appState = appState
        switchLoop = ObservationLoop.observe(
            { [weak self] in
                self?.appState?.settings.indicators.showsInputSource ?? false
            },
            onChange: { [weak self] isOn in
                self?.setObservingInputSource(isOn)
            }
        )
        setObservingInputSource(appState.settings.indicators.showsInputSource)
        volumeSwitchLoop = ObservationLoop.observe(
            { [weak self] in
                self?.appState?.settings.indicators.showsVolumeBrightness ?? false
            },
            onChange: { [weak self] isOn in
                self?.setObservingVolume(isOn)
            }
        )
        setObservingVolume(appState.settings.indicators.showsVolumeBrightness)
    }

    var activities: [LiveActivity] {
        flashes
    }

    /// Never called: the module has no tab.
    func makeBody(host _: any HubHost) -> AnyView {
        AnyView(EmptyView())
    }

    /// While the hub is open nothing flashes, and a flash still on show goes: it would come back
    /// into the closed notch when the hub closes.
    func hubVisibilityDidChange(isOpen: Bool) {
        isHubOpen = isOpen
        guard isOpen else {
            return
        }
        deferredTask?.cancel()
        deferredTask = nil
        volumeDeferredTask?.cancel()
        volumeDeferredTask = nil
        pendingVolume = nil
        if !flashes.isEmpty {
            flashes = []
        }
    }

    func shutDown() {
        switchLoop?.cancel()
        switchLoop = nil
        volumeSwitchLoop?.cancel()
        volumeSwitchLoop = nil
        stopObservingInputSource()
        stopObservingVolume()
    }

    // MARK: Flashes

    /// Puts a flash on show, replacing the one of the same kind.
    private func setFlash(_ flash: LiveActivity) {
        var updated = flashes.filter { $0.id != flash.id }
        updated.append(flash)
        flashes = updated
    }

    /// Takes the flash of a kind away, if it is on show.
    private func removeFlash(of kind: IndicatorKind) {
        let id = IndicatorLook.activityID(kind)
        if flashes.contains(where: { $0.id == id }) {
            flashes = flashes.filter { $0.id != id }
        }
    }

    // MARK: Switch

    private func setObservingInputSource(_ isOn: Bool) {
        if isOn {
            startObservingInputSource()
        } else {
            stopObservingInputSource()
        }
    }

    private func startObservingInputSource() {
        guard !isObserving else {
            return
        }
        isObserving = true
        enabledCount = InputSourceObserver.enabledCount()
        observer.start { [weak self] change in
            self?.inputSourceDidChange(change)
        }
        // macOS selects the per-document input source when an app comes forward; the policy needs
        // to know when that happened, to tell it from the user's own switch.
        activationTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            ) {
                self?.policy.appDidActivate(at: .now)
            }
        }
    }

    private func stopObservingInputSource() {
        isObserving = false
        observer.stop()
        activationTask?.cancel()
        activationTask = nil
        deferredTask?.cancel()
        deferredTask = nil
        announceTask?.cancel()
        announceTask = nil
        policy.reset(.inputSource)
        enabledCount = 0
        removeFlash(of: .inputSource)
    }

    // MARK: Changes

    private func inputSourceDidChange(_ change: InputSourceObserver.Change) {
        guard isObserving else {
            return
        }
        switch change {
        case .enabledSources:
            // Counted again on this notification only, never on a clock.
            enabledCount = InputSourceObserver.enabledCount()
            if !InputSourceLabel.shows(enabledCount: enabledCount) {
                deferredTask?.cancel()
                deferredTask = nil
                removeFlash(of: .inputSource)
            }
        case .selected:
            offerCurrentSource()
        }
    }

    /// Reads the source in use now and shows it, defers it or ignores it, as the policy decides.
    private func offerCurrentSource() {
        guard isObserving, InputSourceLabel.shows(enabledCount: enabledCount) else {
            return
        }
        guard let source = InputSourceObserver.current() else {
            return
        }
        if isHubOpen {
            // Not shown, and not remembered as shown: the same source flashes again after the hub
            // closes.
            policy.reset(.inputSource)
            return
        }
        let now = Date.now
        switch policy.offer(.inputSource, value: source.id, at: now) {
        case .show:
            deferredTask?.cancel()
            deferredTask = nil
            show(source, at: now)
        case .deferred(let moment):
            deferredTask?.cancel()
            deferredTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(0, moment.timeIntervalSinceNow)))
                } catch {
                    return
                }
                // The latest source at that moment, not the one that was deferred.
                self?.offerCurrentSource()
            }
        case .ignored:
            break
        }
    }

    private func show(_ source: InputSourceInfo, at moment: Date) {
        let code = InputSourceLabel.shortCode(languages: source.languages, localizedName: source.localizedName)
        let name = source.localizedName
        let title = String(localized: "Input source \(name)")
        let duration = IndicatorLook.inputSourceDuration(
            appState?.settings.indicators.inputSourceDuration ?? DesignTokens.Indicator.inputSourceDefaultDuration
        )
        let flash = IndicatorLook.flash(
            kind: .inputSource,
            symbol: "keyboard",
            value: code,
            title: title,
            at: moment,
            hold: duration,
            flash: LiveActivityFlash(
                secondaryValue: name.isEmpty ? nil : name,
                symbolImageURL: source.iconURL
            )
        )
        setFlash(flash)
        announce(flash)
    }

    // MARK: Volume

    private func setObservingVolume(_ isOn: Bool) {
        if isOn {
            startObservingVolume()
        } else {
            stopObservingVolume()
        }
    }

    /// Adds the listener and reads the output once, which is the baseline: nothing flashes at
    /// start.
    private func startObservingVolume() {
        guard !isObservingVolume else {
            return
        }
        isObservingVolume = true
        volumeListener.start { [weak self] in
            self?.volumeDidChange()
        }
        volumeDidChange()
    }

    private func stopObservingVolume() {
        isObservingVolume = false
        volumeListener.stop()
        volumeDeferredTask?.cancel()
        volumeDeferredTask = nil
        pendingVolume = nil
        volumeSteps.reset()
        volumeDevice = nil
        policy.reset(.volume)
        removeFlash(of: .volume)
    }

    /// Reads the default output and shows a key-sized change of it. A new default output, and the
    /// first reading, only set the baseline; no output, or one with no readable level (an HDMI
    /// monitor without volume control), shows nothing. Only symbols, percentages and the word
    /// Muted ever leave this method: the output's name is not read.
    private func volumeDidChange() {
        guard isObservingVolume else {
            return
        }
        guard let output = OutputVolume.current() else {
            volumeSteps.reset()
            volumeDevice = nil
            return
        }
        if output.device != volumeDevice {
            volumeSteps.reset()
            volumeDevice = output.device
        }
        let change = volumeSteps.offer(
            level: OutputVolume.volume(of: output.device, plan: output.plan),
            isMuted: OutputVolume.isMuted(output.device)
        )
        guard let change else {
            return
        }
        if isHubOpen {
            // The open hub has its own surface; the baseline above is kept current, nothing shows.
            return
        }
        presentVolume(change)
    }

    /// Offers a change to the policy: it shows now, or when its 50 ms window ends with the latest
    /// change then (a burst is one flash).
    private func presentVolume(_ change: VolumeSteps.Change) {
        let now = Date.now
        switch policy.offer(.volume, value: Self.volumeText(change), at: now) {
        case .show:
            volumeDeferredTask?.cancel()
            volumeDeferredTask = nil
            pendingVolume = nil
            showVolume(change, at: now)
        case .deferred(let moment):
            pendingVolume = change
            volumeDeferredTask?.cancel()
            volumeDeferredTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(max(0, moment.timeIntervalSinceNow)))
                } catch {
                    return
                }
                self?.presentPendingVolume()
            }
        case .ignored:
            break
        }
    }

    private func presentPendingVolume() {
        guard isObservingVolume, !isHubOpen, let change = pendingVolume else {
            return
        }
        pendingVolume = nil
        presentVolume(change)
    }

    private func showVolume(_ change: VolumeSteps.Change, at moment: Date) {
        let percent: Int
        let isMuted: Bool
        switch change {
        case .level(let value), .unmuted(let value):
            percent = value
            isMuted = false
        case .muted:
            percent = 0
            isMuted = true
        }
        let title = isMuted ? String(localized: "Muted") : String(localized: "Volume \(percent) percent")
        let flash = IndicatorLook.flash(
            kind: .volume,
            symbol: IndicatorLook.volumeSymbol(percent: percent, isMuted: isMuted),
            value: Self.volumeText(change),
            title: title,
            at: moment,
            hold: DesignTokens.Indicator.holdSeconds
        )
        setFlash(flash)
        announce(flash)
    }

    /// The value the flash shows: the level as a percentage in the user's locale, or Muted.
    private static func volumeText(_ change: VolumeSteps.Change) -> String {
        switch change {
        case .level(let percent), .unmuted(let percent):
            (Double(percent) / 100).formatted(.percent)
        case .muted:
            String(localized: "Muted")
        }
    }

    /// Tells VoiceOver once per burst: the announcement is armed again by every change, so it is
    /// spoken only after the last one of a quick series, never once per notification. Nothing is
    /// posted while VoiceOver is off. The text names the source, which stays in the accessibility
    /// layer of this Mac and is never logged.
    private func announce(_ flash: LiveActivity) {
        announceTask?.cancel()
        guard NSWorkspace.shared.isVoiceOverEnabled else {
            announceTask = nil
            return
        }
        let text = flash.title
        announceTask = Task {
            do {
                try await Task.sleep(for: .seconds(DesignTokens.Indicator.announceDelay))
            } catch {
                return
            }
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
