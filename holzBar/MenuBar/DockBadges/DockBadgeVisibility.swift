//
//  DockBadgeVisibility.swift
//  holzBar
//

import Foundation

/// Where the menu bar items of Dock badges stand: which are in a section the bar shows, which are
/// in a section macOS 27 does not draw, and whether the Mac is not in use.
///
/// The widgets ask the same three questions of their own items; the answers are computed here for
/// the badge items so that the widgets' file stays as it is. Every read is of observable state, so
/// one ``ObservationLoop`` over ``inputs(for:in:)`` follows all of it.
@MainActor
enum DockBadgeVisibility {
    /// The answers for a set of items, by autosave name.
    nonisolated struct Inputs: Equatable, Sendable {
        /// The items in a section that is shown. The visible section always counts while the Mac
        /// is in use; the hidden and always-hidden sections count while they are not hidden; an
        /// item the cache does not hold yet counts as shown. A reader that wants to read only while
        /// an item can be seen follows this set.
        var shown = Set<String>()
        /// The items that are collapsed to nothing: in a section the bar does not draw, on macOS 27
        /// only, where holzBar cannot conceal an item of its own and collapses it instead.
        var collapsed = Set<String>()
        /// Whether the Mac is asleep, locked or away.
        var isPaused = false
    }

    /// The answers for the items with the given autosave names.
    static func inputs(for names: [String], in appState: AppState) -> Inputs {
        var inputs = Inputs()
        inputs.isPaused = appState.systemActivityMonitor.isPaused
        let wanted = Set(names)
        guard !wanted.isEmpty else {
            return inputs
        }
        // The section of the item cache that holds each item; the first one that does, in the
        // order of the sections.
        let cache = appState.itemManager.itemCache
        var sections = [String: MenuBarSection.Name]()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where item.tag.namespace == .holzBar && wanted.contains(item.tag.title) {
                if sections[item.tag.title] == nil {
                    sections[item.tag.title] = section
                }
            }
        }
        for name in wanted where isShown(sections[name], in: appState) {
            inputs.shown.insert(name)
        }
        if #available(macOS 27.0, *) {
            for name in wanted {
                guard let section = sections[name] else {
                    continue
                }
                // It follows the state the concealment of the items beside it follows, which is
                // not the same as being shown: with the Shelf the bar stays concealed while the
                // Shelf shows the section, and the item keeps its picture for the Shelf all the
                // same.
                if !appState.concealer27.reveals(MacOS27Section(section)) {
                    inputs.collapsed.insert(name)
                }
            }
        }
        return inputs
    }

    /// Whether the section of an item is shown; an item the cache does not hold yet is.
    private static func isShown(_ section: MenuBarSection.Name?, in appState: AppState) -> Bool {
        guard let section, section != .visible else {
            return true
        }
        return appState.menuBarManager.section(withName: section)?.isHidden == false
    }
}
