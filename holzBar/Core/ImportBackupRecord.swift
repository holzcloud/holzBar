//
//  ImportBackupRecord.swift
//  holzBar
//

import Foundation

/// What an import is about to overwrite, kept so the import can be undone.
///
/// The record holds the previous value of every key the import writes, and the keys that had no
/// value at all. It is written to disk before the first key is touched (the import restarts
/// holzBar, so an in-memory undo would not survive) and restored key by key: restoring sets
/// the previous values and removes the keys the import added, and touches nothing else.
nonisolated struct ImportBackupRecord {
    /// The format of the property list; a record of another format is refused.
    private static let version = 1

    let source: ImportSource
    let date: Date
    /// How many settings the import changed: the number the undo toast says, 0 when unknown.
    let changeCount: Int
    /// The previous values of the keys that had one, by holzBar's stored name.
    let before: [String: Any]
    /// The keys that had no value before the import, sorted.
    let absent: [String]

    /// Records what `domain` holds for the keys an import touches.
    ///
    /// - Parameters:
    ///   - source: The app the import comes from.
    ///   - date: When the import happens.
    ///   - changeCount: How many settings the import changes; a negative number counts as 0.
    ///   - touchedKeys: The stored names the import writes.
    ///   - domain: holzBar's own defaults domain before the import.
    static func make(
        source: ImportSource,
        date: Date,
        changeCount: Int,
        touchedKeys: [String],
        domain: [String: Any]
    ) -> ImportBackupRecord {
        var before: [String: Any] = [:]
        var absent: [String] = []
        for key in Set(touchedKeys) {
            if let value = domain[key] {
                before[key] = value
            } else {
                absent.append(key)
            }
        }
        return ImportBackupRecord(
            source: source,
            date: date,
            changeCount: max(0, changeCount),
            before: before,
            absent: absent.sorted()
        )
    }

    private init(source: ImportSource, date: Date, changeCount: Int, before: [String: Any], absent: [String]) {
        self.source = source
        self.date = date
        self.changeCount = changeCount
        self.before = before
        self.absent = absent
    }

    /// The record as a property list: plain types only (the source's raw value, a date, a
    /// dictionary and a list of strings).
    func propertyList() -> [String: Any] {
        [
            "version": Self.version,
            "source": source.rawValue,
            "date": date,
            "changeCount": changeCount,
            "before": before,
            "absent": absent,
        ]
    }

    /// Reads a record back from a property list, or returns `nil` when it is not one: another
    /// format, an unknown source, a missing or mistyped field (the change count alone reads as 0
    /// when it is missing, negative or not a whole number). Keys that are not holzBar's own
    /// importable settings are dropped.
    init?(propertyList: [String: Any]) {
        guard
            propertyList["version"] as? Int == Self.version,
            let raw = propertyList["source"] as? String,
            let source = ImportSource(rawValue: raw),
            let date = propertyList["date"] as? Date,
            let before = propertyList["before"] as? [String: Any],
            let absent = propertyList["absent"] as? [String]
        else {
            return nil
        }
        self.init(
            source: source,
            date: date,
            changeCount: Self.count(in: propertyList["changeCount"]),
            before: before.filter { Defaults.Key.importableKinds[$0.key] != nil },
            absent: absent.filter { Defaults.Key.importableKinds[$0] != nil }.sorted()
        )
    }

    /// A stored change count: a non-negative whole number, otherwise 0.
    private static func count(in value: Any?) -> Int {
        guard let number = value as? Int, number >= 0 else {
            return 0
        }
        return number
    }

    /// The writes that put the settings back as they were.
    ///
    /// The previous values go through holzBar's validation again, so a record that was changed
    /// on disk cannot write a value of the wrong kind. `remove` holds only importable keys that
    /// had no value before and are not in `set`.
    ///
    /// - Parameter ownBundleIdentifier: holzBar's own bundle identifier.
    func restoreWrites(ownBundleIdentifier: String) -> (set: [String: Any], remove: [String]) {
        let set = Defaults.Key.validatedSettings(before, ownBundleIdentifier: ownBundleIdentifier).accepted
        let remove = absent.filter { Defaults.Key.importableKinds[$0] != nil && before[$0] == nil }
        return (set, remove)
    }
}
