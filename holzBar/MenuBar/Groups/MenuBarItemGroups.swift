//
//  MenuBarItemGroups.swift
//  holzBar
//

import AppKit
import Observation
import OSLog
import SwiftUI

/// A named set of menu bar items behind an icon of its own.
struct MenuBarItemGroup: Codable, Hashable, Identifiable {
    var id = UUID()

    /// The group's name, shown at the top of its panel.
    var name: String

    /// The SF Symbol shown in the menu bar.
    var symbolName: String

    /// The tags of the items in the group, in order.
    var itemTags: [String]
}

/// Puts several menu bar items behind one icon of their own
/// (jordanbaird/Ice#46).
///
/// Each group adds an icon to the menu bar. Clicking it shows the group's items
/// in a small panel, where they can be clicked as in the holzBar Shelf. The items
/// themselves stay wherever they are, usually in a hidden section.
@MainActor
@Observable
final class MenuBarItemGroups {
    /// The saved groups.
    var groups = [MenuBarItemGroup]() {
        didSet {
            save()
            updateStatusItems()
        }
    }

    /// The symbols a group's icon can use.
    static let symbolNames = [
        "square.grid.2x2", "folder", "tray", "briefcase", "house", "gamecontroller",
        "music.note", "network", "bolt", "cloud", "wrench.and.screwdriver", "star",
    ]

    @ObservationIgnored private let logger = Logger(category: "MenuBarItemGroups")
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var statusItems = [UUID: NSStatusItem]()
    @ObservationIgnored private var targets = [UUID: ClickTarget]()
    @ObservationIgnored private let popover = NSPopover()
    @ObservationIgnored private var popoverObservers = [Task<Void, Never>]()

    func performSetup(with appState: AppState) {
        self.appState = appState
        if
            let data = Defaults.data(forKey: .itemGroups),
            let decoded = try? JSONDecoder().decode([MenuBarItemGroup].self, from: data)
        {
            groups = decoded
        } else {
            updateStatusItems()
        }
        popover.behavior = .transient
        // The image cache refreshes item images only while a view shows them.
        let popover = popover
        popoverObservers = [(NSPopover.didShowNotification, true), (NSPopover.didCloseNotification, false)].map { name, isShown in
            Task { [weak appState] in
                for await _ in NotificationCenter.default.notifications(named: name, object: popover) {
                    appState?.navigationState.isItemGroupPanelPresented = isShown
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(groups) {
            Defaults.set(data, forKey: .itemGroups)
        }
    }

    // MARK: Editing

    func addGroup(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        groups.append(MenuBarItemGroup(name: name, symbolName: Self.symbolNames[groups.count % Self.symbolNames.count], itemTags: []))
    }

    func deleteGroup(_ group: MenuBarItemGroup) {
        groups.removeAll { $0.id == group.id }
    }

    func toggle(_ item: MenuBarItem, in group: MenuBarItemGroup) {
        guard
            let itemManager = appState?.itemManager,
            let index = groups.firstIndex(where: { $0.id == group.id })
        else {
            return
        }
        // Members are stored under their identity, which survives a changing title; keys of
        // earlier versions (`namespace:title`) match through it too.
        let identityKey = itemManager.identityKey(for: item)
        if let itemIndex = groups[index].itemTags.firstIndex(where: { itemManager.storedIdentityKey($0) == identityKey }) {
            groups[index].itemTags.remove(at: itemIndex)
        } else {
            groups[index].itemTags.append(identityKey)
        }
    }

    /// Whether the given item belongs to the group.
    func contains(_ item: MenuBarItem, in group: MenuBarItemGroup) -> Bool {
        guard let itemManager = appState?.itemManager else {
            return false
        }
        let identityKey = itemManager.identityKey(for: item)
        return group.itemTags.contains { itemManager.storedIdentityKey($0) == identityKey }
    }

    func setSymbol(_ symbolName: String, for group: MenuBarItemGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        groups[index].symbolName = symbolName
    }

    // MARK: Status Items

    private func updateStatusItems() {
        let ids = Set(groups.map(\.id))
        for (id, statusItem) in statusItems where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(statusItem)
            statusItems[id] = nil
            targets[id] = nil
        }
        for group in groups {
            let statusItem = statusItems[group.id] ?? {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                statusItem.autosaveName = "holzBar.Group.\(group.id.uuidString)"
                return statusItem
            }()
            statusItems[group.id] = statusItem
            let target = targets[group.id] ?? ClickTarget { [weak self] button in
                self?.showPanel(for: group.id, relativeTo: button)
            }
            targets[group.id] = target
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: group.symbolName, accessibilityDescription: group.name)
                button.image?.isTemplate = true
                button.toolTip = group.name
                button.target = target
                button.action = #selector(ClickTarget.clicked(_:))
            }
        }
    }

    private func showPanel(for id: UUID, relativeTo button: NSStatusBarButton) {
        guard let appState, let group = groups.first(where: { $0.id == id }) else {
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let view = MenuBarItemGroupPanel(
            group: group,
            imageCache: appState.imageCache,
            itemManager: appState.itemManager
        ) { [weak self] in
            self?.popover.performClose(nil)
        }
        popover.contentViewController = NSHostingController(rootView: view)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Set at once (the notification may come later), so the update below captures.
        appState.navigationState.isItemGroupPanelPresented = true
        Task {
            await appState.imageCache.updateCache(sections: MenuBarSection.Name.allCases)
        }
    }

    /// Forwards a status item button's click to a closure.
    private final class ClickTarget: NSObject {
        let action: (NSStatusBarButton) -> Void

        init(action: @escaping (NSStatusBarButton) -> Void) {
            self.action = action
        }

        @objc func clicked(_ sender: NSStatusBarButton) {
            action(sender)
        }
    }
}

// MARK: - MenuBarItemGroupPanel

/// The items of a group, shown below the group's icon.
private struct MenuBarItemGroupPanel: View {
    let group: MenuBarItemGroup
    var imageCache: MenuBarItemImageCache
    var itemManager: MenuBarItemManager
    let close: () -> Void

    private var items: [MenuBarItem] {
        let byIdentityKey = Dictionary(
            itemManager.itemCache.managedItems.map { (itemManager.identityKey(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return group.itemTags.compactMap { byIdentityKey[itemManager.storedIdentityKey($0)] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.name)
                .font(.headline)
            if items.isEmpty {
                Text("Add items to this group in holzBar's Menu Bar Layout settings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 4) {
                    ForEach(items, id: \.tag) { item in
                        Button {
                            close()
                            Task {
                                try? await Task.sleep(for: .milliseconds(25))
                                await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: nil)
                            }
                        } label: {
                            if let image = imageCache.images[item.tag]?.nsImage {
                                Image(nsImage: image)
                            } else {
                                Text(item.displayName)
                            }
                        }
                        .buttonStyle(.plain)
                        .help(item.displayName)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180)
    }
}
