import Foundation

/// What one Mac's replica of the shared folder holds at one path (A2 section 2.2).
enum SimFolderEntry: Equatable, Sendable {
    /// Content is on this Mac.
    case present(Data)
    /// A placeholder: the content is not on this Mac. Reading starts a download that can block.
    case dataless(Data)
    /// Truncated or in-progress content (non-coordinating providers, SMB).
    case partial(Data)
    /// A symbolic link someone put at the path. Never followed.
    case symbolicLink
    case absent
}

/// The result of a bounded read through a Mac's context.
enum SimReadResult: Equatable, Sendable {
    /// The bytes and the provider version they come from (0 when unknown, for example foreign bytes).
    case data(Data, version: Int)
    case absent
    /// The file is dataless: no content is available. A download has to be requested.
    case notLocal
    /// The file is larger than the bound; the actual size is reported, no bytes are returned.
    case tooLarge(size: Int)
    case symbolicLink
    case notMounted
    /// The provider stalled longer than the I/O bound; the caller gave up.
    case timedOut
}

enum SimWriteResult: Equatable, Sendable {
    case written
    case notMounted
    case timedOut
}

enum SimListResult: Equatable, Sendable {
    /// Sorted names of the entries directly inside the directory (files and links, not dataless-hidden ones).
    case names([String])
    case notMounted
    case timedOut
}

/// One Mac's view of the shared folder.
struct SimFolderReplica: Equatable, Sendable {
    /// Content or marker per path, relative to the folder root (`holzBar/Settings.plist`).
    var entries: [String: SimFolderEntry] = [:]
    /// The provider version ID that produced the main content at each path (0: unknown or foreign,
    /// -1: written during a hook and not yet submitted to the provider).
    var versions: [String: Int] = [:]
    /// Unresolved conflict versions per path (iCloud `NSFileVersion`), readable through the coordinated read API.
    var conflictVersions: [String: [ConflictVersion]] = [:]
    /// Main versions this replica holds or has held (used to tell concurrent writes from informed ones).
    var seenVersions: Set<Int> = []
    var isMounted = true
    /// Global virtual time until which coordinated reads and writes on this Mac block. `Int64.max` is forever.
    var stalledUntil: Int64 = 0
    /// Global virtual time until which this Mac neither sends nor receives.
    var offlineUntil: Int64 = 0
    /// Partial exposure windows: the full content comes back at `until`.
    var partialWindows: [String: PartialWindow] = [:]

    struct PartialWindow: Equatable, Sendable {
        var until: Int64
        var full: Data
        var version: Int
    }

    struct ConflictVersion: Equatable, Sendable {
        var version: Int
        var data: Data
    }

    func entry(_ path: String) -> SimFolderEntry { entries[path] ?? .absent }

    func isStalled(at now: Int64) -> Bool { stalledUntil > now }

    /// Ends partial windows and stalls that have run out.
    mutating func settle(at now: Int64) {
        for path in partialWindows.keys.sorted() {
            guard let window = partialWindows[path], window.until <= now else { continue }
            if case .partial = entry(path) { entries[path] = .present(window.full) }
            partialWindows[path] = nil
        }
        if stalledUntil <= now { stalledUntil = 0 }
    }

    /// A bounded read with the provider's semantics. Does no I/O accounting; the context does.
    func read(_ path: String, maximumBytes: Int) -> SimReadResult {
        guard isMounted else { return .notMounted }
        switch entry(path) {
        case .absent:
            return .absent
        case .symbolicLink:
            return .symbolicLink
        case .dataless:
            return .notLocal
        case .present(let data), .partial(let data):
            if data.count > maximumBytes { return .tooLarge(size: data.count) }
            return .data(data, version: max(versions[path] ?? 0, 0))
        }
    }

    /// Names directly inside a directory path such as `holzBar/Macs`, sorted.
    func list(_ directory: String) -> [String] {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        var names = Set<String>()
        for (path, entry) in entries where path.hasPrefix(prefix) {
            if case .absent = entry { continue }
            let rest = path.dropFirst(prefix.count)
            names.insert(String(rest.split(separator: "/", maxSplits: 1).first ?? ""))
        }
        return names.filter { !$0.isEmpty }.sorted()
    }
}
