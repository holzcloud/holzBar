//
//  MenuBarWidgets.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// Menu bar items of the user's own: a line of text from a built-in source (Phase 12).
///
/// Each widget is a status item of holzBar's with the autosave name `holzBar.Widget.<uuid>`,
/// so macOS remembers its place and the layout model sees a stable identity (D-17). The text
/// is monospaced-digit, a template, and has one fixed length measured from the widest text of
/// its format, so neighbouring items never move (D-11, D-12).
///
/// Nothing exists while the module is off: no status item, no timer, no observer (D-06, D-16).
/// While it is on, every widget has a ``WidgetRefreshPolicy`` that decides when its source is
/// read. This class feeds the policy events and does what the returned command says; every
/// wait is a one-shot task the policy armed, never a repeating timer (D-14, D-15).
///
/// A button widget runs a Shortcut of the user's when it is clicked, in the menu bar or from the
/// holzBar Shelf, the search, a group or a hint; a text widget has no action (D-20). The
/// Shortcut's name is chosen by typing it and stays on this Mac (D-21, D-25).
///
/// A script widget shows the first line of an approved script's output, in a fixed width. It
/// asks the script when it becomes visible, on the system events the automation engine follows
/// while it is visible (at most every 30 seconds) and on a click, never on a timer and never
/// while hidden, asleep or locked. This class starts no process: the run goes through
/// ``AutomationManager/runWidgetScript(named:)``, the runner and the gate of the scripts (D-23).
/// The script it runs is bound in `Scripts.json` on this Mac, never in its definition (D-25).
@MainActor
@Observable
final class MenuBarWidgets {
    /// The identifier of the module in ``ModuleCatalog``.
    static let moduleID = "widgets"

    /// The widgets, in the order they were added. At most ``WidgetDefinition/maximumCount``.
    private(set) var definitions = [WidgetDefinition]()

    /// Whether the module is on, and the widgets exist in the menu bar.
    private(set) var isActive = false

    /// The name of the Shortcut each button runs, by widget identifier. Kept on this Mac only:
    /// it is neither exported, imported nor shared (D-25).
    private(set) var shortcutNames = [UUID: String]()

    /// The picture of each widget that is in the menu bar, by autosave name, drawn by holzBar
    /// itself so the Shelf, the search, groups and hints need no screen recording (D-24).
    private(set) var images = [String: NSImage]()

    @ObservationIgnored private let logger = Logger(category: "MenuBarWidgets")
    @ObservationIgnored private weak var appState: AppState?

    /// Follows the module switch; the only observation that exists while the module is off.
    @ObservationIgnored private var moduleLoop: ObservationLoop?

    /// Follows which widgets are shown and whether the Mac is in use, while the module is on.
    @ObservationIgnored private var visibilityLoop: ObservationLoop?

    /// What exists for each widget while the module is on.
    @ObservationIgnored private var runtimes = [UUID: Runtime]()

    /// The tasks that follow the clock, Low Power Mode and the locale, while the module is on.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// The task that follows power source events, while a battery widget is visible.
    @ObservationIgnored private var batteryTask: Task<Void, Never>?

    /// Waits for the script store to be read at start-up, so that script widgets that were
    /// revealed before it was ready ask their script then. It ends itself.
    @ObservationIgnored private var scriptStoreLoop: ObservationLoop?

    // MARK: Setup

