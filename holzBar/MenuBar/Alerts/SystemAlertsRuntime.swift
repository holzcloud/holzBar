//
//  SystemAlertsRuntime.swift
//  holzBar
//

import SwiftUI

/// The System alerts module in the Notch hub: a facade with no tab, no tile and no state of its own.
///
/// The alerts are measured and held by ``ThresholdAlertsManager``, an app service that lives
/// without the hub. This runtime exists only while the hub and the module are both on and hands
/// that service's activities to the hub, which widens the notch for a firing alert, shows it in
/// the open hub's right pill and lists it in the Live activities module. It starts and measures
/// nothing, so there is nothing to release when the hub goes off.
@MainActor
final class SystemAlertsRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = AlertLook.moduleID

    let moduleID = SystemAlertsRuntime.identifier
    let offersTab = false

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    var activities: [LiveActivity] {
        appState?.systemAlerts.activities ?? []
    }

    /// Never called: the module has no tab.
    func makeBody(host _: any HubHost) -> AnyView {
        AnyView(EmptyView())
    }

    /// The manager owns everything, so there is nothing to release.
    func shutDown() {}
}
