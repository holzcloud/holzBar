//
//  FileStash.swift
//  holzBar
//

import Foundation

/// A file the user dragged to the File drop module: where it is, and whether it was last seen
/// to be gone.
nonisolated struct StashedFile: Identifiable, Equatable, Sendable {
    /// Identifies the file in the stash for as long as it is stashed; dropping the same path
    /// again keeps it.
    let id: UUID

    /// The address of the file. Nothing is read from it.
    var url: URL

    /// Whether the file was not found the last time the stash looked. A file that was moved or
    /// deleted stays in the stash, marked.
    var isMissing: Bool
}

/// The File drop module's stash and its rules, as a pure value.
///
/// The stash holds references only: the addresses of the files the user dragged, in memory. It
/// reads no file, opens no file and touches no file system, so macOS has nothing to ask about
/// and nothing about the user's files is written anywhere.
///
/// Rules:
/// 1. A URL is acceptable when it is a file URL with an absolute path that is not the root;
///    anything else is ignored and counted.
/// 2. Two URLs are the same file when their ``key(for:)`` is equal: the standardized path
///    without a trailing slash. Nothing is looked up on disk.
/// 3. A batch is processed in order. A key seen twice in the batch counts once. A key that is
///    already stashed moves to the front, keeps its id and loses its missing mark. A new key is
///    inserted. The batch keeps its own order at the front of the list.
/// 4. At most ``maximumFiles`` are kept. When the stash is full a new key is refused and
///    counted, and nothing already stashed is dropped; a key already stashed can still move.
/// 5. Removing is by id; an unknown id changes nothing.
/// 6. The newest drop comes first.
nonisolated struct FileStash: Equatable, Sendable {
    /// The most files the stash keeps.
    static let maximumFiles = 50

    /// What a call to ``add(_:makeID:)`` did, so the interface can say that a drop was refused.
    struct AddResult: Equatable, Sendable {
        /// Files that were not in the stash and are now.
        var added = 0
        /// Files that were already stashed and moved to the front.
        var moved = 0
        /// URLs that are not an absolute file path.
        var ignored = 0
        /// New files that did not fit because the stash is full.
        var refusedFull = 0
    }

    /// The stashed files, the newest first.
    private(set) var files = [StashedFile]()

    /// The keys of the stashed files, in order.
    var keys: [String] {
        files.map { Self.key(for: $0.url) }
    }

    /// Whether a URL can be stashed: a file URL with an absolute path that is not the root.
    static func isAcceptable(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }
        let key = key(for: url)
        return key.hasPrefix("/") && key != "/"
    }

    /// The identity of a file in the stash: its standardized path, without a trailing slash.
    static func key(for url: URL) -> String {
        let path = url.standardized.path
        if path.count > 1, path.hasSuffix("/") {
            return String(path.dropLast())
        }
        return path
    }

    /// Stashes the files of a drop and tells what happened.
    ///
    /// - Parameters:
    ///   - urls: The dropped URLs, in the order of the drop.
    ///   - makeID: Makes the id of a file that was not stashed yet.
    @discardableResult
    mutating func add(_ urls: [URL], makeID: () -> UUID = UUID.init) -> AddResult {
        var result = AddResult()
        var seen = Set<String>()
        var front = [StashedFile]()
        var existing = [String: StashedFile]()
        for file in files {
            existing[Self.key(for: file.url)] = file
        }
        var count = files.count
        for url in urls {
            guard Self.isAcceptable(url) else {
                result.ignored += 1
                continue
            }
            let key = Self.key(for: url)
            guard seen.insert(key).inserted else {
                continue
            }
            if var file = existing[key] {
                file.url = url
                file.isMissing = false
                front.append(file)
                result.moved += 1
            } else if count < Self.maximumFiles {
                front.append(StashedFile(id: makeID(), url: url, isMissing: false))
                count += 1
                result.added += 1
            } else {
                result.refusedFull += 1
            }
        }
        guard !front.isEmpty else {
            return result
        }
        files = front + files.filter { !seen.contains(Self.key(for: $0.url)) }
        return result
    }

    /// Marks the files that are gone and clears the mark on every other file.
    ///
    /// The set holds keys, as ``key(for:)`` makes them. A key that is not stashed is ignored.
    /// Order and ids never change.
    mutating func markMissing(_ missing: Set<String>) {
        for index in files.indices {
            files[index].isMissing = missing.contains(Self.key(for: files[index].url))
        }
    }

    /// Whether a file leaves the stash after the user dragged it out.
    ///
    /// A drag is completed when the receiver took the file, that is, when the drop's operation
    /// was anything other than none. A cancelled or refused drag leaves the file in the stash,
    /// and so does the setting being off.
    static func shouldRemoveAfterDrag(completed: Bool, removesAfterDrop: Bool) -> Bool {
        completed && removesAfterDrop
    }

    /// Takes a file out of the stash. An unknown id changes nothing.
    mutating func remove(_ id: UUID) {
        files.removeAll { $0.id == id }
    }

    /// Empties the stash.
    mutating func removeAll() {
        files.removeAll()
    }
}
