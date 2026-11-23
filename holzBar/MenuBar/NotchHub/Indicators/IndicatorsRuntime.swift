//
//  IndicatorsRuntime.swift
//  holzBar
//

import AppKit
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

    /// The flash on show: at most one, which a second change replaces.
    private var flashes = [LiveActivity]()

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var policy = IndicatorPolicy()
    @ObservationIgnored private let observer = InputSourceObserver()
    @ObservationIgnored private var switchLoop: ObservationLoop?
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
        if !flashes.isEmpty {
            flashes = []
        }
    }

    func shutDown() {
        switchLoop?.cancel()
        switchLoop = nil
        stopObservingInputSource()
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
        if !flashes.isEmpty {
            flashes = []
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
                if !flashes.isEmpty {
                    flashes = []
                }
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
        flashes = [flash]
        announce(flash)
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
