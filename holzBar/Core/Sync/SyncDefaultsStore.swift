//
//  SyncDefaultsStore.swift
//  holzBar
//

import Foundation

/// What ``SyncDefaultsStore/apply(_:table:)`` did with the units it was given.
nonisolated struct SyncApplyReport: Hashable, Sendable {
    /// The units whose payload was valid and is now in the preferences (also when it
    /// changed nothing because the preferences already held it).
    var applied: Set<SyncUnitKey>
    /// The units whose payload was not written: a unit this build does not know, a set, an
    /// invalid value or a value over its cap. The engine reports these as unusable.
    var skipped: Set<SyncUnitKey>
}

/// The preferences domain of the synced settings: reads it into a ``SyncSnapshot``, writes
/// unit payloads back and holds the few raw keys of this Mac's sync state.
///
/// The store is the only way the engine meets the real preferences. A snapshot holds the
/// synced units only (local keys, window frames and every `SettingsSync` key never appear),
/// and a payload reaches the preferences only through ``SyncProjection/defaultsWrites(applying:to:table:)``,
/// which checks every value, and only for a key that has a synced class.
///
/// The order of a remote apply is the one of the analysis (section 4.4): ``apply(_:table:)``
/// writes the preferences, then the caller calls ``setGeneration(_:)``, ``flush()`` and only
/// then persists this Mac's sync state, so a crash in between re-applies, and applying is
/// idempotent.
///
/// `SettingsSyncLastSynced` is read, never written: 0.0.7-beta1 needs it after a downgrade
/// and this build uses it as a tripwire (D-02), so the type has no function that changes it.
///
/// The type holds no logger: no value of a setting is ever logged (T-28-35).
nonisolated struct SyncDefaultsStore: @unchecked Sendable {
    /// The raw key of the generation of the last local change (analysis section 4.4).
    static let generationKey = "SettingsSyncGeneration"
    /// The raw key of the mirror of this Mac's counter (analysis section 4.4).
    static let counterMirrorKey = "SettingsSyncCounter"
    /// The raw key of the date 0.0.7-beta1 wrote at its last sync.
    static let lastSyncedKey = "SettingsSyncLastSynced"

    private let defaults: UserDefaults
    private let domainName: String

    /// - Parameters:
    ///   - defaults: The preferences, `UserDefaults.standard` in the app.
    ///   - domainName: The name of the domain `defaults` persists to: the bundle identifier
    ///     in the app, a unique suite name in tests.
    init(defaults: UserDefaults, domainName: String) {
        self.defaults = defaults
        self.domainName = domainName
    }

    // MARK: Snapshot

    /// The synced preferences as a snapshot.
    ///
    /// - Parameters:
    ///   - table: The unit table; its normalizers make the values comparable.
    ///   - generation: The generation of this Mac; the macOS 27 families and `known27` are
    ///     read only on ``SyncGeneration/g27``.
    ///   - baselineKeys: The units the sync state's baseline holds; one that this Mac maps
    ///     to another key is aliased even when the preferences no longer hold it (INV-A6).
    func snapshot(table: SyncUnitTable, generation: SyncGeneration, baselineKeys: Set<SyncUnitKey>) -> SyncSnapshot {
        let domain = persistentDomain().filter { key, _ in
            !SyncUnitTable.excludedKeyPrefixes.contains { key.hasPrefix($0) }
        }
        let values = SyncProjection.snapshot(defaults: domain, table: table, generation: generation)
        let owners = Set(domain[Defaults.Key.titleChangingItemOwners.rawValue] as? [String] ?? [])
        let aliased = SyncAlias.aliasedUnits(among: Set(values.keys).union(baselineKeys), titleChangingOwners: owners)
        let known27 = generation == .g27 ? SyncProjection.knownApplications(in: domain) : []
        return SyncSnapshot(values: values, aliased: aliased, known27: known27)
    }

    // MARK: Apply

    /// Writes the payloads into the preferences, each checked on its own: an invalid
    /// payload is skipped and reported, never the whole batch.
    @discardableResult
    func apply(_ units: [SyncUnitKey: SyncPayload], table: SyncUnitTable) -> SyncApplyReport {
        let current = persistentDomain()
        var report = SyncApplyReport(applied: [], skipped: [])
        for key in units.keys.sorted() {
            guard let payload = units[key] else {
                continue
            }
            if Self.isAcceptable(payload, for: key, table: table) {
                report.applied.insert(key)
            } else {
                report.skipped.insert(key)
            }
        }
        let accepted = units.filter { report.applied.contains($0.key) }
        write(SyncProjection.defaultsWrites(applying: accepted, to: current, table: table))
        return report
    }

    /// Adds the applications of the set `known27` to `KnownApplications27`, which never
    /// loses an element (D-06).
    func applyKnownApplications(_ elements: [String]) {
        write(SyncProjection.knownApplicationsUnion(elements, into: persistentDomain()))
    }

    /// Whether ``SyncProjection/defaultsWrites(applying:to:table:)`` writes the payload of a
    /// unit: it is a known value unit, and the value is valid and within its cap.
    private static func isAcceptable(_ payload: SyncPayload, for key: SyncUnitKey, table: SyncUnitTable) -> Bool {
        guard let descriptor = table.descriptor(for: key), !descriptor.isSet else {
            return false
        }
        switch payload {
        case .deleted:
            return true
        case .value(let value):
            let item: String? = if case .split(_, let name) = key { name } else { nil }
            return descriptor.validate(item, value) && !descriptor.isOverCap(value)
        }
    }

    /// Sets or removes each key, only when it is a key with a synced class.
    private func write(_ writes: [String: Any?]) {
        for key in writes.keys.sorted() {
            guard Self.isSynced(storedKey: key), let change = writes[key] else {
                continue
            }
            if let value = change {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Whether the stored key belongs to a synced unit.
    private static func isSynced(storedKey: String) -> Bool {
        guard !SyncUnitTable.isExcluded(storedKey: storedKey), let key = Defaults.Key(rawValue: storedKey) else {
            return false
        }
        if case .local = SyncUnitTable.keyClass(key) {
            return false
        }
        return true
    }

    // MARK: Sync state keys

    /// The generation of the last local change; `nil` when none was written.
    var generation: UInt64? {
        (defaults.object(forKey: Self.generationKey) as? NSNumber)?.uint64Value
    }

    func setGeneration(_ value: UInt64) {
        defaults.set(NSNumber(value: value), forKey: Self.generationKey)
    }

    /// The mirror of this Mac's counter; `0` when none was written.
    var counterMirror: UInt64 {
        (defaults.object(forKey: Self.counterMirrorKey) as? NSNumber)?.uint64Value ?? 0
    }

    func setCounterMirror(_ value: UInt64) {
        defaults.set(NSNumber(value: value), forKey: Self.counterMirrorKey)
    }

    /// The date 0.0.7-beta1 stored at its last sync, if it is there. Read only (D-02).
    var lastSyncedSeen: Date? {
        defaults.object(forKey: Self.lastSyncedKey) as? Date
    }

    /// Writes the preferences to disk, so another process (and a Mac that is restored from a
    /// backup) never sees a generation older than the values it belongs to.
    func flush() {
        CFPreferencesAppSynchronize(domainName as CFString)
    }

    private func persistentDomain() -> [String: Any] {
        defaults.persistentDomain(forName: domainName) ?? [:]
    }
}
