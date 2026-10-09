//
//  SettingsSyncFile.swift
//  holzBar
//

import Foundation

/// Reads the files of the sync folder safely.
///
/// Anyone who can write the synced folder can write the files: a shared Dropbox or Nextcloud folder, a network
/// share, a Syncthing peer. So a file is read only when it is a regular file of at most ``maximumFileSize`` bytes,
/// never through a symbolic link (``readContents(atPath:maximumSize:)``), and a folder is used only when it is a
/// real folder (``isUsableFolder(atPath:)``). The device files of the redesigned sync, the legacy file of 0.0.6 and
/// 0.0.7-beta1 and the state file are all read this way; what they mean is decided elsewhere (`SyncDeviceFile`,
/// `SyncLegacyInput`, `SyncStateCodec`).
nonisolated enum SettingsSyncFile {
    /// The key of the date the legacy file was written.
    static let modifiedKey = "modified"

    /// The key of the settings in the legacy file.
    static let settingsKey = "settings"

    /// The largest file holzBar reads: 1 MB. holzBar's settings take a few kilobytes.
    static let maximumFileSize = 1 << 20

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
