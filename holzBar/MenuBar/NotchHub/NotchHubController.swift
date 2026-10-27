//
//  NotchHubController.swift
//  holzBar
//

import AppKit
import Observation
import OSLog
import SwiftUI

/// The Notch hub module's controller: it follows the module switch, and opens and closes the
/// hub's panel.
///
/// Nothing exists while the module is off except the observation of the switch: no panel, no
/// monitor and no task. The panel is created the first time the hub opens, and released when
/// the module goes off.
///
/// A module of the hub has a runtime object only while both the hub and the module are on:
/// ``HubModuleLifecycle`` decides which runtimes start and stop, this class creates them from
/// their registrations and shuts them down.
@MainActor
@Observable
final class NotchHubController: HubHost {
    /// The identifier of the module in ``ModuleCatalog``.
    static let moduleID = "notch-hub"

    /// Whether the module is on.
    private(set) var isActive = false

    /// Whether the hub is open.
    private(set) var isOpen = false

    /// What the hub's views read: the runtimes, the strip and the selected tab.
    let model = NotchHubModel()

    /// The display the hub is open on, or `nil` while it is closed.
    var screenID: CGDirectDisplayID? {
        openScreenID
    }

    @ObservationIgnored private let logger = Logger(category: "NotchHub")
    @ObservationIgnored private weak var appState: AppState?

    /// Follows the module switch; the only observation that exists while the module is off.
    @ObservationIgnored private var moduleLoop: ObservationLoop?

    /// Follows which hub modules are switched on, while the hub is on.
    @ObservationIgnored private var modulesLoop: ObservationLoop?

    /// The runtimes of the hub modules that are on, by identifier. Empty while the hub is off.
    @ObservationIgnored private var runtimes = [String: any HubModuleRuntime]()

    /// The panel, created by the first open and released when the module goes off.
    @ObservationIgnored private var panel: NotchHubPanel?

    @ObservationIgnored private var openScreenID: CGDirectDisplayID?

    /// Follows the module switch. With the module off, nothing else is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] isOn in
            self?.setActive(isOn)
        }
        setActive(appState.modules.isEnabled(Self.moduleID))
    }

    private func setActive(_ isOn: Bool) {
        guard isOn != isActive else {
            return
        }
        isActive = isOn
        if isOn {
            modulesLoop = ObservationLoop.observe { [weak appState] in
                guard let appState else {
                    return Set<String>()
                }
                return Set(HubModules.all.map(\.id).filter { appState.modules.isEnabled($0) })
            } onChange: { [weak self] _ in
                self?.reconcileRuntimes()
            }
            reconcileRuntimes()
        } else {
            modulesLoop = nil
            close()
            // The hub is off, so the plan stops every runtime before the panel goes.
            reconcileRuntimes()
            panel?.orderOut(nil)
            panel = nil
        }
    }

    /// Starts and stops the runtimes the plan says: a module has one only while the hub and the
    /// module are both on.
    private func reconcileRuntimes() {
        guard let appState else {
            return
        }
        let registered = HubModuleLifecycle.registeredOrder(
            catalogOrder: ModuleCatalog.all.map(\.id),
            registrations: HubModules.all.map(\.id)
        )
        let plan = HubModuleLifecycle.plan(
            hubIsOn: isActive,
            enabled: Set(registered.filter { appState.modules.isEnabled($0) }),
            registered: registered,
            running: Set(runtimes.keys)
        )
        for id in plan.stop {
            runtimes.removeValue(forKey: id)?.shutDown()
        }
        for id in plan.start {
            if let runtime = HubModules.registration(for: id)?.makeRuntime(appState) {
                runtimes[id] = runtime
            }
        }
        // The model follows the runtimes in catalog order. An unchanged list is not stored,
        // so the views do not draw again for it.
        let ordered = registered.compactMap { runtimes[$0] }
        if ordered.map(\.moduleID) != model.runtimes.map(\.moduleID) {
            model.runtimes = ordered
        }
    }

    // MARK: Opening and closing

    /// Opens the hub on the display under the pointer, or closes it. Does nothing while the
    /// module is off.
    func toggle() {
        guard isActive else {
            return
        }
        if isOpen {
            close()
        } else {
            open(on: NSScreen.screenWithMouse ?? NSScreen.main)
        }
    }

    /// Opens the hub on a screen. Shows nothing where the screen has no usable size.
    private func open(on screen: NSScreen?) {
        guard
            isActive,
            let screen,
            let layout = NotchHubGeometry.layout(
                display: Self.display(of: screen),
                content: NotchHubGeometry.Content(bodyHeight: Self.tracerBodyHeight)
            )
        else {
            logger.debug("The Notch hub has no layout for this screen")
            return
        }
        let panel = panel ?? NotchHubPanel()
        self.panel = panel
        let flipped = NotchHubGeometry.flipped(layout.silhouette, displayHeight: Double(screen.frame.height))
        panel.applyDarkAppearance()
        panel.contentView = NotchHubHostingView(view: NotchHubView(layout: layout))
        panel.setFrame(
            NSRect(
                x: screen.frame.minX + flipped.x,
                y: screen.frame.minY + flipped.y,
                width: flipped.width,
                height: flipped.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
        isOpen = true
        openScreenID = screen.displayID
        notifyRuntimes(isOpen: true)
        logger.debug("The Notch hub opened on display \(screen.displayID, privacy: .public)")
    }

    /// Closes the hub. The panel stays for the next open, without content.
    func close() {
        let wasOpen = isOpen
        panel?.orderOut(nil)
        panel?.contentView = nil
        isOpen = false
        openScreenID = nil
        if wasOpen {
            notifyRuntimes(isOpen: false)
        }
    }

    private func notifyRuntimes(isOpen: Bool) {
        for runtime in model.runtimes {
            runtime.hubVisibilityDidChange(isOpen: isOpen)
        }
    }

    // MARK: HubHost

    func select(moduleID: String) {
        model.select(moduleID)
    }

    func openSettings(for moduleID: String) {
        close()
        guard let appState else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .modules
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    // MARK: Geometry

    /// The height of the body until the hub has parts to show.
    private static let tracerBodyHeight: Double = 120

    /// What the geometry needs to know about a screen, read from the system's own values.
    private static func display(of screen: NSScreen) -> NotchHubGeometry.Display {
        let frame = screen.frame
        let notch: NotchHubGeometry.Notch? = if screen.hasNotch {
            NotchHubGeometry.notch(
                displayWidth: Double(frame.width),
                leftAreaWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
                rightAreaWidth: screen.auxiliaryTopRightArea.map { Double($0.width) },
                height: Double(screen.safeAreaInsets.top)
            )
        } else {
            nil
        }
        let menuBarHeight: CGFloat
        if screen.hasNotch {
            menuBarHeight = screen.safeAreaInsets.top
        } else if frame.maxY - screen.visibleFrame.maxY > 0 {
            menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        } else {
            menuBarHeight = NSStatusBar.system.thickness
        }
        return NotchHubGeometry.Display(
            width: Double(frame.width),
            height: Double(frame.height),
            menuBarHeight: Double(menuBarHeight),
            notch: notch
        )
    }
}
