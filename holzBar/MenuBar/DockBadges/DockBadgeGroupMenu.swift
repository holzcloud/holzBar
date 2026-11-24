//
//  DockBadgeGroupMenu.swift
//  holzBar
//

import AppKit

/// The native menu a group's item of Dock badges opens: a section header with the group's name,
/// then one item for each of its apps with the app's icon, its name and the menu's own trailing
/// badge (the count, or the label; none for an app without a badge), the apps with a badge first.
/// Choosing an app opens it or brings it forward, as a click in the Dock does.
///
/// The menu is built when it opens, from the badges the module already holds in memory; it reads
/// nothing from the Dock. The system draws it, so it has no look of its own. What a choice opens
/// is the bundle identifier stored with the item, resolved through `NSWorkspace`; the text of a
/// badge never chooses an app. Names and badges stay in memory and are never logged.
@MainActor
enum DockBadgeGroupMenu {
    /// The most characters of a label that is not a number the menu shows; a longer one is cut
    /// with "…", so a badge text of any length cannot widen the menu.
    private static let labelCharacterLimit = 24

    /// What a choice in the menu does: opens the app whose bundle identifier the item carries. The
    /// menu holds its items and an item holds its target weakly, so one target lives here.
    private final class Target: NSObject {
        @objc func chosen(_ sender: NSMenuItem) {
            guard let bundleID = sender.representedObject as? String else {
                return
            }
            DockBadgeItems.open(bundleID)
        }
    }

    private static let target = Target()

    /// The menu of a group.
    ///
    /// - Parameters:
    ///   - title: The group's name, shown in the section header.
    ///   - members: The bundle identifiers of the group's chosen apps, in the group's order.
    ///   - labels: The badge of each app by bundle identifier; an app without an entry has none.
    static func menu(title: String, members: [String], labels: [String: DockBadgeLabel]) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: title))
        for bundleID in DockBadgeSum.menuOrder(members, labels: labels) {
            let name = BuiltInItemActions.applicationName(forBundleID: bundleID) ?? bundleID
            let item = NSMenuItem(title: name, action: #selector(Target.chosen(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = bundleID
            item.image = icon(forBundleID: bundleID)
            item.badge = badge(for: labels[bundleID] ?? .none)
            menu.addItem(item)
        }
        return menu
    }

    /// The trailing badge of an app: its count, or its label; none while there is no badge.
    private static func badge(for label: DockBadgeLabel) -> NSMenuItemBadge? {
        switch label {
        case .count(let number) where number > 0:
            return NSMenuItemBadge(count: number)
        case .mark(let text):
            let shown = text.count > labelCharacterLimit ? String(text.prefix(labelCharacterLimit - 1)) + "…" : text
            return NSMenuItemBadge(string: shown)
        case .count, .none:
            return nil
        }
    }

    /// The app's icon at the menu's icon size, or `nil` when the app is not installed.
    private static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let url = BuiltInItemActions.applicationURL(forBundleID: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        let edge = CGFloat(DesignTokens.DockBadge.iconSize)
        image.size = NSSize(width: edge, height: edge)
        return image
    }
}
