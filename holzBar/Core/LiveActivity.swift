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

/// The colour of an activity's symbol in the capsule and the tab. The cases map to colours of
/// the theme, so an activity cannot bring a colour of its own.
nonisolated enum LiveActivityTint: String, CaseIterable, Sendable {
    case accent
    case amber
    case red
    case green
}

/// Something that is going on, as a plain value: a camera in use, a download, a timer.
///
/// A module of the Notch hub returns its activities through ``HubModuleRuntime/activities``;
/// the hub shows the top one as a small capsule below the notch while it is closed, and the
/// list in the Live activities tab. The value holds text that may be personal (a file name),
/// so it is capped, stays in memory and is never logged. The capsule shows only the title.
nonisolated struct LiveActivity: Equatable, Sendable, Identifiable {
    /// The most characters of a title.
    static let maximumTitleLength = 80
    /// The most characters of a detail.
    static let maximumDetailLength = 200
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
    /// The short phrase the capsule shows, at most ``maximumTitleLength`` characters.
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

    /// A key that is unique across modules: the module's identifier and the activity's id.
    var key: String {
        "\(moduleID)/\(id)"
    }

    /// Creates an activity. A title or detail beyond its cap is cut, a progress outside
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
        tint: LiveActivityTint = .accent
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
    }
}
