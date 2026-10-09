//
//  CaptureIndicatorItems.swift
//  holzBar
//

import Foundation

/// The system items that show that the camera, the microphone or the screen is in use
/// (AudioVideoModule), or that a FaceTime call is running.
///
/// They can never be hidden, whichever app holzBar attributes them to. On macOS 26 an
/// item's app is found from the Accessibility frames that apps report about themselves,
/// so another app could claim one of these windows and make it hideable under its own
/// name. `Item-0` is not among the titles: it is the default title of every app's first
/// status item. The screen recording item of screencaptureui, which has that title, is
/// protected by its namespace instead (`MenuBarItemTag.screenCaptureUI`).
nonisolated enum CaptureIndicatorItems {
    /// The titles of the items, compared exactly.
    static let titles: Set<String> = ["AudioVideoModule", "FaceTime"]

    /// Whether an item with the given title is one of the indicators.
    static func isIndicator(title: String) -> Bool {
        titles.contains(title)
    }
}
