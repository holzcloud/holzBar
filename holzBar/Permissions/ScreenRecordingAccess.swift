//
//  ScreenRecordingAccess.swift
//  holzBar
//

import OSLog
import SwiftUI

// MARK: - ScreenRecordingAccess

/// Asks for Screen Recording in context: from the feature that needs it, when it is first
/// used, instead of at the first launch.
@MainActor
enum ScreenRecordingAccess {
    /// The logger for Screen Recording requests.
    private static let logger = Logger(category: "ScreenRecordingAccess")

    /// Returns a Boolean value that indicates whether holzBar has Screen Recording.
    static func isGranted(_ appState: AppState) -> Bool {
        appState.permissions.screenRecording.hasPermission
    }

    /// Whether the offer in ``offerOnce(for:appState:willRequest:)`` is still due.
    static func shouldOfferOnce(_ appState: AppState) -> Bool {
        !isGranted(appState) && !Defaults.bool(forKey: .screenRecordingOffered)
    }

    /// Asks once, in a window, whether holzBar may use Screen Recording for the pictures in the
    /// holzBar Shelf, and remembers that it asked. Without the permission the Shelf shows the
    /// apps' icons; the Permissions window can still allow or revoke it later.
    ///
    /// - Parameter willRequest: Runs before the window, for example to hide a panel that would
    ///   cover it.
    static func offerOnce(for feature: ScreenRecordingFeature, appState: AppState, willRequest: () -> Void = {}) {
        guard shouldOfferOnce(appState) else {
            return
        }
        Defaults.set(true, forKey: .screenRecordingOffered)
        willRequest()
        _ = appState.activate(for: .settings)
        let alert = NSAlert()
        alert.messageText = String(localized: "Show real pictures of your menu bar items?")
        alert.informativeText = feature.reason.localizedFromCatalog + "\n\n"
            + String(localized: "Without it holzBar shows the apps' icons. You can change this any time in Settings → Advanced.")
            + "\n\n" + String(localized: "If macOS offers to quit and reopen holzBar after you allow it, choose Quit & Reopen.")
        alert.addButton(withTitle: String(localized: "Allow Screen Recording…"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task {
            await request(for: feature, appState: appState)
        }
    }

    /// Asks for Screen Recording for the given feature.
    ///
    /// Shows the system prompt and opens the Screen Recording pane of System Settings, then
    /// waits for the grant (see ``Permission/waitForPermission()``).
    ///
    /// - Returns: `true` when holzBar has the permission, at once when it already had it.
    @discardableResult
    static func request(for feature: ScreenRecordingFeature, appState: AppState) async -> Bool {
        let permission = appState.permissions.screenRecording
        guard !permission.hasPermission else {
            return true
        }
        // The feature's name is part of holzBar, not personal data.
        logger.info("Asking for Screen Recording for the \(feature.name, privacy: .public)")
        permission.performRequest()
        guard await permission.waitForPermission() else {
            return false
        }
        _ = ScreenCapture.cachedCheckPermissions(reset: true)
        await appState.imageCache.updateCache()
        return true
    }
}

// MARK: - ScreenRecordingHint

/// Says why a feature needs Screen Recording and offers to allow it.
///
/// The hint is shown only while holzBar does not have the permission; the views that show
/// it observe the app state, which publishes the grant.
struct ScreenRecordingHint: View {
    /// The feature that needs Screen Recording.
    let feature: ScreenRecordingFeature

    /// The shared app state.
    let appState: AppState

    /// Runs before the request, for example to hide a panel that would cover the prompt.
    var willRequest: () -> Void = {}

    /// macOS may need holzBar to reopen before the pictures appear.
    private var reopenNote: String {
        String(localized: "If macOS offers to quit and reopen holzBar after you allow it, choose Quit & Reopen.")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text(feature.reason.localizedFromCatalog)
                    .multilineTextAlignment(.center)
                PreviewBadge()
            }
            allowButton
            Text(reopenNote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(10)
    }

    @ViewBuilder
    private var allowButton: some View {
        Button("Allow Screen Recording…") {
            willRequest()
            Task {
                await ScreenRecordingAccess.request(for: feature, appState: appState)
            }
        }
    }
}
