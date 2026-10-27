//
//  ModuleCatalog.swift
//  holzBar
//

import Foundation

/// The areas modules are grouped in, in the order the settings gallery shows them.
nonisolated enum ModuleArea: String, CaseIterable, Sendable {
    case menuBar
    case notch
    case monitor
    case launcher
    case clipboard
    case windows
    case input
    case sound
    case display
    case capture
    case system
    case intelligence
}

/// A permission a module asks for when it is switched on, never earlier.
nonisolated enum ModulePermission: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording
    case inputMonitoring
    case microphone
    case camera
    case calendar
    case bluetooth
    case notifications
    case fullDiskAccess
    case files
}

/// What holzBar knows about one optional module before the module's code is loaded.
///
/// A module that is off costs nothing: it runs no timer, holds no memory and has asked for no
/// permission. Everything the settings gallery needs to show its card is in this value; the
/// module's own code is touched only once the user switches it on.
nonisolated struct ModuleDescriptor: Equatable, Sendable, Identifiable {
    /// A stable identifier, lowercase words joined by hyphens, such as "notch-hub". It is
    /// stored with the user's choices and never changes.
    let id: String
    let area: ModuleArea
    /// The name of the SF Symbol on the module's card.
    let symbol: String
    /// The key of the module's title in the string catalog.
    let titleKey: String
    /// The key of the module's one-line description in the string catalog.
    let summaryKey: String
    /// The permission the module asks for when it is switched on, if any.
    let permission: ModulePermission?
    /// Whether the module is built but not yet tested on a Mac. Its row carries the Preview
    /// badge until it has been.
    var isPreview = false
}

/// The list of modules and the rules it must keep.
nonisolated enum ModuleCatalog {
    /// Every module holzBar ships. Modules are added with the release that brings them.
    ///
    /// Widgets are off until the user switches them on, ask for no permission and cost nothing
    /// while off: no status item, no timer and no sampler (D-06). Drag in the Menu Bar is off
    /// until the user switches it on, asks for no permission beyond holzBar's Accessibility and
    /// runs no tap while off. Apple Items is off until the user switches it on, asks for no
    /// permission beyond holzBar's Accessibility and changes no assertion while off. The Notch hub
    /// is off until the user switches it on, asks for no permission and creates nothing while
    /// off: no window, no monitor and no module of its own. The title and the summary are the
    /// English strings the settings show; their keys are those strings.
    static let all: [ModuleDescriptor] = [
        ModuleDescriptor(
            id: "widgets",
            area: .menuBar,
            symbol: "clock",
            titleKey: "Widgets",
            summaryKey: "Readouts, app launchers, a timer and media controls of your own in the menu bar.",
            permission: nil
        ),
        ModuleDescriptor(
            id: "menu-bar-drag",
            area: .menuBar,
            symbol: "arrow.left.arrow.right",
            titleKey: "Drag in the Menu Bar",
            summaryKey: "Move menu bar items by dragging them, without holding ⌘ Command.",
            permission: nil
        ),
        ModuleDescriptor(
            id: "apple-items",
            area: .menuBar,
            symbol: "menubar.rectangle",
            titleKey: "Apple Items",
            summaryKey: "Hide the clock or Control Center, and keep Apple items one click away on macOS 27.",
            permission: nil
        ),
        ModuleDescriptor(
            id: "notch-hub",
            area: .notch,
            symbol: "capsule.tophalf.filled",
            titleKey: "Notch hub",
            summaryKey: "A panel at the notch for the modules you switch on.",
            permission: nil
        ),
    ]

    /// The modules of an area, in catalog order.
    static func modules(in area: ModuleArea, of list: [ModuleDescriptor] = all) -> [ModuleDescriptor] {
        list.filter { $0.area == area }
    }

    /// The areas that have at least one module, in the gallery's order.
    static func populatedAreas(of list: [ModuleDescriptor] = all) -> [ModuleArea] {
        ModuleArea.allCases.filter { area in list.contains { $0.area == area } }
    }

    /// Whether an identifier has the required form: lowercase letters and digits in words
    /// joined by single hyphens.
    static func isValidIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.count <= 40 else {
            return false
        }
        let words = identifier.split(separator: "-", omittingEmptySubsequences: false)
        return words.allSatisfy { word in
            !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
        }
    }

    /// The problems of a list: identifiers that are malformed or used twice, and empty keys.
    /// A list without problems returns an empty array.
    static func problems(in list: [ModuleDescriptor]) -> [String] {
        var problems = [String]()
        var seen = Set<String>()
        for module in list {
            if !isValidIdentifier(module.id) {
                problems.append("Malformed identifier: \(module.id)")
            }
            if !seen.insert(module.id).inserted {
                problems.append("Identifier used twice: \(module.id)")
            }
            if module.symbol.isEmpty || module.titleKey.isEmpty || module.summaryKey.isEmpty {
                problems.append("Empty symbol or key: \(module.id)")
            }
        }
        return problems
    }

    /// The identifiers of the user's enabled modules that still exist, so that an identifier
    /// left behind by a module that was removed never counts.
    static func enabledIdentifiers(_ stored: [String], knownTo list: [ModuleDescriptor] = all) -> Set<String> {
        let known = Set(list.map(\.id))
        return Set(stored).intersection(known)
    }
}

/// How full a gauge is, as the three levels the design uses for it.
nonisolated enum GaugeLevel: Sendable {
    case normal
    case elevated
    case critical

    /// The level of a fraction from 0 to 1. Values outside that range count as the nearest
    /// end; a value that is not a number counts as normal.
    static func level(for fraction: Double) -> GaugeLevel {
        guard fraction.isFinite else {
            return .normal
        }
        switch min(max(fraction, 0), 1) {
        case ..<0.6: return .normal
        case ..<0.85: return .elevated
        default: return .critical
        }
    }
}
