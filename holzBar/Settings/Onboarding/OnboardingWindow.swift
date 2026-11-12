//
//  OnboardingWindow.swift
//  holzBar
//

import SwiftUI

// MARK: - OnboardingWindow

/// The scene of the onboarding: three short steps after the first launch, and again from About
/// (D-20, D-22).
struct OnboardingWindow: Scene {
    let appState: AppState
    @State private var model = OnboardingWindowModel()

    var body: some Scene {
        HolzBarWindow(id: .onboarding, appState: appState) {
            OnboardingView {
                appState.dismissWindow(.onboarding)
            }
            .onWindowChange { window in
                model.observe(window, navigationState: appState.navigationState)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: HolzBarTheme.Onboarding.width, height: 420)
        .environment(appState)
    }
}

// MARK: - OnboardingWindowModel

/// Centres the window once, tells the navigation state whether it is shown, and keeps only the
/// close button.
@MainActor
@Observable
private final class OnboardingWindowModel {
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var isCentered = false
    @ObservationIgnored private weak var navigationState: AppNavigationState?

    func observe(_ window: NSWindow?, navigationState: AppNavigationState) {
        observation = nil
        self.navigationState = navigationState
        guard let window else {
            return
        }
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        observation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] window, _ in
            Task { @MainActor in
                self?.windowVisibilityChanged(window)
            }
        }
    }

    private func windowVisibilityChanged(_ window: NSWindow) {
        if navigationState?.isOnboardingPresented != window.isVisible {
            navigationState?.isOnboardingPresented = window.isVisible
        }
        guard window.isVisible, !isCentered else {
            return
        }
        isCentered = true
        window.center()
    }
}
