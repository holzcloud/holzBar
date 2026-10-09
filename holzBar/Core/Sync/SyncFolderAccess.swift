//
//  SyncFolderAccess.swift
//  holzBar
//

import Foundation

/// Reads the sync folder for the engine: lists `holzBar/Macs`, reads and decodes the device
/// files, and reads the legacy file `holzBar/Settings.plist` when it is asked to.
///
/// Anyone who can write the sync folder can write anything into it, so nothing is trusted:
/// the folder, `holzBar` and `Macs` must be real folders (`lstat`, never a link), a device file
/// is opened without following a link and read up to one MiB (``SettingsSyncFile/readContents(atPath:maximumSize:)``),
/// a name that is not exactly `<MacID>.plist` is ignored, and at most
/// ``SyncReadRequest/defaultMaximumFiles`` files are read. A file whose content is not on this
/// Mac yet is never read: reading it would wait for a download.
///
/// Every call blocks. The host runs them on its file queue, never on the main thread, and
/// bounds them with a deadline and a time limit (INV-F7, INV-R2). No file name leaves this
/// type except inside a ``SyncFileOutcome`` that carries a Mac ID: a name can hold a computer
/// name and is never logged.
nonisolated enum SyncFolderReader {
    /// Reads the folder.
    ///
    /// - Parameters:
    ///   - syncFolder: The folder the user chose.
    ///   - purpose: Why the folder is read; a join also reads the legacy file's settings.
    ///   - knownMacs: The Macs whose conflict copies are recognized by name.
    ///   - isDownloaded: Whether the content of a file is on this Mac.
    ///   - deadline: When the read gives up: the files it has not read by then are `pending`.
    ///   - legacy: What to read of the legacy file; `nil` follows the purpose (the settings for
    ///     a join, nothing otherwise).
    ///   - maximumFiles: The most device files read, the most recently modified first.
    static func read(
        syncFolder: URL,
        purpose: SyncReadPurpose,
        knownMacs: [SyncMacID],
        isDownloaded: (URL) -> Bool,
        deadline: ContinuousClock.Instant? = nil,
        legacy: SyncLegacyRequest? = nil,
        maximumFiles: Int = SyncReadRequest.defaultMaximumFiles
    ) -> SyncFolderRead {
        let folderPath = SyncFolderLayout.path(of: syncFolder)
        switch SyncFolderLayout.kind(atPath: folderPath, followingLinks: true) {
        case .missing, .unreadable:
            return SyncFolderRead(availability: .unavailable)
        case .other:
            return SyncFolderRead(availability: .unusable)
        case .folder:
            break
        }
        let holzBar = syncFolder.appending(path: SyncFolderLayout.folderName, directoryHint: .isDirectory)
        switch SyncFolderLayout.kind(atPath: SyncFolderLayout.path(of: holzBar), followingLinks: false) {
        case .missing:
            // Nothing was written here yet: a folder that holds no device file.
            return SyncFolderRead(availability: .available, legacy: legacyOutcome(purpose: purpose, requested: legacy, in: holzBar, isDownloaded: isDownloaded, deadline: deadline))
        case .unreadable:
            return SyncFolderRead(availability: .unavailable)
        case .other:
            return SyncFolderRead(availability: .unusable)
        case .folder:
            break
        }
        let macs = holzBar.appending(path: SyncFolderLayout.devicesName, directoryHint: .isDirectory)
        var files: [SyncFileOutcome] = []
        var skipped = 0
        switch SyncFolderLayout.kind(atPath: SyncFolderLayout.path(of: macs), followingLinks: false) {
        case .missing:
            break
        case .unreadable:
            return SyncFolderRead(availability: .unavailable)
        case .other:
            return SyncFolderRead(availability: .unusable)
        case .folder:
            guard let listing = list(macs, knownMacs: knownMacs) else {
                return SyncFolderRead(availability: .unavailable)
            }
            files = listing.conflictCopies
            var candidates = listing.candidates
            // The most recently modified files first, so a folder that holds more than the limit keeps the live Macs.
            candidates.sort { left, right in
                if left.modified != right.modified {
                    return left.modified > right.modified
                }
                return left.name < right.name
            }
            skipped = max(0, candidates.count - maximumFiles)
            let taken = candidates.prefix(maximumFiles).sorted { $0.name < $1.name }
            for candidate in taken {
                if let deadline, ContinuousClock.now >= deadline {
                    files.append(SyncFileOutcome(macID: candidate.mac, modified: candidate.modified, state: .pending))
                    continue
                }
                if let outcome = readDeviceFile(candidate, in: macs, isDownloaded: isDownloaded) {
                    files.append(outcome)
                }
            }
        }
        return SyncFolderRead(
            availability: .available,
            files: files,
            legacy: legacyOutcome(purpose: purpose, requested: legacy, in: holzBar, isDownloaded: isDownloaded, deadline: deadline),
            skipped: skipped
        )
    }

    /// Reads what `request` asks for.
    static func read(
        _ request: SyncReadRequest,
        syncFolder: URL,
        isDownloaded: (URL) -> Bool,
        deadline: ContinuousClock.Instant? = nil
    ) -> SyncFolderRead {
        read(
            syncFolder: syncFolder,
            purpose: request.purpose,
            knownMacs: request.knownMacs,
            isDownloaded: isDownloaded,
            deadline: deadline,
            legacy: request.legacy,
            maximumFiles: request.maximumFiles
        )
    }

    /// Whether the content of the file at `url` is on this Mac, so reading it does not wait for
    /// a download (``SettingsSyncFile/isLocal(flags:isUbiquitous:downloadingStatus:)``). A missing
    /// file counts as local: the read reports it.
    static func isDownloaded(_ url: URL) -> Bool {
        var status = stat()
        guard lstat(SyncFolderLayout.path(of: url), &status) == 0 else {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return SettingsSyncFile.isLocal(
            flags: status.st_flags,
            isUbiquitous: values?.isUbiquitousItem,
            downloadingStatus: values?.ubiquitousItemDownloadingStatus
        )
    }

    // MARK: Listing

    private struct Candidate {
        var name: String
        var mac: SyncMacID
        var modified: Date
    }

    private struct Listing {
        var candidates: [Candidate]
        var conflictCopies: [SyncFileOutcome]
    }

    /// The device files and the conflict copies of `macs`, or `nil` when it cannot be listed.
    private static func list(_ macs: URL, knownMacs: [SyncMacID]) -> Listing? {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: macs,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: []
            )
        } catch {
            return nil
        }
        var listing = Listing(candidates: [], conflictCopies: [])
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            if let mac = SyncDeviceFile.macID(fromFileName: name) {
                let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                listing.candidates.append(Candidate(name: name, mac: mac, modified: modified ?? .distantPast))
            } else if let owner = SyncDeviceFile.conflictCopyOwner(fileName: name, knownMacs: knownMacs) {
                listing.conflictCopies.append(SyncFileOutcome(macID: nil, state: .conflictCopy(owner: owner)))
            }
        }
        return listing
    }

    // MARK: Device files

    private static func readDeviceFile(_ candidate: Candidate, in macs: URL, isDownloaded: (URL) -> Bool) -> SyncFileOutcome? {
        let url = macs.appending(path: candidate.name)
        let path = SyncFolderLayout.path(of: url)
        guard isDownloaded(url) else {
            return SyncFileOutcome(macID: candidate.mac, modified: candidate.modified, state: .dataless)
        }
        switch SettingsSyncFile.readContents(atPath: path, maximumSize: SyncDeviceFile.maximumReadSize) {
        case .missing:
            return nil
        case .refused(.notRegularFile):
            let refusal: SyncRefusal = SyncFolderLayout.isLink(atPath: path) ? .symbolicLink : .notRegularFile
            return SyncFileOutcome(macID: candidate.mac, modified: candidate.modified, state: .refused(refusal))
        case .refused(.tooLarge):
            let size = SyncFolderLayout.size(atPath: path) ?? SyncDeviceFile.maximumReadSize + 1
            return SyncFileOutcome(macID: candidate.mac, size: size, modified: candidate.modified, state: .refused(.tooLarge(size)))
        case .refused(.unreadable):
            return SyncFileOutcome(macID: candidate.mac, modified: candidate.modified, state: .refused(.unreadable))
        case .contents(let data):
            switch SyncDeviceFile.decode(data, fileName: candidate.name) {
            case .success(let contents):
                return SyncFileOutcome(macID: candidate.mac, size: data.count, modified: candidate.modified, state: .contents(contents))
            case .failure(let refusal):
                return SyncFileOutcome(macID: candidate.mac, size: data.count, modified: candidate.modified, state: .refused(refusal))
            }
        }
    }

    // MARK: The legacy file

    /// What the legacy file `holzBar/Settings.plist` of 0.0.6 and 0.0.7-beta1 holds, when the
    /// engine or the purpose asks for it. holzBar only reads it (decision D-02).
    private static func legacyOutcome(
        purpose: SyncReadPurpose,
        requested: SyncLegacyRequest?,
        in holzBar: URL,
        isDownloaded: (URL) -> Bool,
        deadline: ContinuousClock.Instant?
    ) -> SyncLegacyOutcome? {
        var request = requested ?? .none
        if requested == nil, case .join = purpose {
            request = .settings
        }
        guard request != .none else {
            return nil
        }
        if let deadline, ContinuousClock.now >= deadline {
            return nil
        }
        let url = holzBar.appending(path: SettingsSyncLocation.fileComponents[1])
        guard isDownloaded(url) else {
            return .absent
        }
        switch SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: url)) {
        case .missing:
            return .absent
        case .refused(.notRegularFile):
            return .refused(SyncFolderLayout.isLink(atPath: SyncFolderLayout.path(of: url)) ? .symbolicLink : .notRegularFile)
        case .refused(.tooLarge):
            return .refused(.tooLarge(SyncFolderLayout.size(atPath: SyncFolderLayout.path(of: url)) ?? SettingsSyncFile.maximumFileSize + 1))
        case .refused(.unreadable):
            return .absent
        case .contents(let data):
            switch SyncLegacyInput.read(data) {
            case .success(let file):
                if request == .metadata {
                    return .file(SyncLegacyFile(modified: file.modified, deviceID: file.deviceID, settings: [:], identityDigest: file.identityDigest))
                }
                return .file(file)
            case .failure(let refusal):
                return .refused(refusal)
            }
        }
    }
}

