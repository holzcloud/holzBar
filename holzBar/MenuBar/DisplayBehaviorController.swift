//
//  DisplayBehaviorController.swift
//  holzBar
//

import AppKit

/// Follows which display the pointer is on and applies that display's behaviour for the hidden
/// items (`DisplayBehavior`): Default changes nothing, Always show everything keeps every
/// section shown there, Collapse keeps them hidden there.
///
/// A display the holzBar Shelf is not used on (`HolzBarShelfDisplays`) shows everything unless
/// the user chose another behaviour for it: the hidden items never hide there.
///
/// The display under the pointer wins. While no display has a choice, nothing runs: no monitor
/// exists and ``effective`` stays the default. With a choice, one mouse-moved monitor watches
/// the pointer; each event costs one rectangle test until the pointer leaves the display it was
/// on. Moving onto a display with another behaviour shows or hides the sections once
/// (`DisplayBehavior.action(from:to:)`); holzBar never does this on its own while Zen mode is on,
/// on a display the holzBar Shelf is used on (it holds the hidden items itself), while the Shelf
/// is open or while the lock for hidden items asks for authentication.
@MainActor
final class DisplayBehaviorController {
    /// The behaviour of the display the pointer is on now.
    private(set) var effective = DisplayBehavior.standard

    private weak var appState: AppState?

    /// Observers of the choices.
    private var observers = [ObservationLoop]()

    /// Receives the changes of the display configuration.
    private var screenTask: Task<Void, Never>?

    /// The monitor of the pointer; it exists only while a display has a choice.
    private var monitor: EventMonitor?

    /// The frame of the screen the pointer was on at the last check.
    private var pointerScreenFrame = CGRect.null

    /// Starts following the choices. With none, nothing else is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        let general = appState.settings.general
        observers = [
            ObservationLoop.observe { general.displayBehaviors } onChange: { [weak self] _ in
                self?.refresh(takingAction: true)
            },
            ObservationLoop.observe { general.useShelf } onChange: { [weak self] _ in
                // Switching the Shelf hides the sections once (`Concealer27`); this looks one
                // turn later, so a display that shows everything shows it again after that hide.
                Task { [weak self] in
                    self?.refresh(takingAction: true)
                }
            },
            ObservationLoop.observe { general.shelfDisplays } onChange: { [weak self] _ in
                self?.refresh(takingAction: true)
            },
        ]
        screenTask = Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.refresh(takingAction: true)
            }
        }
        // The first look only learns where the pointer is: nothing is shown or hidden at launch.
        refresh(takingAction: false)
    }

    /// Starts or stops the pointer monitor for the choices as they are, and looks where the
    /// pointer is.
    private func refresh(takingAction: Bool) {
        guard let appState else {
            return
        }
        let general = appState.settings.general
        // A Shelf limited to some displays leaves the others showing everything; while every
        // connected display uses the Shelf, there is no other display to watch for.
        let leavesDisplaysWithoutShelf = general.useShelf
            && !NSScreen.screens.allSatisfy { general.shelfDisplays.includes($0) }
        let isNeeded = !general.displayBehaviors.isEmpty || leavesDisplaysWithoutShelf
        if isNeeded, monitor == nil {
            let monitor = EventMonitor.universal(for: .mouseMoved) { [weak self] event in
                self?.pointerMoved()
                return event
            }
            monitor.start()
            self.monitor = monitor
        } else if !isNeeded, let monitor {
            monitor.stop()
            self.monitor = nil
        }
        evaluate(takingAction: takingAction)
    }

    /// Looks again only when the pointer left the screen it was on.
    private func pointerMoved() {
        if !pointerScreenFrame.isNull, NSMouseInRect(NSEvent.mouseLocation, pointerScreenFrame, false) {
            return
        }
        evaluate(takingAction: true)
    }

    /// Reads the display under the pointer, stores its behaviour and acts on a change.
    private func evaluate(takingAction: Bool) {
        guard let appState else {
            return
        }
        let screen = NSScreen.screenWithMouse
        pointerScreenFrame = screen?.frame ?? .null
        let uuid = screen.flatMap { Bridging.getDisplayUUIDString(for: $0.displayID) }
        let general = appState.settings.general
        var behavior = general.displayBehaviors.behavior(of: uuid)
        if behavior == .standard, let screen, general.useShelf, !general.shelfDisplays.includes(screen) {
            // The Shelf is on but not used here: the hidden items never hide on this display.
            behavior = .showEverything
        }
        let previous = effective
        effective = behavior
        guard takingAction else {
            return
        }
        perform(DisplayBehavior.action(from: previous, to: behavior), with: appState)
    }

    private func perform(_ action: DisplayBehavior.Action, with appState: AppState) {
        let manager = appState.menuBarManager
        switch action {
        case .none:
            return
        case .showAll:
            guard
                !appState.settings.general.usesShelf,
                manager.zenMode.allows(.revealRule),
                !appState.hiddenItemsLock.requiresAuthentication
            else {
                return
            }
            // Showing the deepest section that exists shows every section.
            let deepest = manager.section(withName: .alwaysHidden).flatMap { $0.isEnabled ? $0 : nil }
                ?? manager.section(withName: .hidden)
            deepest?.show(origin: .displayBehavior)
        case .hideAll:
            // The per-display behaviour never closes an open Shelf.
            guard !manager.shelfPanel.isVisible else {
                return
            }
            manager.section(withName: .hidden)?.hide()
        }
    }
}
