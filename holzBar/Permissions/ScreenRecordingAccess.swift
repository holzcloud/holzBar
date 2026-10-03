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

    /// Whether the hint fits on one line, as in the holzBar Shelf.
    var isCompact = false

    /// Runs before the request, for example to hide a panel that would cover the prompt.
    var willRequest: () -> Void = {}

    /// macOS may need holzBar to reopen before the pictures appear.
    private var reopenNote: String {
        "If macOS offers to quit and reopen holzBar after you allow it, choose Quit & Reopen."
    }

    var body: some View {
        if isCompact {
            HStack {
                Text(feature.reason)
                    .lineLimit(1)
                allowButton
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
            }
            .help(reopenNote)
        } else {
            VStack(spacing: 8) {
                Text(feature.reason)
                    .multilineTextAlignment(.center)
                allowButton
                Text(reopenNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        }
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
