//
//  SettingsSyncFile.swift
//  holzBar
//

import Foundation

/// Decides which settings of the sync file this Mac applies, and reads the file safely.
///
/// The file holds the date it was written (``modifiedKey``), the writing Mac's id (see
/// ``SettingsSyncDevice``), the settings (``settingsKey``), the layouts among them that
/// are current (``currentLayoutsKey``) and those that are a Mac's copy (``copiedLayoutsKey``),
/// and the newest write of each Mac that the settings hold (``seenKey``).
///
/// Anyone who can write the synced folder can write the file: a shared Dropbox or
/// Nextcloud folder, a network share, a Syncthing peer. So the file is read only when it
/// is a regular file of at most ``maximumFileSize`` bytes, never through a symbolic link
/// (``readContents(atPath:maximumSize:)``); the `holzBar` folder must be a real folder
/// too (``isUsableFolder(atPath:)``); and a file dated far in the future is ignored, so
/// it cannot make this Mac ignore the other Macs' changes (``allowedClockSkew``).
nonisolated enum SettingsSyncFile {
    /// The key of the date the file was written.
    static let modifiedKey = "modified"

    /// The key of the synced settings.
    static let settingsKey = "settings"

    /// The key of the layout keys whose values in the settings are current: the writer's
    /// own layout, and the other macOS version's when the writer kept it from a file that
    /// listed it (`SettingsSyncPolicy.Layouts`). Files of earlier builds lack it; their
    /// layouts are not used, as their copy of the other version's layout may be older than
    /// the layout it stands for. Earlier builds ignore the key.
    static let currentLayoutsKey = "currentLayouts"

    /// The key of the layout keys whose values in the settings are a Mac's copy of another
    /// macOS version's layout, written unlisted for builds before this one, which delete a
    /// layout missing from a file they apply (F-60). Such a copy is no Mac's arrangement: it is
    /// never compared, and a Mac of that macOS version writes its own layout over it. Earlier
    /// builds ignore the key, and their files lack it.
    static let copiedLayoutsKey = "copiedLayouts"

    /// The key of the writes a version holds: for each Mac, by its sync id
    /// (`SettingsSyncDevice.deviceIDKey`), the date of its newest write whose changes the
    /// version includes, the writing Mac's own write among them
    /// (`SettingsSyncPolicy.seen(writingOver:local:)`). A Mac whose last write is newer than
    /// its entry knows the version lacks that write, and asks instead of applying it
    /// (`SettingsSyncPolicy.missesLastWrite(_:local:)`). Each Mac's dates come from its own
    /// clock, so clocks that differ do not matter. Earlier builds ignore the key, and their
    /// files lack it.
    static let seenKey = "seen"

    /// The most Macs a record of the writes a version holds (``seenKey``) keeps: the newest
    /// writes. A folder is shared by a few Macs; the limit keeps a file written by anyone
    /// who can write the folder from growing the record without bound.
    static let seenLimit = 64

    /// The record of writes `seen`, at most `limit` of them, the newest kept.
    static func limitedSeen(_ seen: [String: Date], limit: Int = seenLimit) -> [String: Date] {
        guard seen.count > limit else {
            return seen
        }
        let newest = seen.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(max(limit, 0))
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    /// The record of writes to write into the file (``seenKey``): the writes of the other Macs
    /// that the written settings hold, and this Mac's write.
    ///
    /// - Parameters:
    ///   - seen: The other Macs' writes (`SettingsSyncPolicy.WritePlan.seen`).
    ///   - deviceID: This Mac's sync id.
    ///   - modified: The date written into the file.
    static func seenToWrite(_ seen: [String: Date], deviceID: String, modified: Date) -> [String: Date] {
        var written = limitedSeen(seen.filter { $0.key != deviceID }, limit: seenLimit - 1)
        written[deviceID] = modified
        return written
    }

    /// The largest sync file holzBar reads: 1 MB. holzBar's settings take a few kilobytes.
    static let maximumFileSize = 1 << 20

    /// Whether a sync file of `byteCount` bytes is small enough for holzBar to read. holzBar
    /// never writes a larger one, which every Mac would leave alone.
    static func fitsSizeLimit(byteCount: Int) -> Bool {
        byteCount <= maximumFileSize
    }

    /// How far in the future a file's date may lie, for Macs whose clocks differ.
    static let allowedClockSkew: TimeInterval = 60 * 60

    /// What the sync file holds, as seen from this Mac.
    nonisolated struct Contents {
        /// When the file was written.
        let modified: Date
        /// Whether this Mac wrote it.
        let isFromThisMac: Bool
        /// Whether another Mac wrote it after this Mac last synced, and it is dated at most
        /// ``allowedClockSkew`` in the future. The date alone cannot tell whether a version
        /// that is not newer holds changes this Mac has not synced, as with a clock behind this
        /// Mac's; the digests decide that (`SettingsSyncPolicy.isUnsyncedChange(_:local:)`).
        let isNewer: Bool
        /// The settings, without the keys that stay on each Mac.
        let settings: [String: Any]
        /// The layout keys whose values in ``settings`` are current (``currentLayoutsKey``);
        /// empty for files of earlier builds.
        let currentLayouts: Set<String>
        /// The layout keys whose values in ``settings`` are a Mac's copy
        /// (``copiedLayoutsKey``); empty for files of earlier builds.
        var copiedLayouts: Set<String> = []
        /// The newest write of each other Mac that the version holds, by sync id, the writing
        /// Mac's among them (``seenKey``); `nil` for files of earlier builds.
        var seen: [String: Date]?
        /// The date of this Mac's newest write that the version holds (``seenKey``); `nil` when
        /// it holds none, or the file records no writes.
        var seenWrite: Date?
    }

    /// Returns what the sync file holds.
    ///
    /// - Parameters:
    ///   - file: The contents of the sync file.
    ///   - lastSynced: When this Mac last wrote or applied the file, if ever.
    ///   - deviceID: This Mac's sync id.
    ///   - computerName: This Mac's computer name, if it has one; only compared with files
    ///     of older holzBar builds, which carry no id.
    ///   - localKeys: The keys that stay on this Mac; they are removed from the settings.
    ///   - now: The current date.
    /// - Returns: The contents, or `nil` when the file lacks its date or settings.
    static func contents(
        of file: [String: Any],
        lastSynced: Date?,
        deviceID: String,
        computerName: String?,
        localKeys: Set<String>,
        now: Date = .now
    ) -> Contents? {
        guard
            let modified = file[modifiedKey] as? Date,
            let settings = file[settingsKey] as? [String: Any]
        else {
            return nil
        }
        let isFromThisMac = SettingsSyncDevice.isFromThisMac(file: file, deviceID: deviceID, computerName: computerName)
        // Each entry is a sync id and a date; anything else is no record.
        let seen = (file[seenKey] as? [String: Any]).map { limitedSeen($0.compactMapValues { $0 as? Date }) }
        return Contents(
            modified: modified,
            isFromThisMac: isFromThisMac,
            isNewer: !isFromThisMac
                && modified > lastSynced ?? .distantPast
                && modified <= now.addingTimeInterval(allowedClockSkew),
            settings: settings.filter { !localKeys.contains($0.key) },
            currentLayouts: Set(file[currentLayoutsKey] as? [String] ?? []),
            copiedLayouts: Set(file[copiedLayoutsKey] as? [String] ?? []),
            seen: seen?.filter { $0.key != deviceID },
            seenWrite: seen?[deviceID]
        )
    }

    /// Whether the sync file's contents are on this Mac, so reading it does not wait for a
    /// download.
    ///
    /// An online-only file of iCloud Drive or another file provider is dataless
    /// (`SF_DATALESS`), and a ubiquitous file may hold an older version until the current
    /// one is downloaded.
    ///
    /// - Parameters:
    ///   - flags: The file's flags (`st_flags` of `lstat`).
    ///   - isUbiquitous: Whether the file is in iCloud Drive, if known.
    ///   - downloadingStatus: The file's download status, if it is ubiquitous.
    static func isLocal(flags: UInt32, isUbiquitous: Bool?, downloadingStatus: URLUbiquitousItemDownloadingStatus?) -> Bool {
        guard flags & UInt32(SF_DATALESS) == 0 else {
            return false
        }
        guard isUbiquitous == true else {
            return true
        }
        return downloadingStatus == .current
    }

    // MARK: Reading

    /// Why the sync file was not read.
    nonisolated enum Refusal: Equatable, Sendable {
        /// A symbolic link, a folder, a pipe or anything else that is not a regular file.
        case notRegularFile
        /// Larger than the limit.
        case tooLarge
        /// It could not be opened or read.
        case unreadable
    }

    /// The outcome of reading the sync file.
    nonisolated enum ReadResult: Equatable, Sendable {
        /// The file's bytes.
        case contents(Data)
        /// There is no file.
        case missing
        /// The file was not read.
        case refused(Refusal)
    }

    /// Reads the file at `path`, if it is a regular file of at most `maximumSize` bytes.
    ///
    /// The file is opened without following a symbolic link (`O_NOFOLLOW`) and without
    /// waiting on a pipe (`O_NONBLOCK`), its type and size are checked on the open file
    /// (`fstat`), so it cannot be swapped between the check and the read, and at most
    /// `maximumSize` bytes are read.
    static func readContents(atPath path: String, maximumSize: Int = maximumFileSize) -> ReadResult {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT:
                return .missing
            case ELOOP:
                return .refused(.notRegularFile)
            default:
                return .refused(.unreadable)
            }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            return .refused(.unreadable)
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            return .refused(.notRegularFile)
        }
        guard status.st_size <= off_t(maximumSize) else {
            return .refused(.tooLarge)
        }
        do {
            // One byte more than allowed tells a file that grew since `fstat`.
            let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
            guard data.count <= maximumSize else {
                return .refused(.tooLarge)
            }
            return .contents(data)
        } catch {
            return .refused(.unreadable)
        }
    }

    /// Whether holzBar may create, or write into, the folder at `path`: it does not exist
    /// yet, or it is a real folder, not a symbolic link to another one.
    static func isUsableFolder(atPath path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else {
            return errno == ENOENT
        }
        return status.st_mode & S_IFMT == S_IFDIR
    }
}
