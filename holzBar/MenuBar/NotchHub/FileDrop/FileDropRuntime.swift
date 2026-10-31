//
//  FileDropRuntime.swift
//  holzBar
//

import AppKit
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

    /// The app state, for the setting that decides whether a dropped file leaves the stash.
    @ObservationIgnored private weak var appState: AppState?

    /// Creates the runtime. It has nothing to start: the stash fills when files are dropped.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Whether a file dragged to the notch opens the hub on this module's tab: the setting. It
    /// reads observable state, so the hub follows a change.
    var acceptsFileDrags: Bool {
        appState?.settings.fileDrop.opensOnDrag ?? false
    }

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

    /// Takes every file out of the stash.
    func removeAll() {
        stash.removeAll()
    }

    /// Handles the end of a drag out of the stash: the file leaves when the receiver took it and
    /// the setting says so; a cancelled or refused drag leaves it where it is.
    func dragFinished(id: UUID, completed: Bool) {
        let removesAfterDrop = appState?.settings.fileDrop.removesAfterDrop ?? true
        if FileStash.shouldRemoveAfterDrag(completed: completed, removesAfterDrop: removesAfterDrop) {
            stash.remove(id)
        }
    }

    /// Shows a file in the Finder. A file that is marked missing is not looked for.
    func showInFinder(_ id: UUID) {
        guard let file = stash.files.first(where: { $0.id == id }), !file.isMissing else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
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

    /// The Overview card: how many files are stashed, never a name. None while the stash is empty.
    var tile: HubTile? {
        let count = stash.files.count
        guard count > 0 else {
            return nil
        }
        return HubTile(
            symbol: "tray.and.arrow.down",
            title: Text("File drop"),
            value: String(count),
            detail: Text("in the stash")
        )
    }

    /// The pill beside the notch: the count, never a name. None while the stash is empty.
    var statusPill: HubStatusPill? {
        let count = stash.files.count
        guard count > 0 else {
            return nil
        }
        return HubStatusPill(
            symbol: "tray.full",
            text: String(count),
            accessibilityLabel: Text("\(count) in the stash")
        )
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
