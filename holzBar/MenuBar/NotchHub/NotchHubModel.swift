//
//  NotchHubModel.swift
//  holzBar
//

import Foundation
import Observation

/// What the Notch hub's views read: the runtimes of the modules that are on, the tabs,
/// the tiles of the Overview, the status pills and the selected tab.
///
/// The model holds no timer and starts nothing. The controller sets the runtimes; a view that
/// reads the model follows them, and a tile or a pill that reads observable state follows
/// that state.
///
/// What is in front is decided per opening (``HubContext``): while the hub is open, a
/// ``HubContext/Session`` holds the module in front, which the context chose, or the user picked,
/// or a file drag brought forward for this opening only. Only a user's pick is remembered as the
/// module chosen last, and only on this Mac (it is never exported); the context's decision, its
/// one late re-decision and a file drag's temporary pick are never stored.
@MainActor
@Observable
final class NotchHubModel {
    /// The runtimes of the hub modules that are on, in catalog order.
    var runtimes = [any HubModuleRuntime]()

    /// Counts the moments a finished activity left, so that a view that reads the board or the
    /// tiles draws again then. Nothing else reads it.
    private(set) var expiryCount = 0

    /// The tab the user chose last, which may not be available now: a module that is off has
    /// no tab, and its tab comes back with it. Only a user's pick sets it.
    private var lastChosenID: String

    /// What the open hub has in front, from the opening until the hub has closed; `nil` while it
    /// is closed.
    private(set) var session: HubContext.Session?

    init() {
        lastChosenID = Defaults.string(forKey: .notchHubLastTab) ?? HubTabStrip.overviewID
    }

    /// The modules that offer a tab, in catalog order.
    var tabModuleIDs: [String] {
        runtimes.filter(\.offersTab).map(\.moduleID)
    }

    /// The selected tab, always one that exists: the Overview where the tab in front is gone.
    /// While the hub is open it is the session's front module, else the module chosen last.
    var selectedID: String {
        HubTabStrip.selection(session?.front.moduleID ?? lastChosenID, moduleTabs: tabModuleIDs)
    }

    /// Why the module in front is in front, while the hub is open.
    var frontReason: HubContext.Reason? {
        session?.front.reason
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
        // A tile may show an activity that has just expired.
        _ = expiryCount
        return runtimes.compactMap { runtime in
            runtime.tile.map { (id: runtime.moduleID, tile: $0) }
        }
    }

    /// What is going on, as the modules report it: the activities of every runtime, in catalog
    /// order. A runtime keeps its activities current from observable state, so this follows
    /// every change.
    var activities: [LiveActivity] {
        runtimes.flatMap(\.activities)
    }

    /// The board of the live activities at a moment: what is listed, which one is compact, how
    /// many are hidden and when the next finished one leaves.
    func board(now: Date) -> HubActivityBoard.Board {
        _ = expiryCount
        return HubActivityBoard.board(activities, now: now)
    }

    /// Records that a finished activity left, so that the views that show the board draw again.
    func activitiesDidExpire() {
        expiryCount &+= 1
    }

    /// The status pills of the right wing, in catalog order.
    var pills: [(id: String, pill: HubStatusPill)] {
        runtimes.compactMap { runtime in
            runtime.statusPill.map { (id: runtime.moduleID, pill: $0) }
        }
    }

    /// Starts what one opening has in front with the context's decision. The decision is not
    /// remembered.
    func beginOpening(_ decision: HubContext.Decision) {
        session = HubContext.Session(opening: decision)
    }

    /// Ends what the opening had in front, once the hub has closed.
    func endOpening() {
        session = nil
    }

    /// The context's inputs at a moment: the tabs, what the modules tell, the owner of the top
    /// live activity and the module chosen last. It reads only what the modules already hold in
    /// memory.
    func contextInputs(now: Date, showsActiveFirst: Bool) -> HubContext.Inputs {
        HubContext.Inputs(
            now: now,
            moduleTabs: tabModuleIDs,
            signals: runtimes.compactMap { runtime in
                runtime.contextSignal.map { HubContext.ModuleSignal(moduleID: runtime.moduleID, signal: $0) }
            },
            liveOwner: board(now: now).compact?.moduleID,
            lastChosen: lastChosenID,
            showsActiveFirst: showsActiveFirst
        )
    }

    /// The user picks a tab: it stays in front until the hub closes and is remembered as the
    /// module chosen last. An identifier that is not a tab selects the Overview.
    func select(_ id: String) {
        let selected = session?.pick(id, moduleTabs: tabModuleIDs)
            ?? HubTabStrip.selection(id, moduleTabs: tabModuleIDs)
        lastChosenID = selected
        Defaults.set(selected, forKey: .notchHubLastTab)
    }

    /// Brings a tab to the front for this opening only, as a file drag does: nothing is
    /// remembered. Without an opening it does nothing.
    func selectTemporarily(_ id: String) {
        session?.pickTemporarily(id, moduleTabs: tabModuleIDs)
    }

    /// Lets the context decide once more, for a meeting whose events arrived late. Returns
    /// whether the decision took the front.
    func reconsider(_ decision: HubContext.Decision, elapsed: TimeInterval) -> Bool {
        session?.reconsider(decision, elapsed: elapsed) ?? false
    }
}
