//
//  PresentationSignals.swift
//  holzBar
//

import Foundation

/// Whether the screen is shown to someone else, for Zen mode while presenting (THAW-10).
///
/// Only signals that need no permission and no polling: a display in a mirror set (read
/// when the displays change) and macOS's screen sharing agent among the running
/// applications (read when an application launches or quits). Thaw read the process table
/// every 5 seconds for `screensharingd`; holzBar never polls.
nonisolated enum PresentationSignals {
    /// The bundle identifier of macOS's per-user screen sharing agent, which runs while
    /// another Mac views or controls this one.
    static let screenSharingAgentBundleID = "com.apple.screensharing.agent"

    /// Whether the screen is presented: a display is mirrored or the screen is shared.
    ///
    /// - Parameters:
    ///   - mirroredDisplays: The number of active displays in a mirror set.
    ///   - runningBundleIDs: The bundle identifiers of the running applications.
    static func isPresenting(mirroredDisplays: Int, runningBundleIDs: Set<String>) -> Bool {
        mirroredDisplays > 0 || runningBundleIDs.contains(screenSharingAgentBundleID)
    }
}
