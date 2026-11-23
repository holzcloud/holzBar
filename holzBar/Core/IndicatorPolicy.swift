//
//  IndicatorPolicy.swift
//  holzBar
//

import Foundation

/// What an indicator of the closed notch is about. New cases go at the end; the raw values are
/// part of an activity's id and are never stored.
nonisolated enum IndicatorKind: String, CaseIterable, Sendable {
    /// The keyboard input source changed.
    case inputSource
    /// The output volume changed.
    case volume
    /// A display's brightness changed.
    case brightness
    /// A trackpad or mouse gesture was recognised.
    case gesture
}

/// Decides whether an indicator event is shown now, shown later or not shown, as a pure value
/// the main actor drives (D-09, D-10).
///
/// It reads no clock and waits for nothing: the caller passes the moment of each event and, on
/// ``Decision/deferred(until:)``, offers the latest value again at that moment.
///
/// - Input source: a change within ``activationQuiet`` after an app activation is ignored (macOS
///   switches the source per document when an app comes forward, which is not the user's doing);
///   a value equal to the last shown is ignored; a different one within ``inputSourceRateLimit`` of
///   the last shown is deferred to the end of that window, so a quick second switch still shows,
///   never dropped.
/// - Volume, brightness and gesture: events within `DesignTokens.Indicator.coalescingSeconds` of the
///   last shown are deferred to its end, so a fast burst is one flash. An identical value is not
///   ignored: a held key at the end of the range still shows.
nonisolated struct IndicatorPolicy: Equatable, Sendable {
    /// 150 ms: the per-document source switch follows an app activation within a few frames, a
    /// deliberate switch of the user does not come that fast (research section 2).
    static let activationQuiet: TimeInterval = 0.15
    /// 400 ms: a deliberate second switch takes longer than that, a burst of notifications from
    /// the system does not.
    static let inputSourceRateLimit: TimeInterval = 0.4

    /// What to do with an offered value.
    nonisolated enum Decision: Equatable, Sendable {
        /// Show it now.
        case show
        /// Offer the latest value again at the given moment; it shows then.
        case deferred(until: Date)
        /// Do not show it.
        case ignored
    }

    private var lastValue: [IndicatorKind: String] = [:]
    private var lastShownAt: [IndicatorKind: Date] = [:]
    private var lastActivation: Date?

    init() {}

    /// Notes that an app came forward at a moment.
    mutating func appDidActivate(at moment: Date) {
        lastActivation = moment
    }

    /// Offers a value for a kind at a moment and says what to do with it. A shown value becomes the
    /// last shown one.
    mutating func offer(_ kind: IndicatorKind, value: String, at moment: Date) -> Decision {
        let window: TimeInterval
        if kind == .inputSource {
            if let activation = lastActivation, moment < activation.addingTimeInterval(Self.activationQuiet) {
                return .ignored
            }
            if lastValue[kind] == value {
                return .ignored
            }
            window = Self.inputSourceRateLimit
        } else {
            window = DesignTokens.Indicator.coalescingSeconds
        }
        if let shownAt = lastShownAt[kind] {
            let end = shownAt.addingTimeInterval(window)
            if moment < end {
                return .deferred(until: end)
            }
        }
        lastValue[kind] = value
        lastShownAt[kind] = moment
        return .show
    }

    /// Forgets the last shown value of a kind, so the same value shows again. The window since the
    /// last shown moment still holds.
    mutating func reset(_ kind: IndicatorKind) {
        lastValue[kind] = nil
    }
}

/// What a flash looks like as a live activity.
nonisolated enum IndicatorLook {
    /// The module identifier of every indicator activity.
    static let moduleID = "indicators"

    /// The id of the one activity a kind has: a second change replaces it and restarts its hold.
    static func activityID(_ kind: IndicatorKind) -> String {
        "indicator-\(kind.rawValue)"
    }

    /// The nearest of the durations the user may choose; a tie goes to the shorter one and a value
    /// that is not a finite number to the default.
    static func inputSourceDuration(_ stored: Double) -> TimeInterval {
        guard stored.isFinite else {
            return DesignTokens.Indicator.inputSourceDefaultDuration
        }
        var best = DesignTokens.Indicator.inputSourceDefaultDuration
        var bestDistance = Double.infinity
        for choice in DesignTokens.Indicator.inputSourceDurations.sorted() {
            let distance = abs(choice - stored)
            if distance < bestDistance {
                best = choice
                bestDistance = distance
            }
        }
        return best
    }

    /// The live activity of a flash: finished at the moment it happens, so its hold runs from there.
    static func flash(
        kind: IndicatorKind,
        symbol: String,
        value: String,
        title: String,
        at moment: Date,
        hold: TimeInterval = DesignTokens.Indicator.holdSeconds,
        flash: LiveActivityFlash = LiveActivityFlash()
    ) -> LiveActivity {
        LiveActivity(
            id: activityID(kind),
            moduleID: moduleID,
            kind: .other,
            symbol: symbol,
            title: title,
            priority: DesignTokens.Indicator.flashPriority,
            startedAt: moment,
            finishedAt: moment,
            tint: .accent,
            announcesItself: true,
            compactValue: value,
            holdSeconds: hold,
            flash: flash
        )
    }
}
