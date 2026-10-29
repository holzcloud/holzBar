//
//  HubModule.swift
//  holzBar
//

// This file is the stable interface of the Notch hub, version 1.
//
// Every module of the hub is built against it: Now Playing, the calendar, live activities,
// timers, file drop, display controls, accessory alerts, and the system readouts. It grows
// only by members that come with a default implementation in a protocol extension. Nothing
// here is renamed, removed or re-typed once a module has shipped against it. A module is
// three things: a ``ModuleDescriptor`` in ``ModuleCatalog`` (area notch; its place in the
// list is its tab order), a ``HubModuleRegistration`` in ``HubModules`` and a class that
// conforms to ``HubModuleRuntime``. A module never touches the panel, the tab strip or the
// geometry, and the hub never imports a module.

import CoreGraphics
import SwiftUI

/// The colour a module wears in the hub: its tab when selected, and its tile.
///
/// The cases map to colours of the theme, so a module cannot bring a colour of its own.
enum HubTint: Sendable {
    /// holzBar's accent, the Overview's and the default.
    case accent
    /// Amber, for clipboard-like modules.
    case amber
    /// Red, for timers and alerts.
    case red
    /// Green, for states that are fine.
    case green
    /// Violet, for modules that need a permission.
    case violet
    /// White at 70 percent, for modules without a colour of their own.
    case neutral

    /// The colour in the hub, which is always dark.
    var color: Color {
        switch self {
        case .accent: HolzBarTheme.Palette.accent
        case .amber: HolzBarTheme.Palette.warning
        case .red: HolzBarTheme.Palette.danger
        case .green: HolzBarTheme.Palette.success
        case .violet: HolzBarTheme.Palette.permission
        case .neutral: HolzBarTheme.Hub.neutral
        }
    }
}

/// A module's card on the Overview: the same inputs as ``HubWidget``.
struct HubTile {
    /// The name of the SF Symbol inside the ring.
    var symbol: String
    /// What is measured.
    var title: Text
    /// The value, already formatted.
    var value: String
    /// The unit, if any.
    var unit: Text?
    /// One quiet extra line, if any.
    var detail: Text?
    /// The share of the limit from 0 to 1, or `nil` for a state without a level.
    var fraction: Double?

    init(
        symbol: String,
        title: Text,
        value: String,
        unit: Text? = nil,
        detail: Text? = nil,
        fraction: Double? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.value = value
        self.unit = unit
        self.detail = detail
        self.fraction = fraction
    }
}

/// A module's small status in the hub's right wing, such as the battery or the time.
struct HubStatusPill {
    /// The name of an SF Symbol before the text, if any.
    var symbol: String?
    /// The text, which is short.
    var text: String
    /// What VoiceOver reads instead of the text.
    var accessibilityLabel: Text

    init(symbol: String? = nil, text: String, accessibilityLabel: Text) {
        self.symbol = symbol
        self.text = text
        self.accessibilityLabel = accessibilityLabel
    }
}

/// What a module may ask of the hub. The hub's controller implements it.
@MainActor
protocol HubHost: AnyObject {
    /// Whether the hub is open.
    var isOpen: Bool { get }

    /// The display the hub is open on, or `nil` while it is closed.
    var screenID: CGDirectDisplayID? { get }

    /// Shows the tab of a module, or the Overview for an identifier that has no tab.
    func select(moduleID: String)

    /// Closes the hub.
    func close()

    /// Closes the hub and opens holzBar's Settings at the modules, where the module's settings
    /// are.
    func openSettings(for moduleID: String)

    /// Asks the hub to take the keyboard, so that a text field in a module's body can be typed
    /// into. A module whose body has a text field calls it when the field gains focus. The
    /// hub makes its panel the key window, as it is for a hub opened by its hotkey, without
    /// making holzBar the active app. The default does nothing.
    func takeKeyboard()
}

extension HubHost {
    func takeKeyboard() {}
}

/// The running part of a hub module.
///
/// The object does not exist until both the hub and the module are switched on, and the hub
/// calls ``shutDown()`` and releases it the moment either goes off (``HubModuleLifecycle``).
/// Everything the module holds lives and dies with it.
@MainActor
protocol HubModuleRuntime: AnyObject {
    /// The identifier of the module's descriptor in ``ModuleCatalog``.
    var moduleID: String { get }

    /// The colour of the module's tab and tile. The default is the accent.
    var tint: HubTint { get }

    /// Whether the module has a tab in the icon strip. The default is `true`.
    var offersTab: Bool { get }

    /// The module's card on the Overview, or `nil` for none. The hub reads it while it draws,
    /// so a tile that reads observable state follows it. The default is `nil`.
    var tile: HubTile? { get }

    /// The module's status in the right wing, or `nil` for none. The default is `nil`.
    var statusPill: HubStatusPill? { get }

    /// The body of the module's tab. The hub calls it only while the hub is open and the tab
    /// is selected; the view fills the hub's one body area and scrolls if it needs more.
    func makeBody(host: any HubHost) -> AnyView

    /// Tells the module that the hub opened or closed, so it can pause cheap work while the
    /// hub is closed. The default does nothing.
    func hubVisibilityDidChange(isOpen: Bool)

    /// Releases every task, observer, timer and byte the module holds. The hub calls it once,
    /// before it drops the object.
    func shutDown()
}

extension HubModuleRuntime {
    var tint: HubTint { .accent }

    var offersTab: Bool { true }

    var tile: HubTile? { nil }

    var statusPill: HubStatusPill? { nil }

    func hubVisibilityDidChange(isOpen: Bool) {}
}

/// How a hub module is created and configured. One line in ``HubModules/all`` per module.
struct HubModuleRegistration {
    /// The identifier of the module's descriptor in ``ModuleCatalog``.
    var id: String

    /// Creates the runtime. Called when the hub and the module are both on, and not before.
    var makeRuntime: @MainActor (AppState) -> any HubModuleRuntime

    /// The module's settings, shown under its row in the Modules pane while it is on.
    var makeSettings: @MainActor () -> AnyView
}
