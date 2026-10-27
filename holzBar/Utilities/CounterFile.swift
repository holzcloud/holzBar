//
//  CounterFile.swift
//  holzBar
//

import Foundation

/// The file a set of usage counters lives in: one small JSON file in holzBar's folder in
/// Application Support, mode 0600, excluded from backups, and in no export, snapshot or log.
///
/// The usage suggestions and the search's memory of what was opened keep the same counters
/// (`UsageCounters`) in a file each, written and read here.
nonisolated enum CounterFile {
    /// The location of the file with the given name in holzBar's folder.
    static func url(named name: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
    }

    /// The counters in the file, with the days beyond the retention dropped, or `nil` when there
    /// is no file or it cannot be read.
    static func read(at url: URL, today: Int) -> UsageCounters? {
        guard
            let data = try? Data(contentsOf: url),
            var counters = try? JSONDecoder().decode(UsageCounters.self, from: data)
        else {
            return nil
        }
        counters.prune(today: today)
        return counters
    }

    /// Writes the counters, replacing the file.
    static func write(_ counters: UsageCounters, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var url = url
        try JSONEncoder().encode(counters).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Deletes the file, if there is one.
    static func delete(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
