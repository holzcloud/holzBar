//
//  SettingsSyncFile.swift
//  holzBar
//

import Foundation

/// Decides which settings of the sync file this Mac applies, and reads the file safely.
///
/// The file holds the date it was written (``modifiedKey``), the writing Mac's id (see
/// ``SettingsSyncDevice``) and the settings (``settingsKey``).
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

    /// The largest sync file holzBar reads: 1 MB. holzBar's settings take a few kilobytes.
    static let maximumFileSize = 1 << 20

    /// How far in the future a file's date may lie, for Macs whose clocks differ.
    static let allowedClockSkew: TimeInterval = 60 * 60

    /// Returns the settings to apply from the sync file, if another Mac wrote them after
    /// this Mac last synced.
    ///
    /// - Parameters:
    ///   - file: The contents of the sync file.
    ///   - lastSynced: When this Mac last wrote or applied the file, if ever.
    ///   - deviceID: This Mac's sync id.
    ///   - computerName: This Mac's computer name, if it has one; only compared with files
    ///     of older holzBar builds, which carry no id.
    ///   - localKeys: The keys that stay on this Mac; they are removed from the settings.
    ///   - now: The current date.
    /// - Returns: The settings and the date the file was written, or `nil` when the file
    ///   is this Mac's own, is not newer, is dated more than ``allowedClockSkew`` in the
    ///   future, or lacks its date or settings.
    static func newerSettings(
        in file: [String: Any],
        lastSynced: Date?,
        deviceID: String,
        computerName: String?,
        localKeys: Set<String>,
        now: Date = .now
    ) -> (settings: [String: Any], modified: Date)? {
        guard
            let modified = file[modifiedKey] as? Date,
            let settings = file[settingsKey] as? [String: Any],
            !SettingsSyncDevice.isFromThisMac(file: file, deviceID: deviceID, computerName: computerName),
            modified > lastSynced ?? .distantPast,
            modified <= now.addingTimeInterval(allowedClockSkew)
        else {
            return nil
        }
        return (settings.filter { !localKeys.contains($0.key) }, modified)
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
