//
//  HubTabStrip.swift
//  holzBar
//

import Foundation

/// Which module the Notch hub has selected and how the arrow keys step through the modules.
///
/// The Overview is always the first tab. The modules follow in catalog order. A selection that
/// is not a tab (a module that is off) becomes the Overview, and the arrow keys step through all
/// tabs, wrapping at both ends.
nonisolated enum HubTabStrip {
    /// The identifier of the Overview, the first tab.
    static let overviewID = "overview"

    /// The tab that is selected for a wanted one: the wanted one if it is a tab, else the
    /// Overview.
    static func selection(_ wanted: String, moduleTabs: [String]) -> String {
        allTabs(moduleTabs).contains(wanted) ? wanted : overviewID
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

    /// The Overview followed by the module tabs, each once.
    static func allTabs(_ moduleTabs: [String]) -> [String] {
        var seen: Set<String> = [overviewID]
        return [overviewID] + moduleTabs.filter { seen.insert($0).inserted }
    }
}
