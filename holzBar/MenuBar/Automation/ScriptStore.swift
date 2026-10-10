//
//  ScriptStore.swift
//  holzBar
//

import AppKit
import CryptoKit
import Darwin
import Observation
import OSLog

/// What holzBar knows about scripts on this Mac: the scripts folder and the scripts in it, what
/// the user approved, the time limits, the rules that use a script and the profile hooks.
///
/// All of it is in `Scripts.json` next to the app's other data, mode 0600, and stays on this
/// Mac: it is not in `Defaults`, so no export, import or sync carries it, and no URL command or
/// Shortcut reaches this class (D-03, D-05). A script runs only after the user saw its name,
/// size and checksum and allowed that exact content: the approval binds the full SHA-256, and a
/// changed file needs a new one. A scripts folder that is a link, is not the user's or that
/// others can write to runs nothing (T-11-M6).
@MainActor
@Observable
final class ScriptStore {
    /// One script file in the folder.
    struct Entry: Identifiable, Equatable {
        let name: String
        let size: Int
        /// The full SHA-256 of the contents the user is shown. An approval binds this value, not
        /// the prefix.
        let sha256: String
        let decision: ScriptGate.Decision

        /// The first characters of the SHA-256, shown when the user decides.
        var checksumPrefix: String {
            String(sha256.prefix(8))
        }

        var id: String { name }
    }

    /// Why the store holds back.
    enum Problem: Equatable {
        /// `Scripts.json` was written by a newer holzBar. It is not read and not overwritten, and
        /// no script runs until that version is back.
        case newerVersion
        /// `Scripts.json` could not be read. It was moved to `Scripts-unreadable.json` and the
        /// store started empty.
        case setAside
    }

    /// The scripts, sorted by name. Empty while the folder is refused.
    private(set) var scripts = [Entry]()
    /// The scripts folder in use: the one the user chose, or the default.
    private(set) var folderURL = ScriptStore.defaultFolder
    /// Why the folder runs nothing, or `nil` when it is a folder the user owns and nobody else
    /// can write to.
    private(set) var folderRefusal: ScriptGate.FolderRefusal?
    private(set) var problem: Problem?
    private(set) var profileHooks = [ProfileHook]()

    @ObservationIgnored private let logger = Logger(category: "ScriptStore")
    @ObservationIgnored private var file = ScriptStoreFile()

    private static let supportFolder: URL = URL.applicationSupportDirectory
        .appending(path: "holzBar", directoryHint: .isDirectory)

    /// `~/Library/Application Support/holzBar/Scripts`, the folder used until the user chooses
    /// another one. It is the only folder holzBar ever creates.
    static let defaultFolder: URL = supportFolder.appending(path: "Scripts", directoryHint: .isDirectory)

    /// `~/Library/Application Support/holzBar/Scripts.json`.
    private static let storeFile: URL = supportFolder.appending(path: "Scripts.json", directoryHint: .notDirectory)

    /// Where a store that could not be read is moved to.
    private static let unreadableFile: URL = supportFolder
        .appending(path: "Scripts-unreadable.json", directoryHint: .notDirectory)

    /// The approvals file of 0.0.8-beta1 and beta2. It is read once, when the betas' data moves
    /// into `Scripts.json`, and left where it is.
    private static let legacyApprovalsFile: URL = supportFolder
        .appending(path: "ScriptApprovals.json", directoryHint: .notDirectory)

    // MARK: Loading

    func performSetup() {
        loadStoreFile()
        folderURL = file.folderPath.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultFolder
        profileHooks = file.profileHooks
        refresh()
    }

    private func loadStoreFile() {
        switch Self.readRegularFile(at: Self.storeFile, maximumSize: ScriptStoreFile.maximumSize) {
        case .missing:
            file = ScriptStoreFile()
        case .unreadable:
            setStoreAside()
        case .data(let data):
            switch ScriptStoreFile.decode(data) {
            case .file(let decoded):
                file = decoded
            case .unsupportedVersion:
                file = ScriptStoreFile()
                problem = .newerVersion
                logger.error("Scripts.json is from a newer version; scripts are off until that version is back")
            case .unreadable:
                setStoreAside()
            }
        }
    }

