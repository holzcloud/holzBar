//
//  SyncDeviceFile.swift
//  holzBar
//

import Foundation

/// Why a file or a state was refused. A refused device file is never partly merged.
nonisolated enum SyncRefusal: Error, Hashable, Sendable {
    /// Larger than the limit, with its size in bytes.
    case tooLarge(Int)
    /// Not a property list.
    case notPropertyList
    /// A property list of the wrong shape; the text names the part, never the content.
    case wrongStructure(String)
    /// Written by a newer major format, with its number. It is never rewritten.
    case newerFormat(Int)
    /// The file's name is not the `mac` field it holds.
    case nameMismatch
    /// A counter above the largest allowed one, or below the smallest.
    case counterOutOfRange
    /// A family or a set with more elements than allowed, with its name.
    case tooManyEntries(String)
    /// An entry whose dot the file's own context has not seen: the file claims a change it
    /// has not seen itself.
    case uncoveredEntry
    /// A symbolic link where a file is expected.
    case symbolicLink
    /// A folder, a pipe or anything else that is not a regular file.
    case notRegularFile
    /// The file could not be opened or read.
    case unreadable
}

/// The per-Mac file of the synced settings: `<folder>/holzBar/Macs/<MacID>.plist`.
///
/// Each file is a binary property list that holds one Mac's whole replica and is written
/// only by that Mac, so no two writers ever race. Every other Mac reads it and joins it
/// into its own replica.
///
/// Anyone who can write the folder can write these files. A file that is too large, is not
/// a property list, comes from a newer format, is named differently from the Mac it
/// claims to be or is malformed in any part is refused whole (``SyncRefusal``). Names,
/// fields and units this build does not know pass through decode and encode unchanged, so
/// a later build can add units and families and this build relays them.
nonisolated enum SyncDeviceFile {
    /// The folder of the device files, below the sync folder.
    static let folderComponents = ["holzBar", "Macs"]

    /// The major format this build reads and writes.
    static let currentFormat = 1

    /// The additive minor format this build writes.
    static let currentMinor = 0

    /// The largest device file read, 1 MiB. The writer's limit is the same, so no build
    /// refuses a file a build of the same format wrote.
    static let maximumReadSize = 1 << 20

    /// The largest device file written, 1 MiB.
    static let maximumWriteSize = 1 << 20

    /// The largest counter a dot or a context may hold.
    static let maximumCounter: UInt64 = 1 << 34

    /// The most items a family of split units holds.
    static let maximumEntriesPerFamily = 1024

    /// The most elements a set holds.
    static let maximumSetElements = 2000

    /// The most characters of an installation nonce.
    static let maximumInstallationLength = 64

    /// What a device file holds.
    nonisolated struct Contents: Hashable, Sendable {
        /// The major format.
        var format: Int
        /// The additive minor format.
        var minor: Int
        /// The version of the unit table the writer used.
        var unitTable: Int
        /// The Mac that wrote the file; it is also the file's name.
        var mac: SyncMacID
        /// The nonce of the writer's installation, changed when the Mac re-identifies.
        var installation: String
        /// When the file was written, for display only.
        var written: Date
        /// The writer's replica.
        var replica: SyncReplica
        /// The top-level fields this build does not know.
        var extra: [String: SyncValue]

        init(
            format: Int = SyncDeviceFile.currentFormat,
            minor: Int = SyncDeviceFile.currentMinor,
            unitTable: Int,
            mac: SyncMacID,
            installation: String,
            written: Date,
            replica: SyncReplica,
            extra: [String: SyncValue] = [:]
        ) {
            self.format = format
            self.minor = minor
            self.unitTable = unitTable
            self.mac = mac
            self.installation = installation
            self.written = written
            self.replica = replica
            self.extra = extra
        }
    }

    // MARK: Keys

    private static let knownKeys: Set<String> = [
        "format", "minor", "unitTable", "mac", "installation", "written", "context", "units", "entries", "sets",
    ]
    private static let knownEntryKeys: Set<String> = ["mac", "n", "at", "value", "deleted"]

    // MARK: Encoding

    /// The binary property list of `contents`.
    ///
    /// - Throws: ``SyncRefusal/tooLarge(_:)`` when the file would exceed
    ///   ``maximumWriteSize``; no byte is returned then.
    static func encode(_ contents: Contents) throws(SyncRefusal) -> Data {
        var root: [String: Any] = contents.extra.mapValues(\.propertyList)
        root["format"] = contents.format
        root["minor"] = contents.minor
        root["unitTable"] = contents.unitTable
        root["mac"] = contents.mac.rawValue
        root["installation"] = contents.installation
        root["written"] = contents.written
        // sync-lint: ordered every item is assigned to its own key of a dictionary
        for (name, value) in replicaFields(contents.replica) {
            root[name] = value
        }
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        } catch {
            throw .wrongStructure("encode")
        }
        guard data.count <= maximumWriteSize else {
            throw .tooLarge(data.count)
        }
        return data
    }

    /// The `context`, `units`, `entries` and `sets` fields of a replica, as property-list
    /// objects. The sync state (``SyncStateCodec``) stores its replica the same way.
    static func replicaFields(_ replica: SyncReplica) -> [String: Any] {
        var context: [String: Any] = [:]
        for mac in replica.context.macs {
            context[mac.rawValue] = Int64(clamping: replica.context[mac])
        }
        var units: [String: Any] = [:]
        var entries: [String: [String: Any]] = [:]
        // sync-lint: ordered every unit is assigned to its own key of a dictionary
        for key in replica.keys {
            let list = replica.live(key).map(entryFields)
            switch key {
            case .whole(let name):
                units[name] = list
            case .split(let family, let item):
                entries[family, default: [:]][item] = list
            }
        }
        var sets: [String: Any] = [:]
        for name in replica.sets.keys.sorted() {
            sets[name] = replica.sets[name]
        }
        return ["context": context, "units": units, "entries": entries, "sets": sets]
    }

    private static func entryFields(_ entry: SyncEntry) -> [String: Any] {
        var fields: [String: Any] = entry.extra.mapValues(\.propertyList)
        fields["mac"] = entry.dot.mac.rawValue
        fields["n"] = Int64(clamping: entry.dot.n)
        fields["at"] = entry.at
        switch entry.payload {
        case .value(let value):
            fields["value"] = value.propertyList
        case .deleted:
            fields["deleted"] = true
        }
        return fields
    }

    // MARK: Decoding

    /// Reads a device file.
    ///
    /// - Parameters:
    ///   - data: The file's bytes.
    ///   - fileName: The file's name; it must be `<mac>.plist` for the `mac` the file holds.
    /// - Returns: The contents, or the reason the whole file is refused.
    static func decode(_ data: Data, fileName: String) -> Result<Contents, SyncRefusal> {
        do throws(SyncRefusal) {
            return .success(try parse(data, fileName: fileName))
        } catch {
            return .failure(error)
        }
    }

    private static func parse(_ data: Data, fileName: String) throws(SyncRefusal) -> Contents {
        guard data.count <= maximumReadSize else {
            throw .tooLarge(data.count)
        }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw .notPropertyList
        }
        guard let root = object as? [String: Any] else {
            throw .wrongStructure("root")
        }
        // The format comes first: a file of a newer format is named as such and never read
        // further, whatever else is in it.
        let format = try integer(root["format"].flatMap { SyncValue(propertyList: $0) }, "format")
        guard format >= 1 else {
            throw .wrongStructure("format")
        }
        guard format <= currentFormat else {
            throw .newerFormat(format)
        }
        guard let top = SyncValue(propertyList: root)?.dictionaryValue else {
            throw .wrongStructure("values")
        }
        guard let macString = top["mac"]?.stringValue, let mac = SyncMacID(macString) else {
            throw .wrongStructure("mac")
        }
        guard macID(fromFileName: fileName) == mac else {
            throw .nameMismatch
        }
        guard
            let installation = top["installation"]?.stringValue,
            !installation.isEmpty,
            installation.count <= maximumInstallationLength
        else {
            throw .wrongStructure("installation")
        }
        guard let written = top["written"]?.dateValue else {
            throw .wrongStructure("written")
        }
        let minor = try integer(top["minor"], "minor")
        let unitTable = try integer(top["unitTable"], "unitTable")
        guard minor >= 0, unitTable >= 0 else {
            throw .wrongStructure("minor")
        }
        return Contents(
            format: format,
            minor: minor,
            unitTable: unitTable,
            mac: mac,
            installation: installation,
            written: written,
            replica: try decodeReplica(top),
            extra: top.filter { !knownKeys.contains($0.key) }
        )
    }

    private static func integer(_ value: SyncValue?, _ what: String) throws(SyncRefusal) -> Int {
        guard let number = value?.integerValue, let int = Int(exactly: number) else {
            throw .wrongStructure(what)
        }
        return int
    }

    /// Reads the `context`, `units`, `entries` and `sets` fields of a replica.
    static func decodeReplica(_ top: [String: SyncValue]) throws(SyncRefusal) -> SyncReplica {
        guard let contextFields = top["context"]?.dictionaryValue else {
            throw .wrongStructure("context")
        }
        var counters: [SyncMacID: UInt64] = [:]
        for name in contextFields.keys.sorted() {
            guard let mac = SyncMacID(name), let number = contextFields[name]?.integerValue else {
                throw .wrongStructure("context")
            }
            counters[mac] = try counter(number, minimum: 0)
        }
        let context = SyncContext(counters: counters)

        var registers: [SyncUnitKey: [SyncEntry]] = [:]
        guard let units = top["units"]?.dictionaryValue else {
            throw .wrongStructure("units")
        }
        for name in units.keys.sorted() {
            registers[.whole(name)] = try decodeEntries(units[name], context: context)
        }
        guard let families = top["entries"]?.dictionaryValue else {
            throw .wrongStructure("entries")
        }
        for family in families.keys.sorted() {
            guard let items = families[family]?.dictionaryValue else {
                throw .wrongStructure("entries")
            }
            guard items.count <= maximumEntriesPerFamily else {
                throw .tooManyEntries(family)
            }
            for item in items.keys.sorted() {
                registers[.split(family: family, item: item)] = try decodeEntries(items[item], context: context)
            }
        }

        var sets: [String: [String]] = [:]
        guard let setFields = top["sets"]?.dictionaryValue else {
            throw .wrongStructure("sets")
        }
        for name in setFields.keys.sorted() {
            guard let elements = setFields[name]?.arrayValue else {
                throw .wrongStructure("sets")
            }
            guard elements.count <= maximumSetElements else {
                throw .tooManyEntries(name)
            }
            sets[name] = try elements.map { element throws(SyncRefusal) in
                guard let string = element.stringValue else {
                    throw .wrongStructure("sets")
                }
                return string
            }
        }
        return SyncReplica(context: context, registers: registers, sets: sets)
    }

    private static func counter(_ number: Int64, minimum: UInt64) throws(SyncRefusal) -> UInt64 {
        guard let counter = UInt64(exactly: number), counter >= minimum, counter <= maximumCounter else {
            throw .counterOutOfRange
        }
        return counter
    }

    private static func decodeEntries(_ value: SyncValue?, context: SyncContext) throws(SyncRefusal) -> [SyncEntry] {
        guard let list = value?.arrayValue else {
            throw .wrongStructure("entries")
        }
        return try list.map { element throws(SyncRefusal) in
            try decodeEntry(element, context: context)
        }
    }

    private static func decodeEntry(_ value: SyncValue, context: SyncContext) throws(SyncRefusal) -> SyncEntry {
        guard let fields = value.dictionaryValue else {
            throw .wrongStructure("entry")
        }
        guard
            let macString = fields["mac"]?.stringValue,
            let mac = SyncMacID(macString),
            let number = fields["n"]?.integerValue,
            let at = fields["at"]?.dateValue
        else {
            throw .wrongStructure("entry")
        }
        let dot = SyncDot(mac: mac, n: try counter(number, minimum: 1))
        // Honest publication: a file never holds a change its own context has not seen.
        guard context.covers(dot) else {
            throw .uncoveredEntry
        }
        let payload: SyncPayload
        switch (fields["value"], fields["deleted"]) {
        case (let value?, nil):
            payload = .value(value)
        case (nil, .bool(true)?):
            payload = .deleted
        default:
            throw .wrongStructure("entry")
        }
        return SyncEntry(
            dot: dot,
            at: at,
            payload: payload,
            extra: fields.filter { !knownEntryKeys.contains($0.key) }
        )
    }

    // MARK: Names

    /// Whether `name` is the name of a device file: exactly `<MacID>.plist`, with an
    /// upper-case UUID. Everything else in the folder is ignored: `.DS_Store`, `Icon\r`,
    /// temporary files and the conflict names of Dropbox, Nextcloud, OneDrive and Syncthing.
    static func isDeviceFileName(_ name: String) -> Bool {
        macID(fromFileName: name) != nil
    }

    /// The Mac a device file name belongs to, or `nil` when it is not exactly `<MacID>.plist`.
    static func macID(fromFileName name: String) -> SyncMacID? {
        guard name.utf8.count == SyncMacID.length + fileExtension.utf8.count, name.hasSuffix(fileExtension) else {
            return nil
        }
        return SyncMacID(String(name.dropLast(fileExtension.count)))
    }

    /// The Mac whose device file `fileName` is a conflict copy of: a `.plist` name that
    /// begins with the identity of a Mac in `knownMacs` but is not exactly `<MacID>.plist`.
    ///
    /// A conflict copy is a collision signal for that Mac only. Conflict names can contain
    /// the computer name (OneDrive does), so they are never logged, stored or shown; only
    /// the returned identity is.
    static func conflictCopyOwner(fileName: String, knownMacs: [SyncMacID]) -> SyncMacID? {
        guard fileName.hasSuffix(fileExtension), macID(fromFileName: fileName) == nil else {
            return nil
        }
        return knownMacs.sorted().first { fileName.hasPrefix($0.rawValue) }
    }

    private static let fileExtension = ".plist"
}
