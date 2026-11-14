//
//  LiveActivity.swift
//  holzBar
//

import Foundation

/// What a live activity is about. New cases go at the end.
nonisolated enum LiveActivityKind: String, CaseIterable, Sendable {
    /// A camera or the microphone in use by another app.
    case capture
    /// A download in progress.
    case download
    /// A timer or a countdown.
    case timer
    /// Anything else.
    case other
}

/// The colour of an activity's symbol in the widened notch, the open hub's right pill and the
/// Live activities list. The cases map to colours of the theme, so an activity cannot bring a
/// colour of its own.
nonisolated enum LiveActivityTint: String, CaseIterable, Sendable {
    case accent
    case amber
    case red
    case green
}

/// Something that is going on, as a plain value: a camera in use, a download, a timer.
///
/// A module of the Notch hub returns its activities through ``HubModuleRuntime/activities``;
/// while the hub is closed it shows the top one by widening the notch at menu bar height, and
/// the Live activities module lists them (concept section 10b). The widened notch and the open
/// hub's right pill show only the symbol and ``compactValue`` (or the countdown or the
/// percentage), never ``title`` or ``detail``. The value holds text that may be personal (a file
/// name), so it is capped, stays in memory and is never logged.
nonisolated struct LiveActivity: Equatable, Sendable, Identifiable {
    /// The most characters of a title.
    static let maximumTitleLength = 80
    /// The most characters of a detail.
    static let maximumDetailLength = 200
    /// The most characters of a short word.
    static let maximumCompactValueLength = 16
    /// The range a progress is clamped into.
    static let progressRange: ClosedRange<Double> = 0...1

    /// Identifies the activity within its module; the same id from the same module is the same
    /// activity.
    let id: String
    /// The identifier of the module that returned the activity.
    let moduleID: String
    let kind: LiveActivityKind
    /// The name of an SF Symbol.
    let symbol: String
    /// The short phrase VoiceOver hears once, and the list shows, at most
    /// ``maximumTitleLength`` characters. The widened notch never draws it.
    let title: String
    /// One quiet extra line for the tab, such as a file name, at most
    /// ``maximumDetailLength`` characters, or `nil`.
    let detail: String?
    /// How far along the activity is, from 0 to 1, or `nil` for one without a measure.
    let progress: Double?
    /// Which activity is the compact one when several are live: the higher goes first.
    let priority: Int
    let startedAt: Date
    /// When the activity ends by itself, such as a timer, or `nil`.
    let endsAt: Date?
    /// When the activity finished, or `nil` while it runs. A finished activity stays for
    /// ``HubActivityBoard/finishedHold`` seconds with its own done title and symbol.
    let finishedAt: Date?
    let tint: LiveActivityTint
    /// Whether the module that returned the activity speaks it to VoiceOver itself, so the hub
    /// does not announce its title a second time.
    let announcesItself: Bool
    /// The short word the widened notch and the open hub's right pill show, such as "Camera" or
    /// "Done", at most ``maximumCompactValueLength`` characters, never a name; `nil` where the
    /// countdown or the percentage says it.
    let compactValue: String?

    /// A key that is unique across modules: the module's identifier and the activity's id.
    var key: String {
        "\(moduleID)/\(id)"
    }

    /// Creates an activity. A title, detail or short word beyond its cap is cut, a progress outside
    /// ``progressRange`` is clamped into it and a progress that is not a number is dropped.
    init(
        id: String,
        moduleID: String,
        kind: LiveActivityKind,
        symbol: String,
        title: String,
        detail: String? = nil,
        progress: Double? = nil,
        priority: Int = 0,
        startedAt: Date,
        endsAt: Date? = nil,
        finishedAt: Date? = nil,
        tint: LiveActivityTint = .accent,
        announcesItself: Bool = false,
        compactValue: String? = nil
    ) {
        self.id = id
        self.moduleID = moduleID
        self.kind = kind
        self.symbol = symbol
        self.title = String(title.prefix(Self.maximumTitleLength))
        self.detail = detail.map { String($0.prefix(Self.maximumDetailLength)) }
        self.progress = progress.flatMap { value in
            value.isNaN ? nil : min(max(value, Self.progressRange.lowerBound), Self.progressRange.upperBound)
        }
        self.priority = priority
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.finishedAt = finishedAt
        self.tint = tint
        self.announcesItself = announcesItself
        self.compactValue = compactValue.map { String($0.prefix(Self.maximumCompactValueLength)) }
    }
}
