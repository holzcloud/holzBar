//
//  SettingsNavigationIdentifier.swift
//  holzBar
//

/// The navigation identifier type for the "Settings" interface.
nonisolated enum SettingsNavigationIdentifier: String, NavigationIdentifier {
    case general = "General"
    case menuBarLayout = "Menu Bar Layout"
    case menuBarAppearance = "Menu Bar Appearance"
    case automation = "Automation"
    case modules = "Modules"
    case hotkeys = "Hotkeys"
    case advanced = "Advanced"
    case about = "About"

    /// The panes about the menu bar, the first group of the sidebar.
    static let menuBarGroup: [SettingsNavigationIdentifier] = [.menuBarLayout, .menuBarAppearance, .automation]

    /// The pane that lists the optional modules, the second group of the sidebar.
    static let modulesGroup: [SettingsNavigationIdentifier] = [.modules]

    /// The panes about holzBar itself, the third group of the sidebar.
    static let appGroup: [SettingsNavigationIdentifier] = [.general, .hotkeys, .advanced, .about]

    @MainActor var iconResource: IconResource {
        switch self {
        case .general: .systemSymbol("gearshape")
        case .menuBarLayout: .systemSymbol("rectangle.topthird.inset.filled")
        case .menuBarAppearance: .systemSymbol("swatchpalette")
        case .automation: .systemSymbol("bolt")
        case .modules: .systemSymbol("square.grid.2x2")
        case .hotkeys: .systemSymbol("keyboard")
        case .advanced: .systemSymbol("gearshape.2")
        case .about: .assetCatalog(.logoStroke)
        }
    }
}
