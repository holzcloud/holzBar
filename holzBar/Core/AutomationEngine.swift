//
//  AutomationEngine.swift
//  holzBar
//

import Foundation

/// Decides what the automation rules do, from the facts alone.
///
/// The engine is a pure function: facts in, effects out. A rule acts once when it becomes
/// true, not again while it stays true, and, if chosen, undoes its change when it stops being
/// true. A profile that is already applied is not applied again. Effects never feed back into
/// the same pass, so a rule cannot loop.
nonisolated enum AutomationEngine {
    /// What the app should do.
    nonisolated enum Effect: Equatable, Sendable {
        case applyProfile(String)
        case showSection(AutomationSection)
        case setZen(Bool)
    }

    /// What the app looks like right now.
    nonisolated struct Context: Equatable, Sendable {
        /// The name of the profile that is applied.
        var currentProfile: String?
        var isZenOn: Bool
    }

    /// What the engine remembers between two passes.
    nonisolated struct State: Equatable, Sendable {
        /// What a rule changed and how to undo it.
        nonisolated struct Undo: Equatable, Sendable {
            var applied: Effect
            var restore: Effect
        }

        /// The rules that were true at the last pass and acted.
        var active: Set<UUID> = []
        /// How to undo the change of each active rule that restores when it ends.
        var undo: [UUID: Undo] = [:]
    }

    /// The result of one pass.
    nonisolated struct Result: Equatable, Sendable {
        var effects: [Effect]
        var state: State
    }

    /// Runs one pass.
    ///
    /// - Parameters:
    ///   - rules: The rules, in their order. The first rule that applies a profile wins over
    ///     later ones in the same pass.
    ///   - facts: The current facts.
    ///   - context: The current profile and Zen mode.
    ///   - state: The state returned by the last pass.
    static func evaluate(
        rules: [AutomationRule],
        facts: AutomationFacts,
        context: Context,
        state: State
    ) -> Result {
        var next = state
        var effects: [Effect] = []
        var context = context

        func apply(_ effect: Effect) {
            switch effect {
            case .applyProfile(let name): context.currentProfile = name
            case .setZen(let isOn): context.isZenOn = isOn
            case .showSection: break
            }
            effects.append(effect)
        }

        // Whether the change a rule made is still in place, so the user's own change in the
        // meantime is not overwritten.
        func holds(_ effect: Effect) -> Bool {
            switch effect {
            case .applyProfile(let name): context.currentProfile == name
            case .setZen(let isOn): context.isZenOn == isOn
            case .showSection: false
            }
        }

        func end(_ id: UUID) {
            next.active.remove(id)
            guard let undo = next.undo.removeValue(forKey: id), holds(undo.applied) else {
                return
            }
            apply(undo.restore)
        }

        // Rules that were removed or disabled end like rules that stopped being true.
        let live = Set(rules.filter(\.isEnabled).map(\.id))
        for id in state.active.subtracting(live).sorted(by: { $0.uuidString < $1.uuidString }) {
            end(id)
        }

        var profileWasChosen = false
        for rule in rules where rule.isEnabled {
            let isMet = rule.isMet(in: facts)
            let wasActive = next.active.contains(rule.id)
            if !isMet && wasActive {
                end(rule.id)
            } else if isMet && !wasActive {
                let effect = rule.action.effect
                if case .applyProfile = effect {
                    if profileWasChosen {
                        // An earlier rule won this pass; try again when it is free.
                        continue
                    }
                    profileWasChosen = true
                }
                let restore = rule.restoresWhenEnded ? undo(for: effect, in: context) : nil
                if !isRedundant(effect, in: context) {
                    apply(effect)
                }
                next.active.insert(rule.id)
                if let restore {
                    next.undo[rule.id] = State.Undo(applied: effect, restore: restore)
                }
            }
        }
        return Result(effects: effects, state: next)
    }

    /// Whether the effect would change nothing.
    private static func isRedundant(_ effect: Effect, in context: Context) -> Bool {
        switch effect {
        case .applyProfile(let name): context.currentProfile == name
        case .setZen(let isOn): context.isZenOn == isOn
        case .showSection: false
        }
    }

    /// The effect that undoes `effect`, or `nil` when there is nothing to undo.
    private static func undo(for effect: Effect, in context: Context) -> Effect? {
        guard !isRedundant(effect, in: context) else {
            return nil
        }
        switch effect {
        case .applyProfile:
            return context.currentProfile.map(Effect.applyProfile)
        case .setZen:
            return .setZen(context.isZenOn)
        case .showSection:
            return nil
        }
    }
}

extension AutomationAction {
    nonisolated var effect: AutomationEngine.Effect {
        switch self {
        case .applyProfile(let name): .applyProfile(name)
        case .showSection(let section): .showSection(section)
        case .zen(let isOn): .setZen(isOn)
        }
    }
}