/// Writes this Mac's own device file, and nothing else.
///
/// The writer creates `holzBar/Macs` only inside a folder that exists and can be used, writes
/// a dot-prefixed temporary file there, renames it onto `<MacID>.plist` and reads the file
/// back. It never touches `holzBar/Settings.plist` or another Mac's file (decision D-02), and
/// it refuses a destination that is not exactly the own device file name.
///
/// The call blocks; the host runs it on its file queue.
nonisolated enum SyncFolderWriter {
    /// Writes the file.
    ///
    /// - Parameters:
    ///   - contents: The whole file.
    ///   - syncFolder: The folder the user chose.
    ///   - expecting: What the own file must be before it is replaced.
    ///   - counter: The counter this write publishes; the Mac's own counter in the file's
    ///     context if `nil`.
    ///   - isDownloaded: Whether the content of a file is on this Mac.
    static func write(
        _ contents: SyncDeviceFile.Contents,
        syncFolder: URL,
        expecting: SyncOwnFileExpectation,
        counter: UInt64? = nil,
        isDownloaded: (URL) -> Bool = { SyncFolderReader.isDownloaded($0) }
    ) -> SyncWriteResult {
        let name = "\(contents.mac.rawValue).plist"
        guard SyncDeviceFile.isDeviceFileName(name) else {
            return .failed(.unavailable)
        }
        let data: Data
        do throws(SyncRefusal) {
            data = try SyncDeviceFile.encode(contents)
        } catch {
            return .failed(.tooLarge)
        }
        guard SyncFolderLayout.kind(atPath: SyncFolderLayout.path(of: syncFolder), followingLinks: true) == .folder else {
            return .failed(.unavailable)
        }
        let holzBar = syncFolder.appending(path: SyncFolderLayout.folderName, directoryHint: .isDirectory)
        let macs = holzBar.appending(path: SyncFolderLayout.devicesName, directoryHint: .isDirectory)
        guard
            SyncFolderLayout.ensureFolder(atPath: SyncFolderLayout.path(of: holzBar)),
            SyncFolderLayout.ensureFolder(atPath: SyncFolderLayout.path(of: macs))
        else {
            return .failed(.unavailable)
        }
        let destination = macs.appending(path: name)
        if let failure = check(expecting, at: destination, name: name, isDownloaded: isDownloaded) {
            return .failed(failure)
        }
        let temporary = macs.appending(path: ".\(contents.mac.rawValue).tmp")
        guard
            SyncFolderLayout.writeAtomically(data, temporary: SyncFolderLayout.path(of: temporary), destination: SyncFolderLayout.path(of: destination))
        else {
            return .failed(.unavailable)
        }
        // Read back: what another Mac will read is what must be there.
        guard
            case .contents(let back) = SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: destination), maximumSize: SyncDeviceFile.maximumReadSize),
            case .success(let written) = SyncDeviceFile.decode(back, fileName: name),
            written.replica.digest == contents.replica.digest
        else {
            return .unverified
        }
        return .verified(SyncWriteReceipt(
            counter: counter ?? contents.replica.context[contents.mac],
            replicaDigest: contents.replica.digest,
            fileDigest: written.replica.digest
        ))
    }

    /// Writes what `request` asks for.
    static func write(_ request: SyncWriteRequest, syncFolder: URL, isDownloaded: (URL) -> Bool = { SyncFolderReader.isDownloaded($0) }) -> SyncWriteResult {
        write(request.contents, syncFolder: syncFolder, expecting: request.expectation, counter: request.counter, isDownloaded: isDownloaded)
    }

    /// Why the own file is not what the request expects, or `nil` when it is.
    private static func check(
        _ expectation: SyncOwnFileExpectation,
        at destination: URL,
        name: String,
        isDownloaded: (URL) -> Bool
    ) -> SyncWriteFailure? {
        if case .unchecked = expectation {
            return nil
        }
        guard isDownloaded(destination) else {
            return .unavailable
        }
        let current = SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: destination), maximumSize: SyncDeviceFile.maximumReadSize)
        switch (expectation, current) {
        case (.absent, .missing):
            return nil
        case (.readThisSession(let digest), .contents(let bytes)):
            guard case .success(let contents) = SyncDeviceFile.decode(bytes, fileName: name), contents.replica.digest == digest else {
                return .ownFileChanged
            }
            return nil
        case (_, .refused(.unreadable)):
            return .unavailable
        default:
            return .ownFileChanged
        }
    }
}

