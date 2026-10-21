//
//  ItemRuleMemory.swift
//  holzBar
//

import Foundation

/// What holzBar remembers about one item that a rule of the kind "show it only while …"
/// controls.
nonisolated struct ItemRuleMemory: Equatable, Sendable {
    /// Where holzBar last put the item, or found it, in this run, and whether that was the
    /// hiding state. `nil` before the first look and after a restart.
    struct Applied: Equatable, Sendable {
        var section: Int
        var isHiding: Bool
    }

    /// The section the item has while the rule shows it (0 visible, 1 hidden), or `nil` when
    /// holzBar does not know yet. It outlives a restart.
    var shownSection: Int?
    var applied: Applied?
    /// Whether the item was not found at the last look. An item that is found again is looked
    /// at anew, as at its first look: what holzBar knew of where it left the item no longer
    /// holds, so the item is never taken for one the user moved by hand.
    var wasAbsent = false
}

/// A move by hand that holzBar undid.
nonisolated struct ItemRuleRevert: Equatable, Sendable {
    /// The section the item was found in.
    var found: Int
    /// The section holzBar put it back in.
    var putBack: Int
}

/// What to do with one item after looking at its rule.
nonisolated struct ItemRuleDecision: Equatable, Sendable {
    /// The section to move the item to, or `nil` when it stays.
    var moveTo: Int?
    /// What holzBar remembers once the decision is carried out.
    var memory: ItemRuleMemory
    /// Set when the item is put back because the user moved it by hand against its rule. The
    /// user is told (never silent).
    var revert: ItemRuleRevert?
}

/// The hint that an item was put back, shown at the top of Menu Bar Layout until the user
/// dismisses it. It lives in memory only.
nonisolated struct ItemRuleNotice: Equatable, Identifiable, Sendable {
    var itemKey: String
    var itemName: String
    /// The section the item was put back in, as a profile index (0 visible, 1 hidden, 2 always hidden).
    var putBackIn: Int

    var id: String {
        itemKey
    }
}

