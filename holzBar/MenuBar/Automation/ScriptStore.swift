//
//  ScriptStore.swift
//  holzBar
//

import AppKit
import CryptoKit
import Observation
import OSLog

/// The scripts of the Scripts folder, what the user approved, and the facts of each file that
/// ``ScriptGate`` decides on.
///
/// Scripts are local to the Mac. Their approvals are in a file next to the folder, not in the
/// settings: no export, import, sync, URL or Shortcut can create or approve one. A script
/// runs only after the user saw its name, size and checksum and allowed that content; a
/// changed file needs a new approval.
@MainActor
@Observable
final class ScriptStore {
    /// One script file in the folder.
    struct Entry: Identifiable, Equatable {
        let name: String
        let size: Int
        /// The first characters of the SHA-256, shown when the user decides.
        let checksumPrefix: String
        let decision: ScriptGate.Decision

        var id: String { name }
    }

    /// The scripts, sorted by name.
    private(set) var scripts = [Entry]()

    @ObservationIgnored private let logger = Logger(category: "ScriptStore")
    @ObservationIgnored private var approvals = [String: String]()

    /// `~/Library/Application Support/holzBar/Scripts`.
    static let folder: URL = URL.applicationSupportDirectory
        .appending(path: "holzBar", directoryHint: .isDirectory)
        .appending(path: "Scripts", directoryHint: .isDirectory)

    private static let approvalsFile: URL = URL.applicationSupportDirectory
        .appending(path: "holzBar", directoryHint: .isDirectory)
        .appending(path: "ScriptApprovals.json", directoryHint: .notDirectory)

    func performSetup() {
        loadApprovals()
        refresh()
    }

    // MARK: Reading the folder

    /// Reads the folder again.
    func refresh() {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: Self.folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let names = (try? manager.contentsOfDirectory(atPath: Self.folder.path(percentEncoded: false))) ?? []
        scripts = names.sorted().compactMap { name in
            guard let info = fileInfo(for: name) else {
                return nil
            }
            return Entry(
                name: name,
                size: info.size,
                checksumPrefix: String(info.sha256.prefix(8)),
                decision: ScriptGate.decide(info, approvedHash: approvals[name])
            )
        }
    }

    /// The facts of a script file, or `nil` when it cannot be read.
    func fileInfo(for name: String) -> ScriptFileInfo? {
        guard ScriptGate.isPlainName(name) else {
            return nil
        }
        let url = Self.folder.appending(path: name, directoryHint: .notDirectory)
        let path = url.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let type = attributes[.type] as? FileAttributeType
        let size = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
        let isRegular = type == .typeRegular
        // The contents are read only for a plain file of a sensible size.
        var hash = ""
        if isRegular, size <= ScriptGate.maximumSize, let data = try? Data(contentsOf: url) {
            hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return ScriptFileInfo(
            name: name,
            isRegularFile: isRegular,
            isSymbolicLink: type == .typeSymbolicLink,
            isOwnedByCurrentUser: (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
            mode: UInt16((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0),
            hasQuarantineAttribute: getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0,
            size: size,
            sha256: hash
        )
    }

    /// The checksum the user approved for the file, if any.
    func approvedHash(for name: String) -> String? {
        approvals[name]
    }

    // MARK: Approving

    /// Approves the contents the file has now. Called only after the user confirmed.
    func approve(_ entry: Entry) {
        guard let info = fileInfo(for: entry.name), String(info.sha256.prefix(8)) == entry.checksumPrefix else {
            // The file changed while the sheet was open: the user decides again.
            refresh()
            return
        }
        approvals[entry.name] = info.sha256
        saveApprovals()
        refresh()
    }

    func revokeApproval(_ entry: Entry) {
        approvals.removeValue(forKey: entry.name)
        saveApprovals()
        refresh()
    }

    func openFolder() {
        refresh()
        NSWorkspace.shared.open(Self.folder)
    }

    // MARK: Approvals file

    private func loadApprovals() {
        guard
            let data = try? Data(contentsOf: Self.approvalsFile),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }
        approvals = decoded
    }

    private func saveApprovals() {
        do {
            try FileManager.default.createDirectory(
                at: Self.approvalsFile.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try JSONEncoder().encode(approvals).write(to: Self.approvalsFile, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Self.approvalsFile.path(percentEncoded: false)
            )
        } catch {
            logger.error("Could not save the script approvals: \(error.localizedDescription, privacy: .private)")
        }
    }
}
