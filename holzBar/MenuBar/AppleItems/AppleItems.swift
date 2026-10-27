//
//  AppleItems.swift
//  holzBar
//

import Foundation
import Observation

/// The Apple Items module (macOS 27): hiding the clock, the battery, Wi-Fi and Control Centre.
///
/// The module is off until the user switches it on and costs nothing while off. The stored
/// choice never takes effect while the module is off or the holzBar Shelf is on
/// (``concealedSystemItems(in:)``). There is no timer and no observer in this class: the
/// concealer observes ``concealedSystemItems(in:)``.
@MainActor
@Observable
final class AppleItems {
    /// The identifier of the module in ``ModuleCatalog``.
    static let moduleID = "apple-items"

    /// Whether the running macOS offers the module: macOS 27, where Apple's items are drawn by
    /// MenuBarAgent and hidden through assessment-mode assertions.
    static var isSupported: Bool {
        MenuBarBackendKind.current == .accessibility27
    }

    /// The system items the user chose to hide. They take effect only through
    /// ``concealedSystemItems(in:)``.
    private(set) var hiddenSystemItems: Set<SystemItem27>

    init() {
        let stored = Defaults.array(forKey: .hiddenSystemItems27) as? [String] ?? []
        hiddenSystemItems = SystemItems27.hidden(fromStored: stored)
    }

    /// Whether the user chose to hide the item.
    func isHidden(_ item: SystemItem27) -> Bool {
        hiddenSystemItems.contains(item)
    }

    /// Stores the choice to hide or show a system item.
    func setHidden(_ item: SystemItem27, _ isHidden: Bool) {
        if isHidden {
            hiddenSystemItems.insert(item)
        } else {
            hiddenSystemItems.remove(item)
        }
        Defaults.set(SystemItems27.storedNames(of: hiddenSystemItems), forKey: .hiddenSystemItems27)
    }

    /// The system items to hide now: none while the module is off, and none while the holzBar
    /// Shelf is on, whatever is stored. The Shelf cannot show a system item, and nothing else
    /// would bring it back.
    func concealedSystemItems(in appState: AppState) -> Set<SystemItem27> {
        SystemItems27.concealed(
            stored: hiddenSystemItems,
            moduleIsOn: appState.modules.isEnabled(Self.moduleID),
            shelfIsOn: appState.settings.general.useShelf
        )
    }
}
