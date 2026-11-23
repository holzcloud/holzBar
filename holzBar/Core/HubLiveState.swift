//
//  HubLiveState.swift
//  holzBar
//

import Foundation

/// What the widened notch shows while the hub is closed, and what the open hub's right pill
/// draws, as one pure rule over the activity board (concept section 10b, "Live state").
///
/// The content is the top activity's symbol and tint, then a trailing value, then how many other
/// activities are live. The trailing value is, in this order, for a running activity:
/// 1. the countdown of an activity that ends by itself, while its end lies after the moment the
///    rule works at (the system draws it; holzBar runs no timer for it);
/// 2. a percentage, where the activity reports progress;
/// 3. its short word (``LiveActivity/compactValue``);
/// 4. nothing.
/// A finished activity shows its short word or nothing: it is done, so neither a countdown nor
/// a percentage; an activity whose finish still lies ahead counts as running until then. A flash
/// that shows a word also carries its second text and its icon file. The rule reads no clock and never a title, a detail or a name: only the symbol,
/// the tint, the end, the progress and the short word reach the content.
nonisolated enum HubLiveState {
    /// The value drawn after the symbol.
    nonisolated enum Trailing: Equatable, Sendable {
        /// The system-drawn countdown to the given moment.
        case countdown(end: Date)
        /// A whole percentage, 0 to 100.
        case percent(Int)
        /// A short word such as "Camera" or "Done".
        case word(String)
        /// No value; the symbol stands alone.
        case none
    }

    /// What the live state draws.
    nonisolated struct Content: Equatable, Sendable {
        /// The name of an SF Symbol: the top activity's.
        var symbol: String
        /// The tint of the symbol: the top activity's.
        var tint: LiveActivityTint
        var trailing: Trailing
        /// How many live activities are not the top one, for the `+n` badge.
        var extraCount: Int
        /// The second text of a flash whose trailing value is a word, or `nil`.
        var secondary: String?
        /// The icon file of a flash whose trailing value is a word, or `nil`.
        var symbolImageURL: URL?

        init(
            symbol: String,
            tint: LiveActivityTint,
            trailing: Trailing,
            extraCount: Int,
            secondary: String? = nil,
            symbolImageURL: URL? = nil
        ) {
            self.symbol = symbol
            self.tint = tint
            self.trailing = trailing
            self.extraCount = extraCount
            self.secondary = secondary
            self.symbolImageURL = symbolImageURL
        }
    }

    /// The content for a board at a moment, or `nil` when nothing is live.
    static func make(board: HubActivityBoard.Board, now: Date) -> Content? {
        guard let activity = board.compact else {
            return nil
        }
        let value = trailing(of: activity, now: now)
        var content = Content(
            symbol: activity.symbol,
            tint: activity.tint,
            trailing: value,
            extraCount: board.hiddenCount
        )
        if case .word = value, let flash = activity.flash {
            content.secondary = flash.secondaryValue
            content.symbolImageURL = flash.symbolImageURL
        }
        return content
    }

    private static func trailing(of activity: LiveActivity, now: Date) -> Trailing {
        let isRunning = activity.finishedAt.map { $0 > now } ?? true
        if isRunning {
            if let end = activity.endsAt, end > now {
                return .countdown(end: end)
            }
            if let progress = activity.progress {
                return .percent(Int((progress * 100).rounded()))
            }
        }
        if let word = activity.compactValue, !word.trimmingCharacters(in: .whitespaces).isEmpty {
            return .word(word)
        }
        return .none
    }
}
