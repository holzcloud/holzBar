//
//  ItemClick27.swift
//  holzBar
//

import CoreGraphics

/// Pure rules for clicking an item from the holzBar Shelf on macOS 27.
nonisolated enum ItemClick27 {
    /// Whether the menu bar of the holzBar Shelf's display must be made active first: an
    /// item's menu opens on the display with the active menu bar (measured on macOS 27.0).
    static func needsMenuBarActivation(activeDisplayID: CGDirectDisplayID?, shelfDisplayID: CGDirectDisplayID?) -> Bool {
        guard let shelfDisplayID else {
            return false
        }
        return activeDisplayID != shelfDisplayID
    }

    /// A window on screen that may be a system item's panel, with the process that draws it.
    typealias PanelWindow = (number: Int, layer: Int, height: CGFloat, ownerPID: Int32)

    /// The window a system item's panel opened in, if one appeared.
    ///
    /// Both panels stand at or above the menu bar's level and are tall, which the ordinary
    /// windows that may open at the same moment are not (measured on macOS 27.0: Control
    /// Centre opens "Control Center", layer 101, 656×964, about 177 ms after the press, and
    /// the clock opens "Notification Center", layer 21, the size of the display, about 166 ms
    /// after the click — a level an earlier version of this rule was too high to notice, so
    /// Notification Center counted as never opening).
    static func panelWindow(before: Set<Int>, windows: [PanelWindow]) -> Int? {
        windows.first { !before.contains($0.number) && isPanel($0) }?.number
    }

    /// Whether a system item's panel opened, judged by the windows on screen.
    static func panelOpened(before: Set<Int>, windows: [PanelWindow]) -> Bool {
        panelWindow(before: before, windows: windows) != nil
    }

    /// The window of a system item's panel that is already on screen, if one is.
    ///
    /// The caller must pass only the windows of the processes that draw those panels. Every
    /// window at this level and size is not a panel: the Dock's window stands at layer 20 and
    /// the size of the display and never goes away, so with it in the list every click looked
    /// like a click that closes a panel (measured on macOS 27.0).
    ///
    /// A click that lands while a panel is up is the click that closes it. Putting concealment
    /// back stalls MenuBarAgent for 100 to 150 ms (measured on macOS 27.0, against the moment
    /// each assertion was applied), and in the middle of a closing animation that shows as a
    /// lag — so a click that closes a panel waits for the panel to be gone first.
    static func openPanelWindow(windows: [PanelWindow]) -> Int? {
        panelWindow(before: [], windows: windows)
    }

    /// Whether the panel that opened in the given window is still on screen.
    static func panelIsOnScreen(window: Int, windows: [PanelWindow]) -> Bool {
        windows.contains { $0.number == window }
    }

    /// A system item's panel that holzBar saw open after a click it bridged.
    nonisolated struct OpenPanel: Equatable, Sendable {
        /// The identifier of the system item that opened it.
        let item: String
        /// The number of the window the panel opened in.
        let window: Int
        /// The process that draws the panel, the only one Escape is sent to.
        let ownerPID: Int32
    }

    /// The panel holzBar saw open after a bridged click, and which click that was.
    ///
    /// A click the bridge lets through can close the panel unseen (a click on the desktop
    /// closes Notification Center), and a banner shows in the same window as the panel
    /// afterwards (measured on macOS 27.0), so the panel is forgotten at every such click.
    /// Every click counts, so a panel found for a click that a later one overtook is dropped.
    nonisolated struct PanelMemory {
        /// The panel holzBar saw open, while no click may have closed it since.
        private(set) var panel: OpenPanel?

        /// The number of the latest click the bridge saw.
        private(set) var click = 0

        /// Forgets the panel, for a click that may have closed it unseen.
        mutating func forget() {
            click += 1
            panel = nil
        }

        /// Hands the panel to a bridged click, which either closes it or proves it gone.
        ///
        /// - Returns: The panel remembered before the click, and the click's number.
        mutating func takeForBridgedClick() -> (remembered: OpenPanel?, click: Int) {
            click += 1
            defer {
                panel = nil
            }
            return (panel, click)
        }

        /// Remembers the panel a bridged click opened, or that it opened none, unless a
        /// later click arrived meanwhile.
        mutating func remember(_ opened: OpenPanel?, openedBy click: Int) {
            guard click == self.click else {
                return
            }
            panel = opened
        }
    }

    /// What the bridge does with a click it held back.
    nonisolated enum BridgeStep: Equatable {
        /// Sends Escape to the panel's own process, which closes it with no lift of concealment.
        case dismiss(OpenPanel)
        /// Presses the item through Accessibility, which opens its panel while concealed.
        case press
        /// Lifts concealment for a moment and replays the click.
        case liftAndReplay
    }

    /// The first step for a click the bridge held back.
    ///
    /// Only a panel holzBar saw open, whose window is still up, is dismissed with Escape. A
    /// panel already up that holzBar did not see open is closed by the replayed click, as it
    /// would be without holzBar: a press would close it as well, look like a press the item
    /// ignores, and the replay would open it again.
    static func firstStep(remembered: OpenPanel?, windows: [PanelWindow], mayOpenFromPress: Bool) -> BridgeStep {
        if let remembered, panelIsOnScreen(window: remembered.window, windows: windows) {
            return .dismiss(remembered)
        }
        if mayOpenFromPress, openPanelWindow(windows: windows) == nil {
            return .press
        }
        return .liftAndReplay
    }

    /// The step after Escape was sent to a panel, or `nil` when the click is done.
    ///
    /// A panel whose window stayed has the click replayed, which closes it as well, so the
    /// click is never dropped; the press would leave that panel up.
    static func stepAfterDismissal(
        of panel: OpenPanel,
        clickedItem: String?,
        windowWent: Bool,
        windows: [PanelWindow],
        mayOpenFromPress: Bool
    ) -> BridgeStep? {
        guard windowWent else {
            return .liftAndReplay
        }
        guard clickedItem != panel.item else {
            return nil
        }
        return firstStep(remembered: nil, windows: windows, mayOpenFromPress: mayOpenFromPress)
    }

    /// The panel the click on the given item opened, if a new panel window appeared.
    ///
    /// A window that was already there is no panel that opened: a banner can stand in it.
    static func openedPanel(item: String?, before: Set<Int>, windows: [PanelWindow]) -> OpenPanel? {
        guard let item, let window = windows.first(where: { !before.contains($0.number) && isPanel($0) }) else {
            return nil
        }
        return OpenPanel(item: item, window: window.number, ownerPID: window.ownerPID)
    }

    /// Whether a window stands at the panels' level and is tall enough to be one.
    private static func isPanel(_ window: PanelWindow) -> Bool {
        window.layer >= panelLayer && window.height > panelHeight
    }

    /// The level the panels stand at: the menu bar's own level and above.
    private static let panelLayer = 20

    /// Taller than the menu bar's own windows, so the bar never passes for a panel.
    private static let panelHeight: CGFloat = 150

    static func interfaceIsOpen(windowOwners: [(number: Int, ownerPID: Int32)], ownerPID: Int32, baseline: Set<Int>) -> Bool {
        windowOwners.contains { $0.ownerPID == ownerPID && !baseline.contains($0.number) }
    }
}
