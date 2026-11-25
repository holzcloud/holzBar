//
//  WhatsNewHistory.swift
//  holzBar
//

import Foundation

// The release script reads this file line by line, so each release starts with its version on
// the first line of the call; that layout is not what these two rules want.
// swiftlint:disable multiline_arguments_brackets vertical_parameter_alignment_on_call

/// The release history the What's New window shows.
///
/// This file is the single source of the What's New texts. It is written by hand from
/// `docs/release-notes/vX.md`, newest first, with one entry per stable-numbered version (a
/// beta shares the entry of its stable version). Adding a release means adding its entry here
/// and its texts to the String Catalog through `python3 .github/scripts/translations.py
/// add-strings`; every title, sentence and fix is an English catalog key.
///
/// Keep the format a script can read: one `WhatsNewRelease` call per release, written with
/// `version:` and the version string on its first line, items as `WhatsNewItem` calls with
/// `symbol:`, `title:` and `detail:`, fixes as `WhatsNewFix` calls with `text:`, plain
/// one-line string literals, no interpolation and no escaped quotes.
nonisolated enum WhatsNewHistory {
    /// The releases, newest first.
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "1.2.0",
            new: [
                WhatsNewItem(
                    symbol: "gauge.with.dots.needle.67percent",
                    title: "System readouts",
                    detail: "Tiles for the CPU, memory, network, disk and battery, and for the GPU behind its own switch, with two-minute curves in the Notch hub."
                ),
                WhatsNewItem(
                    symbol: "network",
                    title: "Readout widgets",
                    detail: "Network Speed, Disk Activity, GPU Load and Thermal State widgets, and new formats for the CPU, memory and battery widgets."
                ),
                WhatsNewItem(
                    symbol: "exclamationmark.triangle",
                    title: "System alerts",
                    detail: "The notch warns when the CPU, memory pressure, thermal state, free disk space or the Mac's battery crosses a limit you set, with optional system notifications."
                ),
                WhatsNewItem(
                    symbol: "airpods",
                    title: "Devices",
                    detail: "Accessory alerts lists your devices with their battery levels, and the Lowest Device Battery widget shows the lowest one."
                ),
                WhatsNewItem(
                    symbol: "dial.medium",
                    title: "Indicators",
                    detail: "The closed notch flashes the input source and the volume or brightness, and can replace macOS's own display."
                ),
                WhatsNewItem(
                    symbol: "app.badge",
                    title: "Dock badges",
                    detail: "The unread counts of apps in your Dock as menu bar items, with groups."
                ),
                WhatsNewItem(
                    symbol: "arrow.down.circle",
                    title: "Import from Thaw and Hidden Bar",
                    detail: "Bring over their settings with a preview, a backup and Undo."
                ),
                WhatsNewItem(
                    symbol: "menubar.rectangle",
                    title: "Making room on macOS 27",
                    detail: "A notice when macOS folds menu bar icons away or they do not fit beside the notch, with Move to Hidden as one Undo step, or Automatic."
                ),
                WhatsNewItem(
                    symbol: "app.dashed",
                    title: "Ask where a new app goes",
                    detail: "An optional question for each new menu bar app."
                ),
                WhatsNewItem(
                    symbol: "eye.slash",
                    title: "Not shown by macOS",
                    detail: "On macOS 27, Layout lists the apps macOS does not show, each with a link to the fix."
                ),
                WhatsNewItem(
                    symbol: "circle.lefthalf.filled",
                    title: "Readable menu bar",
                    detail: "A built-in mood that gives the menu bar an opaque background."
                ),
                WhatsNewItem(
                    symbol: "magnifyingglass",
                    title: "Spotlight button",
                    detail: "A widget that opens Spotlight."
                ),
                WhatsNewItem(
                    symbol: "battery.75percent",
                    title: "Large Percent",
                    detail: "A Battery widget format with a larger percentage."
                ),
                WhatsNewItem(
                    symbol: "arrow.clockwise",
                    title: "Restart Menu Bar and Pause holzBar",
                    detail: "On macOS 27, in holzBar's menu and the command palette."
                ),
            ],
            improved: [
                WhatsNewItem(
                    symbol: "capsule.tophalf.filled",
                    title: "Notch hub",
                    detail: "Gestures, a pin, opening on the display with the pointer, a switch for the bounce, and the hotkey closes the hub too."
                ),
                WhatsNewItem(
                    symbol: "slider.horizontal.3",
                    title: "Display tab",
                    detail: "Choose the sound output, dim a monitor without brightness control, and no DDC request for three seconds after a wake."
                ),
                WhatsNewItem(
                    symbol: "bell.badge",
                    title: "Notifications and calendar in the notch",
                    detail: "A count and a card with a +N queue, and meeting details with a countdown to the next meeting."
                ),
                WhatsNewItem(
                    symbol: "rectangle.topthird.inset.filled",
                    title: "Dynamic Island",
                    detail: "The hub opens below Apple's island, and a setting overrides the detection."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "holzBar opens Settings only when you open it from the Dock, the Finder, Spotlight or Launchpad, not for Siri on macOS 27."),
                WhatsNewFix(text: "On macOS 27.3, holzBar leaves the system's Live Activities on the bar and neither counts, moves nor lists them."),
                WhatsNewFix(text: "On macOS 27, a click on a system item through holzBar never leaves the mouse button down, and the click handling no longer waits on a busy holzBar."),
                WhatsNewFix(text: "On macOS 27, an app that launches into a hidden section keeps its full item until holzBar has read it, up to 45 seconds."),
                WhatsNewFix(text: "On macOS 27, after more than three MenuBarAgent restarts in ten minutes holzBar shows every item for 30 minutes instead of retrying in a loop."),
                WhatsNewFix(text: "Before macOS 27, the holzBar Shelf on a second display takes the colours of the display it is on."),
                WhatsNewFix(text: "On macOS 27, an item never shows another item's picture when two items claim the same place."),
                WhatsNewFix(text: "holzBar takes its hiding anew after a wake, an unlock or a display change, and saves your sections only from a settled bar."),
                WhatsNewFix(text: "Automatic rehide is no longer held back by thin windows at the screen edge, and a click inside an open menu or popup no longer starts it."),
                WhatsNewFix(text: "Where the menu bar is a little taller than the notch, the closed notch is as tall as the menu bar and meets the hardware notch."),
            ]
        ),
        WhatsNewRelease(version: "1.1.1",
            new: [
                WhatsNewItem(
                    symbol: "display",
                    title: "External monitors",
                    detail: "Display controls sets the brightness, contrast, volume and mute of external monitors that support DDC, with its own switch in the module's settings."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "The Notch hub's content no longer shows outside its black shape while it opens or closes."),
                WhatsNewFix(text: "With the holzBar Shelf limited to some displays, the other displays always show every menu bar item, unless they are set to Collapse."),
            ]
        ),
        WhatsNewRelease(version: "1.1.0",
            new: [
                WhatsNewItem(
                    symbol: "gearshape",
                    title: "Settings, redesigned",
                    detail: "Eleven panes sorted by task, compact rows with their explanation one click away, and a search over every setting with ⌘F."
                ),
                WhatsNewItem(
                    symbol: "list.bullet",
                    title: "Layout as a list",
                    detail: "Layout shows your items as bars or as a list, with a filter and a section menu for each item."
                ),
                WhatsNewItem(
                    symbol: "arrow.uturn.backward",
                    title: "Undo after every change",
                    detail: "After a change of the layout, in Settings or in the menu bar, a notice offers Undo, and ⌘Z works too."
                ),
                WhatsNewItem(
                    symbol: "hand.wave",
                    title: "A short introduction",
                    detail: "The first launch needs only Accessibility and then shows three short steps, which About shows again."
                ),
                WhatsNewItem(
                    symbol: "capsule.tophalf.filled",
                    title: "Notch hub, redesigned",
                    detail: "The hub grows out of the notch in black, opens on what is active with a line that says why, and shows every module as a round button."
                ),
                WhatsNewItem(
                    symbol: "arrow.left.and.right",
                    title: "Live activities in the notch",
                    detail: "A running timer, the camera, the microphone, a download or an accessory widens the notch at menu bar height instead of a capsule below it."
                ),
            ],
            improved: [
                WhatsNewItem(
                    symbol: "contextualmenu.and.cursorarrow",
                    title: "Move to",
                    detail: "The menu of an item in Layout starts with Move to Visible, Hidden or Always Hidden."
                ),
                WhatsNewItem(
                    symbol: "menubar.rectangle",
                    title: "More in holzBar's menu",
                    detail: "holzBar's menu has Arrange Menu Bar… and Profiles, which applies a profile in one click."
                ),
                WhatsNewItem(
                    symbol: "rectangle.3.group",
                    title: "Whole apps on macOS 27",
                    detail: "On macOS 27, Layout highlights the items of one app together and says that macOS hides whole apps."
                ),
                WhatsNewItem(
                    symbol: "square.on.square.dashed",
                    title: "Stand-in icons",
                    detail: "On macOS 27, an app outside the Applications folder whose menu bar icon macOS hides while holzBar hides items gets a stand-in that opens its menu."
                ),
                WhatsNewItem(
                    symbol: "trash.slash",
                    title: "Deleting can be undone",
                    detail: "A deleted condition, group, snapshot, mood or profile hook comes back with Undo."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "The question to tidy up the menu bar no longer interrupts after the first launch; the suggestion waits in Layout."),
                WhatsNewFix(text: "Loading the menu bar items no longer spins without end, and empty lists say what to do."),
                WhatsNewFix(text: "The first launch no longer lists Calendar and Bluetooth; their modules ask when you switch them on."),
                WhatsNewFix(text: "Turning off usage suggestions asks before it deletes the stored usage."),
                WhatsNewFix(text: "The offer to use Screen Recording appears in holzBar's own look."),
                WhatsNewFix(text: "On macOS 27, an app whose picture matched another app's tile gets its own picture again, and items without a picture show their app's icon."),
                WhatsNewFix(text: "holzBar uses one word for each thing: Always Hidden, apps, and Delete for what you made."),
                WhatsNewFix(text: "On macOS 27.2, a right-click on an empty area of the menu bar opens Apple's menu again; hold ⌥ Option for holzBar's menu."),
                WhatsNewFix(text: "On macOS 27, the items of an app outside the Applications folder open from the holzBar Shelf, search and hotkeys."),
                WhatsNewFix(text: "QQ and WeChat no longer get a new item in Layout for each unread count."),
                WhatsNewFix(text: "On macOS 27.2, holzBar's own items no longer drop out of Layout for a moment."),
            ]
        ),
        WhatsNewRelease(version: "1.0.5",
            improved: [
                WhatsNewItem(
                    symbol: "hand.draw",
                    title: "Command-drag sets the section",
                    detail: "On macOS 27, a ⌘ Command-drag across the holzBar icon hides an app (to the left) or shows it (to the right), with Undo in Menu Bar Layout."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "On macOS 27, an automation rule changes only its own apps, and a profile keeps the apps a rule hides hidden."),
                WhatsNewFix(text: "On macOS 27, an app you made visible is no longer hidden again as a new item."),
                WhatsNewFix(text: "On macOS 27, turning off the always-hidden section moves its apps to Hidden."),
                WhatsNewFix(text: "Show on hover hides only what hover showed, and never while an item's menu is open."),
                WhatsNewFix(text: "Automatic rehide waits while a menu is open or the pointer is on the Shelf, and hides everything its show opened."),
                WhatsNewFix(text: "A ⌘ Command-drag respects the Touch ID lock, Zen mode and Collapse, and hides what it showed after the drop."),
                WhatsNewFix(text: "The peek and changed items hide again after Touch ID, but not while their menu is open or after you showed the section."),
                WhatsNewFix(text: "A holzBar icon dragged into the hidden section moves back out of it on its own."),
                WhatsNewFix(text: "On macOS 27, hiding comes back after MenuBarAgent restarts, and helper apps and slow apps appear sooner."),
                WhatsNewFix(text: "On macOS 27, busy apps such as Slack cost less energy."),
                WhatsNewFix(text: "On macOS 27, items folded beside the notch come back at once on a wider display."),
                WhatsNewFix(text: "After you unlock the hidden items with Touch ID, the app you were using keeps the keyboard focus."),
            ]
        ),
        WhatsNewRelease(version: "1.0.4",
            improved: [
                WhatsNewItem(
                    symbol: "arrow.left.arrow.right",
                    title: "Order inside sections",
                    detail: "On macOS 26 and earlier, items keep their order inside each section and go back to their place when they reappear."
                ),
                WhatsNewItem(
                    symbol: "link",
                    title: "Safer URL commands",
                    detail: "While Zen mode is on, the command that toggles application menus is ignored, and a burst of commands from another app is limited."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "holzBar no longer moves items or records your layout while the menu bar is still settling after a display change."),
                WhatsNewFix(text: "Apps that start slowly, such as OneDrive, are placed once they have started."),
                WhatsNewFix(text: "Items with a second line or a live value in their title keep their place."),
                WhatsNewFix(text: "If one of holzBar's own moves pushes the items next to it out of place, holzBar puts them back."),
                WhatsNewFix(text: "Control Center controls pinned to the menu bar show as fixed in Menu Bar Layout on macOS 27."),
                WhatsNewFix(text: "Tray icons of Windows apps run with Wine or CrossOver are no longer moved by holzBar on its own."),
                WhatsNewFix(text: "An imported settings file can no longer bring an unlimited number of layout profiles."),
            ]
        ),
        WhatsNewRelease(version: "1.0.3",
            fixed: [
                WhatsNewFix(text: "Hidden apps that were already running when holzBar started now appear in the Shelf."),
                WhatsNewFix(text: "The Shelf no longer shows an error while the item pictures are still being taken."),
                WhatsNewFix(text: "A tile no longer shows another app's icon."),
            ]
        ),
        WhatsNewRelease(version: "1.0.2",
            improved: [
                WhatsNewItem(
                    symbol: "square.stack",
                    title: "What's New by version",
                    detail: "A tab for every major version, a sub tab for every minor version and the fixes below as sections."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "The Permissions window is smaller, so Quit and Continue stay on screen."),
                WhatsNewFix(text: "Clicking a tab of the Notch hub no longer opens the Shelf."),
                WhatsNewFix(text: "Clicking the holzBar icon no longer opens another item's menu, such as Wi-Fi, instead of the Shelf."),
            ]
        ),
        WhatsNewRelease(version: "1.0.1",
            new: [
                WhatsNewItem(
                    symbol: "sparkles",
                    title: "What's New window",
                    detail: "Opens after an update and from About in Settings, with a tab for every version."
                ),
                WhatsNewItem(
                    symbol: "switch.2",
                    title: "Show after an update",
                    detail: "Turn the window off here or under General in Settings."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "holzBar no longer quits when a Bluetooth device such as AirPods connects."),
            ]
        ),
        WhatsNewRelease(version: "1.0.0",
            new: [
                WhatsNewItem(
                    symbol: "music.note",
                    title: "Now Playing",
                    detail: "See what Music and Spotify play and control it at the notch."
                ),
                WhatsNewItem(
                    symbol: "calendar",
                    title: "Calendar",
                    detail: "Your next events, with a Join button for meeting links."
                ),
                WhatsNewItem(
                    symbol: "waveform",
                    title: "Live activities",
                    detail: "A capsule while the camera or microphone is in use or a download runs."
                ),
                WhatsNewItem(
                    symbol: "timer",
                    title: "Timers",
                    detail: "Timers, countdowns and a stopwatch, with a sound at the end."
                ),
                WhatsNewItem(
                    symbol: "tray.and.arrow.down",
                    title: "File drop",
                    detail: "Stash files at the notch and drag them out later as copies."
                ),
                WhatsNewItem(
                    symbol: "speaker.wave.2",
                    title: "Display controls",
                    detail: "Volume, mute and brightness sliders in the hub."
                ),
                WhatsNewItem(
                    symbol: "bell",
                    title: "Notifications",
                    detail: "The banners macOS shows, newest first."
                ),
                WhatsNewItem(
                    symbol: "airpods",
                    title: "Accessory alerts",
                    detail: "A capsule when AirPods or headphones connect or run low."
                ),
                WhatsNewItem(
                    symbol: "arrow.up.arrow.down",
                    title: "Sort the menu bar",
                    detail: "Put the items of a section in order in Menu Bar Layout on macOS 27."
                ),
                WhatsNewItem(
                    symbol: "number.circle",
                    title: "Count badge",
                    detail: "A small number on the holzBar icon says how many items are hidden."
                ),
                WhatsNewItem(
                    symbol: "square.and.arrow.down",
                    title: "Drop to hide",
                    detail: "Drag a bar item onto the open Shelf to hide its app on macOS 27."
                ),
                WhatsNewItem(
                    symbol: "applelogo",
                    title: "Apple Items in the Shelf",
                    detail: "The clock, Control Center, Wi-Fi and battery stay hidden and open from a tile."
                ),
                WhatsNewItem(
                    symbol: "globe",
                    title: "20 languages",
                    detail: "Nine more languages, all machine-made."
                ),
            ],
            improved: [
                WhatsNewItem(
                    symbol: "rectangle.split.3x1",
                    title: "Hub tabs in one row",
                    detail: "The tabs stand in one row across both sides of the notch."
                ),
            ],
            fixed: [
                WhatsNewFix(text: "Updating from macOS 26 to 27 keeps your hidden items hidden."),
                WhatsNewFix(text: "A Shelf click that does not reach its item beeps and is announced to VoiceOver."),
                WhatsNewFix(text: "Hidden items such as Time Machine and Docker no longer drop out of the Shelf."),
                WhatsNewFix(text: "On macOS 27.2 the items macOS folds behind its overflow button stay listed."),
                WhatsNewFix(text: "The layout bars in Menu Bar Layout use a thin overlay scroller."),
            ]
        ),
    ]
}

// swiftlint:enable multiline_arguments_brackets vertical_parameter_alignment_on_call
