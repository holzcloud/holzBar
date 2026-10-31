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
///
/// The tabs are 30 points wide. If they do not all fit, the whole row steps down to 28 and then
/// to 26 points (``DesignTokens/Hub/tabWidthSteps``) before any tab goes into a More menu; the
/// menu is the last place in the right group (in the left group where there is no right wing)
/// and only a row that does not fit at 26 points shows it. The selected tab is always visible.
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
        /// The group whose last place the More button takes, or `nil` where every tab has a
        /// place. The button's width is the tab width, and it lists ``overflow``.
        var moreWing: Wing?
    }

    /// One of the two groups of the row.
    nonisolated enum Wing: Equatable, Sendable {
        case left
        case right
    }

    /// The row for the module tabs, a selection and the room the two wings give.
    ///
    /// The widths of ``DesignTokens/Hub/tabWidthSteps`` are tried in order, and the first at
    /// which every tab has a place wins. If none does, the smallest width is used, one place
    /// is kept for the More button, and the tabs that do not fit go to ``Row/overflow``.
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
        let selected = selection(selected, moduleTabs: moduleTabs)
        let rightRoom = usable(rightWingWidth) - usable(rightReservedWidth) - gap
        let steps = DesignTokens.Hub.tabWidthSteps.isEmpty ? [DesignTokens.Hub.tabWidth] : DesignTokens.Hub.tabWidthSteps

        for width in steps {
            let left = slots(in: leftWingWidth, tabWidth: width, gap: gap)
            let right = slots(in: rightRoom, tabWidth: width, gap: gap)
            if left + right >= tabs.count {
                return place(tabs, selected: selected, tabWidth: width, leftSlots: left, rightSlots: right, moreWing: nil)
            }
        }
        let width = steps[steps.count - 1]
        var left = slots(in: leftWingWidth, tabWidth: width, gap: gap)
        var right = slots(in: rightRoom, tabWidth: width, gap: gap)
        var moreWing: Wing?
        if right > 0 {
            right -= 1
            moreWing = .right
        } else if left > 0 {
            left -= 1
            moreWing = .left
        }
        return place(tabs, selected: selected, tabWidth: width, leftSlots: left, rightSlots: right, moreWing: moreWing)
    }

    /// The tab that is selected for a wanted one: the wanted one if it is a tab, else the
    /// Overview.
    static func selection(_ wanted: String, moduleTabs: [String]) -> String {
        allTabs(moduleTabs).contains(wanted) ? wanted : overviewID
    }

    /// Puts the tabs in the places: the first ones left, the next ones right, the rest in the
    /// overflow, with the selected tab taking the last place if it would be in the overflow.
    private static func place(
        _ tabs: [String],
        selected: String,
        tabWidth: Double,
        leftSlots: Int,
        rightSlots: Int,
        moreWing: Wing?
    ) -> Row {
        var visible = Array(tabs.prefix(leftSlots + rightSlots))
        if visible.isEmpty, tabs.count == 1 {
            // A lone Overview is never put in a menu, however little room there is.
            return Row(left: tabs, right: [], overflow: [], selected: selected, tabWidth: tabWidth, moreWing: nil)
        }
        if !visible.isEmpty, !visible.contains(selected) {
            visible[visible.count - 1] = selected
        }
        return Row(
            left: Array(visible.prefix(leftSlots)),
            right: Array(visible.dropFirst(leftSlots)),
            overflow: tabs.filter { !visible.contains($0) },
            selected: selected,
            tabWidth: tabWidth,
            moreWing: moreWing
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
