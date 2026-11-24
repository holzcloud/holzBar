//
//  DockBadgeLabel.swift
//  holzBar
//

import Foundation

/// What the Dock answered when asked for the badge of one application item.
///
/// The cases separate the three things a missing number can mean, because only one of them is a
/// reason to switch the read off: an item with no badge answers with no value (``none``, the zero
/// state), the Dock saying it has no such attribute at all is ``unsupported`` (the interface is
/// gone), and anything else is ``failed``.
nonisolated enum DockLabelAnswer: Equatable, Sendable {
    /// The badge's text, as the Dock holds it.
    case text(String)
    /// The attribute exists and holds no value: the app has no badge.
    case none
    /// The Dock says the attribute does not exist.
    case unsupported
    /// Any other Accessibility error, or a value that is not a string.
    case failed
}

/// The badge of one app as holzBar shows it: nothing, a count, or a mark.
///
/// The Dock's badge is a text, and a text is not always a number: an app can show "•", "!" or a
/// word. The text is parsed once, here. A count is whole digits, optionally grouped by a comma,
/// a point, a space or a no-break space in groups of three, and optionally followed by "+"; every
/// other text is a ``mark`` and is shown as it is, never read as a number anywhere else.
nonisolated enum DockBadgeLabel: Equatable, Sendable {
    /// No badge.
    case none
    /// A number of things waiting. Zero is possible and is the zero state.
    case count(Int)
    /// A badge that is not a number, as the trimmed text.
    case mark(String)

    /// Parses an answer of the Dock. Only ``DockLabelAnswer/text(_:)`` can carry a badge.
    init(_ answer: DockLabelAnswer) {
        guard case .text(let raw) = answer else {
            self = .none
            return
        }
        let text = Self.trimmed(raw)
        if text.isEmpty {
            self = .none
        } else if let count = Self.count(in: text) {
            self = .count(count)
        } else {
            self = .mark(text)
        }
    }

    /// Whether there is nothing to show: no badge, or a count of zero.
    var isZero: Bool {
        switch self {
        case .none: true
        case .count(let number): number == 0
        case .mark: false
        }
    }

    /// The text in the badge item's bubble, or `nil` while there is nothing to show.
    ///
    /// A count shows as the number up to ``DesignTokens/DockBadge/countLimit`` and as "99+" above
    /// it. A mark shows as it is up to ``DesignTokens/DockBadge/labelCharacterLimit`` characters,
    /// and longer as its first characters with "…" in the last place, so the text is never wider
    /// than "99+". Characters are whole letters, so an accent or an emoji is never cut apart.
    var bubbleText: String? {
        guard !isZero else {
            return nil
        }
        switch self {
        case .none:
            return nil
        case .count(let number):
            let limit = DesignTokens.DockBadge.countLimit
            return number > limit ? "\(limit)+" : String(number)
        case .mark(let text):
            let limit = DesignTokens.DockBadge.labelCharacterLimit
            guard text.count > limit else {
                return text
            }
            return String(text.prefix(limit - 1)) + "…"
        }
    }

    /// The real count or the whole label, for the tooltip and VoiceOver; `nil` when there is no
    /// badge or the count is zero, which both read "No badge".
    var fullText: String? {
        guard !isZero else {
            return nil
        }
        switch self {
        case .none: return nil
        case .count(let number): return String(number)
        case .mark(let text): return text
        }
    }

    // MARK: Parsing

    /// The characters that may group the digits of a count.
    private static let separators: Set<Character> = [",", ".", " ", "\u{00A0}", "\u{202F}", "\u{2009}"]

    private static func trimmed(_ text: String) -> String {
        var scalars = Substring(text)
        while let first = scalars.first, first.isWhitespace {
            scalars.removeFirst()
        }
        while let last = scalars.last, last.isWhitespace {
            scalars.removeLast()
        }
        return String(scalars)
    }

    /// The number a text counts, or `nil` when it is not a count. The digits stand alone, or in
    /// groups of three after a first group of one to three, with one separator character between
    /// the groups, and a single "+" may end them.
    private static func count(in text: String) -> Int? {
        var body = Substring(text)
        if body.last == "+" {
            body.removeLast()
        }
        guard !body.isEmpty else {
            return nil
        }
        if body.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return Int(body)
        }
        let groups = body.split(omittingEmptySubsequences: false) { separators.contains($0) }
        guard groups.count > 1, groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        guard groups[0].count <= 3, groups.dropFirst().allSatisfy({ $0.count == 3 }) else {
            return nil
        }
        return Int(groups.joined())
    }
}

