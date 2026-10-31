//
//  AppleItems.swift
//  holzBar
//

import AppKit
import Observation

/// The Apple Items module (macOS 27): hiding the clock, the battery, Wi-Fi and Control Centre,
/// and replacement items for Apple's other items.
///
/// The module is off until the user switches it on and costs nothing while off: no status
/// item exists and no assertion changes. The stored choice of hidden system items takes effect
/// only while the module is on (``concealedSystemItems(in:)``); with the holzBar Shelf on, each
/// hidden item has a tile in the Shelf that opens it.
/// There is no timer and no polling: the concealer observes ``concealedSystemItems(in:)``, and
/// this class follows the module switch.
///
/// A replacement is an icon of holzBar's own, a status item with a symbol, that opens one
/// Apple item through the open path item hotkeys and groups use. It does not ask the
/// hidden-items lock: it opens the one item the user chose, not the hidden section.
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

    /// The replacement items, in the order they were added. At most
    /// ``AppleItemReplacement/maximumCount``.
    private(set) var replacements = [AppleItemReplacement]()

    @ObservationIgnored private weak var appState: AppState?

    /// Follows the module switch; the only observation that exists while the module is off.
    @ObservationIgnored private var moduleLoop: ObservationLoop?

    /// The status items of the replacements, by identifier. Empty while the module is off.
    @ObservationIgnored private var statusItems = [UUID: NSStatusItem]()
    @ObservationIgnored private var targets = [UUID: ClickTarget]()

    init() {
        let stored = Defaults.array(forKey: .hiddenSystemItems27) as? [String] ?? []
        hiddenSystemItems = SystemItems27.hidden(fromStored: stored)
    }

    // MARK: Setup

    /// Loads the replacements and follows the module switch. With the module off, nothing else
    /// is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        replacements = AppleItemReplacementList.decode(Defaults.data(forKey: .appleItemReplacements) ?? Data())
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] isOn in
            self?.setActive(isOn)
        }
        setActive(appState.modules.isEnabled(Self.moduleID))
    }

    /// Creates the replacements' status items while the module is on, and removes every one
    /// while it is off.
    private func setActive(_ isOn: Bool) {
        if isOn, Self.isSupported {
            updateStatusItems()
        } else {
            for statusItem in statusItems.values {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItems.removeAll()
            targets.removeAll()
        }
    }

    // MARK: Hidden system items

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

    /// The system items to hide now: the chosen ones while the module is on, whatever the
    /// holzBar Shelf does. The Shelf lists a tile for each of them, which opens the item.
    func concealedSystemItems(in appState: AppState) -> Set<SystemItem27> {
        SystemItems27.concealed(
            stored: hiddenSystemItems,
            moduleIsOn: appState.modules.isEnabled(Self.moduleID)
        )
    }

    // MARK: Replacement items

    /// Adds a replacement for the Apple item with the given key, unless the model refuses it
    /// (not an Apple item, a system item, a name that is empty, a seventh, one already there).
    ///
    /// - Returns: Whether the replacement was added.
    @discardableResult
    func addReplacement(forItemKey key: String, title: String) -> Bool {
        let replacement = AppleItemReplacement(
            id: UUID(),
            itemKey: key,
            title: title,
            symbolName: AppleItemCatalog.suggestedSymbol(forItemKey: key)
        )
        // Every rule of the stored form applies, through the list.
        guard
            let data = AppleItemReplacementList.encoded(replacements + [replacement]),
            let valid = AppleItemReplacementList.decode(data).first(where: { $0.id == replacement.id })
        else {
            return false
        }
        replacements.append(valid)
        save()
        updateStatusItems()
        return true
    }

    /// Removes a replacement and its status item.
    func removeReplacement(id: UUID) {
        guard let index = replacements.firstIndex(where: { $0.id == id }) else {
            return
        }
        replacements.remove(at: index)
        save()
        updateStatusItems()
    }

    /// Gives a replacement another symbol of the offered ones. Does nothing for a symbol that
    /// is not offered, one it already wears or a replacement that is gone.
    func setSymbol(_ symbolName: String, for id: UUID) {
        guard
            AppleItemCatalog.symbolNames.contains(symbolName),
            let index = replacements.firstIndex(where: { $0.id == id }),
            replacements[index].symbolName != symbolName
        else {
            return
        }
        replacements[index].symbolName = symbolName
        save()
        updateStatusItems()
    }

    /// The Apple items on the bar that can be replaced and are not yet, one per key, by name.
    func candidates() -> [(key: String, title: String)] {
        guard let itemManager = appState?.itemManager else {
            return []
        }
        let replaced = Set(replacements.map(\.itemKey))
        var seen = Set<String>()
        var result = [(key: String, title: String)]()
        for item in itemManager.itemCache.managedItems {
            let key = itemManager.identityKey(for: item)
            let title = WidgetDefinition.cleanedTitle(item.displayName)
            guard
                AppleItemCatalog.isReplaceable(itemKey: key),
                !title.isEmpty,
                !replaced.contains(key),
                seen.insert(key).inserted
            else {
                continue
            }
            result.append((key, title))
        }
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func save() {
        if let data = AppleItemReplacementList.encoded(replacements) {
            Defaults.set(data, forKey: .appleItemReplacements)
        }
    }

    // MARK: Status items

    /// Brings the status items in step with the replacements: nothing while the module is off.
    private func updateStatusItems() {
        guard appState?.modules.isEnabled(Self.moduleID) == true, Self.isSupported else {
            return
        }
        let ids = Set(replacements.map(\.id))
        for (id, statusItem) in statusItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(statusItem)
            statusItems[id] = nil
            targets[id] = nil
        }
        for replacement in replacements {
            let statusItem = statusItems[replacement.id] ?? {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                statusItem.autosaveName = replacement.autosaveName
                return statusItem
            }()
            statusItems[replacement.id] = statusItem
            let id = replacement.id
            let target = targets[id] ?? ClickTarget { [weak self] in
                self?.open(replacementWithID: id)
            }
            targets[id] = target
            if let button = statusItem.button {
                let symbol = NSImage(systemSymbolName: replacement.symbolName, accessibilityDescription: nil)
                    ?? NSImage(systemSymbolName: AppleItemCatalog.defaultSymbolName, accessibilityDescription: nil)
                symbol?.isTemplate = true
                button.image = symbol
                button.toolTip = replacement.title
                button.setAccessibilityLabel(replacement.title)
                button.target = target
                button.action = #selector(ClickTarget.clicked(_:))
            }
        }
    }

    /// Opens the Apple item of a replacement through the one open path.
    private func open(replacementWithID id: UUID) {
        guard let replacement = replacements.first(where: { $0.id == id }) else {
            return
        }
        appState?.itemManager.openItem(withIdentityKey: replacement.itemKey)
    }

    /// Forwards a status item button's click to a closure.
    private final class ClickTarget: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked(_ sender: NSStatusBarButton) {
            action()
        }
    }
}