nonisolated extension ItemVisibility {
    /// What a rule says about its item now: the item's identity key, whether the conditions
    /// hold (`nil` when the facts do not tell), and the index of the section that hides the
    /// item (1 hidden, 2 always hidden). `nil` when the rule is off or of another kind.
    static func follow(
        of rule: AutomationRule,
        facts: AutomationFacts
    ) -> (itemKey: String, holds: Bool?, hiding: Int)? {
        guard rule.isEnabled, case .showItemOnlyWhile(let key, let hiding) = rule.action else {
            return nil
        }
        return (key, rule.evaluation(in: facts), hiding == .alwaysHidden ? 2 : 1)
    }

    /// Decides what happens to one item that follows a rule.
    ///
    /// - While the rule shows the item, the item may be anywhere more visible than the
    ///   hiding section. A move by hand there is kept as the section it has while shown; a
    ///   move into the hiding section or deeper is put back.
    /// - While the rule hides the item, it is moved into the hiding section, and the section
    ///   it had is remembered. An item that is found in a more visible section than holzBar
    ///   left it in was moved by hand: it is put back. One moved deeper stays there.
    /// - When the facts do not tell, nothing changes.
    ///
    /// Deciding again with the result carried out yields no move and no revert.
    ///
    /// - Parameters:
    ///   - holds: Whether the conditions hold, or `nil` when they cannot be read.
    ///   - hiding: The index of the hiding section: 1 or 2.
    ///   - actual: The section the item is in now, or `nil` when it is not found.
    ///   - memory: What holzBar remembers of the item.
    static func decide(holds: Bool?, hiding: Int, actual: Int?, memory: ItemRuleMemory) -> ItemRuleDecision {
        var memory = memory
        if actual != nil, memory.wasAbsent {
            // The item is back after it was missing: a fresh first look, never a revert.
            memory.applied = nil
            memory.wasAbsent = false
        }
        var result: ItemRuleDecision
        if let holds {
            result = holds
                ? decideShown(hiding: hiding, actual: actual, memory: memory)
                : decideHidden(hiding: hiding, actual: actual, memory: memory)
        } else {
            result = ItemRuleDecision(moveTo: nil, memory: memory, revert: nil)
        }
        result.memory.wasAbsent = actual == nil
        return result
    }

    /// The section a shown item returns to: the remembered one when it is more visible than
    /// the hiding section, else the visible bar.
    private static func shownTarget(of memory: ItemRuleMemory, hiding: Int) -> Int {
        if let shown = memory.shownSection, shown >= 0, shown < hiding {
            return shown
        }
        return 0
    }

    private static func decision(
        _ memory: ItemRuleMemory,
        applied: ItemRuleMemory.Applied,
        shown: Int? = nil,
        moveTo: Int? = nil,
        revert: ItemRuleRevert? = nil
    ) -> ItemRuleDecision {
        var next = memory
        next.applied = applied
        if let shown {
            next.shownSection = shown
        }
        return ItemRuleDecision(moveTo: moveTo, memory: next, revert: revert)
    }

    private static func decideShown(hiding: Int, actual: Int?, memory: ItemRuleMemory) -> ItemRuleDecision {
        let target = shownTarget(of: memory, hiding: hiding)
        let unchanged = ItemRuleDecision(moveTo: nil, memory: memory, revert: nil)
        guard let applied = memory.applied else {
            // First look. A new rule never drags an item that is already more visible than the
            // hiding section to the visible bar.
            guard let actual else {
                return unchanged
            }
            if actual < hiding {
                return decision(memory, applied: .init(section: actual, isHiding: false), shown: actual)
            }
            return decision(memory, applied: .init(section: target, isHiding: false), shown: target, moveTo: target)
        }
        if applied.isHiding {
            // The rule shows the item again: back to where it had been.
            let shownState = ItemRuleMemory.Applied(section: target, isHiding: false)
            return decision(memory, applied: shownState, shown: target, moveTo: actual == target ? nil : target)
        }
        guard let actual else {
            return unchanged
        }
        if actual < hiding {
            // Moved by hand (or not moved at all) to a section where the item is shown.
            return decision(memory, applied: .init(section: actual, isHiding: false), shown: actual)
        }
        // In the hiding section or deeper while the rule shows it: put back. Only a move by hand
        // (the item is not where holzBar left it) is announced.
        return decision(
            memory,
            applied: .init(section: target, isHiding: false),
            shown: target,
            moveTo: target,
            revert: actual == applied.section ? nil : ItemRuleRevert(found: actual, putBack: target)
        )
    }

    private static func decideHidden(hiding: Int, actual: Int?, memory: ItemRuleMemory) -> ItemRuleDecision {
        let hidden = ItemRuleMemory.Applied(section: hiding, isHiding: true)
        guard let applied = memory.applied else {
            // First look.
            guard let actual else {
                // Not found: nothing moved, so nothing is recorded as applied. The hiding section
                // is asked for once, so a layout that is keyed by application (macOS 27) places
                // the item when it shows up.
                return ItemRuleDecision(moveTo: memory.wasAbsent ? nil : hiding, memory: memory, revert: nil)
            }
            if actual >= hiding {
                return decision(memory, applied: .init(section: actual, isHiding: true))
            }
            // The shown section that is stored stays: where the item sits at launch (its default
            // position) says nothing about where the user wants it while the rule shows it.
            return decision(memory, applied: hidden, shown: memory.shownSection ?? actual, moveTo: hiding)
        }
        if applied.isHiding {
            if let actual, actual != applied.section {
                if actual >= hiding {
                    // Moved deeper by hand: that hides the item as well.
                    return decision(memory, applied: .init(section: actual, isHiding: true))
                }
                // Found in a more visible section than the hiding one: put back.
                return decision(
                    memory,
                    applied: hidden,
                    moveTo: hiding,
                    revert: ItemRuleRevert(found: actual, putBack: hiding)
                )
            }
            if applied.section >= hiding {
                return decision(memory, applied: applied)
            }
            // The hiding section was edited and is deeper now; the old one is not a shown section.
            return decision(memory, applied: hidden, moveTo: hiding)
        }
        // The conditions stopped holding: remember the section the item has now, as the user
        // may have moved it by hand while it was shown.
        let basis = actual ?? applied.section
        if basis < hiding {
            return decision(memory, applied: hidden, shown: basis, moveTo: hiding)
        }
        return decision(memory, applied: .init(section: basis, isHiding: true))
    }

    /// One decision per followed item.
    ///
    /// - Parameters:
    ///   - follows: The result of ``follow(of:facts:)`` for each rule that is on.
    ///   - actual: The section of each item now, by identity key. An item not in it is not found.
    ///   - memory: What holzBar remembers, by identity key. A missing entry is an empty memory.
    static func decisions(
        follows: [(itemKey: String, holds: Bool?, hiding: Int)],
        actual: [String: Int],
        memory: [String: ItemRuleMemory]
    ) -> [String: ItemRuleDecision] {
        var result = [String: ItemRuleDecision]()
        for follow in follows {
            result[follow.itemKey] = decide(
                holds: follow.holds,
                hiding: follow.hiding,
                actual: actual[follow.itemKey],
                memory: memory[follow.itemKey] ?? ItemRuleMemory()
            )
        }
        return result
    }

    // MARK: Carrying out

    /// What holzBar remembers once a decision with a move was carried out and the bar was read
    /// again. Only an item that was seen in the section it was moved to keeps what the decision
    /// recorded as applied; for any other the earlier `applied` stays, so the next look does
    /// not take the item, which the move did not reach, for one the user moved by hand.
    static func settledMemory(of decision: ItemRuleDecision, before: ItemRuleMemory, reached: Bool) -> ItemRuleMemory {
        guard decision.moveTo != nil, !reached else {
            return decision.memory
        }
        var kept = decision.memory
        kept.applied = before.applied
        return kept
    }

    /// The decisions without the moves that were given up: such a decision moves nothing and
    /// announces nothing, and remembers as a move that did not reach the item.
    ///
    /// - Parameters:
    ///   - found: The identity keys of the items that are on the bar now.
    static func droppingGivenUpMoves(
        from decisions: [String: ItemRuleDecision],
        memory: [String: ItemRuleMemory],
        attempts: ItemRuleMoveAttempts,
        found: Set<String>
    ) -> [String: ItemRuleDecision] {
        var result = decisions
        for (key, decision) in decisions {
            guard let target = decision.moveTo, attempts.isGivenUp(key: key, target: target, isFound: found.contains(key)) else {
                continue
            }
            let kept = settledMemory(of: decision, before: memory[key] ?? ItemRuleMemory(), reached: false)
            result[key] = ItemRuleDecision(moveTo: nil, memory: kept, revert: nil)
        }
        return result
    }

    // MARK: Persistence

    /// The memory in the app after the rules were loaded: what is already known stays (the
    /// section where holzBar left each item), the shown sections are refreshed from `stored`
    /// (see ``restoredMemory(from:ruleKeys:)``), entries are added for items that are new and
    /// dropped for items no rule controls.
    static func mergingStored(
        _ stored: [String: ItemRuleMemory],
        into current: [String: ItemRuleMemory],
        ruleKeys: Set<String>
    ) -> [String: ItemRuleMemory] {
        var result = [String: ItemRuleMemory]()
        for key in ruleKeys.sorted() {
            guard result.count < AutomationRule.maximumCount, var memory = current[key] ?? stored[key] else {
                continue
            }
            if let shown = stored[key]?.shownSection {
                memory.shownSection = shown
            }
            result[key] = memory
        }
        return result
    }

    /// The identity keys of the items of all item rules, whether the rule is on or off.
    static func ruleKeys(in rules: [AutomationRule]) -> Set<String> {
        Set(rules.compactMap(itemKey(of:)))
    }

    /// The memory read from the stored shown sections. The stored value is untrusted: only
    /// keys of item rules, the values 0 and 1 and at most ``AutomationRule/maximumCount``
    /// entries are kept.
    static func restoredMemory(from stored: [String: Int], ruleKeys: Set<String>) -> [String: ItemRuleMemory] {
        var result = [String: ItemRuleMemory]()
        for key in stored.keys.sorted() where ruleKeys.contains(key) {
            guard result.count < AutomationRule.maximumCount, let shown = stored[key], shown == 0 || shown == 1 else {
                continue
            }
            result[key] = ItemRuleMemory(shownSection: shown)
        }
        return result
    }

    /// The shown sections to store: those of item rules that are known. Nothing is stored for
    /// an item whose shown section is unknown.
    static func persistableShownSections(_ memory: [String: ItemRuleMemory], ruleKeys: Set<String>) -> [String: Int] {
        var result = [String: Int]()
        for key in memory.keys.sorted() where ruleKeys.contains(key) {
            guard result.count < AutomationRule.maximumCount, let shown = memory[key]?.shownSection, shown == 0 || shown == 1 else {
                continue
            }
            result[key] = shown
        }
        return result
    }
}

