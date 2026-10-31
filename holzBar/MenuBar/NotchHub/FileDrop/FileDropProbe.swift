//
//  FileDropProbe.swift
//  holzBar
//

import Foundation

/// Tells which stashed files are gone.
///
/// This is the only place the File drop module touches the file system. A path on a network
/// volume that cannot be reached can make a lookup wait a long time, so the lookup runs off the
/// main actor and the interface never waits for it.
enum FileDropProbe {
    /// The keys, among the given ones, of the paths that do not exist (any more).
    ///
    /// - Parameter keys: Stash keys: standardized absolute paths.
    /// - Returns: The keys of the missing paths. The check stops early when the task is
    ///   cancelled, and then returns what it found so far, which the caller discards.
    @concurrent
    static func missingKeys(among keys: [String]) async -> Set<String> {
        var missing = Set<String>()
        for key in keys {
            if Task.isCancelled {
                break
            }
            if !FileManager.default.fileExists(atPath: key) {
                missing.insert(key)
            }
        }
        return missing
    }
}
