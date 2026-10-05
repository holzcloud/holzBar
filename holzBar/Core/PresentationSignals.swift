//
//  PresentationSignals.swift
//  holzBar
//

import Foundation

/// Whether the screen is shown to someone else, for Zen mode while presenting (THAW-10).
///
/// Only signals that need no permission and no polling: a display in a mirror set (read
/// when the displays change) and macOS's screen sharing agent among the running
/// applications (read when the running applications change). Thaw read the process table
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

    /// Tells which changes of the running applications are evaluated: only those that change
    /// the set of bundle identifiers.
    ///
    /// NSWorkspace reports every process that starts or quits, helpers included, and most of
    /// those changes leave the set of bundle identifiers as it was (measured 2026-10-05: 115
    /// processes shared 90 identifiers, and 7 of 9 changes in five idle minutes left the set
    /// unchanged), so only a change of the set is evaluated.
    nonisolated struct Trigger: Equatable, Sendable {
        /// The bundle identifiers last evaluated; `nil` before the first evaluation.
        private(set) var evaluated: Set<String>?

        /// Whether `running` differs from the identifiers last evaluated; records it when it does.
        mutating func needsEvaluation(running: Set<String>) -> Bool {
            guard running != evaluated else {
                return false
            }
            evaluated = running
            return true
        }

        /// Forgets the last identifiers, so the next call evaluates.
        mutating func reset() {
            evaluated = nil
        }
    }
}