/// How often holzBar tried to move an item without the bar showing it in the new section. After
/// ``limit`` tries in a row for the same target it stops, until the facts change: the target is
/// another one, the item appears or disappears, the rules are edited or the user arranges items.
nonisolated struct ItemRuleMoveAttempts: Equatable, Sendable {
    /// The most tries in a row for one item and target.
    static let limit = 3

    private struct Failure: Equatable, Sendable {
        var target: Int
        var isFound: Bool
        var count: Int
    }

    private var failures = [String: Failure]()

    /// Whether the move of the item to `target` is not tried again. `isFound` tells whether the
    /// item is on the bar.
    func isGivenUp(key: String, target: Int, isFound: Bool) -> Bool {
        guard let failure = failures[key] else {
            return false
        }
        return failure.target == target && failure.isFound == isFound && failure.count >= Self.limit
    }

    /// Notes a move that did not reach the item. A try with other facts starts the count anew.
    mutating func recordFailure(key: String, target: Int, isFound: Bool) {
        if var failure = failures[key], failure.target == target, failure.isFound == isFound {
            failure.count += 1
            failures[key] = failure
        } else {
            failures[key] = Failure(target: target, isFound: isFound, count: 1)
        }
    }

    /// Notes a move that reached the item.
    mutating func recordSuccess(key: String) {
        failures.removeValue(forKey: key)
    }

    /// Forgets every failure: the facts changed.
    mutating func removeAll() {
        failures.removeAll()
    }
}

