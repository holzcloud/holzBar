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
