//
//  StandInItems27.swift
//  holzBar
//

import AppKit
import OSLog

/// Draws a stand-in icon for every visible application whose menu bar item macOS 27 hides
/// anyway, and opens the real item when the user clicks it.
///
/// MenuBarAgent names an item by its owner's bundle identifier only when the owner runs from
/// `/Applications` or `/System` (``UnnameableApps27``); any other item is hidden whenever
/// something is concealed, even in Visible. holzBar's own item is named, so it stays: the
/// stand-in is a status item of holzBar's that shows the application's picture, or else its
/// icon, in the place of the hidden item. A click on it (left or right) opens the real item
/// through the release-all route of ``ItemClicker27``; the stand-in is not drawn while that
/// hold lasts, so the icon is never doubled, and comes back with the concealment.
///
/// The stand-in has no accessibility identifier and an autosave name of its own
/// (``StandIns27/autosaveName(for:)``): the provider drops it from every read, so it is never
/// an item in the layout, the holzBar Shelf or the image store. Its frame feeds the hit test
/// instead (``hitTestFrames``), so a click on it is never a click on the empty bar.
///
/// Nothing is polled. One observation follows the switch; while it is off nothing else is read.
@available(macOS 27.0, *)
@MainActor
final class StandInItems27: NSObject {
    private weak var appState: AppState?

    private let logger = Logger(category: "StandInItems27")

    /// The stand-ins, by the bundle identifier of their application.
    private var statusItems = [String: NSStatusItem]()

    private var observer: ObservationLoop?

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Starts following the switch and the apps MenuBarAgent cannot name. Does nothing off
    /// macOS 27's backend, and nothing while holzBar itself runs from a place MenuBarAgent
    /// cannot name: it conceals holzBar's own items too, so a stand-in would be hidden as well.
    func performSetup() {
        guard MenuBarBackendKind.current == .accessibility27 else {
            return
        }
        let isNameable = !UnnameableApps27.isUnnameable(
            bundleID: Bundle.main.bundleIdentifier,
            bundlePath: UnnameableApps27.rulePath(of: Bundle.main.bundleURL)
        )
        guard isNameable else {
            logger.notice("holzBar runs outside /Applications, so macOS conceals its own items too and stand-in icons stay off")
            return
        }
        observer = ObservationLoop(
            observing: { [weak self] in self?.observedInputs() ?? false },
            onChange: { [weak self] _ in self?.update() }
        )
        update()
    }

    /// The frames of the stand-ins that are drawn, in the coordinates of the window list (the
    /// origin at the top left of the primary screen), for the hit test.
    var hitTestFrames: [CGRect] {
        guard let primaryScreenHeight = NSScreen.screens.first?.frame.height else {
            return []
        }
        return statusItems.values.compactMap { statusItem in
            guard statusItem.isVisible, let frame = statusItem.button?.window?.frame else {
                return nil
            }
            return StatusItemWindowFrame.windowBounds(fromAppKitFrame: frame, primaryScreenHeight: primaryScreenHeight)
        }
    }

    /// Reads what the stand-ins depend on, so the observation reports a change of any of it.
    /// With the switch off it reads only the switch.
    private func observedInputs() -> Bool {
        guard let appState, appState.settings.general.standInIcons else {
            return false
        }
        let concealer = appState.concealer27
        _ = concealer.concealsThroughSuspensions
        _ = concealer.isReleasedForAnyReason
        guard !concealer.unnameableVisible.isEmpty else {
            return true
        }
        _ = appState.itemManager.itemCache
        _ = appState.imageCache.images
        return true
    }

    /// Brings the stand-ins in line with the plan.
    private func update() {
        guard let appState else {
            return
        }
        let concealer = appState.concealer27
        let plan = StandIns27.plan(
            isEnabled: appState.settings.general.standInIcons,
            holzBarIsNameable: true,
            unnameableVisible: concealer.unnameableVisible,
            isConcealing: concealer.concealsThroughSuspensions,
            isHoldingRelease: concealer.isReleasedForAnyReason
        )
        var planned = [(bundleID: String, application: NSRunningApplication)]()
        for bundleID in plan.bundleIDs {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                planned.append((bundleID, application))
            }
        }
        let plannedIDs = Set(planned.map(\.bundleID))
        for bundleID in statusItems.keys where !plannedIDs.contains(bundleID) {
            remove(bundleID)
        }
        for (bundleID, application) in planned {
            let statusItem = statusItems[bundleID] ?? makeStatusItem(for: bundleID)
            configure(statusItem, for: application, bundleID: bundleID, appState: appState)
            setVisible(plan.isShown, statusItem)
        }
    }

    private func makeStatusItem(for bundleID: String) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = StandIns27.autosaveName(for: bundleID)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(standInClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        }
        statusItems[bundleID] = statusItem
        logger.debug("Added a stand-in icon (\(self.statusItems.count, privacy: .public) now)")
        return statusItem
    }

    private func configure(
        _ statusItem: NSStatusItem,
        for application: NSRunningApplication,
        bundleID: String,
        appState: AppState
    ) {
        guard let button = statusItem.button else {
            return
        }
        if let item = realItem(of: bundleID, appState: appState), let image = appState.itemIconStore.image(for: item) {
            button.image = image
        } else if let icon = application.icon {
            button.image = ItemIconStore.sizedForMenuBar(icon)
        } else if let path = application.bundleURL?.path(percentEncoded: false) {
            button.image = ItemIconStore.sizedForMenuBar(NSWorkspace.shared.icon(forFile: path))
        }
        let name = application.localizedName ?? ""
        button.toolTip = name
        button.setAccessibilityLabel(name)
    }

    /// Shows or hides a stand-in. Hiding a status item deletes the place macOS remembered for
    /// it, as it does for a control item, so the place is kept and restored.
    private func setVisible(_ isVisible: Bool, _ statusItem: NSStatusItem) {
        guard statusItem.isVisible != isVisible else {
            return
        }
        let name = statusItem.autosaveName as String
        let position = ControlItemDefaults[.preferredPosition, name]
        statusItem.isVisible = isVisible
        ControlItemDefaults[.preferredPosition, name] = position
    }

    /// Takes a stand-in out of the bar, keeping the place it had for when it comes back.
    private func remove(_ bundleID: String) {
        guard let statusItem = statusItems.removeValue(forKey: bundleID) else {
            return
        }
        let name = statusItem.autosaveName as String
        let position = ControlItemDefaults[.preferredPosition, name]
        NSStatusBar.system.removeStatusItem(statusItem)
        ControlItemDefaults[.preferredPosition, name] = position
    }

    /// The first item of the application in Visible, which is the one the stand-in opens.
    private func realItem(of bundleID: String, appState: AppState) -> MenuBarItem? {
        appState.itemManager.itemCache[.visible].first { item in
            !item.isControlItem && !item.isOwnArrangedItem && item.sourceApplication?.bundleIdentifier == bundleID
        }
    }

    @objc private func standInClicked(_ sender: NSStatusBarButton) {
        guard
            let appState,
            let bundleID = statusItems.first(where: { $0.value.button === sender })?.key,
            let item = realItem(of: bundleID, appState: appState)
        else {
            return
        }
        let mouseButton: CGMouseButton = NSApp.currentEvent?.type == .rightMouseUp ? .right : .left
        Task {
            await appState.itemManager.openItem(item, mouseButton: mouseButton, shelfDisplayID: nil, origin: .click)
        }
    }
}
