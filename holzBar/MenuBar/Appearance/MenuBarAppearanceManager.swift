//
//  MenuBarAppearanceManager.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog

/// A manager for the appearance of the menu bar.
@MainActor
@Observable
final class MenuBarAppearanceManager {
    /// The current menu bar appearance configuration.
    var configuration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration {
        didSet {
            if !isLoadingStoredValues {
                do {
                    let data = try encoder.encode(configuration)
                    Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
                } catch {
                    Logger.serialization.error("Error encoding menu bar appearance configuration: \(error, privacy: .private)")
                }
            }
            // The overlay panels may not have been configured yet. Since some of the
            // properties on the manager might call for them, try to configure now
            // (at most every 0.1 s, with the latest configuration).
            configurationThrottle.throttle(latest: true) { [weak self] in
                guard let self, overlayPanels.isEmpty else {
                    return
                }
                configureOverlayPanels(with: configuration)
            }
        }
    }

    /// The currently previewed partial configuration.
    var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// A Boolean value that indicates whether ``loadInitialState()`` is assigning the stored
    /// configuration. While it is, the configuration is not encoded and saved again: a launch
    /// never rewrites a stored synced setting the user did not change (analysis §4.9 item 2).
    @ObservationIgnored private var isLoadingStoredValues = false

    /// Encoder for UserDefaults values.
    @ObservationIgnored private let encoder = JSONEncoder()

    /// Decoder for UserDefaults values.
    @ObservationIgnored private let decoder = JSONDecoder()

    /// Rebuilds the overlay panels 0.1 s after the screens stop changing.
    @ObservationIgnored private let screenParametersDebouncer = Debouncer(delay: .milliseconds(100))

    /// Configures the overlay panels at most every 0.1 s when the configuration changes.
    @ObservationIgnored private let configurationThrottle = Debouncer(delay: .milliseconds(100))

    /// The task that follows screen parameter changes.
    @ObservationIgnored private var screenParametersTask: Task<Void, Never>?

    /// The currently managed menu bar overlay panels.
    @ObservationIgnored private(set) var overlayPanels = Set<MenuBarOverlayPanel>()

    /// The rounded screen corners.
    @ObservationIgnored private let screenCorners = ScreenCorners()

    /// The retries after launch for panels that found no menu bar yet.
    @ObservationIgnored private var launchRetryTask: Task<Void, Never>?

    /// How many times, and how far apart, panels that found no menu bar at launch are
    /// tried again (at login the menu bar can appear after holzBar).
    private static let launchRetries = (count: 3, interval: Duration.seconds(3))

    /// The amount to inset the menu bar if called for by the configuration.
    let menuBarInsetAmount: CGFloat = if #available(macOS 26.0, *) { 3.5 } else { 5 }

    /// Performs initial setup of the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        configureObservers()
        if overlayPanels.isEmpty {
            configureOverlayPanels(with: configuration)
        }
        screenCorners.performSetup(with: self)
        scheduleLaunchRetries()
    }

    /// Tries the panels that found no menu bar again, at most three times 3 s apart, then
    /// stops; later the next settle or screen change tries them again.
    private func scheduleLaunchRetries() {
        launchRetryTask = Task { [weak self] in
            for _ in 0..<Self.launchRetries.count {
                do {
                    try await Task.sleep(for: Self.launchRetries.interval)
                } catch {
                    return
                }
                guard let self, overlayPanels.contains(where: { $0.needsRetry }) else {
                    return
                }
                retryPanels()
            }
        }
    }

    /// Reads the menu bar again and shows the panels that found none.
    private func retryPanels() {
        appState?.applicationMenuFrames.refresh(reason: "appearance retry", settling: false)
        for panel in overlayPanels where panel.needsRetry {
            panel.needsShow = true
        }
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        isLoadingStoredValues = true
        defer {
            isLoadingStoredValues = false
        }
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.serialization.error("Error decoding menu bar appearance configuration: \(error, privacy: .private)")
        }
    }

    /// Configures the internal observers for the manager.
    private func configureObservers() {
        screenParametersTask = Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.screenParametersDebouncer.schedule { [weak self] in
                    self?.screenParametersDidChange()
                }
            }
        }
    }

    /// Takes the overlay panels down and rebuilds them for the current screens.
    private func screenParametersDidChange() {
        while let panel = overlayPanels.popFirst() {
            panel.orderOut(self)
        }
        if Set(overlayPanels.map { $0.owningScreen }) != Set(NSScreen.screens) {
            configureOverlayPanels(with: configuration)
        }
    }

    /// Restores the appearance once the bar has settled after the screen was locked, the
    /// Mac slept, the session was away or the displays changed (`SystemActivityMonitor`).
    ///
    /// The panels are rebuilt when the screens changed or a panel found no menu bar;
    /// otherwise they are drawn again with a fresh wallpaper.
    func systemActivityDidSettle() {
        guard needsOverlayPanels(for: configuration) else {
            return
        }
        if
            Set(overlayPanels.map { $0.owningScreen }) != Set(NSScreen.screens) ||
            overlayPanels.contains(where: { $0.needsRetry })
        {
            configureOverlayPanels(with: configuration)
            return
        }
        for panel in overlayPanels {
            panel.refresh()
        }
    }

    /// Returns a Boolean value that indicates whether a set of overlay panels
    /// is needed for the given configuration.
    ///
    /// A dynamic appearance needs them when either mode does: nothing rebuilds the panels
    /// when light/dark mode switches, and "Hold to Preview" shows the other mode.
    func needsOverlayPanels(for configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        let partials = if configuration.isDynamic {
            [configuration.lightModeConfiguration, configuration.darkModeConfiguration]
        } else {
            [configuration.staticConfiguration]
        }
        if partials.contains(where: { $0.hasShadow || $0.hasBorder || $0.tintKind != .noTint }) {
            return true
        }
        if configuration.shapeKind != .noShape {
            return true
        }
        if configuration.blackBackground != .off {
            return true
        }
        return false
    }

    /// Configures the manager's overlay panels, if required by the given configuration.
    private func configureOverlayPanels(with configuration: MenuBarAppearanceConfigurationV2) {
        guard
            let appState,
            needsOverlayPanels(for: configuration)
        else {
            while let panel = overlayPanels.popFirst() {
                panel.close()
            }
            return
        }

        // Close the panels being replaced before building their successors.
        //
        // A visible NSWindow is retained by AppKit, so dropping the last Swift
        // reference to it does not close it. Reassigning `overlayPanels` therefore
        // left the previous set alive and on screen, each panel still running its
        // own update loops. This function runs on every screen-parameter change,
        // so attaching and detaching a display accumulated a full set of live
        // panels per display each time, all competing to own the menu bar's
        // appearance. The not-needed path above already closes them; this one did
        // not.
        while let panel = overlayPanels.popFirst() {
            panel.close()
        }

        var overlayPanels = Set<MenuBarOverlayPanel>()
        for screen in NSScreen.screens {
            let panel = MenuBarOverlayPanel(appState: appState, owningScreen: screen)
            overlayPanels.insert(panel)
            panel.needsShow = true
        }

        self.overlayPanels = overlayPanels
    }
}
