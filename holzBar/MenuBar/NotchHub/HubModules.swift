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
        HubModuleRegistration(
            id: "live-activities",
            makeRuntime: { LiveActivitiesRuntime(appState: $0) },
            makeSettings: { AnyView(LiveActivitiesSettingsView()) }
        ),
        HubModuleRegistration(
            id: "file-drop",
            makeRuntime: { FileDropRuntime(appState: $0) },
            makeSettings: { AnyView(FileDropSettingsView()) }
        ),
        HubModuleRegistration(
            id: "display-controls",
            makeRuntime: { DisplayControlsRuntime(appState: $0) },
            makeSettings: { AnyView(EmptyView()) }
        ),
    ]

    /// The registration of a module, if it has one.
    static func registration(for id: String) -> HubModuleRegistration? {
        all.first { $0.id == id }
    }
}
