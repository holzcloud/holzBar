//
//  HubModules.swift
//  holzBar
//

import SwiftUI

/// The modules of the Notch hub.
enum HubModules {
    /// One registration per hub module. A new module adds one line here, one descriptor to
    /// ``ModuleCatalog/all`` and one runtime class; the order of the tabs is the catalog's,
    /// not this list's.
    static let all: [HubModuleRegistration] = [
        HubModuleRegistration(
            id: TimersRuntime.identifier,
            makeRuntime: { TimersRuntime(appState: $0) },
            makeSettings: { AnyView(TimersSettingsView()) }
        ),
        HubModuleRegistration(
            id: CalendarRuntime.identifier,
            makeRuntime: { CalendarRuntime(appState: $0) },
            makeSettings: { AnyView(CalendarSettingsView()) }
        ),
    ]

    /// The registration of a module, if it has one.
    static func registration(for id: String) -> HubModuleRegistration? {
        all.first { $0.id == id }
    }
}
