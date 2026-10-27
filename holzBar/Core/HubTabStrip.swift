//
//  HubTabStrip.swift
//  holzBar
//

import Foundation

/// The rules of the Notch hub's icon strip: which tabs are visible, which are in the More menu
/// and which tab is selected.
///
/// The Overview is always the first tab. The modules follow in catalog order. At most
/// ``maximumVisible`` tabs are visible; the rest are in the More menu, except that the
/// selected tab is always visible: it takes the place of the last visible tab, and the tab it
/// displaces joins the menu.
nonisolated enum HubTabStrip {
    /// The identifier of the Overview, the first tab.
    static let overviewID = "overview"

    /// How many tabs fit in the left wing.
    static let maximumVisible = 5

    /// What the strip shows.
    nonisolated struct Layout: Equatable, Sendable {
        /// The tabs in the strip, in order.
        var visible: [String]
        /// The tabs in the More menu, in catalog order.
        var overflow: [String]
        /// The selected tab, which is always one of the tabs.
        var selected: String
    }

    /// The strip for the module tabs and a selection.
    ///
    /// - Parameters:
    ///   - moduleTabs: The modules that offer a tab, in catalog order. A duplicate and a stray
    ///     Overview are dropped.
    ///   - selected: The wanted tab. One that is not a tab becomes the Overview.
    ///   - maximumVisible: How many tabs are visible; below 1 counts as 1.
    static func layout(
        moduleTabs: [String],
        selected: String,
        maximumVisible: Int = HubTabStrip.maximumVisible
    ) -> Layout {
        let tabs = allTabs(moduleTabs)
        let selected = tabs.contains(selected) ? selected : overviewID
        let limit = max(maximumVisible, 1)
        guard tabs.count > limit else {
            return Layout(visible: tabs, overflow: [], selected: selected)
        }
        var visible = Array(tabs.prefix(limit))
        if !visible.contains(selected) {
            visible = Array(visible.prefix(limit - 1)) + [selected]
        }
        let overflow = tabs.filter { !visible.contains($0) }
        return Layout(visible: visible, overflow: overflow, selected: selected)
    }

    /// How many tabs are visible in a wing of the given width, so that the strip, with its More
    /// button where tabs overflow, never reaches past the wing into the clearance of the notch.
    ///
    /// - Parameters:
    ///   - tabCount: The number of tabs, the Overview included.
    ///   - wingWidth: The width of the wing.
    ///   - tabWidth: The width of a tab.
    ///   - gap: The space between tabs.
    ///   - maximum: The most tabs ever visible.
    /// - Returns: At least 1.
    static func visibleCapacity(
        tabCount: Int,
        wingWidth: Double,
        tabWidth: Double,
        gap: Double,
        maximum: Int = HubTabStrip.maximumVisible
    ) -> Int {
        let unit = tabWidth + gap
        guard wingWidth.isFinite, unit.isFinite, unit > 0 else {
            return 1
        }
        let slots = max(Int(((wingWidth + gap) / unit).rounded(.down)), 0)
        let limit = min(maximum, slots)
        if tabCount <= limit {
            return max(limit, 1)
        }
        // The More button takes a slot.
        return max(min(maximum, slots - 1), 1)
    }

    /// The tab a step of the arrow keys leads to, wrapping at both ends.
    ///
    /// - Parameters:
    ///   - current: The tab the step starts from. One that is not in the list steps from the
    ///     Overview.
    ///   - delta: How far to step; negative steps back.
    ///   - tabs: All tabs, the Overview first.
    static func step(from current: String, by delta: Int, in tabs: [String]) -> String {
        guard !tabs.isEmpty else {
            return overviewID
        }
        let start = tabs.firstIndex(of: current) ?? tabs.firstIndex(of: overviewID) ?? 0
        let count = tabs.count
        let index = ((start + delta) % count + count) % count
        return tabs[index]
    }

    /// The tab to show when the hub starts: the remembered one if it is a tab now, else the
    /// Overview.
    static func remembered(lastTab: String?, available: [String]) -> String {
        guard let lastTab, allTabs(available).contains(lastTab) else {
            return overviewID
        }
        return lastTab
    }

    /// The Overview followed by the module tabs, each once.
    static func allTabs(_ moduleTabs: [String]) -> [String] {
        var seen: Set<String> = [overviewID]
        return [overviewID] + moduleTabs.filter { seen.insert($0).inserted }
    }
}
