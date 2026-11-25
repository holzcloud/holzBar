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
        /// The chosen file is not something holzBar reads as settings: not a regular local file,
        /// too large, or not a property list dictionary.
        case unusableFile
    }

    /// What a read refuses before it looks at a single key: the file is not one holzBar reads.
    /// Any other error of the read (no permission, the file is gone) is a read that failed.
    private static let refusedFileCodes: Set<CocoaError.Code> = [
        .fileReadUnsupportedScheme,
        .fileReadUnknown,
        .fileReadTooLarge,
        .fileReadCorruptFile,
        .propertyListReadCorrupt,
        .propertyListReadUnknownVersion,
        .propertyListReadStream,
    ]

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

    /// Reads a settings file the user chose, as a property list dictionary.
    ///
    /// The same guards as the import of holzBar's own settings (``SettingsBackup``): a local file
    /// only, a regular one, of at most the import size limit checked before the read and again on
    /// the bytes read, decoded as a property list and never unarchived. Which app the dictionary
    /// belongs to is decided afterwards, from its keys (``PreviousAppImport/recognize(_:)``).
    ///
    /// - Throws: ``ImportError/unusableFile`` when the URL is not a file, the file is not a regular
    ///   one, is too large or is not a property list dictionary, and the system's error when the
    ///   read itself fails (no permission, the file is gone).
    static func readFile(at url: URL) throws -> [String: Any] {
        do {
            return try decodeFile(at: url)
        } catch let error as CocoaError where refusedFileCodes.contains(error.code) {
            throw ImportError.unusableFile
        }
    }

    private static func decodeFile(at url: URL) throws -> [String: Any] {
        // Data(contentsOf:) would fetch an http(s) URL; holzBar reads only files.
        guard url.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let file = url.resolvingSymlinksInPath()
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        // A pipe or a device could block the read or never end.
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnknown)
        }
        // A settings file is read whole into memory: one over the limit is refused unread.
        if let size = values.fileSize, !SettingsSchema.acceptsImport(ofSize: size) {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: file)
        defer {
            try? handle.close()
        }
        // The size above can change after it was read, so the read itself stops one byte past
        // the limit.
        let data = try handle.read(upToCount: SettingsSchema.maximumImportSize + 1) ?? Data()
        guard SettingsSchema.acceptsImport(ofSize: data.count) else {
            throw CocoaError(.fileReadTooLarge)
        }
        guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return settings
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
    /// of range, an unknown modifier bit, no modifier or Shift alone, Option alone where the
    /// system refuses it, and one the system reserves for itself) is never imported.
    private static var hotkeyRules: ImportHotkeyRules {
        let reserved = KeyCombination.systemReservedPairs()
        return ImportHotkeyRules(
            knownActions: Set(HotkeyAction.allCases.map(\.rawValue).filter { ImportTargets.hotkeyEntry(for: $0) != nil })
        ) { data in
            guard let combination = HotkeyStorage.decode(data) else {
                return nil
            }
            let refusesOptionOnly = if #available(macOS 15.0, *) { true } else { false }
            guard
                HotkeyStorage.loadRejection(modifiers: combination.modifiers, refusesOptionOnly: refusesOptionOnly) == nil,
                !reserved.contains([combination.key, combination.modifiers])
            else {
                return nil
            }
            return "\(combination.key)-\(combination.modifiers)"
        }
    }

    /// Writes the record of the settings the plan overwrites, marks the undo to be offered, writes
    /// the plan's keys, then restarts holzBar so every model reads them at launch.
    ///
    /// The record comes first and is written atomically: when it cannot be written, this throws
    /// before any key is touched. The marker for the undo toast is set only once the record is on
    /// disk. Only keys of the plan are written, validated once more, and no key is removed.
    ///
    /// - Throws: ``ImportError/backupFailed`` when the record could not be written.
    static func apply(_ plan: ImportPlan) throws {
        let writes = Defaults.Key.validatedSettings(plan.writes, ownBundleIdentifier: Constants.bundleIdentifier).accepted
        let defaults = UserDefaults.standard
        let domain = defaults.persistentDomain(forName: Constants.bundleIdentifier) ?? [:]
        let record = ImportBackupRecord.make(
            source: plan.source,
            date: .now,
            changeCount: plan.changes.count,
            touchedKeys: Array(writes.keys),
            domain: domain
        )
        do {
            try write(record)
        } catch {
            logger.error("The backup before an import could not be written: \(error, privacy: .private)")
            throw ImportError.backupFailed
        }
        // After the record is on disk and before the first key is written: a quit in between
        // still offers the undo of what was written.
        Defaults.set(true, forKey: .previousAppImportUndoPending)
        for (key, value) in writes {
            defaults.set(value, forKey: key)
        }
        logger.notice("Imported \(writes.count, privacy: .public) settings from \(plan.source.rawValue, privacy: .public)")
        SettingsBackup.relaunch()
    }

    /// The record of the settings before the last import, or `nil` when there is none or the file
    /// is not a record holzBar reads. It stays until the next import replaces it or a restore
    /// uses it.
    static func lastImport() -> ImportBackupRecord? {
        guard
            let data = try? Data(contentsOf: backupURL),
            let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return ImportBackupRecord(propertyList: list)
    }

    /// Puts the settings back as the record holds them, deletes the record and restarts holzBar.
    ///
    /// Only the keys the import touched change: each gets its earlier value (validated again), and
    /// each that had none is removed. No other key is read or written.
    static func restore(_ record: ImportBackupRecord) {
        let writes = record.restoreWrites(ownBundleIdentifier: Constants.bundleIdentifier)
        let defaults = UserDefaults.standard
        for (key, value) in writes.set {
            defaults.set(value, forKey: key)
        }
        for key in writes.remove {
            defaults.removeObject(forKey: key)
        }
        Defaults.removeObject(forKey: .previousAppImportUndoPending)
        // Deleted once the keys are back; a record that cannot be deleted would only offer the
        // same restore again.
        try? FileManager.default.removeItem(at: backupURL)
        logger.notice("Restored \(writes.set.count + writes.remove.count, privacy: .public) settings from before an import")
        SettingsBackup.relaunch()
    }

    /// How long after the setup the undo toast waits, so that it does not compete with the bar
    /// that comes up (as the first-run offers do).
    private static let undoOfferDelay = Duration.seconds(1)

    /// After the restart an import causes, offers its undo once as the toast at the menu bar.
    ///
    /// The marker is cleared first, so the offer never shows twice, also when the toast is not
    /// shown. With no record on disk there is no toast. Undo calls ``restore(_:)`` without a
    /// question: nothing but the import is lost.
    ///
    /// - Parameter appState: The app state, whose undo history holds the change.
    static func offerUndoAfterLaunch(appState: AppState) async {
        guard Defaults.bool(forKey: .previousAppImportUndoPending) else {
            return
        }
        Defaults.removeObject(forKey: .previousAppImportUndoPending)
        guard let record = lastImport() else {
            return
        }
        do {
            try await Task.sleep(for: undoOfferDelay)
        } catch {
            return
        }
        guard appState.isSetUp else {
            return
        }
        let sentence = String(localized: "Imported \(record.changeCount) settings from \(record.source.productName)")
        let change = LayoutUndo.Change(
            sentence: sentence,
            actionName: String(localized: "Import Settings"),
            inverse: { nil },
            perform: {
                restore(record)
                return true
            }
        )
        appState.layoutUndo.record(change, place: .menuBar)
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
