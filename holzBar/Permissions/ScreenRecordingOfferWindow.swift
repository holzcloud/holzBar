//
//  ScreenRecordingOfferWindow.swift
//  holzBar
//

import SwiftUI

// MARK: - ScreenRecordingOfferWindow

/// The one-time offer of Screen Recording, in holzBar's look instead of a system alert (D-25).
///
/// It is a window of its own: the holzBar Shelf closes before the offer (it would cover it),
/// so no window is left to attach a sheet to. Closing the window is Not Now.
struct ScreenRecordingOfferWindow: Scene {
    let appState: AppState
    @State private var model = ScreenRecordingOfferWindowModel()

    var body: some Scene {
        HolzBarWindow(id: .screenRecordingOffer, appState: appState) {
            ScreenRecordingOfferView()
                .onWindowChange { window in
                    model.observe(window)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .environment(appState)
    }
}

/// The confirmation of the offer for the feature the navigation state names.
private struct ScreenRecordingOfferView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let feature = appState.navigationState.screenRecordingOfferFeature {
            ConfirmSheet(
                title: Text("Show real pictures of your menu bar items?"),
                message: Text(verbatim: feature.reason.localizedFromCatalog)
                    + Text(verbatim: "\n\n")
                    + Text("Without it holzBar shows the apps' icons. You can allow it later in Layout.")
                    + Text(verbatim: "\n\n")
                    + Text("If macOS offers to quit and reopen holzBar after you allow it, choose Quit & Reopen."),
                confirmTitle: "Allow Screen Recording…",
                cancelTitle: "Not Now",
                onConfirm: {
                    close()
                    Task {
                        await ScreenRecordingAccess.request(for: feature, appState: appState)
                    }
                },
                onCancel: close
            )
        }
    }

    private func close() {
        appState.navigationState.screenRecordingOfferFeature = nil
        appState.dismissWindow(.screenRecordingOffer)
    }
}

// MARK: - ScreenRecordingOfferWindowModel

/// Centres the window once and keeps only the close button.
@MainActor
@Observable
private final class ScreenRecordingOfferWindowModel {
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var isCentered = false

    func observe(_ window: NSWindow?) {
        observation = nil
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
        guard window.isVisible, !isCentered else {
            return
        }
        isCentered = true
        window.center()
    }
}
