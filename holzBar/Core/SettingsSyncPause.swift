//
//  SettingsSyncPause.swift
//  holzBar
//

/// The switch that pauses settings sync in this build.
///
/// Settings sync is paused in 0.0.7-beta2: even reworked, it could still lose a menu bar
/// arrangement between Macs in rare cases, so it returns after a redesign in the next beta.
/// While it is paused, holzBar never reads, writes, watches, creates or mounts anything in
/// the sync folder, never asks about synced settings or hints at them, and never changes
/// the stored sync configuration: the choice to sync, the folder's bookmark, this Mac's
/// sync id and every `SettingsSync…` key stay as they are, so sync can resume later.
/// Exporting and importing settings files keep working.
nonisolated enum SettingsSyncPause {
    /// Whether settings sync is paused in this build.
    static let isPaused = true

    /// Whether settings sync runs.
    ///
    /// - Parameters:
    ///   - isTurnedOn: Whether the user turned sync on, as stored.
    ///   - isPaused: Whether sync is paused in this build.
    static func syncs(isTurnedOn: Bool, isPaused: Bool = isPaused) -> Bool {
        isTurnedOn && !isPaused
    }

    /// Whether the user can turn sync on or off, or choose its folder.
    ///
    /// - Parameter isPaused: Whether sync is paused in this build.
    static func allowsChanges(isPaused: Bool = isPaused) -> Bool {
        !isPaused
    }
}
