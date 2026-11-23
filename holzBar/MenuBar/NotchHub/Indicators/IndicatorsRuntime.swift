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
/// and nothing else; with the switch off it holds no observer and no task.
/// Every change is read once, offered to ``IndicatorPolicy`` (the activation quiet, the repeat of
/// the shown source and the rate limit are decided there, nowhere else) and, where the policy says
/// so, published as one flash activity of ``IndicatorLook``: the source's icon, its short code and
/// its name, held for the Show for duration. A deferred change is offered again, with the source
/// read at that moment, when its window ends, so a quick second switch still shows.
///
/// The runtime exists only while the hub and the module are both on. Names stay in memory, are
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
    @ObservationIgnored private var deferredTask: Task<Void, Never>?
    @ObservationIgnored private var enabledCount = 0
    @ObservationIgnored private var isObserving = false

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
    }

    private func stopObservingInputSource() {
        isObserving = false
        observer.stop()
        deferredTask?.cancel()
        deferredTask = nil
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
            hold: duration
        )
        flashes = [flash]
    }
}
