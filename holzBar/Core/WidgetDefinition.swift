//
//  WidgetDefinition.swift
//  holzBar
//

import Foundation

/// What a widget is: a line of text from a built-in source, or a button that runs a Shortcut
/// (D-20). A text widget has no click action and a button has no data source.
nonisolated enum WidgetKind: String, Codable, Sendable {
    case text
    case button
}

/// The built-in source of a text widget. Every one reads without a permission (D-01); the
/// sources that were deferred (network throughput, Wi-Fi name, calendar, thermal, VPN state,
/// audio device) have no case, and weather and a public address are never offered (D-04).
///
/// The raw values are stored in the settings and never change.
nonisolated enum WidgetSource: String, Codable, CaseIterable, Sendable {
    case dateTime
    case battery
    case cpu
    case memory
    case uptime
    case freeDisk
    case countdown

    /// The one fixed SF Symbol of the source, shown before the text when the widget asks for it
    /// (D-11).
    var symbolName: String {
        switch self {
        case .dateTime: "clock"
        case .battery: "battery.75percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .uptime: "power"
        case .freeDisk: "internaldrive"
        case .countdown: "hourglass"
        }
    }

    /// The formats the source offers, in the order the editor lists them (D-09). There is no
    /// template language.
    var presets: [WidgetPreset] {
        switch self {
        case .dateTime: [.time, .weekdayAndTime, .dateAndTime, .weekdayDateAndTime]
        case .battery: [.percent, .percentAndState]
        case .cpu: [.percent]
        case .memory: [.percentUsed, .gigabytesUsed]
        case .uptime, .countdown: [.duration, .compactDuration]
        case .freeDisk: [.gigabytesFree, .percentFree]
        }
    }

    /// The format a new widget of the source starts with.
    var defaultPreset: WidgetPreset {
        switch self {
        case .dateTime: .time
        case .battery: .percentAndState
        case .cpu: .percent
        case .memory: .percentUsed
        case .uptime, .countdown: .duration
        case .freeDisk: .gigabytesFree
        }
    }

    /// The seconds a stored refresh interval is kept within, for the sources the user may tune;
    /// `nil` for the others (D-15). CPU never refreshes faster than every 2 s and memory never
    /// faster than every 5 s, whatever the defaults hold.
    var refreshRange: ClosedRange<Int>? {
        switch self {
        case .cpu: 2...60
        case .memory: 5...300
        case .dateTime, .battery, .uptime, .freeDisk, .countdown: nil
        }
    }

    /// The refresh interval, in seconds, a new widget of the source starts with (D-15).
    var defaultRefreshSeconds: Int? {
        switch self {
        case .cpu: 5
        case .memory: 10
        case .dateTime, .battery, .uptime, .freeDisk, .countdown: nil
        }
    }

    /// The intervals, in seconds, the editor offers for the source; empty when the source has no
    /// interval of its own.
    var refreshChoices: [Int] {
        switch self {
        case .cpu: [2, 5, 10, 30]
        case .memory: [5, 10, 30, 60]
        case .dateTime, .battery, .uptime, .freeDisk, .countdown: []
        }
    }
}

/// How the reading of a source is written: one of the fixed formats of ``WidgetSource/presets``.
///
/// The raw values are stored in the settings and never change.
nonisolated enum WidgetPreset: String, Codable, CaseIterable, Sendable {
    // Date and time
    case time
    case weekdayAndTime
    case dateAndTime
    case weekdayDateAndTime
    // Battery, CPU
    case percent
    case percentAndState
    // Memory
    case percentUsed
    case gigabytesUsed
    // Uptime, countdown
    case duration
    case compactDuration
    // Free disk space
    case gigabytesFree
    case percentFree
}