    /// Moves a store that cannot be read out of the way, so it is never overwritten by accident
    /// and nothing runs from it. A fresh empty store starts.
    private func setStoreAside() {
        file = ScriptStoreFile()
        problem = .setAside
        let path = Self.storeFile.path(percentEncoded: false)
        unlink(Self.unreadableFile.path(percentEncoded: false))
        if rename(path, Self.unreadableFile.path(percentEncoded: false)) != 0 {
            logger.error("Could not set the unreadable Scripts.json aside")
        } else {
            logger.notice("Set an unreadable Scripts.json aside")
        }
    }

    /// Moves the script rules and approvals of 0.0.8-beta1 and beta2 into the store, once (D-14).
    ///
    /// `ScriptApprovals.json` is not changed or deleted: it is never read again once the store
    /// has migrated, and a downgrade to beta 2 still finds it.
    ///
    /// - Parameters:
    ///   - rules: The rules of the settings that use a script.
    ///   - order: The order of every rule of the settings, so the rules keep their place.
    func adoptLegacyData(rules: [AutomationRule], order: [UUID]) {
        guard problem != .newerVersion, !file.hasMigratedLegacyData else {
            return
        }
        var approvals = [String: String]()
        if case .data(let data) = Self.readRegularFile(at: Self.legacyApprovalsFile, maximumSize: 1_000_000) {
            approvals = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        file = file.adoptingLegacy(rules: rules, approvals: approvals, order: order)
        if !rules.isEmpty || !approvals.isEmpty {
            save()
            logger.notice(
                "Moved \(rules.count, privacy: .public) script rules and \(approvals.count, privacy: .public) approvals into the local store"
            )
        }
        refresh()
    }

    // MARK: The rules that use a script

    /// The rules that use a script, as stored on this Mac.
    var scriptRules: [AutomationRule] {
        file.rules
    }

    /// The order of every rule, as stored on this Mac.
    var ruleOrder: [UUID] {
        file.ruleOrder
    }

    /// Stores the rules that use a script and the order of all rules. Nothing is written when
    /// nothing changed.
    func setScriptRules(_ rules: [AutomationRule], order: [UUID]) {
        var candidate = file
        candidate.rules = rules
        candidate.ruleOrder = order
        candidate = candidate.validated()
        guard candidate != file else {
            return
        }
        file = candidate
        save()
    }

    // MARK: The folder

    /// Uses the folder the user chose. The approvals and time limits of the old folder are
    /// cleared: a name in another folder is another file.
    func setFolder(_ url: URL) {
        guard problem != .newerVersion else {
            return
        }
        let path = url.standardizedFileURL.path(percentEncoded: false)
        var candidate = file
        candidate.folderPath = path == Self.defaultFolder.path(percentEncoded: false) ? nil : path
        candidate.approvals = [:]
        candidate.timeLimits = [:]
        file = candidate.validated()
        folderURL = file.folderPath.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Self.defaultFolder
        save()
        refresh()
    }

    /// Why the folder is refused right now, read from the file system without following a link.
    private func currentFolderRefusal() -> ScriptGate.FolderRefusal? {
        var status = stat()
        guard lstat(folderURL.path(percentEncoded: false), &status) == 0 else {
            return .notDirectory
        }
        return ScriptGate.folderRefusal(
            ScriptFolderInfo(
                isDirectory: status.st_mode & S_IFMT == S_IFDIR,
                isSymbolicLink: status.st_mode & S_IFMT == S_IFLNK,
                isOwnedByCurrentUser: status.st_uid == getuid(),
                mode: UInt16(status.st_mode & 0o7777)
            )
        )
    }

    /// Creates the default folder when it does not exist. A folder the user chose is never
    /// created or changed.
    private func createDefaultFolderIfNeeded() {
        guard folderURL == Self.defaultFolder else {
            return
        }
        let path = Self.defaultFolder.path(percentEncoded: false)
        var status = stat()
        guard lstat(path, &status) != 0, errno == ENOENT else {
            return
        }
        try? FileManager.default.createDirectory(
            at: Self.defaultFolder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    // MARK: Reading the folder

    /// Reads the folder again.
    func refresh() {
        createDefaultFolderIfNeeded()
        folderRefusal = currentFolderRefusal()
        guard folderRefusal == nil, problem != .newerVersion else {
            scripts = []
            return
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path(percentEncoded: false))) ?? []
        let plainNames = names.filter(ScriptGate.isPlainName).sorted().prefix(ScriptStoreFile.maximumEntries)
        scripts = plainNames.compactMap { name in
            guard let info = fileInfo(for: name) else {
                return nil
            }
            return Entry(
                name: name,
                size: info.size,
                sha256: info.sha256,
                decision: ScriptGate.decide(info, approvedHash: file.approvals[name])
            )
        }
    }

    /// The facts of a script file, or `nil` when it must not be looked at: the store is
    /// read-only, the folder is refused, the name is not plain or the file cannot be opened.
    ///
    /// The file is opened once, without following a link and without blocking on a pipe, and
    /// the type, owner, mode, size, quarantine attribute and contents are all read from that
    /// descriptor, so they describe the same file (T-11-M1). The runner reads them again right
    /// before each run. The window between this read and the start of the process stays; it is
    /// documented in SECURITY.md.
    func fileInfo(for name: String) -> ScriptFileInfo? {
        guard problem != .newerVersion, ScriptGate.isPlainName(name), currentFolderRefusal() == nil else {
            return nil
        }
        let path = folderURL.appending(path: name, directoryHint: .notDirectory).path(percentEncoded: false)
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            guard errno == ELOOP else {
                return nil
            }
            // A link in the file's place: the gate refuses it by name.
            return ScriptFileInfo(
                name: name,
                isRegularFile: false,
                isSymbolicLink: true,
                isOwnedByCurrentUser: false,
                mode: 0,
                hasQuarantineAttribute: false,
                size: 0,
                sha256: ""
            )
        }
        defer {
            close(descriptor)
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            return nil
        }
        let isRegular = status.st_mode & S_IFMT == S_IFREG
        var size = Int(status.st_size)
        // The contents are read, from the same descriptor, only for a plain file of a sensible
        // size.
        var hash = ""
        if isRegular, size <= ScriptGate.maximumSize {
            if let data = Self.read(from: descriptor, upTo: ScriptGate.maximumSize + 1) {
                if data.count > ScriptGate.maximumSize {
                    size = data.count
                } else {
                    hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }
            }
        }
        return ScriptFileInfo(
            name: name,
            isRegularFile: isRegular,
            isSymbolicLink: false,
            isOwnedByCurrentUser: status.st_uid == getuid(),
            mode: UInt16(status.st_mode & 0o7777),
            hasQuarantineAttribute: fgetxattr(descriptor, "com.apple.quarantine", nil, 0, 0, 0) >= 0,
            size: size,
            sha256: hash
        )
    }

    /// The checksum the user approved for the file, if any.
    func approvedHash(for name: String) -> String? {
        file.approvals[name]
    }

    // MARK: Approving

    /// Approves the contents the file has now, when they are the contents of `entry`: the full
    /// SHA-256 must be the one the user was shown, not only its first characters (T-11-L5).
    /// Called only after the user confirmed.
    func approve(_ entry: Entry) {
        guard
            problem != .newerVersion,
            ScriptStoreFile.isValidHash(entry.sha256),
            let info = fileInfo(for: entry.name),
            info.sha256 == entry.sha256,
            ScriptGate.decide(info, approvedHash: nil) == .needsApproval,
            file.approvals[entry.name] != nil || file.approvals.count < ScriptStoreFile.maximumEntries
        else {
            // The file changed while the sheet was open, or it is not one that may be
            // approved: the user decides again.
            refresh()
            return
        }
        file.approvals[entry.name] = entry.sha256
        save()
        refresh()
    }

    func revokeApproval(_ entry: Entry) {
        guard problem != .newerVersion, file.approvals.removeValue(forKey: entry.name) != nil else {
            return
        }
        save()
        refresh()
    }

    // MARK: Time limits

    /// The time limit of a script in seconds: the stored value, or the default.
    func timeLimit(for name: String) -> Int {
        ScriptLimits.timeLimit(file.timeLimits[name])
    }

    /// Stores the time limit of a script, from 1 through 60 seconds.
    func setTimeLimit(_ seconds: Int, for name: String) {
        guard
            problem != .newerVersion,
            ScriptGate.isPlainName(name),
            file.timeLimits[name] != nil || file.timeLimits.count < ScriptStoreFile.maximumEntries
        else {
            return
        }
        file.timeLimits[name] = ScriptLimits.timeLimit(seconds)
        save()
    }

    // MARK: Profile hooks

    func addProfileHook(_ hook: ProfileHook) {
        guard
            problem != .newerVersion,
            hook.isValid,
            file.profileHooks.count < ProfileHooks.maximumCount,
            !file.profileHooks.contains(where: { $0.id == hook.id })
        else {
            return
        }
        file.profileHooks.append(hook)
        hooksChanged()
    }

    func updateProfileHook(_ hook: ProfileHook) {
        guard
            problem != .newerVersion,
            hook.isValid,
            let index = file.profileHooks.firstIndex(where: { $0.id == hook.id })
        else {
            return
        }
        file.profileHooks[index] = hook
        hooksChanged()
    }

    func removeProfileHook(id: UUID) {
        guard problem != .newerVersion, file.profileHooks.contains(where: { $0.id == id }) else {
            return
        }
        file.profileHooks.removeAll { $0.id == id }
        hooksChanged()
    }

    /// The hooks of a renamed profile follow it.
    func renameProfileHooks(from oldName: String, to newName: String) {
        guard problem != .newerVersion, file.profileHooks.contains(where: { $0.profileName == oldName }) else {
            return
        }
        file.profileHooks = ProfileHooks.renaming(file.profileHooks, from: oldName, to: newName)
        hooksChanged()
    }

    /// The hooks of a deleted profile go with it.
    func removeProfileHooks(named name: String) {
        guard problem != .newerVersion, file.profileHooks.contains(where: { $0.profileName == name }) else {
            return
        }
        file.profileHooks = ProfileHooks.removing(file.profileHooks, profileName: name)
        hooksChanged()
    }

    private func hooksChanged() {
        file = file.validated()
        profileHooks = file.profileHooks
        save()
    }

    // MARK: Folder in Finder

    func openFolder() {
        refresh()
        NSWorkspace.shared.open(folderURL)
    }

    // MARK: Files

    /// What reading a small file found.
    private enum ReadResult {
        case missing
        case unreadable
        case data(Data)
    }

    /// Reads a regular file of at most `maximumSize` bytes through one descriptor opened without
    /// following a link. A link, a pipe, a folder or a larger file is unreadable.
    private static func readRegularFile(at url: URL, maximumSize: Int) -> ReadResult {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return errno == ENOENT ? .missing : .unreadable
        }
        defer {
            close(descriptor)
        }
        var status = stat()
        guard
            fstat(descriptor, &status) == 0,
            status.st_mode & S_IFMT == S_IFREG,
            Int(status.st_size) <= maximumSize,
            let data = read(from: descriptor, upTo: maximumSize + 1),
            data.count <= maximumSize
        else {
            return .unreadable
        }
        return .data(data)
    }

