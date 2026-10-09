//
//  HolzBarIntents.swift
//  holzBar
//

import AppIntents

// Shortcuts actions (App Intents). They run the same code as holzBar's hotkeys and menu,
// inside holzBar, without a script, a command line tool or a new permission. An action
// only does what the user put into a shortcut, so nothing here asks first (unlike
// `holzbar://profile/<name>`, which any app can open).

// MARK: - Errors

/// Why a Shortcuts action could not run.
nonisolated enum HolzBarIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// holzBar has not finished starting, or waits for its permissions.
    case notReady
    /// The section is turned off in holzBar's settings.
    case sectionUnavailable
    /// No menu bar item's name matches what the shortcut asked for.
    case noMatchingItem(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            "holzBar is not ready yet. Open holzBar and grant its permissions first."
        case .sectionUnavailable:
            "This section is turned off in holzBar's settings."
        case .noMatchingItem(let name):
            "No menu bar item matches \u{201C}\(name)\u{201D}."
        }
    }
}

/// The app's state for an action, or an error when holzBar is not ready.
@MainActor
private func intentAppState() throws -> AppState {
    guard let appState = AppState.current, appState.isSetUp else {
        throw HolzBarIntentError.notReady
    }
    return appState
}

// MARK: - Zen Mode

/// Turns Zen mode on or off.
nonisolated struct ToggleZenModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Zen Mode"

    @MainActor
    func perform() async throws -> some IntentResult {
        try intentAppState().menuBarManager.toggleZenMode()
        return .result()
    }
}

// MARK: - Sections

/// A menu bar section a shortcut can show, hide or toggle.
nonisolated enum MenuBarSectionAppEnum: String, AppEnum {
    case hidden
    case alwaysHidden

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Menu Bar Section"

    static let caseDisplayRepresentations: [MenuBarSectionAppEnum: DisplayRepresentation] = [
        .hidden: "Hidden",
        .alwaysHidden: "Always Hidden",
    ]
}

/// What a shortcut does with a section.
nonisolated enum SectionActionAppEnum: String, AppEnum {
    case show
    case hide
    case toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Section Action"

    static let caseDisplayRepresentations: [SectionActionAppEnum: DisplayRepresentation] = [
        .show: "Show",
        .hide: "Hide",
        .toggle: "Toggle",
    ]
}

/// Shows, hides or toggles a menu bar section.
struct ChangeSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Section"

    @Parameter(title: "Action", default: .toggle)
    var sectionAction: SectionActionAppEnum

    @Parameter(title: "Section", default: .hidden)
    var section: MenuBarSectionAppEnum

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = try intentAppState().menuBarManager
        let name: MenuBarSection.Name = switch section {
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
        guard let target = manager.section(withName: name), target.isEnabled else {
            throw HolzBarIntentError.sectionUnavailable
        }
        switch sectionAction {
        case .show:
            target.show()
            manager.showOnHoverAllowed = false
        case .hide:
            target.hide()
        case .toggle:
            target.toggle()
        }
        return .result()
    }
}

// MARK: - Layout Profiles

/// A saved layout profile, identified by its name.
nonisolated struct LayoutProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Layout Profile"

    static let defaultQuery = LayoutProfileQuery()

    /// The profile's name.
    let id: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

/// Lists the saved layout profiles for Shortcuts.
nonisolated struct LayoutProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [LayoutProfileEntity] {
        let names = Set(try intentAppState().profiles.profiles.map(\.name))
        return identifiers.filter { names.contains($0) }.map { LayoutProfileEntity(id: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LayoutProfileEntity] {
        try intentAppState().profiles.profiles.map { LayoutProfileEntity(id: $0.name) }
    }
}

/// Applies a saved layout profile.
struct ApplyLayoutProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Layout Profile"

    @Parameter(title: "Profile")
    var profile: LayoutProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try intentAppState().profiles.apply(named: profile.id)
        return .result()
    }
}

// MARK: - Automation Rules

/// An automation rule, identified by its identifier.
nonisolated struct AutomationRuleEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Automation Rule"

    static let defaultQuery = AutomationRuleQuery()

    /// The rule's identifier.
    let id: String

    /// The rule's name.
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Lists the automation rules for Shortcuts.
nonisolated struct AutomationRuleQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [AutomationRuleEntity] {
        try intentAppState().automation.rules
            .filter { identifiers.contains($0.id.uuidString) }
            .map { AutomationRuleEntity(id: $0.id.uuidString, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AutomationRuleEntity] {
        try intentAppState().automation.rules.map { AutomationRuleEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

/// Turns an automation rule on or off. Rules are created and edited only in the settings.
struct SetAutomationRuleIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Automation Rule On or Off"

    @Parameter(title: "Rule")
    var rule: AutomationRuleEntity

    @Parameter(title: "Turn On", default: true)
    var isEnabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = try intentAppState().automation
        guard let id = UUID(uuidString: rule.id) else {
            return .result()
        }
        manager.setRule(withID: id, enabled: isEnabled)
        return .result()
    }
}

/// Returns the names of the automation rules that are true now.
struct GetActiveAutomationRulesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Active Automation Rules"

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let manager = try intentAppState().automation
        return .result(value: manager.activeRules.map(\.name))
    }
}

// MARK: - Menu Bar Items

/// Opens the menu of the menu bar item whose name matches best.
struct OpenMenuBarItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Menu Bar Item"

    @Parameter(title: "Name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let itemManager = try intentAppState().itemManager
        let items = itemManager.itemCache.managedItems.filter { !$0.isControlItem }
        guard
            name.contains(where: { !$0.isWhitespace }),
            let item = FuzzyMatch.rank(items, query: name, key: { $0.displayName }).first
        else {
            throw HolzBarIntentError.noMatchingItem(name)
        }
        // The shortcut goes on while the menu is open; the item is hidden again later.
        Task {
            await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: nil)
        }
        return .result()
    }
}

/// Opens the menu bar item search.
nonisolated struct SearchMenuBarItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Menu Bar Items"

    @MainActor
    func perform() async throws -> some IntentResult {
        try intentAppState().menuBarManager.searchPanel.show()
        return .result()
    }
}

// MARK: - App Shortcuts

/// The actions Shortcuts and Spotlight offer without any setup. Main-actor isolated, like
/// the actions with parameters (whose parameter wrappers keep them off `nonisolated`).
struct HolzBarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleZenModeIntent(),
            phrases: ["Toggle Zen mode in \(.applicationName)"],
            shortTitle: "Zen Mode",
            systemImageName: "moon"
        )
        AppShortcut(
            intent: ChangeSectionIntent(),
            phrases: ["Toggle hidden items in \(.applicationName)"],
            shortTitle: "Change Section",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: ApplyLayoutProfileIntent(),
            phrases: ["Apply a layout profile in \(.applicationName)"],
            shortTitle: "Apply Layout Profile",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: OpenMenuBarItemIntent(),
            phrases: ["Open a menu bar item with \(.applicationName)"],
            shortTitle: "Open Menu Bar Item",
            systemImageName: "menubar.rectangle"
        )
        AppShortcut(
            intent: SearchMenuBarItemsIntent(),
            phrases: ["Search menu bar items with \(.applicationName)"],
            shortTitle: "Search Menu Bar Items",
            systemImageName: "magnifyingglass"
        )
    }
}
