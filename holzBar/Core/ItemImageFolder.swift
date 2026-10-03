//
//  ItemImageFolder.swift
//  holzBar
//

import Foundation

/// Moves the captured menu bar item images from their old place to the caches.
///
/// Earlier versions kept the images in `~/Library/Application Support/holzBar/ItemImages`,
/// which is backed up, although the images show other apps' items (message counts, VPN
/// state) and can be captured again at any time. They now live in the caches, which Time
/// Machine skips. This is a one-time move of holzBar's own data: the images are moved, not
/// deleted, so the holzBar Shelf has them at once after the update.
nonisolated enum ItemImageFolder {
    /// What ``moveLegacyFolder(from:to:fileManager:)`` did.
    nonisolated enum Outcome: Equatable {
        /// There was no old folder.
        case nothingToMove
        /// The old folder was moved to the new place.
        case moved
        /// The new place already had images, so the old copy was removed.
        case removedOldCopy
    }

    /// Moves the folder at `legacy` to `destination` once.
    ///
    /// When `destination` already exists, its images are newer and the old folder is removed
    /// instead. Afterwards the old folder's parent is removed if nothing else is left in it.
    ///
    /// - Parameters:
    ///   - legacy: The old folder of the images.
    ///   - destination: The new folder of the images.
    ///   - fileManager: The file manager to use.
    /// - Returns: What was done.
    static func moveLegacyFolder(from legacy: URL, to destination: URL, fileManager: FileManager = .default) throws -> Outcome {
        guard fileManager.fileExists(atPath: legacy.path(percentEncoded: false)) else {
            return .nothingToMove
        }
        let outcome: Outcome
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: legacy)
            outcome = .removedOldCopy
        } else {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacy, to: destination)
            outcome = .moved
        }
        let parent = legacy.deletingLastPathComponent()
        if try fileManager.contentsOfDirectory(atPath: parent.path(percentEncoded: false)).isEmpty {
            try fileManager.removeItem(at: parent)
        }
        return outcome
    }
}