/// The notices of items that were put back.
nonisolated enum ItemRuleNotices {
    /// The most notices that are kept.
    static let limit = 10

    /// The notices with `notice` first. An item has one notice: an earlier one for the same
    /// item is replaced. At most `limit` are kept, the newest first.
    static func adding(_ notice: ItemRuleNotice, to notices: [ItemRuleNotice], limit: Int = ItemRuleNotices.limit) -> [ItemRuleNotice] {
        Array(([notice] + notices.filter { $0.itemKey != notice.itemKey }).prefix(limit))
    }

    /// The notices of the items that are still controlled by a rule.
    static func keeping(_ notices: [ItemRuleNotice], controlled: Set<String>) -> [ItemRuleNotice] {
        notices.filter { controlled.contains($0.itemKey) }
    }

    /// The most characters of an item name that a notice shows.
    static let maximumNameLength = 60

    /// An item name another app chose, made safe to show: control characters and line breaks
    /// are removed, the text is trimmed and cut to 60 characters with an ellipsis, and
    /// `fallback` stands in when nothing is left.
    static func cleanedName(_ name: String, fallback: String) -> String {
        let kept = name.unicodeScalars.filter { !isUnwanted($0) }
        let cleaned = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return fallback
        }
        guard cleaned.count > maximumNameLength else {
            return cleaned
        }
        return String(cleaned.prefix(maximumNameLength - 1)) + "…"
    }

    /// Control characters, line and paragraph separators, and the characters that force a
    /// writing direction (they could make a name read as another).
    private static func isUnwanted(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
        }
    }
}
