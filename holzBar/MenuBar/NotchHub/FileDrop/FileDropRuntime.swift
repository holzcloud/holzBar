//
//  FileDropRuntime.swift
//  holzBar
//

import Foundation
import Observation
import SwiftUI

/// The running part of the File drop module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. It holds the stash:
/// the addresses of the files the user dropped on its tab, in memory only. It never opens,
/// reads or copies a file, and it logs nothing that names a file or a path.
@MainActor
@Observable
final class FileDropRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "file-drop"

    let moduleID = FileDropRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// The stashed files. Names and paths live here in memory only.
    private(set) var stash = FileStash()

    /// The check for files that are gone, while one runs.
    @ObservationIgnored private var probeTask: Task<Void, Never>?

    /// Creates the runtime. It has nothing to start: the stash fills when files are dropped.
    init(appState: AppState) {}

    // MARK: Stash

    /// Stashes dropped files.
    ///
    /// - Returns: What happened, so the caller can tell whether anything was taken.
    @discardableResult
    func add(urls: [URL]) -> FileStash.AddResult {
        stash.add(urls)
    }

    /// Takes a file out of the stash.
    func remove(_ id: UUID) {
        stash.remove(id)
    }

    /// Marks the files that no longer exist. The lookup runs off the main actor and its result is
    /// dropped when it was overtaken by another check or by ``shutDown()``.
    func refreshMissing() {
        probeTask?.cancel()
        let keys = stash.keys
        guard !keys.isEmpty else {
            probeTask = nil
            return
        }
        probeTask = Task { [weak self] in
            let missing = await FileDropProbe.missingKeys(among: keys)
            guard !Task.isCancelled else {
                return
            }
            self?.stash.markMissing(missing)
        }
    }

    // MARK: Hub

    /// Looks for files that are gone when the hub opens, and at no other time: nothing repeats.
    func hubVisibilityDidChange(isOpen: Bool) {
        if isOpen {
            refreshMissing()
        }
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(FileDropBodyView(runtime: self))
    }

    /// Cancels the check and lets go of every reference.
    func shutDown() {
        probeTask?.cancel()
        probeTask = nil
        stash = FileStash()
    }
}
