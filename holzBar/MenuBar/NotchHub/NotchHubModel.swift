//
//  NotchHubModel.swift
//  holzBar
//

import Observation

/// What the Notch hub's views read: the runtimes of the modules that are on, the icon strip's
/// layout, the tiles of the Overview, the status pills and the selected tab.
///
/// The model holds no timer and starts nothing. The controller sets the runtimes; a view that
/// reads the model follows them, and a tile or a pill that reads observable state follows
/// that state. The last selected tab is kept on this Mac (it is never exported).
@MainActor
@Observable
final class NotchHubModel {
    /// The runtimes of the hub modules that are on, in catalog order.
    var runtimes = [any HubModuleRuntime]()

    /// The tab the user chose last, which may not be available now: a module that is off has
    /// no tab, and its tab comes back with it.
    private var chosenID: String

    init() {
        chosenID = Defaults.string(forKey: .notchHubLastTab) ?? HubTabStrip.overviewID
    }

    /// The modules that offer a tab, in catalog order.
    var tabModuleIDs: [String] {
        runtimes.filter(\.offersTab).map(\.moduleID)
    }

    /// The icon strip: the visible tabs, the More menu and the selected tab.
    var layout: HubTabStrip.Layout {
        HubTabStrip.layout(moduleTabs: tabModuleIDs, selected: chosenID)
    }

    /// The selected tab, always one that exists: the Overview where the chosen tab is gone.
    var selectedID: String {
        layout.selected
    }

    /// The selected module's runtime, or `nil` while the Overview is selected.
    var selectedRuntime: (any HubModuleRuntime)? {
        runtimes.first { $0.moduleID == selectedID && $0.offersTab }
    }

    /// Every tab, the Overview first.
    var allTabIDs: [String] {
        HubTabStrip.allTabs(tabModuleIDs)
    }

    /// The cards of the Overview, in catalog order.
    var tiles: [(id: String, tile: HubTile)] {
        runtimes.compactMap { runtime in
            runtime.tile.map { (id: runtime.moduleID, tile: $0) }
        }
    }

    /// The status pills of the right wing, in catalog order.
    var pills: [(id: String, pill: HubStatusPill)] {
        runtimes.compactMap { runtime in
            runtime.statusPill.map { (id: runtime.moduleID, pill: $0) }
        }
    }

    /// Selects a tab and remembers it. An identifier that is not a tab selects the Overview.
    func select(_ id: String) {
        let selected = HubTabStrip.layout(moduleTabs: tabModuleIDs, selected: id).selected
        chosenID = selected
        Defaults.set(selected, forKey: .notchHubLastTab)
    }
}
