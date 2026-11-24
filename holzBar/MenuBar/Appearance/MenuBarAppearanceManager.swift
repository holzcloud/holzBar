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
            if !isApplyingMood {
                currentMoodName = nil
            }
            do {
                let data = try encoder.encode(configuration)
                Defaults.set(data, forKey: .menuBarAppearanceConfigurationV2)
            } catch {
                Logger.serialization.error("Error encoding menu bar appearance configuration: \(error, privacy: .private)")
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

    /// The saved looks of the menu bar.
    private(set) var moods = [AppearanceMood]()

    /// The name of the mood whose look is on now; `nil` once the look is changed by hand.
    /// The built-in mood is held by its identifier (``BuiltInMood/readableMenuBarID``).
    private(set) var currentMoodName: String? {
        didSet {
            followIncreaseContrast(BuiltInMood.readableMenuBarID == currentMoodName)
        }
    }

    /// Whether the built-in "Readable menu bar" mood is the current look.
    var isReadableMenuBarCurrent: Bool {
        currentMoodName == BuiltInMood.readableMenuBarID
    }

    /// Whether the configuration is being set by a mood, which keeps its name.
    @ObservationIgnored private var isApplyingMood = false

    /// Follows Increase Contrast, only while the built-in mood is the current look.
    @ObservationIgnored private let transparencyObserver = TransparencyObserver()

    /// Re-applies the built-in mood's border when Increase Contrast changes.
    @ObservationIgnored private var increaseContrastLoop: ObservationLoop?

    /// The currently previewed partial configuration.
    var previewConfiguration: MenuBarAppearancePartialConfiguration?

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

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

    /// Saves the look that is on now as a mood. Returns its name, or `nil` when the name is
    /// empty or there are too many moods.
    @discardableResult
    func saveCurrentLook(named name: String) -> String? {
        guard moods.count < MoodNaming.maximumCount, let cleaned = MoodNaming.cleaned(name) else {
            return nil
        }
        let unique = MoodNaming.unique(
            cleaned,
            among: moods.map(\.name),
            reserved: BuiltInMood.reservedNames(label: Self.readableMenuBarLabel)
        )
        moods.append(AppearanceMood(name: unique, configuration: configuration))
        currentMoodName = unique
        saveMoods()
        return unique
    }

    /// Switches the menu bar to the mood with this name; does nothing when there is none.
    func applyMood(named name: String) {
        if name == BuiltInMood.readableMenuBarID {
            if #available(macOS 26.0, *) {
                applyReadableMenuBar()
            }
            return
        }
        guard let mood = moods.first(where: { $0.name == name }) else {
            return
        }
        isApplyingMood = true
        configuration = mood.configuration
        isApplyingMood = false
        currentMoodName = mood.name
    }

    /// The built-in mood's label in the user's language.
    static var readableMenuBarLabel: String {
        String(localized: "Readable menu bar")
    }

    /// The name to show for a stored mood name: the localized label for the built-in mood's
    /// identifier, else the name itself.
    static func displayName(ofMood name: String) -> String {
        name == BuiltInMood.readableMenuBarID ? readableMenuBarLabel : name
    }

    /// Gives the bar an opaque tint in the system's light and dark grounds.
    ///
    /// It patches only the tint (and the border under Increase Contrast) of the current
    /// configuration, so the shape, spacing, shadow and widgets stay as they are, and it
    /// never reads or writes a system setting.
    func applyReadableMenuBar() {
        var patched = configuration
        patched.isDynamic = true
        let increaseContrast = TransparencyOptions.system.increaseContrast
        Self.patchReadableMenuBar(&patched.lightModeConfiguration, tint: BuiltInMood.lightTint, border: BuiltInMood.lightBorder, increaseContrast: increaseContrast)
        Self.patchReadableMenuBar(&patched.darkModeConfiguration, tint: BuiltInMood.darkTint, border: BuiltInMood.darkBorder, increaseContrast: increaseContrast)
        isApplyingMood = true
        configuration = patched
        isApplyingMood = false
        currentMoodName = BuiltInMood.readableMenuBarID
    }

    /// Sets one appearance's opaque tint and its border.
    private static func patchReadableMenuBar(
        _ partial: inout MenuBarAppearancePartialConfiguration,
        tint: DesignTokens.RGB,
        border: DesignTokens.Tint,
        increaseContrast: Bool
    ) {
        partial.tintKind = .solid
        partial.tintFollowsAccentColor = false
        partial.tintColor = CGColor(srgbRed: tint.red, green: tint.green, blue: tint.blue, alpha: 1)
        partial.style.tintStrength = MenuBarPartialStyle.opaqueTintStrength
        patchReadableMenuBarBorder(&partial, border: border, increaseContrast: increaseContrast)
    }

    /// Draws the border in the increased stroke colour while Increase Contrast is on, else none.
    private static func patchReadableMenuBarBorder(
        _ partial: inout MenuBarAppearancePartialConfiguration,
        border: DesignTokens.Tint,
        increaseContrast: Bool
    ) {
        partial.hasBorder = increaseContrast
        guard increaseContrast else {
            return
        }
        partial.borderColor = CGColor(
            srgbRed: border.color.red,
            green: border.color.green,
            blue: border.color.blue,
            alpha: border.alpha
        )
        partial.borderWidth = BuiltInMood.borderWidth
        partial.borderStyle = .solid
        partial.style.borderFill = .color
    }

    /// Starts or stops following Increase Contrast: only the built-in mood needs it, and it
    /// listens to one notification, never polls.
    private func followIncreaseContrast(_ isOn: Bool) {
        if isOn {
            guard increaseContrastLoop == nil else {
                return
            }
            transparencyObserver.start()
            increaseContrastLoop = ObservationLoop.observe { [weak self] in
                self?.transparencyObserver.options.increaseContrast ?? false
            } onChange: { [weak self] increaseContrast in
                self?.applyReadableMenuBarBorder(increaseContrast: increaseContrast)
            }
        } else if increaseContrastLoop != nil {
            increaseContrastLoop?.cancel()
            increaseContrastLoop = nil
            transparencyObserver.stop()
        }
    }

    /// Draws or removes the built-in mood's border when Increase Contrast changes, leaving
    /// everything else of the look as it is.
    private func applyReadableMenuBarBorder(increaseContrast: Bool) {
        guard isReadableMenuBarCurrent else {
            return
        }
        var patched = configuration
        Self.patchReadableMenuBarBorder(&patched.lightModeConfiguration, border: BuiltInMood.lightBorder, increaseContrast: increaseContrast)
        Self.patchReadableMenuBarBorder(&patched.darkModeConfiguration, border: BuiltInMood.darkBorder, increaseContrast: increaseContrast)
        isApplyingMood = true
        configuration = patched
        isApplyingMood = false
    }

    /// Removes a mood.
    ///
    /// - Returns: The mood, its former index and whether it was in use, for an undo; `nil`
    ///   if it was not there.
    @discardableResult
    func removeMood(withID id: UUID) -> (mood: AppearanceMood, index: Int, wasCurrent: Bool)? {
        guard let index = moods.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let wasCurrent = moods[index].name == currentMoodName
        if wasCurrent {
            currentMoodName = nil
        }
        let mood = moods.remove(at: index)
        saveMoods()
        return (mood, index, wasCurrent)
    }

    /// Puts a deleted mood back at its former index, unless a mood with its identifier or
    /// name is there again or the list is full.
    func insertMood(_ mood: AppearanceMood, at index: Int, makeCurrent: Bool) {
        guard
            moods.count < MoodNaming.maximumCount,
            !moods.contains(where: { $0.id == mood.id || $0.name == mood.name })
        else {
            return
        }
        DeletionUndo.reinsert(mood, at: index, into: &moods)
        if makeCurrent {
            currentMoodName = mood.name
        }
        saveMoods()
    }

    private func saveMoods() {
        if let data = try? encoder.encode(moods) {
            Defaults.set(data, forKey: .appearanceMoods)
        }
    }

    /// Loads the initial values for the configuration.
    private func loadInitialState() {
        if
            let data = Defaults.data(forKey: .appearanceMoods),
            let decoded = try? decoder.decode([AppearanceMood].self, from: data)
        {
            moods = Array(decoded.prefix(MoodNaming.maximumCount))
        }
        do {
            if let data = Defaults.data(forKey: .menuBarAppearanceConfigurationV2) {
                configuration = try decoder.decode(MenuBarAppearanceConfigurationV2.self, from: data)
            }
        } catch {
            Logger.serialization.error("Error decoding menu bar appearance configuration: \(error, privacy: .private)")
        }
        // The current mood is not stored, so the stored look is recognised: the built-in mood's
        // opaque tints are a look of their own. Its border is then brought in line with
        // Increase Contrast as it is now, and the listener starts, as after applying the mood.
        if Self.isReadableMenuBarLook(configuration) {
            currentMoodName = BuiltInMood.readableMenuBarID
            applyReadableMenuBarBorder(increaseContrast: TransparencyOptions.system.increaseContrast)
        }
    }

    /// Whether a configuration carries the built-in mood's tints in both appearances: dynamic, solid,
    /// opaque, not following the accent colour, and the mood's ground colours (the border is not
    /// compared, it follows Increase Contrast).
    private static func isReadableMenuBarLook(_ configuration: MenuBarAppearanceConfigurationV2) -> Bool {
        configuration.isDynamic
            && hasReadableTint(configuration.lightModeConfiguration, tint: BuiltInMood.lightTint)
            && hasReadableTint(configuration.darkModeConfiguration, tint: BuiltInMood.darkTint)
    }

    private static func hasReadableTint(_ partial: MenuBarAppearancePartialConfiguration, tint: DesignTokens.RGB) -> Bool {
        guard
            partial.tintKind == .solid,
            !partial.tintFollowsAccentColor,
            partial.style.tintStrength == MenuBarPartialStyle.opaqueTintStrength,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let components = partial.tintColor.converted(to: space, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else {
            return false
        }
        // A stored colour is a few bits off the constant; one 8-bit step is far more than that.
        let tolerance = 1.0 / 255
        return abs(components[0] - tint.red) < tolerance
            && abs(components[1] - tint.green) < tolerance
            && abs(components[2] - tint.blue) < tolerance
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
        if configuration.appleLogoStyle == .capsule {
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