/// The names and the safe file operations the reader, the writer and the state store share.
nonisolated enum SyncFolderLayout {
    /// The folder inside the sync folder that holds everything of holzBar.
    static let folderName = SettingsSyncLocation.fileComponents[0]

    /// The folder of the device files, inside ``folderName``.
    static let devicesName = SyncDeviceFile.folderComponents[1]

    /// What is at a path.
    enum Kind: Equatable {
        case missing
        case folder
        /// A file, a link (when links are not followed) or anything else.
        case other
        /// It could not be examined (no access, a stalled volume).
        case unreadable
    }

    /// The path of `url` without a trailing slash. A trailing slash makes `lstat` follow a symbolic link, which would
    /// defeat every check that a path is not a link.
    static func path(of url: URL) -> String {
        withoutTrailingSlash(url.path(percentEncoded: false))
    }

    private static func withoutTrailingSlash(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    static func kind(atPath path: String, followingLinks: Bool) -> Kind {
        let path = withoutTrailingSlash(path)
        var status = stat()
        let result = followingLinks ? stat(path, &status) : lstat(path, &status)
        guard result == 0 else {
            return errno == ENOENT ? .missing : .unreadable
        }
        return status.st_mode & S_IFMT == S_IFDIR ? .folder : .other
    }

    static func isLink(atPath path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else {
            return false
        }
        return status.st_mode & S_IFMT == S_IFLNK
    }

    static func size(atPath path: String) -> Int? {
        var status = stat()
        guard lstat(path, &status) == 0 else {
            return nil
        }
        return Int(status.st_size)
    }

    /// Makes sure a real folder is at `path`: it creates the last component when it is missing,
    /// never the folders above it, and refuses a link or a file.
    static func ensureFolder(atPath path: String) -> Bool {
        switch kind(atPath: path, followingLinks: false) {
        case .folder:
            return true
        case .other, .unreadable:
            return false
        case .missing:
            if mkdir(path, 0o755) != 0, errno != EEXIST {
                return false
            }
            return kind(atPath: path, followingLinks: false) == .folder
        }
    }

    /// Writes `data` to `temporary`, flushes it to disk and renames it onto `destination`, so
    /// the destination holds the old file or the whole new one. A failure leaves the old file
    /// and removes the temporary file.
    static func writeAtomically(_ data: Data, temporary: String, destination: String) -> Bool {
        // A temporary file that an earlier run left (or someone planted) is removed first, and the new one is
        // created exclusively and without following a link.
        unlink(temporary)
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            return false
        }
        var isWritten = true
        data.withUnsafeBytes { buffer in
            var offset = 0
            while let base = buffer.baseAddress, offset < buffer.count {
                let count = write(descriptor, base + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    isWritten = false
                    return
                }
                offset += count
            }
        }
        if isWritten, fcntl(descriptor, F_FULLFSYNC) != 0 {
            isWritten = fsync(descriptor) == 0
        }
        let isClosed = close(descriptor) == 0
        guard isWritten, isClosed, rename(temporary, destination) == 0 else {
            unlink(temporary)
            return false
        }
        return true
    }
}
