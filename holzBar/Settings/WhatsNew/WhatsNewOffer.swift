//
//  WhatsNewOffer.swift
//  holzBar
//

import Foundation

/// Opens the What's New window by itself, once, on the first launch after an update.
///
/// ``WhatsNewPolicy`` decides; this only reads the inputs, stores the last seen version and
/// opens the window. The window opens without activating holzBar: it comes up above the
/// other windows, and the app the user is working in keeps the keyboard. Opening it from
/// Settings -> About is a different path and never stores anything.
@MainActor
enum WhatsNewOffer {
    /// How long after the setup the window waits, so that it never competes with the bar.
    private static let delay = Duration.seconds(2)

    static func offerIfNeeded(appState: AppState) async {
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }
        // The setup only runs once the permissions are in place, so the permissions window
        // is not on screen at this point.
        guard
            appState.isSetUp,
            let current = Bundle.main.versionString
        else {
            return
        }
        let decision = WhatsNewPolicy.decide(
            lastSeen: Defaults.string(forKey: .lastSeenVersion),
            current: current,
            isFreshInstall: appState.isFreshInstall,
            showsAfterUpdate: appState.settings.general.showsWhatsNewAfterUpdate,
            knownVersions: WhatsNewHistory.releases.map(\.version)
        )
        // Stored before the window opens, so a crash or a quick relaunch cannot show it again.
        if let record = decision.record {
            Defaults.set(record, forKey: .lastSeenVersion)
        }
        guard decision.show else {
            return
        }
        // No activation here: the window orders itself in front (`WhatsNewWindow`).
        appState.openWindow(.whatsNew)
    }
}
