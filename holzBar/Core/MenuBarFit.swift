//
//  MenuBarFit.swift
//  holzBar
//

import Foundation

/// Works out whether the apps in the Visible section fit in the menu bar, and which of them
/// holzBar may move to Hidden to make room (Phase 97, D-07).
///
/// macOS 27 folds the items that do not fit beside the notch behind its own overflow control.
/// This is the one model every surface asks: the warning in Layout, the notice in the holzBar
/// Shelf and the automatic pass. It takes plain numbers and returns plain results, so it is
/// tested on Linux; the macOS 27 glue (`MakeRoom27`) turns the item cache into ``Input``.
///
/// Every number in ``Policy`` is an estimate from measurements on macOS 27.0 and 27.2 (the
/// research's section 1 and `Scripts/macos27/fit-probe.swift`), kept in one place and pinned by a
/// test. They are tuned after probes P1 and P2 at the 1.2.0 beta test (D-22); until then the
/// banner carries the Preview badge and no text says that a move frees room (D-23).
nonisolated enum MenuBarFit {
    /// What macOS 27's own overflow control does, from the last read of the bar
    /// (`NativeOverflowState27`).
    nonisolated enum Native: Equatable, Sendable {
        /// The control is not there and nothing is folded.
        case none
        /// The control is there and the folded items are stacked on it.
        case collapsed
        /// The control is there and the folded items are drawn left of the notch.
        case expanded
        /// The frames do not agree, or tell too little.
        case unknown
    }

    /// One application in the Visible section.
    nonisolated struct App: Equatable, Sendable {
        /// The application's layout key (its bundle identifier).
        var key: String
        /// The name to show, already cleaned of control and direction characters.
        var name: String
        /// The widths of its items, the one nearest the notch first.
        var itemWidths: [Double]
        /// Whether holzBar may move it: not holzBar's own, not Apple's, not protected, not
        /// controlled by a rule, not a widget (D-03).
        var isMovable: Bool
        /// How often its items were opened lately while Usage suggestions is on; `nil` while it
        /// is off.
        var clicks: Int?
        /// When the application started, for the tie-break "the newest first".
        var launchedAt: Date?
        /// How far its nearest item lies from the notch (or from the application menu), in points.
        var distanceFromNotch: Double
        /// Whether macOS folded one of its items away already.
        var isFolded: Bool

        init(
            key: String,
            name: String,
            itemWidths: [Double],
            isMovable: Bool,
            clicks: Int? = nil,
            launchedAt: Date? = nil,
            distanceFromNotch: Double = 0,
            isFolded: Bool = false
        ) {
            self.key = key
            self.name = name
            self.itemWidths = itemWidths
            self.isMovable = isMovable
            self.clicks = clicks
            self.launchedAt = launchedAt
            self.distanceFromNotch = distanceFromNotch
            self.isFolded = isFolded
        }

        /// The room its items take: the sum of their widths minus the overlap of each neighbour.
        var width: Double {
            guard !itemWidths.isEmpty else {
                return 0
            }
            return itemWidths.reduce(0, +) - Policy.itemOverlap * Double(itemWidths.count - 1)
        }

        /// The room it frees when it leaves: its width minus the overlap of the neighbour that
        /// closes the gap.
        var pitch: Double {
            guard !itemWidths.isEmpty else {
                return 0
            }
            return width - Policy.itemOverlap
        }
    }

    /// What one evaluation needs.
    nonisolated struct Input: Equatable, Sendable {
        /// The room for the apps in points, or `nil` where it cannot be told.
        var room: Double?
        /// The Visible-section apps, the one nearest the notch first.
        var apps: [App]
        /// What the overflow control does.
        var native: Native
        /// Whether Layout (or another surface) shows every section, so that macOS may fold
        /// items only because they are shown.
        var revealsAll: Bool
        /// Whether the last verdict was does-not-fit: the verdict clears only at the room minus
        /// ``Policy/margin``, so a move can never trigger another move.
        var wasOverflowing: Bool
    }

    /// What the model says.
    nonisolated enum Verdict: Equatable, Sendable {
        /// The apps fit.
        case fits
        /// The apps are wider than the room; this many items have to go, nearest the notch first.
        case doesNotFit(items: Int)
        /// macOS folded these apps away already (the names are the bar's order; `items` counts
        /// the folded items).
        case folded(names: [String], items: Int)
        /// The numbers are missing.
        case unknown

        /// Whether the bar is full.
        var isOverflowing: Bool {
            switch self {
            case .doesNotFit, .folded: true
            case .fits, .unknown: false
            }
        }
    }

    /// The numbers the model rests on.
    nonisolated enum Policy {
        /// Neighbouring items overlap by 2 points (measured on macOS 27.0 and 27.2;
        /// `StuckOverflow27Tests`, `MenuBarGeometry27Tests`).
        static let itemOverlap: Double = 2
        /// How far left of the clock the system items reach (122 points measured on 27.0 on
        /// both displays, 130 used; `MenuBarItemProvider27.systemItemsSpan`).
        static let systemItemsSpan: Double = 130
        /// The width of macOS 27's overflow control (`MenuBarGeometry27Tests`).
        static let overflowControlWidth: Double = 17
        /// How far below the room the sum has to fall before an overflowing bar counts as fitting
        /// again: one typical app of 32 points (an estimate).
        static let margin: Double = 32
        /// The most apps one pass moves (D-09).
        static let maximumPerPass = 3
        /// How long a verdict has to stay unchanged before a banner appears or leaves (the
        /// bar animates for about 250 ms and draws its frames 0.4 to 0.6 s late).
        static let bannerSettle = Duration.seconds(3)
        /// How long the banner stays quiet after a pass or an undo, so it never offers a move
        /// that fights the undo (the undo itself waits 2 seconds before it reads the bar again).
        static let quietAfterPass = Duration.seconds(3)
    }

    // MARK: - Settle

    /// Keeps a verdict from flickering on screen: a verdict that differs from the one shown is
    /// shown only after it stayed the same for ``Policy/bannerSettle``, so a condition that flips
    /// within that time changes nothing (T-97-06). Pure and clock-free: the caller passes the
    /// time of each note and arms one wait for the instant ``note(_:at:)`` returns.
    nonisolated struct Settle: Equatable, Sendable {
        /// The verdict on screen.
        private(set) var shown: Verdict

        /// A different verdict and when it was first seen.
        private var pending: (verdict: Verdict, since: ContinuousClock.Instant)?

        /// Starts with `shown` on screen: a verdict that is already true at the start shows at once.
        init(shown: Verdict) {
            self.shown = shown
        }

        static func == (lhs: Settle, rhs: Settle) -> Bool {
            lhs.shown == rhs.shown && lhs.pending?.verdict == rhs.pending?.verdict && lhs.pending?.since == rhs.pending?.since
        }

        /// Notes the latest verdict.
        ///
        /// - Returns: The instant to note again (the verdict stayed different and will be due
        ///   then), or `nil` when nothing is waiting: the verdict is the one shown, or it just
        ///   became the one shown.
        mutating func note(_ verdict: Verdict, at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
            guard verdict != shown else {
                pending = nil
                return nil
            }
            let since = pending?.verdict == verdict ? pending?.since ?? now : now
            guard now - since < Policy.bannerSettle else {
                shown = verdict
                pending = nil
                return nil
            }
            pending = (verdict, since)
            return since + Policy.bannerSettle
        }
    }

    // MARK: - Room

    /// The room beside a notch: the unobscured area right of the notch minus the system items
    /// and the overflow control.
    ///
    /// - Parameter rightAreaWidth: The width of `auxiliaryTopRightArea`.
    static func room(rightAreaWidth: Double) -> Double {
        guard rightAreaWidth.isFinite else {
            return 0
        }
        return max(0, rightAreaWidth - Policy.systemItemsSpan - Policy.overflowControlWidth)
    }

    /// The room on a display without a notch: the space right of the frontmost application's
    /// menu minus the system items and the overflow control. Never below 0.
    ///
    /// - Parameters:
    ///   - displayMaxX: The display's right edge.
    ///   - applicationMenuMaxX: The right edge of the frontmost application's menu, in the same
    ///     coordinates.
    static func room(displayMaxX: Double, applicationMenuMaxX: Double) -> Double {
        guard displayMaxX.isFinite, applicationMenuMaxX.isFinite else {
            return 0
        }
        return max(0, displayMaxX - applicationMenuMaxX - Policy.systemItemsSpan - Policy.overflowControlWidth)
    }

    // MARK: - Verdict

    /// The prediction: whether the apps fit the room.
    ///
    /// The sum is the width of every item minus the overlap between all neighbours. It fits up
    /// to and including the room; an overflowing bar clears only at the room minus the margin.
    /// `items` counts the items, nearest the notch first, whose pitches have to go to reach that
    /// limit: items, not apps, so it can differ from the number of apps a pass moves.
    ///
    /// Folded apps are counted with the widths they were last read at, like any other.
    ///
    /// What macOS already did wins over the prediction (D-08): while the overflow control is
    /// collapsed, Visible apps that are folded give ``Verdict/folded(names:items:)``. While a
    /// surface shows every section (`revealsAll`, Layout), macOS may fold items only because
    /// they are shown, so the fold counts only when the prediction from the Visible apps' widths
    /// agrees that they do not fit and a Visible app is folded (C7, D-25). Apps of the hidden
    /// sections are never in `apps`, so they are never named.
    static func evaluate(_ input: Input) -> Verdict {
        let prediction = predict(input)
        let folded = input.apps.filter(\.isFolded)
        guard !folded.isEmpty else {
            return prediction
        }
        let isFold: Bool
        if input.revealsAll {
            if case .doesNotFit = prediction {
                isFold = true
            } else {
                isFold = false
            }
        } else {
            isFold = input.native == .collapsed
        }
        guard isFold else {
            return prediction
        }
        return .folded(names: folded.map(\.name), items: folded.reduce(0) { $0 + max(1, $1.itemWidths.count) })
    }

    /// The names a sentence shows and how many more there are: the first two, then the rest as a
    /// count (for "Folded away: Docker, Slack +2").
    static func sentenceNames(_ names: [String]) -> (shown: [String], more: Int) {
        (Array(names.prefix(2)), max(0, names.count - 2))
    }

    /// The prediction alone, from the widths and the room.
    private static func predict(_ input: Input) -> Verdict {
        let items = flatItems(of: input.apps)
        guard !items.isEmpty else {
            return .fits
        }
        guard let room = input.room, room.isFinite else {
            return .unknown
        }
        let limit = input.wasOverflowing ? room - Policy.margin : room
        let total = sum(of: items)
        guard total > limit else {
            return .fits
        }
        let deficit = total - limit
        var freed = 0.0
        var count = 0
        for width in items {
            freed += width - Policy.itemOverlap
            count += 1
            if freed >= deficit {
                break
            }
        }
        return .doesNotFit(items: max(1, count))
    }

    // MARK: - Planner

    /// The apps one pass moves to Hidden, in the order they move.
    ///
    /// Only movable apps, at most ``Policy/maximumPerPass``, and no more than it takes for their
    /// freed pitches to reach the deficit to the room minus the margin (at least one while the
    /// bar is full). The order is the apps used least first while `usesUsage` is true (an app with
    /// no count is unused), the newest launch first among equals, then the one nearest the notch;
    /// with `usesUsage` false the clicks are ignored and the newest launch comes first.
    ///
    /// - Returns: The empty list when the bar is not full, the room is unknown or nothing may move.
    static func plan(_ input: Input, verdict: Verdict, usesUsage: Bool) -> [App] {
        guard verdict.isOverflowing else {
            return []
        }
        var deficit = -Double.infinity
        if let room = input.room, room.isFinite {
            deficit = sum(of: flatItems(of: input.apps)) - (room - Policy.margin)
        }
        if case .folded = verdict {
            // macOS folded these apps away: the room they need back is at least their pitches,
            // whatever the prediction says, and it is the whole answer without a room.
            deficit = max(deficit, input.apps.filter(\.isFolded).reduce(0) { $0 + $1.pitch })
        }
        guard deficit.isFinite else {
            return []
        }
        var chosen = [App]()
        var freed = 0.0
        for candidate in input.apps.filter(\.isMovable).sorted(by: { precedes($0, $1, usesUsage: usesUsage) }) {
            chosen.append(candidate)
            freed += candidate.pitch
            if freed >= deficit || chosen.count >= Policy.maximumPerPass {
                break
            }
        }
        return chosen
    }

    /// Whether `first` moves before `second`.
    private static func precedes(_ first: App, _ second: App, usesUsage: Bool) -> Bool {
        if usesUsage {
            let firstClicks = first.clicks ?? 0
            let secondClicks = second.clicks ?? 0
            if firstClicks != secondClicks {
                return firstClicks < secondClicks
            }
        }
        if first.launchedAt != second.launchedAt {
            switch (first.launchedAt, second.launchedAt) {
            case let (firstDate?, secondDate?): return firstDate > secondDate
            case (_?, nil): return true
            default: return false
            }
        }
        if first.distanceFromNotch != second.distanceFromNotch {
            return first.distanceFromNotch < second.distanceFromNotch
        }
        return first.key < second.key
    }

    // MARK: - Sums

    /// The widths of every item, the apps ordered nearest the notch first.
    private static func flatItems(of apps: [App]) -> [Double] {
        apps.enumerated()
            .sorted { lhs, rhs in
                lhs.element.distanceFromNotch != rhs.element.distanceFromNotch
                    ? lhs.element.distanceFromNotch < rhs.element.distanceFromNotch
                    : lhs.offset < rhs.offset
            }
            .flatMap(\.element.itemWidths)
    }

    /// The widths of the items minus the overlap of every neighbour.
    private static func sum(of widths: [Double]) -> Double {
        guard !widths.isEmpty else {
            return 0
        }
        return widths.reduce(0, +) - Policy.itemOverlap * Double(widths.count - 1)
    }
}
