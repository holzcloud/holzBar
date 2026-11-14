//
//  HubContext.swift
//  holzBar
//

import Foundation

/// Which module the Notch hub puts in front when it opens, and why, as pure decisions.
///
/// The first of these wins:
/// 1. a timed meeting that runs, or starts within ``meetingLead`` seconds (a running one before
///    a coming one);
/// 2. a live activity: its module, or the Live activities module when the owner has no tab;
/// 3. music that plays;
/// 4. the Overview.
///
/// With "Show what is active first" off, the module the user chose last is in front instead.
///
/// The decision reads no clock, no store and no module: the caller passes the moment and the few
/// facts the modules already hold in memory. A meeting is only a start and an end, never a title,
/// so nothing a module shows can reach the context line or VoiceOver. ``Session`` keeps what one
/// opening has in front, and the rule that decides what is remembered: only a user's pick.
nonisolated enum HubContext {
    /// How long before its start a meeting counts as coming.
    static let meetingLead: TimeInterval = 900

    /// How long after the opening the context may decide once more, for a meeting whose events
    /// arrived late.
    static let lateDecisionWindow: TimeInterval = 1

    /// The module that lists the live activities.
    static let liveActivitiesModuleID = "live-activities"

    /// Why a module is in front. The hub says it in one fixed sentence per reason.
    nonisolated enum Reason: String, CaseIterable, Sendable {
        case meetingSoon
        case meetingNow
        case liveActivity
        case music
        case overview
        case chosen
    }

    /// A timed meeting: its times only, never its title.
    nonisolated struct Meeting: Equatable, Sendable {
        var start: Date
        var end: Date
    }

    /// What a module tells the context, as plain values.
    nonisolated enum Signal: Equatable, Sendable {
        /// The timed meetings the module holds.
        case meetings([Meeting])
        /// Whether something plays.
        case playing(Bool)
    }

    /// A signal and the module it comes from.
    nonisolated struct ModuleSignal: Equatable, Sendable {
        var moduleID: String
        var signal: Signal
    }

    /// Everything the decision reads.
    nonisolated struct Inputs: Equatable, Sendable {
        /// The moment of the decision.
        var now: Date
        /// The modules that have a tab, in catalog order.
        var moduleTabs: [String]
        /// What the modules tell, in catalog order.
        var signals: [ModuleSignal]
        /// The module that owns the top live activity, or `nil` when nothing is live.
        var liveOwner: String?
        /// The module the user chose last, if any.
        var lastChosen: String?
        /// The setting "Show what is active first".
        var showsActiveFirst: Bool
    }

    /// The module in front and why.
    nonisolated struct Decision: Equatable, Sendable {
        var moduleID: String
        var reason: Reason
    }

    /// Decides what is in front when the hub opens.
    static func decide(_ inputs: Inputs) -> Decision {
        let tabs = inputs.moduleTabs
        guard inputs.showsActiveFirst else {
            let chosen = HubTabStrip.selection(inputs.lastChosen ?? HubTabStrip.overviewID, moduleTabs: tabs)
            return Decision(moduleID: chosen, reason: .chosen)
        }
        if let meeting = meetingDecision(inputs) {
            return meeting
        }
        if let owner = inputs.liveOwner {
            if tabs.contains(owner) {
                return Decision(moduleID: owner, reason: .liveActivity)
            }
            if tabs.contains(liveActivitiesModuleID) {
                return Decision(moduleID: liveActivitiesModuleID, reason: .liveActivity)
            }
        }
        for entry in inputs.signals where tabs.contains(entry.moduleID) {
            if case .playing(true) = entry.signal {
                return Decision(moduleID: entry.moduleID, reason: .music)
            }
        }
        return Decision(moduleID: HubTabStrip.overviewID, reason: .overview)
    }

    /// The module of a running meeting, else of the soonest meeting within the lead.
    private static func meetingDecision(_ inputs: Inputs) -> Decision? {
        var running: String?
        var soon: (moduleID: String, start: Date)?
        let horizon = inputs.now.addingTimeInterval(meetingLead)
        for entry in inputs.signals where inputs.moduleTabs.contains(entry.moduleID) {
            guard case .meetings(let meetings) = entry.signal else {
                continue
            }
            for meeting in meetings where meeting.end > meeting.start && meeting.end > inputs.now {
                if meeting.start <= inputs.now {
                    running = running ?? entry.moduleID
                } else if meeting.start <= horizon, soon.map({ meeting.start < $0.start }) ?? true {
                    soon = (entry.moduleID, meeting.start)
                }
            }
        }
        if let running {
            return Decision(moduleID: running, reason: .meetingNow)
        }
        if let soon {
            return Decision(moduleID: soon.moduleID, reason: .meetingSoon)
        }
        return nil
    }

    /// What one opening of the hub has in front.
    ///
    /// It starts with the decision made at the opening. A user's pick replaces it and is the only
    /// thing that names a module to remember. A temporary pick (a file dragged to the notch)
    /// replaces it without being remembered. The context may decide once more, for a meeting whose
    /// events arrived late, as long as nobody picked anything.
    nonisolated struct Session: Equatable, Sendable {
        /// What is in front now.
        private(set) var front: Decision
        /// Whether the user, or a file drag, has picked a module in this opening.
        private(set) var hasPick = false
        /// Whether the late decision has happened.
        private(set) var hasReconsidered = false

        init(opening: Decision) {
            front = opening
        }

        /// The user picks a module. Returns the module to remember as the one chosen last.
        mutating func pick(_ id: String, moduleTabs: [String]) -> String {
            let selected = HubTabStrip.selection(id, moduleTabs: moduleTabs)
            front = Decision(moduleID: selected, reason: .chosen)
            hasPick = true
            return selected
        }

        /// A module comes to the front for this opening only: nothing is remembered.
        mutating func pickTemporarily(_ id: String, moduleTabs: [String]) {
            front = Decision(
                moduleID: HubTabStrip.selection(id, moduleTabs: moduleTabs),
                reason: .chosen
            )
            hasPick = true
        }

        /// The context decides once more. It takes the new decision only once, only when nothing
        /// was picked, only within ``HubContext/lateDecisionWindow`` seconds of the opening, and
        /// only for a meeting of another module. Returns whether it did.
        mutating func reconsider(_ decision: Decision, elapsed: TimeInterval) -> Bool {
            guard
                !hasPick,
                !hasReconsidered,
                elapsed <= HubContext.lateDecisionWindow,
                decision.reason == .meetingSoon || decision.reason == .meetingNow,
                decision.moduleID != front.moduleID
            else {
                return false
            }
            front = decision
            hasReconsidered = true
            return true
        }
    }
}
