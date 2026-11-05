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
        WhatsNewRelease(version: "1.0.2",
            fixed: [
                WhatsNewFix(text: "Clicking a tab of the Notch hub no longer opens the Shelf."),
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
