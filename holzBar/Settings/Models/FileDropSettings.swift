//
//  FileDropSettings.swift
//  holzBar
//

import Observation

/// Model for the File drop module's own settings: whether a file dragged to the notch opens the
/// hub, and whether a file leaves the stash once it was dropped elsewhere. Each saves itself in
/// its `didSet`.
@MainActor
@Observable
final class FileDropSettings {
    /// A Boolean value that indicates whether the Notch hub opens on the File drop tab when a
    /// file is dragged to the notch. On by default.
    var opensOnDrag = true {
        didSet {
            Defaults.set(opensOnDrag, forKey: .fileDropOpensOnDrag)
        }
    }

    /// A Boolean value that indicates whether a file leaves the stash once it was dropped
    /// elsewhere. On by default; off keeps the tile until the user removes it.
    var removesAfterDrop = true {
        didSet {
            Defaults.set(removesAfterDrop, forKey: .fileDropRemovesAfterDrop)
        }
    }

    /// Loads the stored settings.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .fileDropOpensOnDrag, assign: &opensOnDrag)
        Defaults.ifPresent(key: .fileDropRemovesAfterDrop, assign: &removesAfterDrop)
    }
}
