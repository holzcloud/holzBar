//
//  PreviousAppImporter.swift
//  holzBar
//

import AppKit
import OSLog

/// Takes over the settings of another app (Thaw): detects it, reads its defaults after the user's
/// click, plans what would change, and applies the plan with a backup first.
///
/// This is not the replacing import of holzBar's own settings file (``SettingsBackup``): it
/// writes only the keys the plan carries and never removes a key. Nothing here reads a file or
/// a defaults domain before the user presses a button of the import sheet, and nothing it reads is
/// logged or kept beyond the preview.
@MainActor
enum PreviousAppImporter {
    private static let logger = Logger(category: "PreviousAppImporter")

    /// Why an import stopped before it changed anything.
    enum ImportError: Error {
        /// The record of the previous settings could not be written, so no key was touched.
        case backupFailed
    }

    /// Where the record of the settings before the last import lives: one file in holzBar's folder
    /// in Application Support, replaced by the next import.
    static var backupURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: "ImportBackup.plist", directoryHint: .notDirectory)
    }

    /// Whether the app is installed, found by its bundle identifier; its files are not read.
    static func isInstalled(_ source: ImportSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) != nil
    }

    /// The app's defaults domain, or `nil` when it is empty or macOS holds none for it.
    static func readDomain(of source: ImportSource) -> [String: Any]? {
        guard let domain = UserDefaults.standard.persistentDomain(forName: source.bundleIdentifier), !domain.isEmpty else {
            return nil
        }
        return domain
    }

    /// What importing `settings` of the app would change in holzBar now.
    static func plan(for source: ImportSource, settings: [String: Any], appState: AppState) -> ImportPlan {
        PreviousAppImport.plan(
            source: source,
            settings: settings,
            current: ImportTargets.currentValues(in: appState.settings),
            currentHotkeys: currentHotkeys(),
            hotkeyRules: hotkeyRules,
            excludedPrefixes: SettingsBackup.excludedKeyPrefixes,
            ownBundleIdentifier: Constants.bundleIdentifier
        )
    }

    /// holzBar's stored hotkeys now, by action: the merged write starts from them, so a hotkey the
    /// source does not have, an item's or a profile's included, is written back unchanged. An entry
    /// that is not a combination is one holzBar cannot read at launch either.
    private static func currentHotkeys() -> [String: Data] {
        (Defaults.dictionary(forKey: .hotkeys) ?? [:]).compactMapValues { $0 as? Data }
    }

    /// The rules a hotkey of another app must pass: an action holzBar has and shows in Settings,
    /// and a combination holzBar would load. A combination it would refuse at launch (a key code out
    /// of range, an unknown modifier bit, no modifier or Shift alone, and Option alone where the
    /// system refuses it) is never imported.
    private static let hotkeyRules = ImportHotkeyRules(
        knownActions: Set(HotkeyAction.allCases.map(\.rawValue).filter { ImportTargets.hotkeyEntry(for: $0) != nil })
    ) { data in
        guard let combination = HotkeyStorage.decode(data) else {
            return false
        }
        let refusesOptionOnly = if #available(macOS 15.0, *) { true } else { false }
        return HotkeyStorage.loadRejection(modifiers: combination.modifiers, refusesOptionOnly: refusesOptionOnly) == nil
    }

    /// Writes the record of the settings the plan overwrites, then the plan's keys, then restarts
    /// holzBar so every model reads them at launch.
    ///
    /// The record comes first and is written atomically: when it cannot be written, this throws
    /// before any key is touched. Only keys of the plan are written, validated once more, and no
    /// key is removed.
    ///
    /// - Throws: ``ImportError/backupFailed`` when the record could not be written.
    static func apply(_ plan: ImportPlan) throws {
        let writes = Defaults.Key.validatedSettings(plan.writes, ownBundleIdentifier: Constants.bundleIdentifier).accepted
        let defaults = UserDefaults.standard
        let domain = defaults.persistentDomain(forName: Constants.bundleIdentifier) ?? [:]
        let record = ImportBackupRecord.make(
            source: plan.source,
            date: .now,
            touchedKeys: Array(writes.keys),
            domain: domain
        )
        do {
            try write(record)
        } catch {
            logger.error("The backup before an import could not be written: \(error, privacy: .private)")
            throw ImportError.backupFailed
        }
        for (key, value) in writes {
            defaults.set(value, forKey: key)
        }
        logger.notice("Imported \(writes.count, privacy: .public) settings from \(plan.source.rawValue, privacy: .public)")
        SettingsBackup.relaunch()
    }

    /// Writes the record: the folder is 0700, the file 0600 and excluded from backups.
    private static func write(_ record: ImportBackupRecord) throws {
        var url = backupURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try PropertyListSerialization.data(fromPropertyList: record.propertyList(), format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
