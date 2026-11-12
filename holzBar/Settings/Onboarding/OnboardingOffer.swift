//
//  OnboardingOffer.swift
//  holzBar
//

import Foundation

/// Opens the onboarding by itself, once, after the first launch of a new install (D-20, D-37).
///
/// ``OnboardingPolicy`` decides. The pending flag is cleared before the window opens, so a
/// crash or a relaunch cannot show it again; About runs it again on request.
@MainActor
enum OnboardingOffer {
    /// How long after the setup the window waits, so that it never competes with the bar.
    private static let delay = Duration.seconds(1)

    static func offerIfPending(appState: AppState) async {
        guard Defaults.bool(forKey: .onboardingPending) else {
            return
        }
        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }
        let opens = OnboardingPolicy.opensByItself(
            isPending: Defaults.bool(forKey: .onboardingPending),
            hasImportedSettings: appState.didImportPreviousSettings,
            hasProfiles: !appState.profiles.profiles.isEmpty
        )
        // Stored first: whether it opens now or can no longer open, it never waits again.
        Defaults.set(false, forKey: .onboardingPending)
        guard opens else {
            return
        }
        appState.activate(for: .onboarding)
        appState.openWindow(.onboarding)
    }
}
