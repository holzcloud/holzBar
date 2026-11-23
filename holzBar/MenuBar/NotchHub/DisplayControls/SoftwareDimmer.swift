//
//  SoftwareDimmer.swift
//  holzBar
//

import AppKit
import Observation

/// Software dimming of external displays (Phase 96, D-19, D-26, DISP-01): one dark overlay window
/// per dimmed display and nothing else.
///
/// A level above 0 puts a borderless black window over that display, at the level's opacity; 0
/// removes the window. The overlay is the only mechanism: no colour table of the display and no
/// private call (D-01). The window ignores the mouse, never becomes key, joins every Space and full-screen
/// Space, and is only a window, so it disappears with holzBar's process. The level is kept per
/// display UUID in ``DisplayControlsSettings/dimLevels`` on this Mac only, and never exceeds
/// ``SoftwareDimming/maximum``. The layer shows in screenshots and recordings: it is not lifted
/// during a capture.
///
/// A window exists only while the Notch hub and Display controls are on and the display's level
/// is above 0 (``SoftwareDimming/layerExists(level:hubOn:moduleOn:displayPresent:)``); with both
/// off or every level at 0 the dimmer holds nothing. Display names are never read here.
@MainActor
@Observable
final class SoftwareDimmer {
    /// The level of the overlay windows: above the menu bar (`.mainMenu`) and below the Notch hub
    /// (`.mainMenu + 2`). The probe on a real Mac confirms it; this is the one constant to change.
    static let layerLevel = NSWindow.Level.statusBar

    /// The dimmed displays, by UUID, whose layer cannot be put on screen now: the display is
    /// asleep or no screen shows it. The card says so (D-19).
    private(set) var unplacedDisplays = Set<String>()

    @ObservationIgnored private weak var appState: AppState?

    /// The overlay window of each dimmed display, by display UUID.
    @ObservationIgnored private var panels = [String: DimPanel]()

    /// Follows the switches that decide whether any layer may exist.
    @ObservationIgnored private var switchLoop: ObservationLoop?

    /// The overlay window: it takes no input and never becomes the key or main window.
    private final class DimPanel: NSPanel {
        override var canBecomeKey: Bool {
            false
        }

        override var canBecomeMain: Bool {
            false
        }
    }

    /// Starts following the switches of the hub and of Display controls. Creates nothing until a
    /// level is above 0.
    func performSetup(with appState: AppState) {
        self.appState = appState
        switchLoop = ObservationLoop.observe({ [weak appState] in
            Switches(
                hubOn: appState?.modules.isEnabled(NotchHubController.moduleID) ?? false,
                moduleOn: appState?.modules.isEnabled(DisplayControlsRuntime.identifier) ?? false
            )
        }, onChange: { [weak self] _ in
            self?.reconcile()
        })
        reconcile()
    }

    /// The two switches that allow a layer.
    private struct Switches: Equatable {
        var hubOn: Bool
        var moduleOn: Bool
    }

    // MARK: Levels

    /// The level of a display from 0 to ``SoftwareDimming/maximum``; 0 for a display that is not
    /// dimmed or has no identifier.
    func level(for display: CGDirectDisplayID) -> Double {
        guard let uuid = Bridging.getDisplayUUIDString(for: display) else {
            return 0
        }
        return appState?.settings.displayControls.dimLevels[uuid] ?? 0
    }

    /// Sets a display's level at once, without animation: held to 0 through the floor, stored on
    /// this Mac, and the layer created, changed or removed. A new display past the limit of 32 is
    /// refused.
    func setLevel(_ level: Double, for display: CGDirectDisplayID) {
        guard let settings = appState?.settings.displayControls,
              let uuid = Bridging.getDisplayUUIDString(for: display) else {
            return
        }
        let clamped = SoftwareDimming.clamped(level)
        var levels = settings.dimLevels
        levels[uuid] = clamped > 0 ? clamped : nil
        let stored = SoftwareDimming.cleaned(levels.mapValues { $0 as Any })
        if stored != settings.dimLevels {
            settings.dimLevels = stored
        }
        if let panel = panels[uuid], let shown = stored[uuid] {
            // The common case, a slider moving: only the opacity changes.
            panel.alphaValue = shown
        } else {
            reconcile()
        }
    }

    /// Removes the dimming of a display: the level goes to 0 and the layer goes away.
    func reset(_ display: CGDirectDisplayID) {
        setLevel(0, for: display)
    }

    /// Whether the layer of a dimmed display is on screen. A display that is not dimmed has
    /// nothing to place and counts as placed.
    func isPlaced(_ display: CGDirectDisplayID) -> Bool {
        guard let uuid = Bridging.getDisplayUUIDString(for: display) else {
            return true
        }
        return !unplacedDisplays.contains(uuid)
    }

    // MARK: Layers

    /// Brings the windows in line with the switches, the levels and the displays: closes those of
    /// displays that left or went to 0, creates those that are missing, refits the frames. The
    /// stored levels are never touched.
    private func reconcile() {
        guard let appState else {
            closeAll()
            return
        }
        let hubOn = appState.modules.isEnabled(NotchHubController.moduleID)
        let moduleOn = appState.modules.isEnabled(DisplayControlsRuntime.identifier)
        let levels = appState.settings.displayControls.dimLevels
        guard hubOn, moduleOn, !levels.isEmpty else {
            closeAll()
            return
        }
        var screens = [String: NSScreen]()
        for screen in NSScreen.screens where CGDisplayIsAsleep(screen.displayID) == 0 {
            if let uuid = Bridging.getDisplayUUIDString(for: screen.displayID) {
                screens[uuid] = screen
            }
        }
        var unplaced = Set<String>()
        var wanted = Set<String>()
        for (uuid, level) in levels {
            let screen = screens[uuid]
            guard SoftwareDimming.layerExists(level: level, hubOn: hubOn, moduleOn: moduleOn, displayPresent: screen != nil),
                  let screen else {
                unplaced.insert(uuid)
                continue
            }
            wanted.insert(uuid)
            place(uuid: uuid, level: level, on: screen)
        }
        for uuid in panels.keys where !wanted.contains(uuid) {
            panels[uuid]?.close()
            panels[uuid] = nil
        }
        setUnplaced(unplaced)
    }

    /// Creates or updates the window of a display.
    private func place(uuid: String, level: Double, on screen: NSScreen) {
        if let panel = panels[uuid] {
            panel.alphaValue = level
            if panel.frame != screen.frame {
                panel.setFrame(screen.frame, display: false)
            }
            return
        }
        let panel = DimPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .black
        panel.alphaValue = level
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = Self.layerLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.orderFrontRegardless()
        panels[uuid] = panel
    }

    private func closeAll() {
        for panel in panels.values {
            panel.close()
        }
        panels.removeAll()
        setUnplaced([])
    }

    private func setUnplaced(_ unplaced: Set<String>) {
        if unplaced != unplacedDisplays {
            unplacedDisplays = unplaced
        }
    }
}
