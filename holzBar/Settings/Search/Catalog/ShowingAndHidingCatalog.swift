//
//  ShowingAndHidingCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Showing & Hiding pane, in the order the pane shows them.
    enum ShowingAndHidingPane {
        static let showHiddenItems = String(localized: "Show hidden items")
        static let hideAgain = String(localized: "Hide again")
        static let displays = String(localized: "Displays")
        static let zenModeAndLock = String(localized: "Zen mode and lock")
        static let animation = String(localized: "Animation")

        static let entries: [SettingsEntry] = [
            .hidingShowOnClick,
            .hidingShowOnHover,
            .hidingHoverDelay,
            .hidingShowOnScroll,
            .hidingOpenInMenuBar,
            .hidingAutoRehide,
            .hidingRehideStrategy,
            .hidingRehideInterval,
            .hidingTempShowInterval,
            .hidingDisplays,
            .hidingZenMode,
            .hidingAutoZen,
            .hidingLock,
            .hidingAnimationStyle,
        ]
    }
}

extension SettingsEntry {
    static let hidingShowOnClick = SettingsEntry(
        id: "hidingShowOnClick",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on click"),
        info: String(localized: "Click inside an empty area of the menu bar to show hidden menu bar items.")
    )

    static let hidingShowOnHover = SettingsEntry(
        id: "hidingShowOnHover",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on hover"),
        info: String(localized: "Hover over an empty area of the menu bar to show hidden menu bar items.")
    )

    static let hidingHoverDelay = SettingsEntry(
        id: "hidingHoverDelay",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Hover delay"),
        info: String(localized: "How long holzBar waits before hovering shows the hidden items, from 0 to 1 second.")
    )

    static let hidingShowOnScroll = SettingsEntry(
        id: "hidingShowOnScroll",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Show on scroll"),
        info: String(localized: "Scroll or swipe in the menu bar to show hidden menu bar items.")
    )

    static let hidingOpenInMenuBar = SettingsEntry(
        id: "hidingOpenInMenuBar",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.showHiddenItems,
        label: String(localized: "Open hidden items in the menu bar"),
        info: String(localized: "Shows a hidden item in the menu bar and opens its menu under it. Off, the menu opens without showing the item.")
    )

    static let hidingAutoRehide = SettingsEntry(
        id: "hidingAutoRehide",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.hideAgain,
        label: String(localized: "Automatically rehide")
    )

    static let hidingRehideStrategy = SettingsEntry(
        id: "hidingRehideStrategy",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.hideAgain,
        label: String(localized: "When to hide again"),
        info: String(localized: "Smart hides items again when you click outside the menu bar, After a fixed time waits for the time you set, and When the app changes hides them when another app comes to the front.")
    )

    static let hidingRehideInterval = SettingsEntry(
        id: "hidingRehideInterval",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.hideAgain,
        label: String(localized: "Time until hiding"),
        info: String(localized: "How long hidden items stay shown after the pointer leaves the menu bar, from 1 to 30 seconds.")
    )

    static let hidingTempShowInterval = SettingsEntry(
        id: "hidingTempShowInterval",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.hideAgain,
        label: String(localized: "Hide opened items again after"),
        info: String(localized: "Counted from when the item's menu closes; 0 hides it at once. The hotkey that shows hidden items for a moment and items shown by a rule use the same time.")
    )

    static let hidingDisplays = SettingsEntry(
        id: "hidingDisplays",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.displays,
        label: String(localized: "Hidden items per display"),
        info: String(localized: "Always show everything keeps every section shown on that display. Collapse keeps hidden items hidden there; only the holzBar icon and the hotkeys show them. Neither applies with the holzBar Shelf.")
    )

    static let hidingZenMode = SettingsEntry(
        id: "hidingZenMode",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.zenModeAndLock,
        label: String(localized: "Zen mode"),
        info: String(localized: "Keeps hidden items hidden: hover, clicks, scrolling and rules don't show them until you turn it off.")
    )

    static let hidingAutoZen = SettingsEntry(
        id: "hidingAutoZen",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.zenModeAndLock,
        label: String(localized: "Zen mode while sharing the screen"),
        info: String(localized: "Turns Zen mode on while the screen is mirrored or shared. Uses no permission: holzBar notices a mirrored display and macOS's screen sharing agent.")
    )

    static let hidingLock = SettingsEntry(
        id: "hidingLock",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.zenModeAndLock,
        label: String(localized: "Require Touch ID before showing"),
        info: String(localized: "This keeps someone at your unlocked Mac from seeing your hidden items. Turning it off asks too. It is not protection against someone who knows your password.")
    )

    static let hidingAnimationStyle = SettingsEntry(
        id: "hidingAnimationStyle",
        pane: .showingAndHiding,
        group: SettingsCatalog.ShowingAndHidingPane.animation,
        label: String(localized: "Style"),
        info: String(localized: "Instant, Smooth or Fade: how hidden items and the holzBar Shelf appear. What moves depends on the macOS version; nothing moves while Reduce Motion is on.")
    )
}