/// One widget of the menu bar, as it is stored and exported (D-25).
///
/// The definition holds the kind, the source, the format and a few options, and nothing that
/// stays on this Mac: the name of a button's Shortcut lives under its own local-only key
/// (`Defaults.Key.widgetShortcutNames`), so no export, import or shared profile carries it.
/// The settings are written by any process of the user, so every value that is read back goes
/// through ``validated(now:)``.
nonisolated struct WidgetDefinition: Codable, Equatable, Identifiable, Sendable {
    /// The most widgets there are (D-05).
    static let maximumCount = 6
    /// The most characters of a button's title.
    static let maximumTitleLength = 24
    /// The symbol of a button that shows one.
    static let buttonSymbolName = "play.circle"
    /// The autosave name of a widget's status item is this prefix and the widget's identifier
    /// (D-17), the pattern of `holzBar.Group.<uuid>`.
    static let autosaveNamePrefix = "holzBar.Widget."
    /// How far a countdown's moment may lie from now, in seconds: about 126 years, in either
    /// direction. A moment beyond it is not a date the user typed.
    static let maximumCountdownDistance: TimeInterval = 126 * 365 * 24 * 60 * 60

    let id: UUID
    var kind: WidgetKind
    /// The source of a text widget. A button keeps the clock here and ignores it.
    var source: WidgetSource
    var preset: WidgetPreset
    /// Whether the source's symbol comes before the text (D-11).
    var showsSymbol = true
    /// The clock's hour cycle: 24-hour or 12-hour.
    var uses24HourClock = false
    /// Whether the clock shows seconds; only the clock has seconds (D-10).
    var showsSeconds = false
    /// The seconds between two readings of CPU or memory; `nil` for the other sources (D-15).
    var refreshSeconds: Int?
    /// The moment a countdown counts down to.
    var countdownTarget: Date?
    /// The text of a button.
    var buttonTitle = ""
    /// Whether a button shows ``buttonSymbolName`` before its title.
    var buttonShowsSymbol = true

    /// The name of the widget's status item (D-17).
    var autosaveName: String {
        Self.autosaveNamePrefix + id.uuidString
    }

    /// The identifier a widget's autosave name holds, or `nil` when the name is not exactly
    /// ``autosaveNamePrefix`` and an uppercase UUID: a group or spacer name, a malformed
    /// identifier and an empty suffix are all refused.
    static func id(fromAutosaveName name: String) -> UUID? {
        guard name.hasPrefix(autosaveNamePrefix) else {
            return nil
        }
        let suffix = String(name.dropFirst(autosaveNamePrefix.count))
        guard let id = UUID(uuidString: suffix), id.uuidString == suffix else {
            return nil
        }
        return id
    }

    /// Whether a name is the autosave name of a widget (D-17).
    static func isAutosaveName(_ name: String) -> Bool {
        id(fromAutosaveName: name) != nil
    }

    /// A new text widget with the source's default format.
    ///
    /// - Parameters:
    ///   - source: The source to read.
    ///   - uses24HourClock: The clock's hour cycle, from the user's locale.
    ///   - now: The moment of creation. A new countdown targets one hour later, rounded down to
    ///     the minute.
    static func text(source: WidgetSource, uses24HourClock: Bool, now: Date) -> WidgetDefinition {
        var target: Date?
        if source == .countdown {
            let seconds = ((now.timeIntervalSinceReferenceDate + 3600) / 60).rounded(.down) * 60
            target = Date(timeIntervalSinceReferenceDate: seconds)
        }
        return WidgetDefinition(
            id: UUID(),
            kind: .text,
            source: source,
            preset: source.defaultPreset,
            showsSymbol: source != .dateTime,
            uses24HourClock: uses24HourClock,
            refreshSeconds: source.defaultRefreshSeconds,
            countdownTarget: target
        )
    }

    /// A new button. The Shortcut it runs is chosen by name and kept apart from the definition.
    static func button(title: String) -> WidgetDefinition {
        WidgetDefinition(
            id: UUID(),
            kind: .button,
            source: .dateTime,
            preset: WidgetSource.dateTime.defaultPreset,
            buttonTitle: cleanedTitle(title)
        )
    }

    /// The definition with every value brought into its range, or `nil` when it cannot be a
    /// widget: a countdown without a moment, or with a moment far outside the calendar.
    ///
    /// A format that does not belong to the source becomes the source's default, seconds exist
    /// only for the clock, an interval is kept within ``WidgetSource/refreshRange``, and a
    /// button's title is cleaned. Values that belong to the other kind are reset, so a stored
    /// definition has one shape.
    ///
    /// - Parameter now: The moment a countdown's distance is measured from.
    func validated(now: Date = Date()) -> WidgetDefinition? {
        var result = self
        switch kind {
        case .button:
            result.source = .dateTime
            result.preset = WidgetSource.dateTime.defaultPreset
            result.showsSeconds = false
            result.refreshSeconds = nil
            result.countdownTarget = nil
            result.buttonTitle = Self.cleanedTitle(buttonTitle)
        case .text:
            if !source.presets.contains(preset) {
                result.preset = source.defaultPreset
            }
            result.showsSeconds = source == .dateTime && showsSeconds
            if let range = source.refreshRange {
                let seconds = refreshSeconds ?? source.defaultRefreshSeconds ?? range.lowerBound
                result.refreshSeconds = min(max(seconds, range.lowerBound), range.upperBound)
            } else {
                result.refreshSeconds = nil
            }
            if source == .countdown {
                // A moment that is not a number fails the comparison and is dropped too.
                guard let target = countdownTarget,
                    abs(target.timeIntervalSince(now)) <= Self.maximumCountdownDistance else {
                    return nil
                }
            } else {
                result.countdownTarget = nil
            }
            result.buttonTitle = ""
            result.buttonShowsSymbol = true
        }
        return result
    }

    /// The general categories of the characters a button's title never keeps: control, format
    /// (such as a right-to-left override), private use, surrogate, unassigned and the line and
    /// paragraph separators.
    private static let droppedCategories: Set<Unicode.GeneralCategory> = [
        .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator,
    ]

    /// A button title as plain text: without the characters of ``droppedCategories``, trimmed and
    /// cut to ``maximumTitleLength`` characters.
    static func cleanedTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in title.unicodeScalars where !droppedCategories.contains(scalar.properties.generalCategory) {
            scalars.append(scalar)
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumTitleLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated extension WidgetDefinition {
    /// Only the identifier, the kind and the source are required, so an older file and a later
    /// one decode alike; every other value that is missing or of the wrong type takes its
    /// default and is then brought into range by ``validated(now:)``.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(WidgetKind.self, forKey: .kind)
        source = try container.decode(WidgetSource.self, forKey: .source)
        preset = (try? container.decodeIfPresent(WidgetPreset.self, forKey: .preset)) ?? source.defaultPreset
        showsSymbol = (try? container.decodeIfPresent(Bool.self, forKey: .showsSymbol)) ?? true
        uses24HourClock = (try? container.decodeIfPresent(Bool.self, forKey: .uses24HourClock)) ?? false
        showsSeconds = (try? container.decodeIfPresent(Bool.self, forKey: .showsSeconds)) ?? false
        refreshSeconds = try? container.decodeIfPresent(Int.self, forKey: .refreshSeconds)
        countdownTarget = try? container.decodeIfPresent(Date.self, forKey: .countdownTarget)
        buttonTitle = (try? container.decodeIfPresent(String.self, forKey: .buttonTitle)) ?? ""
        buttonShowsSymbol = (try? container.decodeIfPresent(Bool.self, forKey: .buttonShowsSymbol)) ?? true
    }
}

/// One element of a stored list that is skipped when it cannot be decoded, instead of making the
/// whole list unreadable.
nonisolated private struct LossyWidget: Decodable {
    let value: WidgetDefinition?

    init(from decoder: any Decoder) {
        value = try? WidgetDefinition(from: decoder)
    }
}

/// The stored list of widgets: decoded element by element, validated, capped and encoded again.
///
/// The list comes from the defaults, an imported settings file or any process of the user, so
/// nothing in it is trusted (T-12-04).
nonisolated enum WidgetList {
    /// The most bytes of a list that is read or written.
    static let maximumDataSize = 65_536

    /// The widgets of a stored list, in order: every element that decodes and validates, the
    /// first of two with the same identifier, at most ``WidgetDefinition/maximumCount`` of them.
    /// Data that is too large or is not a JSON array gives an empty list.
    static func decode(_ data: Data, now: Date = Date()) -> [WidgetDefinition] {
        list(from: data, now: now) ?? []
    }

    /// The JSON to store, with sorted keys, or `nil` when it would be over ``maximumDataSize``.
    static func encoded(_ list: [WidgetDefinition]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(list), data.count <= maximumDataSize else {
            return nil
        }
        return data
    }

    /// An imported list as it may be applied: the decoded and validated widgets, encoded again,
    /// so that unknown fields, unknown kinds and a seventh widget never reach the defaults.
    /// `nil` when the data is too large or is not a JSON array.
    static func normalized(_ data: Data, now: Date = Date()) -> Data? {
        guard let list = list(from: data, now: now) else {
            return nil
        }
        return encoded(list)
    }

    private static func list(from data: Data, now: Date) -> [WidgetDefinition]? {
        guard data.count <= maximumDataSize,
            let elements = try? JSONDecoder().decode([LossyWidget].self, from: data) else {
            return nil
        }
        var seen = Set<UUID>()
        var widgets = [WidgetDefinition]()
        for element in elements {
            guard let widget = element.value?.validated(now: now), seen.insert(widget.id).inserted else {
                continue
            }
            widgets.append(widget)
            if widgets.count == WidgetDefinition.maximumCount {
                break
            }
        }
        return widgets
    }
}