    /// Reads up to `limit` bytes from a descriptor, or `nil` on an error.
    private static func read(from descriptor: Int32, upTo limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < limit {
            let wanted = min(buffer.count, limit - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, wanted) }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if count == 0 {
                break
            }
            data.append(contentsOf: buffer[0..<count])
        }
        return data
    }

    /// Writes `Scripts.json`: to a new temporary file that is created with mode 0600 in the
    /// holzBar folder (mode 0700), then moved over the old file with `rename`, so the store is
    /// never half written and never readable by others, not even for a moment (T-11-L3). Never
    /// while the store is read-only.
    private func save() {
        guard problem != .newerVersion else {
            return
        }
        guard let data = file.encoded() else {
            logger.error("The script store is too large to save")
            return
        }
        let folder = Self.storeFile.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let temporary = folder
                .appending(path: "Scripts.json.\(UUID().uuidString).tmp", directoryHint: .notDirectory)
                .path(percentEncoded: false)
            let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var isComplete = false
            defer {
                close(descriptor)
                if !isComplete {
                    unlink(temporary)
                }
            }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(descriptor, bytes.baseAddress.map { $0 + offset }, bytes.count - offset)
                    if written < 0 {
                        if errno == EINTR {
                            continue
                        }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    offset += written
                }
            }
            guard fsync(descriptor) == 0, rename(temporary, Self.storeFile.path(percentEncoded: false)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            isComplete = true
        } catch {
            logger.error("Could not save the script store: \(error.localizedDescription, privacy: .private)")
        }
    }
}
