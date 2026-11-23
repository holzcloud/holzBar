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
/// macOS's own display shows too. With the switch off the listener does not exist. The volume
/// value keeps one width: every volume flash carries the wider of "100 %" and "Muted" in the user's
/// locale as its width sample.
///
/// The third is the media-key tap (D-21), the first part of replacing the system's own display:
/// while Replace the system display is on as well and holzBar holds Accessibility, the runtime
/// keeps one ``MediaKeyTap``, a session event tap on a thread of its own, and exactly then
/// (``ClosedHubWork`` decides). The tap takes the volume and mute keys where the one rule
/// (``MediaKeyRule``) says holzBar can perform them and show its own flash, and passes everything
/// else unchanged; a taken key moves the default output by Apple's step of 1/16 (1/64 with Option
/// and Shift), and the flash shows the level the output reads back through the same path as the
/// observed volume. The brightness keys pass until their targets are known. The snapshot the tap
/// reads is refreshed from observed state and the system's notifications, never on a clock. Trust is
/// re-read when holzBar or another app becomes active and after a wake, and the tap is removed the
/// moment it is gone; it comes back only after the permission has returned (2 s, then 8 s later).
///
/// On a bar so crowded that no free span is left beside the notch the hub has no live shape; the
/// runtime then has its own ``AlertNotchSurface`` (created on the first flash, released when the
/// last switch goes off) draw the flash detached below the notch (H2). Where the hub can draw its
/// live state the surface stays away, so exactly one of them draws the flash.
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
    private var flashes = [LiveActivity]() {
        didSet {
            surfaceDidChange()
        }
    }

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var policy = IndicatorPolicy()
    @ObservationIgnored private let observer = InputSourceObserver()
    @ObservationIgnored private var observersLoop: ObservationLoop?
    @ObservationIgnored private let volumeListener = OutputVolume.Listener()
    @ObservationIgnored private var volumeSteps = VolumeSteps()
    @ObservationIgnored private var volumeDevice: AudioObjectID?
    @ObservationIgnored private var pendingVolume: VolumeSteps.Change?
    @ObservationIgnored private var volumeDeferredTask: Task<Void, Never>?
    @ObservationIgnored private var isObservingVolume = false
    @ObservationIgnored private var surface: AlertNotchSurface?
    @ObservationIgnored private var widthSample: (locale: String, text: String)?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var deferredTask: Task<Void, Never>?
    @ObservationIgnored private var announceTask: Task<Void, Never>?
    @ObservationIgnored private var enabledCount = 0
    @ObservationIgnored private var isObserving = false
    @ObservationIgnored private var isHubOpen = false
    @ObservationIgnored private var mediaKeyTap: MediaKeyTap?
    @ObservationIgnored private var trustLoop: ObservationLoop?
    @ObservationIgnored private var trustRetryTask: Task<Void, Never>?
    @ObservationIgnored private var trustWatchTasks = [Task<Void, Never>]()
    @ObservationIgnored private var tapStartFailures = 0
    @ObservationIgnored private var mediaKeyInputsLoop: ObservationLoop?

    /// Whether holzBar held Accessibility when it was last looked at. It is what ``ClosedHubWork``
    /// sees as trust: it goes false at once when the permission is found gone, and true again only
    /// after the retry of ``refreshTrust()`` found it back. Tracked, so the loop follows it.
    private var isTrustedForTap = MediaKeyState.accessibilityIsTrusted()

    init(appState: AppState) {
        self.appState = appState
        observersLoop = ObservationLoop.observe(
            { [weak self] in
                self?.wantedObservers() ?? []
            },
            onChange: { [weak self] observers in
                self?.apply(observers)
            }
        )
        trustLoop = ObservationLoop.observe(
            { [weak appState] in
                // The permission model's flag is read only while the switch is on, so nothing
                // follows it with the switch off.
                guard let appState, appState.settings.indicators.replacesSystemDisplay else {
                    return false
                }
                return appState.permissions.accessibility.hasPermission
            },
            onChange: { [weak self] _ in
                self?.refreshTrust()
            }
        )
        apply(wantedObservers())
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
        observersLoop?.cancel()
        observersLoop = nil
        trustLoop?.cancel()
        trustLoop = nil
        trustRetryTask?.cancel()
        trustRetryTask = nil
        apply([])
        releaseSurface()
    }

    // MARK: Flashes

    /// Puts a flash on show, replacing the one of the same kind.
    private func setFlash(_ flash: LiveActivity) {
        var updated = flashes.filter { $0.id != flash.id }
        updated.append(flash)
        flashes = updated
    }

    /// Hands the flashes to the surface of the crowded-bar form. It is created on the first flash,
    /// and with no switch on none is made.
    private func surfaceDidChange() {
        guard isObserving || isObservingVolume, let appState else {
            releaseSurface()
            return
        }
        if flashes.isEmpty, surface == nil {
            return
        }
        let surface = surface ?? AlertNotchSurface(appState: appState)
        self.surface = surface
        surface.update(activities: flashes)
    }

    /// Hides and drops the surface, when there is one.
    private func releaseSurface() {
        surface?.hide()
        surface = nil
    }

    /// Takes the flash of a kind away, if it is on show.
    private func removeFlash(of kind: IndicatorKind) {
        let id = IndicatorLook.activityID(kind)
        if flashes.contains(where: { $0.id == id }) {
            flashes = flashes.filter { $0.id != id }
        }
    }

    // MARK: Media keys

    /// What the media-key snapshot is built from, read inside the observation: when one of these
    /// changes the snapshot is built again (the displays, the output and the presenting signals
    /// follow their own notifications).
    private struct MediaKeyInputs: Equatable {
        var replaceOn = false
        var isTrusted = false
        var isFullscreenSpace = false
        var isMenuBarHidden = false
        var isHubActive = false
        var isHubOpen = false
        var displays = NotchHubDisplays.all
        var wakeGate = DDCWakeGate()
    }

    /// Creates the tap when the rule allows it and removes it when the rule no longer does. Asking
    /// for what already is changes nothing.
    private func setObservingMediaKeys(_ isOn: Bool) {
        guard isOn else {
            stopMediaKeyTap()
            return
        }
        guard mediaKeyTap == nil else {
            return
        }
        let tap = MediaKeyTap { [weak self] in
            self?.trustWasLost()
        }
        tap.onTaken = { [weak self] press, _, quarter in
            self?.mediaKeyWasTaken(press, quarter: quarter)
        }
        mediaKeyTap = tap
        guard tap.start() else {
            // macOS refused the tap or the permission is gone: no tap, and no trust until it is back.
            mediaKeyTap = nil
            tapStartFailures += 1
            trustWasLost()
            return
        }
        tapStartFailures = 0
        watchTrust()
        mediaKeyInputsLoop = ObservationLoop.observe(
            { [weak self] in
                self?.mediaKeyInputs() ?? MediaKeyInputs()
            },
            onChange: { [weak self] _ in
                self?.refreshMediaKeySnapshot()
            }
        )
        refreshMediaKeySnapshot()
    }

    private func stopMediaKeyTap() {
        mediaKeyInputsLoop?.cancel()
        mediaKeyInputsLoop = nil
        mediaKeyTap?.stop()
        mediaKeyTap = nil
        trustWatchTasks.forEach { $0.cancel() }
        trustWatchTasks.removeAll()
    }

    private func mediaKeyInputs() -> MediaKeyInputs {
        guard let appState else {
            return MediaKeyInputs()
        }
        return MediaKeyInputs(
            replaceOn: appState.settings.indicators.replacesSystemDisplay,
            isTrusted: isTrustedForTap,
            isFullscreenSpace: appState.activeSpace.isFullscreen,
            isMenuBarHidden: appState.menuBarManager.isMenuBarHiddenBySystem,
            isHubActive: appState.notchHub.isActive,
            isHubOpen: appState.notchHub.isOpen,
            displays: appState.settings.notchHub.displays,
            wakeGate: appState.systemActivityMonitor.ddcWakeGate
        )
    }

    /// Builds what the tap's thread reads and hands it over. A key is taken only on a display where
    /// a hub may show and only while the hub is closed (an open hub draws no flash, so a key
    /// taken then would show nothing). Every brightness target is unknown here, so those keys pass.
    private func refreshMediaKeySnapshot() {
        guard let appState, let tap = mediaKeyTap else {
            return
        }
        let hub = appState.notchHub
        var snapshot = MediaKeyState.Snapshot()
        snapshot.isTrusted = isTrustedForTap && MediaKeyState.accessibilityIsTrusted()
        snapshot.replaceOn = appState.settings.indicators.replacesSystemDisplay
        snapshot.wakeGate = appState.systemActivityMonitor.ddcWakeGate
        if let output = OutputVolume.current() {
            snapshot.outputSettable = output.plan != .unsupported
            snapshot.muteSettable = output.capabilities.muteSettable
        }
        let mayShow = hub.isActive && !hub.isOpen
        for (index, screen) in NSScreen.screens.enumerated() {
            let environment = hub.policyEnvironment(of: screen, appState: appState)
            if index == 0 {
                snapshot.fullScreenSpace = environment.isFullscreenSpace
                snapshot.menuBarHidden = environment.isMenuBarHiddenBySystem
                snapshot.mirroredOrShared = environment.isPresenting
            }
            snapshot.displays.append(
                MediaKeyState.Snapshot.Display(
                    id: screen.displayID,
                    bounds: CGDisplayBounds(screen.displayID),
                    hubAllowed: mayShow && NotchHubPolicy.blockReason(environment, trigger: .compact) == nil
                )
            )
        }
        tap.update(snapshot)
    }

    /// Performs a taken key, which was already consumed: the volume and mute keys move the default
    /// output and show holzBar's own flash with the level the output reads back. The brightness
    /// keys are never taken in this release of the rule, so none reaches here.
    private func mediaKeyWasTaken(_ press: MediaKeyPress, quarter: Bool) {
        // A release is consumed and does nothing; a repeat of a held key is one more step (the
        // flash coalesces them at 50 ms and VoiceOver speaks once per burst), except for mute.
        guard
            press.isDown,
            !press.isRepeat || MediaKeyRule.repeatsWhileHeld(press.code),
            let output = OutputVolume.current()
        else {
            return
        }
        switch press.code {
        case .soundUp, .soundDown:
            guard let level = OutputVolume.volume(of: output.device, plan: output.plan) else {
                return
            }
            let next = MediaKeyRule.next(level: level, code: press.code, quarter: quarter)
            OutputVolume.setVolume(next, of: output.device, plan: output.plan)
            // A volume key unmutes, as the system's own does.
            if OutputVolume.isMuted(output.device) == true {
                OutputVolume.setMuted(false, output.device)
            }
        case .mute:
            let isMuted = OutputVolume.isMuted(output.device) ?? false
            OutputVolume.setMuted(!isMuted, output.device)
        case .brightnessUp, .brightnessDown:
            return
        }
        showTakenVolume(of: output)
    }

    /// Reads the output back and shows it as one flash through the volume path of the observed
    /// volume, so a key at the end of the range (where nothing changes) still shows and there is
    /// no second path. The listener's own callback for this change then reports nothing more, since
    /// the baseline is kept in step here.
    private func showTakenVolume(of output: OutputVolume.Output) {
        let level = OutputVolume.volume(of: output.device, plan: output.plan)
        let isMuted = OutputVolume.isMuted(output.device)
        _ = volumeSteps.offer(level: level, isMuted: isMuted)
        guard isObservingVolume, !isHubOpen, let level else {
            return
        }
        presentVolume(isMuted == true ? .muted : .level(percent: VolumeSteps.percent(level)))
    }

    /// Looks at Accessibility again whenever holzBar or another app becomes active and after a
    /// wake, only while the tap exists: revoking the permission in System Settings brings one of
    /// them forward, and an event tap that outlives its permission can freeze input (Pitfall 1).
    private func watchTrust() {
        guard trustWatchTasks.isEmpty else {
            return
        }
        func watch(
            _ center: NotificationCenter,
            _ name: Notification.Name,
            checksTrust: Bool = true
        ) -> Task<Void, Never> {
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    if checksTrust {
                        self?.refreshTrust()
                    }
                    // The same events change what the tap may take: the displays, the apps that
                    // present the screen, the Mac's wake.
                    self?.refreshMediaKeySnapshot()
                }
            }
        }
        trustWatchTasks = [
            watch(.default, NSApplication.didBecomeActiveNotification),
            watch(.default, NSApplication.didChangeScreenParametersNotification, checksTrust: false),
            watch(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification),
            watch(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
    }

    /// The permission is gone (the tap said so, or a check found it): the rule drops the tap at
    /// once, and the permission is looked for again.
    private func trustWasLost() {
        isTrustedForTap = false
        refreshTrust()
    }

    /// Looks at Accessibility again. Gone: trust drops at once, which removes the tap. There again
    /// while the tap is not trusted: it is accepted only at a try 2 s, then 8 s later, never before.
    private func refreshTrust() {
        guard appState?.settings.indicators.replacesSystemDisplay == true else {
            trustRetryTask?.cancel()
            trustRetryTask = nil
            return
        }
        if !MediaKeyState.accessibilityIsTrusted() {
            isTrustedForTap = false
        }
        // Three refused tries in a row keep the tap off for the session.
        guard !isTrustedForTap, trustRetryTask == nil, tapStartFailures < 3 else {
            return
        }
        trustRetryTask = Task { [weak self] in
            for delay in MediaKeyTap.trustRetryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else {
                    return
                }
                if MediaKeyState.accessibilityIsTrusted() {
                    isTrustedForTap = true
                    trustRetryTask = nil
                    return
                }
            }
            self?.trustRetryTask = nil
        }
    }

    // MARK: Switch

    /// The observers that exist now, decided by ``ClosedHubWork`` and nowhere else. The module's
    /// own switches are read here, so the loop follows them and the hub's and the module's on
    /// switches alike.
    private func wantedObservers() -> Set<ClosedHubWork.Observer> {
        guard let appState else {
            return []
        }
        return ClosedHubWork.observers(
            ClosedHubWork.Switches(
                hubOn: appState.modules.isEnabled(NotchHubController.moduleID),
                indicatorsOn: appState.modules.isEnabled(Self.identifier),
                inputSourceOn: appState.settings.indicators.showsInputSource,
                volumeBrightnessOn: appState.settings.indicators.showsVolumeBrightness,
                replaceSystemDisplayOn: appState.settings.indicators.replacesSystemDisplay,
                accessibilityTrusted: isTrustedForTap
            )
        )
    }

    /// Starts exactly the observers in the set and stops the rest.
    private func apply(_ observers: Set<ClosedHubWork.Observer>) {
        setObservingInputSource(observers.contains(.inputSource))
        setObservingActivation(observers.contains(.appActivation))
        setObservingVolume(observers.contains(.volumeListener))
        setObservingMediaKeys(observers.contains(.mediaKeyTap))
    }

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
    }

    /// macOS selects the per-document input source when an app comes forward; the policy needs to
    /// know when that happened, to tell it from the user's own switch.
    private func setObservingActivation(_ isOn: Bool) {
        guard isOn else {
            activationTask?.cancel()
            activationTask = nil
            return
        }
        guard activationTask == nil else {
            return
        }
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
        deferredTask?.cancel()
        deferredTask = nil
        announceTask?.cancel()
        announceTask = nil
        policy.reset(.inputSource)
        enabledCount = 0
        removeFlash(of: .inputSource)
        if !isObservingVolume {
            releaseSurface()
        }
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
        if !isObserving {
            releaseSurface()
        }
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
            if volumeDevice != nil {
                volumeDevice = nil
                // The output is gone: the tap's snapshot must not take a volume key.
                refreshMediaKeySnapshot()
            }
            return
        }
        if output.device != volumeDevice {
            volumeSteps.reset()
            volumeDevice = output.device
            // Another output: what the volume keys can do there is read again.
            refreshMediaKeySnapshot()
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
            hold: DesignTokens.Indicator.holdSeconds,
            flash: LiveActivityFlash(widthSample: volumeWidthSample())
        )
        setFlash(flash)
        announce(flash)
    }

    /// The wider of "100 %" and "Muted" in the user's locale, measured in the live value's font once
    /// per locale, so the value never moves the shape while it changes.
    private func volumeWidthSample() -> String {
        let identifier = Locale.current.identifier
        if let widthSample, widthSample.locale == identifier {
            return widthSample.text
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(DesignTokens.Island.liveValueSize), weight: .semibold)
        func width(of text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let full = (1.0).formatted(.percent)
        let muted = String(localized: "Muted")
        let text = width(of: full) >= width(of: muted) ? full : muted
        widthSample = (locale: identifier, text: text)
        return text
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