/// The rules that decide whether the Dock offers the badge at all, and whether a pass that read
/// it counts as a success.
///
/// The badge is an undocumented attribute of the Dock's application items, so the read can only
/// stay on while it works. It is off for the session only when the interface is missing (the
/// Dock's items answer that the attribute does not exist, three passes in a row) or failing (the
/// Dock cannot be read, or every read ends in an error, three passes in a row). An item with no
/// badge answers with no value, which is the zero state and never a reason to switch the read
/// off: a Dock where no app has a badge is a valid Dock. The three-in-a-row rule after the start
/// check is ``PrivateFeatureGate``'s; ``outcome(_:)`` says which of its calls a pass makes.
nonisolated enum DockLabelGate {
    /// What one pass over the Dock found.
    struct Pass: Equatable, Sendable {
        /// Whether the Dock and its list of items could be read.
        var dockReadable: Bool
        /// Whether an application item lists the badge attribute among its attributes.
        var listed: Bool
        /// The answers for the chosen apps that are in the Dock.
        var answers: [DockLabelAnswer]
    }

    /// What a pass makes of the gate once the read has started.
    enum PassOutcome: Equatable, Sendable {
        /// The Dock answered like a Dock that has the interface: record a success.
        case success
        /// The Dock could not be read, or every answer was an error or "unsupported": record a
        /// failure.
        case failure
        /// Nothing was asked: record nothing.
        case nothingRead
    }

    /// The outcome of a pass. Any answer with text or no value is a success, so a Dock where no
    /// chosen app has a badge succeeds every time; a pass with no answer reads nothing.
    static func outcome(_ pass: Pass) -> PassOutcome {
        guard pass.dockReadable else {
            return .failure
        }
        guard !pass.answers.isEmpty else {
            return .nothingRead
        }
        return pass.answers.contains(where: hasEvidence) ? .success : .failure
    }

    /// Whether an answer shows that the interface is there: the Dock gave a text or said the
    /// app has no badge.
    fileprivate static func hasEvidence(_ answer: DockLabelAnswer) -> Bool {
        switch answer {
        case .text, .none: true
        case .unsupported, .failed: false
        }
    }

    /// The start check: collects passes until they say whether the Dock offers the badge.
    ///
    /// It decides once evidence arrives (``PrivateFeatureGate/LoadResult/loaded``), or after
    /// three passes in a row of the same kind of failure. A pass that read nothing decides
    /// nothing and leaves the count as it is; a pass of another kind of failure starts that
    /// kind's count at one. The caller drops the value once it has an answer.
    struct StartCheck: Sendable {
        /// Passes in a row that said "unsupported" (the interface is missing) or that failed
        /// (the Dock cannot be read, or the reads error).
        private enum Kind {
            case unsupported
            case failing
        }

        private var kind: Kind?
        private var run = 0

        init() {}

        /// Takes in one pass. Returns the load result once it is decided, `nil` while more passes
        /// are needed.
        mutating func record(_ pass: Pass) -> PrivateFeatureGate.LoadResult? {
            if pass.listed || pass.answers.contains(where: DockLabelGate.hasEvidence) {
                kind = nil
                run = 0
                return .loaded
            }
            let seen: Kind
            if !pass.dockReadable {
                seen = .failing
            } else if pass.answers.isEmpty {
                return nil
            } else if pass.answers.allSatisfy({ $0 == .unsupported }) {
                seen = .unsupported
            } else {
                // Errors, alone or among "unsupported" answers: the Dock cannot be read cleanly.
                seen = .failing
            }
            run = seen == kind ? run + 1 : 1
            kind = seen
            guard run >= PrivateFeatureGate.failureLimit else {
                return nil
            }
            return seen == .unsupported ? .symbolMissing : .frameworkMissing
        }
    }
}
