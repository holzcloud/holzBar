//
//  HubModuleLifecycle.swift
//  holzBar
//

import Foundation

/// Decides which modules of the Notch hub have a runtime object, and which do not.
///
/// This is what makes a hub module cost nothing while it is off: a runtime is started only
/// for a module that is registered, in the catalog's order, switched on, and only while the
/// hub itself is on. While the hub is off, or the module is off, the plan never starts it,
/// and it stops one that runs. The controller creates and releases runtimes by this plan and
/// by nothing else.
nonisolated enum HubModuleLifecycle {
    /// What to start and what to stop to reach the wanted state.
    nonisolated struct Plan: Equatable, Sendable {
        /// The identifiers to start, in registration order, each once.
        var start: [String]
        /// The identifiers to stop, sorted alphabetically.
        var stop: [String]

        /// Whether nothing changes.
        var isEmpty: Bool {
            start.isEmpty && stop.isEmpty
        }
    }

    /// The plan that brings the running modules in line with the switches.
    ///
    /// - Parameters:
    ///   - hubIsOn: Whether the Notch hub module is switched on.
    ///   - enabled: The identifiers of the modules the user switched on.
    ///   - registered: The identifiers that have a registration, in the order they start.
    ///   - running: The identifiers that have a runtime now.
    static func plan(
        hubIsOn: Bool,
        enabled: Set<String>,
        registered: [String],
        running: Set<String>
    ) -> Plan {
        guard hubIsOn else {
            return Plan(start: [], stop: running.sorted())
        }
        var seen = Set<String>()
        let desired = registered.filter { enabled.contains($0) && seen.insert($0).inserted }
        let desiredSet = Set(desired)
        return Plan(
            start: desired.filter { !running.contains($0) },
            stop: running.subtracting(desiredSet).sorted()
        )
    }

    /// The identifiers of the registrations that also have a descriptor in the catalog, in the
    /// catalog's order, each once. The catalog's order is the order of the tabs.
    static func registeredOrder(catalogOrder: [String], registrations: [String]) -> [String] {
        let registered = Set(registrations)
        var seen = Set<String>()
        return catalogOrder.filter { registered.contains($0) && seen.insert($0).inserted }
    }
}
