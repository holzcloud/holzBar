//
//  HubTabStrip.swift
//  holzBar
//

import Foundation

/// The rules of the Notch hub's icon strip: which tabs sit in which wing, and which tab is
/// selected.
///
/// The Overview is always the first tab. The modules follow in catalog order. The tabs form
/// one row that reads left to right across the notch: the left wing takes as many tabs as fit
/// from its left edge, the right wing takes the rest from its notch side. The status pills and
/// the settings button stay at the far right of the right wing, so the right wing's tab area is
/// the wing minus the width they need.
nonisolated enum HubTabStrip {
    /// The identifier of the Overview, the first tab.
    static let overviewID = "overview"

    /// A status pill as the row sees it: only what its width depends on.
    nonisolated struct Pill: Equatable, Sendable {
        /// The number of characters of the pill's text.
        var textLength: Int
        /// Whether the pill shows a symbol before its text.
        var hasSymbol: Bool

        init(textLength: Int, hasSymbol: Bool) {
            self.textLength = textLength
            self.hasSymbol = hasSymbol
        }
    }

    /// What the row shows.
    nonisolated struct Row: Equatable, Sendable {
        /// The tabs in the left wing, in order.
        var left: [String]
        /// The tabs in the right wing's tab area, in order.
        var right: [String]
        /// The tabs that do not fit, in catalog order.
        var overflow: [String]
        /// The selected tab, which is always one of the tabs.
        var selected: String
        /// The width of one tab in points.
        var tabWidth: Double
    }

    /// The row for the module tabs, a selection and the room the two wings give.
    ///
    /// - Parameters:
    ///   - moduleTabs: The modules that offer a tab, in catalog order. A duplicate and a stray
    ///     Overview are dropped.
    ///   - selected: The wanted tab. One that is not a tab becomes the Overview.
    ///   - leftWingWidth: The width of the left wing; zero where there is none.
    ///   - rightWingWidth: The width of the right wing; zero where there is none.
    ///   - rightReservedWidth: What the status pills and the settings button need at the far
    ///     right of the right wing, see ``rightReservedWidth(pills:)``.
    ///   - gap: The space between two tabs.
    static func row(
        moduleTabs: [String],
        selected: String,
        leftWingWidth: Double,
        rightWingWidth: Double,
        rightReservedWidth: Double,
        gap: Double = DesignTokens.Hub.tabGap
    ) -> Row {
        let tabs = allTabs(moduleTabs)
        let selected = tabs.contains(selected) ? selected : overviewID
        let tabWidth = DesignTokens.Hub.tabWidth
        let leftSlots = slots(in: leftWingWidth, tabWidth: tabWidth, gap: gap)
        let rightSlots = slots(
            in: usable(rightWingWidth) - usable(rightReservedWidth) - gap,
            tabWidth: tabWidth,
            gap: gap
        )
        var visible = Array(tabs.prefix(leftSlots + rightSlots))
        if !visible.isEmpty, !visible.contains(selected) {
            visible[visible.count - 1] = selected
        }
        let overflow = tabs.filter { !visible.contains($0) }
        return Row(
            left: Array(visible.prefix(leftSlots)),
            right: Array(visible.dropFirst(leftSlots)),
            overflow: overflow,
            selected: selected,
            tabWidth: tabWidth
        )
    }

    /// The width a status pill needs, estimated conservatively from its text and symbol; the
    /// view never measures it.
    static func pillWidth(textLength: Int, hasSymbol: Bool) -> Double {
        let text = Double(max(textLength, 0)) * DesignTokens.Hub.pillCharacterWidth
        let symbol = hasSymbol ? DesignTokens.Hub.pillSymbolWidth + DesignTokens.Hub.pillInnerSpacing : 0
        return (text + symbol).rounded(.up) + 2 * DesignTokens.Hub.pillPadding
    }

    /// The width the status pills and the settings button need at the far right of the right
    /// wing: every pill, the button and the space between all of them. No pills gives the
    /// button's width alone.
    static func rightReservedWidth(pills: [Pill]) -> Double {
        let widths = pills.reduce(0) { $0 + pillWidth(textLength: $1.textLength, hasSymbol: $1.hasSymbol) }
        return widths + DesignTokens.Hub.settingsButtonSize + Double(pills.count) * DesignTokens.Hub.pillSpacing
    }

    /// How many tabs of the given width fit in a space, at least 0.
    private static func slots(in width: Double, tabWidth: Double, gap: Double) -> Int {
        let unit = tabWidth + gap
        guard width.isFinite, width > 0, unit.isFinite, unit > 0 else {
            return 0
        }
        return max(Int(((width + gap) / unit).rounded(.down)), 0)
    }

    /// A width that is a number and not negative; anything else counts as 0.
    private static func usable(_ width: Double) -> Double {
        width.isFinite && width > 0 ? width : 0
    }

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