    /// Loads the widgets and follows the module switch. With the module off, nothing else is
    /// created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        definitions = WidgetList.decode(Defaults.data(forKey: .widgets) ?? Data())
        let storedNames = Defaults.dictionary(forKey: .widgetShortcutNames)
        shortcutNames = ShortcutLink.storedNames(storedNames, keeping: Set(definitions.map(\.id)))
        if (storedNames?.count ?? 0) != shortcutNames.count {
            // Names of widgets that are gone, and anything that is not a name, are dropped.
            saveShortcutNames()
        }
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] isOn in
            self?.setActive(isOn)
        }
        setActive(appState.modules.isEnabled(Self.moduleID))
    }

    // MARK: Editing

    /// Adds a widget, unless there are already ``WidgetDefinition/maximumCount`` of them (D-05).
    ///
    /// - Returns: Whether the widget was added.
    @discardableResult
    func addWidget(_ definition: WidgetDefinition) -> Bool {
        guard
            definitions.count < WidgetDefinition.maximumCount,
            !definitions.contains(where: { $0.id == definition.id }),
            let valid = definition.validated()
        else {
            return false
        }
        // Bindings of widgets that are gone (a replaced list) would take places of the six.
        appState?.automation.scriptStore.keepWidgetScripts(for: Set(definitions.map(\.id)))
        definitions.append(valid)
        save()
        if isActive {
            start(valid)
        }
        return true
    }

    /// Removes a widget, its status item and the place macOS remembered for it.
    func removeWidget(id: UUID) {
        guard let index = definitions.firstIndex(where: { $0.id == id }) else {
            return
        }
        let definition = definitions.remove(at: index)
        save()
        // The script a script widget was bound to goes with it (D-25).
        appState?.automation.scriptStore.keepWidgetScripts(for: Set(definitions.map(\.id)))
        if shortcutNames.removeValue(forKey: id) != nil {
            saveShortcutNames()
        }
        if #available(macOS 27.0, *), let appState {
            // A widget's key is no application's, so nothing else would take it out of the
            // layout macOS 27 saves.
            appState.concealer27.removeSection(forKey: definition.autosaveName)
        }
        if let runtime = runtimes.removeValue(forKey: id) {
            stop(runtime, keepingPosition: false)
            updatePowerSourceEvents()
        } else {
            Self.forgetPosition(of: definition.autosaveName)
        }
    }

    /// Replaces a widget's definition with an edited one: the symbol and the fixed length are
    /// measured again and the policy is told what the widget now shows.
    func update(_ definition: WidgetDefinition) {
        guard
            let index = definitions.firstIndex(where: { $0.id == definition.id }),
            let valid = definition.validated(),
            definitions[index] != valid
        else {
            return
        }
        definitions[index] = valid
        save()
        guard let runtime = runtimes[valid.id] else {
            return
        }
        runtime.definition = valid
        runtime.cpuBaseline = nil
        configure(runtime)
        let command = runtime.policy.handle(
            .cadenceChanged(WidgetCadence(definition: valid)),
            at: .now,
            date: Date(),
            calendar: Self.calendar
        )
        apply(command, to: runtime)
        if !command.refreshes {
            // The format changed but not the cadence: show the new text now, or the en dash.
            if runtime.policy.isVisible {
                refresh(runtime)
            } else {
                render(runtime, reading: .unavailable)
            }
        }
    }

    /// Moves a widget up (a negative offset) or down in the list, which is the order a settings
    /// export carries (D-25). Nothing happens at the ends.
    func moveWidget(id: UUID, by offset: Int) {
        guard
            let index = definitions.firstIndex(where: { $0.id == id }),
            definitions.indices.contains(index + offset),
            offset != 0
        else {
            return
        }
        let definition = definitions.remove(at: index)
        definitions.insert(definition, at: index + offset)
        save()
    }

    private func save() {
        if let data = WidgetList.encoded(definitions) {
            Defaults.set(data, forKey: .widgets)
        }
    }

    // MARK: Shortcut names

    /// Stores the name of the Shortcut a button runs, cleaned (``ShortcutLink/cleanedName(_:)``).
    /// A text that is empty removes the name.
    ///
    /// - Returns: `false`, storing nothing, when the name cannot be used.
    @discardableResult
    func setShortcutName(_ text: String, for id: UUID) -> Bool {
        guard definitions.contains(where: { $0.id == id && $0.kind == .button }) else {
            return false
        }
        if text.allSatisfy(\.isWhitespace) {
            if shortcutNames.removeValue(forKey: id) != nil {
                saveShortcutNames()
                refreshHint(of: id)
            }
            return true
        }
        guard let name = ShortcutLink.cleanedName(text) else {
            return false
        }
        if shortcutNames[id] != name {
            shortcutNames[id] = name
            saveShortcutNames()
            refreshHint(of: id)
        }
        return true
    }

    private func saveShortcutNames() {
        var stored = [String: String]()
        for (id, name) in shortcutNames {
            stored[id.uuidString] = name
        }
        Defaults.set(stored, forKey: .widgetShortcutNames)
    }

    private func refreshHint(of id: UUID) {
        guard let runtime = runtimes[id] else {
            return
        }
        runtime.statusItem.button?.setAccessibilityHelp(
            WidgetSpeech.hint(for: runtime.definition, shortcutName: shortcutNames[id])
        )
    }

    // MARK: Clicks

    /// Runs the button's Shortcut by opening its link, and nothing else: holzBar asks for no
    /// permission, shows no confirmation and gives no feedback of its own when the Shortcut
    /// does not exist, because the Shortcuts app says so itself (D-21, D-22). The name is never
    /// logged.
    ///
    /// A button without a name opens the settings, where the name is chosen (D-25).
    func runShortcut(for id: UUID) {
        guard
            isActive,
            let name = shortcutNames[id],
            let url = ShortcutLink.runURL(forShortcutNamed: name)
        else {
            openLayoutSettings()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        // Ask the system not to bring the Shortcuts app forward.
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration, completionHandler: nil)
    }

    private func openLayoutSettings() {
        guard let appState else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .menuBarLayout
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    /// Forwards a status item button's click to a closure (the class of the same name in
    /// `MenuBarItemGroups` is the first copy; a third user lifts it into a shared file).
    private final class ClickTarget: NSObject {
        let action: (NSStatusBarButton) -> Void

        init(action: @escaping (NSStatusBarButton) -> Void) {
            self.action = action
        }

        @objc func clicked(_ sender: NSStatusBarButton) {
            action(sender)
        }
    }

    /// Whether the item is one of the widgets, which then runs its own action instead of a click
    /// on the bar: a left click on a button runs its Shortcut, a left click on a script widget
    /// asks its script again, a text widget does nothing (D-20, D-23). Any other item is left to
    /// the caller.
    ///
    /// - Parameters:
    ///   - item: The item that is opened.
    ///   - mouseButton: The button of the click.
    ///   - origin: How the open started. Only the user's own click skips the 30 seconds between
    ///     two asks of a script widget; a hotkey, a hint, a group or a Shortcut keeps them, so a
    ///     repeat cannot run the script faster than a system event could (WR-02).
    func handlesOpen(of item: MenuBarItem, mouseButton: CGMouseButton, origin: ItemOpenOrigin) -> Bool {
        guard
            isActive,
            item.tag.namespace == .holzBar,
            let id = WidgetDefinition.id(fromAutosaveName: item.tag.title),
            let definition = definitions.first(where: { $0.id == id })
        else {
            return false
        }
        if mouseButton == .left {
            switch definition.kind {
            case .button: runShortcut(for: id)
            case .script: refreshScriptWidget(id: id, isUserAction: origin.isUserClick)
            case .text: break
            }
        }
        return true
    }

    /// The picture of the widget with the given autosave name, or `nil` when it is not in the
    /// menu bar.
    func image(forAutosaveName name: String) -> NSImage? {
        images[name]
    }

    // MARK: Module switch

    private func setActive(_ isOn: Bool) {
        guard isOn != isActive else {
            return
        }
        isActive = isOn
        logger.info("Widgets module on: \(isOn, privacy: .public), \(self.definitions.count, privacy: .public) widgets")
        if isOn {
            activate()
        } else {
            deactivate()
        }
    }

    /// Creates the status items and starts following what decides when they are read.
    private func activate() {
        for definition in definitions {
            makeRuntime(for: definition)
        }
        startObservers()
        followScriptStore()
        // The system events of the automation engine refresh the script widgets that are seen
        // (D-23). Nothing is registered while the module is off.
        appState?.automation.onSystemEvent { [weak self] in
            self?.systemEventArrived()
        }
        visibilityLoop = ObservationLoop.observe { [weak self] in
            self?.visibilityInputs() ?? VisibilityInputs()
        } onChange: { [weak self] inputs in
            self?.visibilityChanged(inputs)
        }
        let inputs = visibilityInputs()
        for runtime in runtimes.values {
            begin(runtime, with: inputs)
        }
    }

    /// Cancels every timer, ends every observation of the widgets and removes the status
    /// items, keeping the place each one had.
    private func deactivate() {
        visibilityLoop?.cancel()
        visibilityLoop = nil
        scriptStoreLoop?.cancel()
        scriptStoreLoop = nil
        appState?.automation.onSystemEvent(nil)
        for task in observerTasks {
            task.cancel()
        }
        observerTasks.removeAll()
        for runtime in runtimes.values {
            stop(runtime, keepingPosition: true)
        }
        runtimes.removeAll()
        updatePowerSourceEvents()
    }

    // MARK: Visibility

    /// What decides whether the widgets are read, and on macOS 27 whether they are drawn: which
    /// of them are in a section that is shown, which of them are in a section the bar does not
    /// draw, and whether the Mac is not in use.
    nonisolated private struct VisibilityInputs: Equatable, Sendable {
        var shown = Set<UUID>()
        /// The widgets that are collapsed to nothing (macOS 27 only).
        var collapsed = Set<UUID>()
        var isPaused = false
    }

    private func visibilityInputs() -> VisibilityInputs {
        guard let appState else {
            return VisibilityInputs()
        }
        var inputs = VisibilityInputs()
        inputs.isPaused = appState.systemActivityMonitor.isPaused
        for definition in definitions where isShown(definition, in: appState) {
            inputs.shown.insert(definition.id)
        }
        if #available(macOS 27.0, *) {
            for definition in definitions where !isDrawn(definition, in: appState) {
                inputs.collapsed.insert(definition.id)
            }
        }
        return inputs
    }

    /// The section of the item cache that holds the widget, `nil` while the cache has not got
    /// it yet.
    private func cachedSection(of definition: WidgetDefinition, in appState: AppState) -> MenuBarSection.Name? {
        let cache = appState.itemManager.itemCache
        let name = definition.autosaveName
        return MenuBarSection.Name.allCases.first { section in
            cache[section].contains { item in
                item.tag.namespace == .holzBar && item.tag.title == name
            }
        }
    }

    /// Whether the section of the widget's item is shown. The visible section always counts as
    /// shown while the Mac is in use (D-14); the hidden and always-hidden sections count when
    /// they are not hidden; an item the cache does not hold yet counts as shown.
    private func isShown(_ definition: WidgetDefinition, in appState: AppState) -> Bool {
        guard let section = cachedSection(of: definition, in: appState), section != .visible else {
            return true
        }
        return appState.menuBarManager.section(withName: section)?.isHidden == false
    }

    /// Whether the bar draws the widget on macOS 27, where holzBar cannot conceal its own item
    /// and collapses it instead (12-SPIKE.md 5.2). It follows the state the concealment of the
    /// items beside it follows, which is not the same as ``isShown(_:in:)``: with the holzBar
    /// Shelf the bar stays concealed while the Shelf shows the section, and the widget is read
    /// for the Shelf's picture all the same. An item the cache does not hold yet is drawn.
    @available(macOS 27.0, *)
    private func isDrawn(_ definition: WidgetDefinition, in appState: AppState) -> Bool {
        guard let section = cachedSection(of: definition, in: appState) else {
            return true
        }
        return appState.concealer27.reveals(MacOS27Section(section))
    }

    private func visibilityChanged(_ inputs: VisibilityInputs) {
        for runtime in runtimes.values {
            setCollapsed(inputs.collapsed.contains(runtime.definition.id), runtime)
            send(.paused(inputs.isPaused), to: runtime)
            send(.shown(inputs.shown.contains(runtime.definition.id)), to: runtime)
        }
    }

    /// Collapses the widget to nothing, or gives it its fixed length again. The item keeps its
    /// element while collapsed, so it stays in the item list, the Shelf and the search; its
    /// picture is the one holzBar draws itself (12-SPIKE.md A3).
    private func setCollapsed(_ isCollapsed: Bool, _ runtime: Runtime) {
        guard runtime.isCollapsed != isCollapsed else {
            return
        }
        runtime.isCollapsed = isCollapsed
        applyLength(of: runtime)
    }

    /// Sets the status item's length: the fixed one, or none while the widget is collapsed. As
    /// `ControlItem.updateStatusItemVisibility` collapses a divider, the item's window is made
    /// one point wide as well.
    private func applyLength(of runtime: Runtime) {
        let statusItem = runtime.statusItem
        guard runtime.isCollapsed else {
            statusItem.length = runtime.fixedLength
            return
        }
        statusItem.length = 0
        if let window = statusItem.button?.window {
            var size = window.frame.size
            size.width = 1
            window.setContentSize(size)
        }
    }

    // MARK: Status items

    /// The font of every widget: monospaced digits at the menu bar's size.
    private static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }

    /// The locale and the calendar of the user, read when they are needed, so a change of the
    /// language, the region or the time zone shows at the next reading.
    private static var locale: Locale {
        .autoupdatingCurrent
    }

    private static var calendar: Calendar {
        .autoupdatingCurrent
    }

    /// The room the button keeps around its content when the system's own measure is not
    /// available.
    private static let minimumPadding = CGFloat(12)

    /// What exists for one widget while the module is on.
    private final class Runtime {
        var definition: WidgetDefinition
        let statusItem: NSStatusItem
        var policy: WidgetRefreshPolicy
        /// The one wait the policy armed, if any.
        var timer: Task<Void, Never>?
        /// Tells a wait that was replaced from the current one.
        var timerToken = 0
        /// The last reading that was rendered.
        var reading = WidgetReading.unavailable
        /// The last text that was drawn, so an equal text is not drawn again.
        var text: WidgetText?
        /// The last value that was handed to VoiceOver.
        var spoken: String?
        /// The tick counters of the last CPU reading. A load is the difference of two readings,
        /// so it is dropped whenever the widget stops being visible: a reveal never shows an
        /// average over the hidden time.
        var cpuBaseline: CPUTicks?
        /// Forwards a button's click; the status item's button holds its target weakly.
        var clickTarget: ClickTarget?
        /// The one length of the status item, measured from the widest text (D-12).
        var fixedLength = NSStatusItem.variableLength
        /// Whether the widget is collapsed to nothing, because its section is not drawn
        /// (macOS 27).
        var isCollapsed = false
        /// The widest width its text may take, from the widest sample of its format.
        var textWidth = CGFloat.zero
        /// A script widget's last result: the line its script printed, or nothing. Kept apart
        /// from ``reading`` so a reveal inside the 30 seconds shows it again without a new run.
        var scriptReading = WidgetReading.unavailable
        /// When the script was last started, on the monotonic clock (the 30 seconds between two
        /// runs of one widget).
        var lastScriptStart: ContinuousClock.Instant?
        /// Whether a run is going. A widget runs its script one at a time.
        var isScriptRunning = false
        /// Whether the gate refused the script at its last run: not allowed, or changed since.
        var isScriptRefused = false
        /// Whether the script was busy when this widget asked: another widget (or a rule) was
        /// running it. The widget takes over the result of the run that ends (WR-03).
        var isWaitingForScript = false

        init(definition: WidgetDefinition, statusItem: NSStatusItem) {
            self.definition = definition
            self.statusItem = statusItem
            self.policy = WidgetRefreshPolicy(cadence: WidgetCadence(definition: definition))
        }
    }

    /// Creates the widget's status item and starts its policy.
    private func start(_ definition: WidgetDefinition) {
        makeRuntime(for: definition)
        guard let runtime = runtimes[definition.id] else {
            return
        }
        begin(runtime, with: visibilityInputs())
    }

    private func makeRuntime(for definition: WidgetDefinition) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = definition.autosaveName
        // On macOS 26, holzBar recognises its own items' windows by their frames (D-17, D-24).
        OwnStatusItemWindows.register(statusItem, forAutosaveName: definition.autosaveName)
        // On macOS 27, holzBar finds its own items through Accessibility by this identifier, as
        // it does the dividers; a plain status item reports an empty one, and so it would not
        // be listed (12-SPIKE.md, A1).
        statusItem.button?.setAccessibilityIdentifier(definition.autosaveName)
        let runtime = Runtime(definition: definition, statusItem: statusItem)
        runtimes[definition.id] = runtime
        configure(runtime)
        render(runtime, reading: .unavailable)
    }

    /// Feeds a new policy what it needs to know. It starts hidden, and shows its first text
    /// once the Mac is in use and its section is shown.
    private func begin(_ runtime: Runtime, with inputs: VisibilityInputs) {
        setCollapsed(inputs.collapsed.contains(runtime.definition.id), runtime)
        send(.lowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled), to: runtime)
        send(.paused(inputs.isPaused), to: runtime)
        send(.shown(inputs.shown.contains(runtime.definition.id)), to: runtime)
    }

    /// Cancels the widget's timer and takes its status item out of the menu bar.
    ///
    /// - Parameter keepingPosition: Whether the place macOS remembered for it stays, so that the
    ///   widget comes back where it was when the module is switched on again.
    private func stop(_ runtime: Runtime, keepingPosition: Bool) {
        cancelWait(of: runtime)
        let name = runtime.definition.autosaveName
        // Removing a status item deletes its preferred position. Cache and restore it, as the
        // control items do.
        let position = ControlItemDefaults[.preferredPosition, name]
        NSStatusBar.system.removeStatusItem(runtime.statusItem)
        OwnStatusItemWindows.unregister(autosaveName: name)
        OwnStatusItemNames.set(nil, forAutosaveName: name)
        images[name] = nil
        if keepingPosition {
            ControlItemDefaults[.preferredPosition, name] = position
        } else {
            Self.forgetPosition(of: name)
        }
    }

    /// Deletes what macOS stored for a status item that is gone for good.
    private static func forgetPosition(of autosaveName: String) {
        ControlItemDefaults[.preferredPosition, autosaveName] = nil
        ControlItemDefaults[.visible, autosaveName] = nil
        ControlItemDefaults[.visibleCC, autosaveName] = nil
    }

    // MARK: Rendering

    /// Sets the symbol and the fixed length of the widget (D-11, D-12).
    private func configure(_ runtime: Runtime) {
        guard let button = runtime.statusItem.button else {
            return
        }
        let definition = runtime.definition
        if definition.kind != .button, definition.showsSymbol {
            // A text widget's source symbol, or a script widget's terminal symbol (D-11).
            let image = NSImage(systemSymbolName: definition.symbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        } else if definition.showsButtonSymbolOnly {
            let image = NSImage(systemSymbolName: WidgetDefinition.buttonSymbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.imagePosition = .noImage
        }
        // A button runs its Shortcut when it is clicked; a text widget has no action (D-20).
        if definition.kind == .button {
            let id = definition.id
            let target = runtime.clickTarget ?? ClickTarget { [weak self] _ in
                self?.runShortcut(for: id)
            }
            runtime.clickTarget = target
            button.target = target
            button.action = #selector(ClickTarget.clicked(_:))
        } else if definition.kind == .script {
            // A click asks the script again (D-23). A line wider than the fixed width is cut
            // with an ellipsis at its end (D-12).
            let id = definition.id
            let target = runtime.clickTarget ?? ClickTarget { [weak self] _ in
                self?.refreshScriptWidget(id: id)
            }
            runtime.clickTarget = target
            button.target = target
            button.action = #selector(ClickTarget.clicked(_:))
            button.lineBreakMode = .byTruncatingTail
        } else {
            runtime.clickTarget = nil
            button.target = nil
            button.action = nil
        }
        // The tooltip repeats the label; a text widget has no action, so it is static text and
        // a button is a button with the Shortcut's name as its hint (D-27). The value is set
        // with every text.
        let label = WidgetSpeech.label(for: definition)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(WidgetSpeech.hint(for: definition, shortcutName: shortcutNames[definition.id]))
        // The layout editor and search name the widget by the same label, on every backend
        // (D-24).
        OwnStatusItemNames.set(label, forAutosaveName: definition.autosaveName)
        button.setAccessibilityRole(definition.kind == .text ? .staticText : .button)
        runtime.fixedLength = measuredLength(for: runtime)
        applyLength(of: runtime)
        // The measure changed the title and the value may change with the language; draw both
        // again.
        runtime.text = nil
        runtime.spoken = nil
    }

    /// The one length of the status item: the widest text of the widget's format with the
    /// symbol and the button's own padding, rounded up. Measured when the item is created and
    /// when its definition or the locale changes, never on a refresh.
    private func measuredLength(for runtime: Runtime) -> CGFloat {
        let definition = runtime.definition
        // A button that shows its symbol has no text; the symbol and the padding are measured.
        let samples = definition.showsButtonSymbolOnly ? [""] : WidgetFormat.widthSamples(
            for: definition,
            locale: Self.locale,
            calendar: Self.calendar,
            capacityBytes: capacityBytes(for: definition),
            now: .now
        )
        guard let button = runtime.statusItem.button, var widest = samples.first else {
            return NSStatusItem.squareLength
        }
        let font = Self.font
        var widestWidth = CGFloat.zero
        for sample in samples {
            let width = NSAttributedString(string: sample, attributes: [.font: font]).size().width
            if width > widestWidth {
                widest = sample
                widestWidth = width
            }
        }
        // The battery's state symbol is part of the text; the wider of the two is measured.
        var measured = WidgetText(string: widest)
        if definition.kind == .text, definition.source == .battery, definition.preset == .percentAndState {
            let candidates = [BatteryState.charging, .onAdapter].map { WidgetText(string: widest, batteryState: $0) }
            measured = candidates.max { first, second in
                Self.attributedTitle(for: first).size().width < Self.attributedTitle(for: second).size().width
            } ?? measured
        }
        // The picture of a script widget is cut at the same width as its text.
        runtime.textWidth = widestWidth
        // Ask the button itself what the widest text needs, with its symbol.
        let previous = button.attributedTitle
        let title = Self.attributedTitle(for: measured)
        button.attributedTitle = title
        let fitting = button.fittingSize.width
        button.attributedTitle = previous
        let symbolWidth = button.image?.size.width ?? 0
        let minimum = max(widestWidth, title.size().width) + symbolWidth + Self.minimumPadding
        return max(fitting, minimum).rounded(.up)
    }

    /// The memory or the volume a byte count is a part of, for the width samples.
    private func capacityBytes(for definition: WidgetDefinition) -> UInt64? {
        guard definition.kind == .text else {
            return nil
        }
        switch (definition.source, definition.preset) {
        case (.memory, .gigabytesUsed):
            return ProcessInfo.processInfo.physicalMemory
        case (.freeDisk, .gigabytesFree):
            return WidgetSamplers.diskSpace().map { UInt64(max($0.total, 0)) }
        default:
            return nil
        }
    }

    /// The symbol that shows the battery's state next to the percentage, if the state has one:
    /// a bolt while it charges, a plug on the adapter when it is full or holds its level, and
    /// nothing on battery power.
    private static func stateSymbolName(for state: BatteryState?) -> String? {
        switch state {
        case .charging: "bolt.fill"
        case .charged, .onAdapter: "powerplug.fill"
        case .onBattery, nil: nil
        }
    }

    /// The text of a widget in the menu bar font, muted when it is a passed countdown, with the
    /// battery's state as a template symbol after it, and cut at its end when it asks for it.
    private static func attributedTitle(for text: WidgetText, truncates: Bool = false) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if truncates {
            // A script's line can be wider than the fixed width: it is cut with an ellipsis.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            attributes[.paragraphStyle] = paragraph
        }
        if text.isMuted {
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        }
        let title = NSMutableAttributedString(string: text.string, attributes: attributes)
        if
            let name = stateSymbolName(for: text.batteryState),
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular))
        {
            symbol.isTemplate = true
            let attachment = NSTextAttachment()
            attachment.image = symbol
            title.append(NSAttributedString(string: " ", attributes: attributes))
            title.append(NSAttributedString(attachment: attachment))
        }
        return title
    }

    /// Draws the text of a reading, unless it is the text already drawn.
    private func render(_ runtime: Runtime, reading: WidgetReading) {
        runtime.reading = reading
        var text = WidgetFormat.text(
            for: reading,
            definition: runtime.definition,
            locale: Self.locale,
            calendar: Self.calendar
        )
        if runtime.definition.showsButtonSymbolOnly {
            // The symbol is the button's image; its title is not drawn.
            text = WidgetText(string: "")
        }
        guard let button = runtime.statusItem.button else {
            return
        }
        if text != runtime.text {
            runtime.text = text
            let isScript = runtime.definition.kind == .script
            button.attributedTitle = Self.attributedTitle(for: text, truncates: isScript)
            // The same text as a picture, for the surfaces that show items elsewhere (D-24).
            images[runtime.definition.autosaveName] = Self.picture(
                for: runtime.definition,
                text: text,
                maximumTextWidth: isScript && runtime.textWidth > 0 ? runtime.textWidth : nil
            )
        }
        // VoiceOver reads the reading in full, not the short text (D-27). A button has no
        // reading: it says its label and its hint. A script widget says its line, or what is
        // missing.
        let spoken: String
        if runtime.definition.kind == .script {
            spoken = scriptSpeech(for: runtime, reading: reading)
        } else {
            spoken = WidgetSpeech.value(
                for: reading,
                definition: runtime.definition,
                locale: Self.locale,
                calendar: Self.calendar
            )
        }
        if spoken != runtime.spoken {
            runtime.spoken = spoken
            button.setAccessibilityValue(spoken.isEmpty ? nil : spoken)
        }
    }

    // MARK: Pictures

    /// The widget as an image of its own: the leading symbol, the text and the battery's state
    /// symbol, in the font of the menu bar, as a template at the height of a menu bar item. A
    /// widget that cannot be read is the en dash, like its status item (D-13).
    private static func picture(
        for definition: WidgetDefinition,
        text: WidgetText,
        maximumTextWidth: CGFloat?
    ) -> NSImage? {
        var symbolName: String?
        var string = text.string
        switch definition.kind {
        case .text:
            symbolName = definition.showsSymbol ? definition.source.symbolName : nil
        case .button:
            if definition.showsButtonSymbolOnly {
                symbolName = WidgetDefinition.buttonSymbolName
                string = ""
            }
        case .script:
            symbolName = definition.showsSymbol ? WidgetDefinition.scriptSymbolName : nil
        }
        return drawnPicture(
            symbolName: symbolName,
            string: string,
            isMuted: text.isMuted,
            stateSymbolName: stateSymbolName(for: text.batteryState),
            fontSize: font.pointSize,
            height: ItemIconStore.drawnHeight,
            maximumTextWidth: maximumTextWidth
        )
    }

    /// Draws the parts side by side. It takes plain values only: the image's drawing block runs
    /// whenever and wherever the image is drawn, so it holds nothing of the main actor.
    nonisolated private static func drawnPicture(
        symbolName: String?,
        string: String,
        isMuted: Bool,
        stateSymbolName: String?,
        fontSize: CGFloat,
        height: CGFloat,
        maximumTextWidth: CGFloat?
    ) -> NSImage? {
        let gap = CGFloat(4)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let configuration = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
        func symbol(_ name: String?) -> NSImage? {
            name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
                .withSymbolConfiguration(configuration)
        }
        let leading = symbol(symbolName)
        let trailing = symbol(stateSymbolName)
        // A template image keeps only its shape, so a muted text is a lighter one.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black.withAlphaComponent(isMuted ? 0.55 : 1),
        ]
        let text = NSAttributedString(string: string, attributes: attributes)
        let textSize = text.size()
        // A script's line is cut with an ellipsis at the width of the widget's format.
        let textWidth = min(textSize.width, maximumTextWidth ?? textSize.width)
        let isCut = textWidth < textSize.width
        let cutText: NSAttributedString = {
            guard isCut else {
                return text
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            var cutAttributes = attributes
            cutAttributes[.paragraphStyle] = paragraph
            return NSAttributedString(string: string, attributes: cutAttributes)
        }()
        var width = textWidth
        if let leading {
            width += leading.size.width + (string.isEmpty ? 0 : gap)
        }
        if let trailing {
            width += gap + trailing.size.width
        }
        guard width > 0, height > 0 else {
            return nil
        }
        let image = NSImage(size: NSSize(width: width.rounded(.up), height: height), flipped: false) { bounds in
            var x = CGFloat.zero
            if let leading {
                let size = leading.size
                leading.draw(in: NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
                x += size.width + (string.isEmpty ? 0 : gap)
            }
            if !string.isEmpty {
                if isCut {
                    let rect = NSRect(x: x, y: (bounds.height - textSize.height) / 2, width: textWidth, height: textSize.height)
                    cutText.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                } else {
                    text.draw(at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2))
                }
                x += textWidth
            }
            if let trailing {
                let size = trailing.size
                trailing.draw(
                    in: NSRect(x: x + gap, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
                )
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Refreshing

    /// Gives the policy an event and does what it says.
    private func send(_ event: WidgetRefreshPolicy.Event, to runtime: Runtime) {
        let command = runtime.policy.handle(event, at: .now, date: Date(), calendar: Self.calendar)
        apply(command, to: runtime)
    }

    /// Does what the policy says: read, arm or cancel the one timer, show the en dash.
    private func apply(_ command: WidgetRefreshPolicy.Command, to runtime: Runtime) {
        if command.marksUnavailable {
            runtime.cpuBaseline = nil
            render(runtime, reading: .unavailable)
        }
        if command.refreshes {
            refresh(runtime)
        }
        switch command.timer {
        case .keep:
            break
        case .cancel:
            cancelWait(of: runtime)
        case .arm(let instant, let tolerance):
            arm(runtime, until: instant, tolerance: tolerance)
        }
        updatePowerSourceEvents()
    }

    /// Reads the widget's source once and draws the text. A script widget asks its script
    /// instead, and draws the line when the run ends.
    private func refresh(_ runtime: Runtime) {
        if runtime.definition.kind == .script {
            runScript(runtime, isUserAction: false)
            return
        }
        render(runtime, reading: sample(runtime))
    }

    /// The reading of the widget's source now; ``WidgetReading/unavailable`` when the source
    /// cannot be read, so the text shows the en dash and never an old value (D-13).
    private func sample(_ runtime: Runtime) -> WidgetReading {
        let definition = runtime.definition
        guard definition.kind == .text else {
            return .unavailable
        }
        switch definition.source {
        case .dateTime:
            return .date(Date())
        case .battery:
            guard let battery = PowerSources.internalBattery(), let percent = battery.percent else {
                return .unavailable
            }
            return .battery(percent: percent, state: battery.state)
        case .cpu:
            // A load needs two readings: the first after a reveal is only the baseline.
            guard let current = WidgetSamplers.cpuTicks() else {
                runtime.cpuBaseline = nil
                return .unavailable
            }
            let previous = runtime.cpuBaseline
            runtime.cpuBaseline = current
            guard let previous, let load = WidgetReadings.cpuLoad(from: previous, to: current) else {
                return .unavailable
            }
            return .fraction(load)
        case .memory:
            guard let memory = WidgetSamplers.memory() else {
                return .unavailable
            }
            if definition.preset == .gigabytesUsed {
                return .bytes(memory.used)
            }
            guard let fraction = WidgetReadings.usedFraction(used: memory.used, total: memory.total) else {
                return .unavailable
            }
            return .fraction(fraction)
        case .freeDisk:
            guard let disk = WidgetSamplers.diskSpace() else {
                return .unavailable
            }
            if definition.preset == .gigabytesFree {
                return disk.available >= 0 ? .bytes(UInt64(disk.available)) : .unavailable
            }
            guard let fraction = WidgetReadings.diskFreeFraction(available: disk.available, total: disk.total) else {
                return .unavailable
            }
            return .fraction(fraction)
        case .uptime:
            guard let boot = WidgetSamplers.bootDate(), let duration = WidgetReadings.uptime(now: Date(), boot: boot) else {
                return .unavailable
            }
            return .duration(duration)
        case .countdown:
            guard let target = definition.countdownTarget else {
                return .unavailable
            }
            return Countdown.reading(now: Date(), target: target)
        }
    }

    /// Replaces the widget's wait with a one-shot task that sleeps until the instant the policy
    /// gave, with the tolerance it gave, and then tells the policy.
    private func arm(_ runtime: Runtime, until instant: ContinuousClock.Instant, tolerance: Duration) {
        cancelWait(of: runtime)
        let id = runtime.definition.id
        let token = runtime.timerToken
        runtime.timer = Task { [weak self] in
            do {
                try await Task.sleep(until: instant, tolerance: tolerance, clock: ContinuousClock())
            } catch {
                return
            }
            self?.timerFired(id: id, token: token)
        }
    }

    private func cancelWait(of runtime: Runtime) {
        runtime.timerToken &+= 1
        runtime.timer?.cancel()
        runtime.timer = nil
    }

    private func timerFired(id: UUID, token: Int) {
        // A wait that was replaced or cancelled after it woke up is not the current one.
        guard let runtime = runtimes[id], runtime.timerToken == token else {
            return
        }
        runtime.timer = nil
        send(.timerFired, to: runtime)
    }

    // MARK: Script widgets

    /// What a script widget says to VoiceOver: its line, "Choose a script" while none is chosen,
    /// "Allow this script in Automation, Scripts" while the gate refuses it (D-27).
    private func scriptSpeech(for runtime: Runtime, reading: WidgetReading) -> String {
        let store = appState?.automation.scriptStore
        // Until the store is read nothing is known, so nothing is said to be missing.
        let hasScript = store.map { !$0.isLoaded || $0.widgetScript(for: runtime.definition.id) != nil } ?? false
        return WidgetSpeech.scriptValue(for: reading, hasScript: hasScript, isRefused: runtime.isScriptRefused)
    }

    /// A click on a script widget, or the user's own request in holzBar's pane: asks the script
    /// again at once. It skips only the 30 seconds between two runs, never the gate, the run
    /// limit or the check that the script is not already running (D-23).
    ///
    /// - Parameter isUserAction: `false` for an open that was not the user's click (a hotkey, a
    ///   hint, a group or a Shortcut), which keeps the 30 seconds (WR-02).
    func refreshScriptWidget(id: UUID, isUserAction: Bool = true) {
        guard let runtime = runtimes[id], runtime.definition.kind == .script else {
            return
        }
        runScript(runtime, isUserAction: isUserAction)
    }

    /// A real event of the system arrived: every script widget that is seen asks its script,
    /// at most every 30 seconds each (D-23).
    private func systemEventArrived() {
        for runtime in runtimes.values where runtime.definition.kind == .script && runtime.policy.isVisible {
            runScript(runtime, isUserAction: false)
        }
    }

    /// Waits for the script store to be read, once, so that script widgets that were revealed
    /// during start-up ask their script when it is ready. No polling: the store tells.
    private func followScriptStore() {
        guard let store = appState?.automation.scriptStore, !store.isLoaded else {
            return
        }
        scriptStoreLoop = ObservationLoop.observe { [weak store] in
            store?.isLoaded ?? true
        } onChange: { [weak self] isLoaded in
            guard isLoaded else {
                return
            }
            self?.scriptStoreLoop?.cancel()
            self?.scriptStoreLoop = nil
            self?.systemEventArrived()
        }
    }

    /// Asks the widget's script once and shows the line it printed.
    ///
    /// Nothing runs while the widget is not visible (hidden, asleep, locked), while a run of it
    /// is going, or when no script is chosen. Unless it is the user's own action, a widget is
    /// asked at most every 30 seconds; a request inside that time shows the line of the run
    /// before. The process is started by the runner and the gate of the scripts only.
    private func runScript(_ runtime: Runtime, isUserAction: Bool) {
        guard isActive, runtime.policy.isVisible, let automation = appState?.automation else {
            return
        }
        let store = automation.scriptStore
        // Until the store is read its bindings are not known; the end of the wait asks again.
        guard store.isLoaded else {
            return
        }
        guard let name = store.widgetScript(for: runtime.definition.id) else {
            runtime.scriptReading = .unavailable
            runtime.isScriptRefused = false
            render(runtime, reading: .unavailable)
            return
        }
        guard !runtime.isScriptRunning else {
            return
        }
        let now = ContinuousClock.now
        guard ScriptLimits.isWidgetAskDue(isUserAction: isUserAction, lastAsked: runtime.lastScriptStart, now: now) else {
            render(runtime, reading: runtime.scriptReading)
            return
        }
        runtime.lastScriptStart = now
        runtime.isScriptRunning = true
        runtime.isWaitingForScript = false
        let id = runtime.definition.id
        Task { [weak self] in
            let report = await automation.runWidgetScript(named: name)
            self?.scriptRunEnded(id: id, name: name, report: report)
        }
    }

    /// Takes in what a run left behind: the cleaned first line when it succeeded, an en dash
    /// when it failed, timed out or was refused (D-13). A run that did not start (busy, over the
    /// limit) changes nothing, except that a widget turned away because its script was busy does
    /// not wait the 30 seconds for its next ask: it takes over the result of the run that has the
    /// script, when that ends (WR-03).
    private func scriptRunEnded(id: UUID, name: String, report: ScriptRunReport) {
        guard let runtime = runtimes[id] else {
            return
        }
        runtime.isScriptRunning = false
        // Only the outcome is logged, as a private value: never the line or the script's name.
        logger.debug("A script widget ran: \(String(describing: report.outcome), privacy: .private)")
        takeIn(report, script: name, into: runtime)
        shareResult(of: report, from: id, script: name)
    }

    /// Shows what a run of the widget's script said, unless the binding changed meanwhile.
    private func takeIn(_ report: ScriptRunReport, script name: String, into runtime: Runtime) {
        // The binding was changed or removed while the script ran: this is not its line.
        let isStillBound = appState?.automation.scriptStore.widgetScript(for: runtime.definition.id) == name
        let outcome: ScriptOutcome = isStillBound ? report.outcome : .failed
        switch outcome {
        case .succeeded:
            runtime.scriptReading = .line(report.record?.displayLine ?? "")
            runtime.isScriptRefused = false
        case .failed, .timedOut:
            runtime.scriptReading = .unavailable
            runtime.isScriptRefused = false
        case .notAllowed:
            runtime.scriptReading = .unavailable
            runtime.isScriptRefused = true
        case .busy:
            // Another widget or a rule has the script. The 30 seconds are not spent: the widget
            // takes over the result of the run that ends, or asks again on the next event.
            runtime.lastScriptStart = nil
            runtime.isWaitingForScript = true
        case .rateLimited:
            break
        }
        // A result that arrives while the widget is hidden is kept and shown at the next reveal.
        if runtime.policy.isVisible {
            render(runtime, reading: runtime.scriptReading)
        }
    }

    /// Gives the result of a run to the widgets that were turned away because its script was
    /// busy and are still bound to it (WR-03). A run that did not start has no result to give.
    private func shareResult(of report: ScriptRunReport, from id: UUID, script name: String) {
        switch report.outcome {
        case .busy, .rateLimited:
            return
        case .succeeded, .failed, .timedOut, .notAllowed:
            break
        }
        var waiting = [UUID: String]()
        for (otherID, runtime) in runtimes where runtime.isWaitingForScript {
            if let bound = appState?.automation.scriptStore.widgetScript(for: otherID) {
                waiting[otherID] = bound
            }
        }
        for otherID in WidgetScriptSharing.takingOver(script: name, finished: id, waiting: waiting) {
            guard let other = runtimes[otherID] else {
                continue
            }
            other.isWaitingForScript = false
            takeIn(report, script: name, into: other)
        }
    }

    // MARK: Observers

    /// Follows the notifications that change what a widget shows or how often: the clock, the
    /// day, the time zone, Low Power Mode and the locale. They exist only while the module is
    /// on (D-15, D-16).
    private func startObservers() {
        let clockChanges: [Notification.Name] = [.NSSystemClockDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange]
        for name in clockChanges {
            observe(name) { widgets in
                widgets.sendToAll(.clockChanged)
            }
        }
        observe(.NSProcessInfoPowerStateDidChange) { widgets in
            widgets.sendToAll(.lowPowerMode(ProcessInfo.processInfo.isLowPowerModeEnabled))
        }
        observe(NSLocale.currentLocaleDidChangeNotification) { widgets in
            widgets.localeChanged()
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (MenuBarWidgets) -> Void) {
        observerTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard let self else {
                    return
                }
                handler(self)
            }
        })
    }

    private func sendToAll(_ event: WidgetRefreshPolicy.Event) {
        for runtime in runtimes.values {
            send(event, to: runtime)
        }
    }

    /// Measures every length again, draws the last reading in the new format and tells the
    /// policies, so a change of the language or the region never leaves a clipped text.
    private func localeChanged() {
        for runtime in runtimes.values {
            configure(runtime)
            render(runtime, reading: runtime.reading)
            send(.cadenceChanged(WidgetCadence(definition: runtime.definition)), to: runtime)
        }
    }

    /// Whether a battery widget is visible. The battery has no timer: the widget is read when it
    /// is revealed and when the power source says it changed.
    private var needsPowerSourceEvents: Bool {
        isActive && runtimes.values.contains { runtime in
            runtime.definition.kind == .text && runtime.definition.source == .battery && runtime.policy.isVisible
        }
    }

    /// Asks for power source events while a battery widget is visible, and gives them back when
    /// none is (D-15). The run loop source is shared with the automation rules.
    private func updatePowerSourceEvents() {
        let isNeeded = needsPowerSourceEvents
        guard isNeeded != (batteryTask != nil) else {
            return
        }
        if isNeeded {
            PowerSourceEvents.shared.begin()
            batteryTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .powerSourcesDidChange) {
                    self?.powerSourcesChanged()
                }
            }
        } else {
            batteryTask?.cancel()
            batteryTask = nil
            PowerSourceEvents.shared.end()
        }
    }

    private func powerSourcesChanged() {
        for runtime in runtimes.values where runtime.definition.kind == .text && runtime.definition.source == .battery {
            send(.sourceChanged, to: runtime)
        }
    }
}
