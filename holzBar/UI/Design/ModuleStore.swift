//
//  ModuleStore.swift
//  holzBar
//

import Foundation
import Observation

/// Which optional modules the user has switched on.
///
/// Only identifiers of modules that exist in the catalog count; an identifier left behind by
/// a module that was removed is ignored and dropped the next time the choice is saved.
@Observable
final class ModuleStore {
    private static let storageKey = "EnabledModules"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let catalog: [ModuleDescriptor]
    private var enabled: Set<String>

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - defaults: Where the choice is kept.
    ///   - catalog: The modules that exist.
    init(defaults: UserDefaults = .standard, catalog: [ModuleDescriptor] = ModuleCatalog.all) {
        self.defaults = defaults
        self.catalog = catalog
        let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
        self.enabled = ModuleCatalog.enabledIdentifiers(stored, knownTo: catalog)
    }

    /// Whether the module is switched on.
    func isEnabled(_ identifier: String) -> Bool {
        enabled.contains(identifier)
    }

    /// Switches a module on or off. An identifier that is not in the catalog is ignored.
    func setEnabled(_ identifier: String, _ isOn: Bool) {
        guard catalog.contains(where: { $0.id == identifier }) else {
            return
        }
        if isOn {
            enabled.insert(identifier)
        } else {
            enabled.remove(identifier)
        }
        defaults.set(enabled.sorted(), forKey: Self.storageKey)
    }
}
