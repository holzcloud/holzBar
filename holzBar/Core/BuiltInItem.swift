//
//  BuiltInItem.swift
//  holzBar
//

import Foundation

/// The built-in items of the Widgets module: icons of holzBar's own that do one small job.
///
/// A built-in item is a widget of the kind ``WidgetKind/builtIn``, so it sits in the menu bar
/// like any item: in a section, hidden with it, moved in the layout, shown in the Shelf and found
/// by the search. macOS takes its own extras away while it hides items; these keep working
/// because holzBar draws them itself. The raw values are stored and never change.
nonisolated enum BuiltInItem: String, Codable, CaseIterable, Sendable {
    /// Opens the Focus menu of Apple's item, or the Focus settings.
    case focus
    /// Opens AirDrop, and sends the files dropped on it.
    case airDrop
    /// Plays, pauses and skips what is playing, through the media keys.
    case media
    /// Opens Apple's fast user switching menu, or the Users & Groups settings.
    case userSwitching
    /// A countdown that sounds when it ends.
    case timer
    /// Opens one application of the user's choice.
    case launcher

    /// The SF Symbol of the item. A launcher shows its application's icon and uses this symbol
    /// only while it has none.
    var symbolName: String {
        switch self {
        case .focus: "moon"
        case .airDrop: "antenna.radiowaves.left.and.right"
        case .media: "playpause"
        case .userSwitching: "person.crop.circle"
        case .timer: "timer"
        case .launcher: "square.grid.2x2"
        }
    }

    /// Whether there can be more than one item of this kind: two timers or many launchers. The
    /// others open one thing, so a second would do the same.
    var allowsSeveral: Bool {
        switch self {
        case .timer, .launcher: true
        case .focus, .airDrop, .media, .userSwitching: false
        }
    }

    /// The words, in lowercase, that tell Apple's item that this one stands for. An item key
    /// (`namespace:title`) that holds one of them, in an Apple namespace, is Apple's item.
    var appleItemWords: [String] {
        switch self {
        case .focus: ["focus"]
        case .airDrop: ["airdrop"]
        case .userSwitching: ["userswitcher", "fastuserswitch", "menuextra.user"]
        case .media, .timer, .launcher: []
        }
    }

    /// The System Settings pane that stands in when Apple's item is not in the menu bar, or
    /// `nil` when the item has none.
    var settingsPaneURL: URL? {
        switch self {
        case .focus: URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")
        case .userSwitching: URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")
        case .airDrop, .media, .timer, .launcher: nil
        }
    }

    /// Whether the item key belongs to the Apple item that this built-in item stands for. The
    /// numbered system items (the clock, the battery, Wi-Fi) are never matched.
    func matchesAppleItem(key: String) -> Bool {
        guard !appleItemWords.isEmpty, AppleItemCatalog.isReplaceable(itemKey: key) else {
            return false
        }
        let lowered = key.lowercased()
        return appleItemWords.contains { lowered.contains($0) }
    }

    /// The key of the first item that belongs to Apple's item, in the order given.
    func appleItemKey(in keys: [String]) -> String? {
        keys.first { matchesAppleItem(key: $0) }
    }
}

/// A media key, as a system-defined event posts it. These are the same events the keys on a
/// keyboard post, so whatever app owns the media keys at that moment answers (Music, Spotify, a
/// browser tab). No private framework is involved.
nonisolated enum MediaKey: Int, CaseIterable, Sendable {
    // The values of NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT and NX_KEYTYPE_PREVIOUS.
    case playPause = 16
    case next = 17
    case previous = 18

    /// The subtype of a system-defined event that carries a media key (NX_SUBTYPE_AUX_CONTROL_BUTTONS).
    static let systemDefinedSubtype = 8

    /// The `data1` of the event that presses or releases the key: the key code, then the state
    /// (0xA for down, 0xB for up).
    func eventData(isDown: Bool) -> Int {
        (rawValue << 16) | ((isDown ? 0xA : 0xB) << 8)
    }

    /// The modifier flags that go with the event, as raw bits: the state again.
    static func modifierBits(isDown: Bool) -> UInt {
        isDown ? 0xA00 : 0xB00
    }
}

/// When the media item is in the menu bar.
///
/// "Active" is told by Core Audio: the default output device runs for some process. That is the
/// one public, event-based sign that something plays. A pause stops it a moment later, so the
/// item stays for a while after the sound stops; otherwise it would be gone just when the user
/// wants to resume.
nonisolated enum MediaVisibility {
    /// The seconds the item stays after the sound stopped.
    static let gracePeriod: TimeInterval = 120

    /// Whether the item is shown.
    ///
    /// - Parameters:
    ///   - onlyWhenActive: The setting: show the item only while sound plays.
    ///   - isActive: Whether the output device runs for some process now.
    ///   - lastActive: When it last ran, if it ever did while the item was watching.
    ///   - now: The moment asked about.
    static func isShown(onlyWhenActive: Bool, isActive: Bool, lastActive: Date?, now: Date) -> Bool {
        guard onlyWhenActive, !isActive else {
            return true
        }
        guard let lastActive else {
            return false
        }
        return now.timeIntervalSince(lastActive) < gracePeriod
    }

    /// The moment the answer of ``isShown(onlyWhenActive:isActive:lastActive:now:)`` changes
    /// by itself, or `nil` when only an event can change it.
    static func nextChange(onlyWhenActive: Bool, isActive: Bool, lastActive: Date?, now: Date) -> Date? {
        guard
            onlyWhenActive, !isActive,
            let lastActive,
            isShown(onlyWhenActive: true, isActive: false, lastActive: lastActive, now: now)
        else {
            return nil
        }
        return lastActive.addingTimeInterval(gracePeriod)
    }
}
