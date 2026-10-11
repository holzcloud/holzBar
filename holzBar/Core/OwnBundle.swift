//
//  OwnBundle.swift
//  holzBar
//

import Foundation

/// holzBar's own bundle and its widgets, in the places that name applications.
///
/// On macOS 27 the saved layout (`Defaults.Key.macOS27Layout`) hides whole applications by
/// bundle identifier, and a widget is an item of holzBar's own process. A widget is keyed by its
/// autosave name there, never by holzBar's bundle: an entry for holzBar's bundle would conceal
/// holzBar's own icon and dividers. Every place that turns an item into an application key
/// goes through this type, so none of them can write that entry.
///
/// The bundle identifier is always a parameter, so the app passes `Constants.bundleIdentifier`
/// and this file keeps no second copy of it.
nonisolated enum OwnBundle {
    /// Whether an identifier is holzBar's own bundle identifier, whatever its case.
    ///
    /// A widget's autosave name is not: it is a layout key of its own.
    static func matches(_ id: String, bundleIdentifier: String) -> Bool {
        id.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }

    /// The layout without the entry for holzBar's own bundle.
    ///
    /// - Parameters:
    ///   - layout: The sections by application key.
    ///   - bundleIdentifier: holzBar's own bundle identifier.
    static func removing<Value>(from layout: [String: Value], bundleIdentifier: String) -> [String: Value] {
        guard layout.keys.contains(where: { matches($0, bundleIdentifier: bundleIdentifier) }) else {
            return layout
        }
        return layout.filter { !matches($0.key, bundleIdentifier: bundleIdentifier) }
    }

    /// The autosave name of the widget an item's identity key stands for (`namespace:title`,
    /// possibly with a number for a second item of the same title), or `nil` when the key is
    /// not a widget's: another namespace, or a title that is no widget's autosave name.
    static func widgetAutosaveName(inItemKey key: String, bundleIdentifier: String) -> String? {
        guard let colon = key.firstIndex(of: ":") else {
            return nil
        }
        guard matches(String(key[..<colon]), bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let title = String(key[key.index(after: colon)...].prefix { $0 != ":" })
        return WidgetDefinition.isAutosaveName(title) ? title : nil
    }

    /// The key an item's identity key has in the saved macOS 27 layout, or `nil` when the item
    /// has none: a widget's autosave name, or the namespace (the bundle identifier of the
    /// item's application) of any other item. holzBar's own bundle and namespaces that are no
    /// bundle identifiers (the UUIDs of system items) have none.
    ///
    /// - Parameters:
    ///   - key: The item's identity key (`namespace:title`).
    ///   - itemLayoutKey: The layout key of the item itself (`MenuBarItem.layoutKey27`) when the
    ///     item is known, which is the better answer: a widget's autosave name, or the bundle
    ///     of the application that really owns the item. It is used unless it is holzBar's own
    ///     bundle.
    ///   - bundleIdentifier: holzBar's own bundle identifier.
    static func layoutKey(forItemKey key: String, itemLayoutKey: String? = nil, bundleIdentifier: String) -> String? {
        if let itemLayoutKey {
            return matches(itemLayoutKey, bundleIdentifier: bundleIdentifier) ? nil : itemLayoutKey
        }
        if let name = widgetAutosaveName(inItemKey: key, bundleIdentifier: bundleIdentifier) {
            return name
        }
        let namespace = String(key.prefix { $0 != ":" })
        guard
            SharedProfile.isValidBundleIdentifier(namespace),
            !matches(namespace, bundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        return namespace
    }
}
