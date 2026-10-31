//
//  TimerBoard.swift
//  holzBar
//

import Foundation

/// One timer on a ``TimerBoard``.
nonisolated struct TimerItem: Identifiable, Equatable, Sendable {
    /// What the timer measures.
    nonisolated enum Kind: Equatable, Sendable {
        /// A length of time in seconds; it can be paused and restarted.
        case length(Double)
        /// A countdown to a moment of the wall clock.
        case moment(Date)
        /// A stopwatch that counts up from zero and never ends by itself.
        case stopwatch
    }

    /// Where the timer is in its life.
    nonisolated enum State: Equatable, Sendable {
        /// Running from `start` to `end`.
        case running(start: Date, end: Date)
        /// Paused with `remaining` of `total` seconds left.
        case paused(remaining: Double, total: Double)
        /// Ended (or was found ended) at the given moment.
        case finished(at: Date)
        /// A stopwatch counting up since the given moment.
        case counting(since: Date)
        /// A stopwatch stopped at `elapsed` seconds.
        case halted(elapsed: Double)
    }

    let id: UUID
    var label: String
    let kind: Kind
    var state: State
}

/// The timers of one board, as plain values and explicit dates: no clock, no I/O.
///
/// Every function takes the moment it works at as a parameter, so the rules can be tested
/// without waiting. A timer stores the `Date` it ends (the wall clock), so a countdown to a
/// moment and a length of time follow one rule; setting the Mac's clock moves them both.
/// A late ending, one that happened more than ``lateTolerance`` seconds before the board
/// noticed it, is reported apart so that the app can skip the sound for it.
nonisolated struct TimerBoard: Equatable, Sendable {
    /// The most timers on a board at once (the maintainer's choice: eight).
    static let maximumItems = 8
    /// The shortest length of a timer, in seconds.
    static let minimumLength: Double = 1
    /// The longest length of a timer, in seconds: 99 hours, 59 minutes and 59 seconds.
    static let maximumLength: Double = 359_999
    /// The least time between now and a moment a countdown may end at, in seconds.
    static let minimumLead: Double = 2
    /// The farthest a countdown's moment may lie ahead: 366 days, in seconds.
    static let maximumDistance: Double = 366 * 24 * 60 * 60
    /// The longest label, in characters.
    static let maximumLabelLength = 40
    /// How late, in seconds, an ending may be noticed and still ring. An ending noticed later
    /// than this (the Mac slept, holzBar was not running) is marked finished without a sound.
    static let lateTolerance: Double = 15
    /// The most a stopwatch counts, in seconds: 99 hours, 59 minutes and 59 seconds. Beyond it
    /// the display stays there.
    static let maximumElapsed: Double = 359_999

    /// Why a timer could not be started.
    nonisolated enum Refusal: Equatable, Sendable {
        case full
        case lengthOutOfRange
        case momentTooSoon
        case momentTooFar
    }

    /// The result of starting a timer.
    nonisolated enum StartResult: Equatable, Sendable {
        case started(UUID)
        case refused(Refusal)
    }

    /// The timers that ended since the last look, in the order they ended.
    struct Finished: Equatable, Sendable {
        /// Ended at most ``TimerBoard/lateTolerance`` seconds ago: the sound rings.
        var rang: [UUID] = []
        /// Ended earlier: finished silently.
        var missed: [UUID] = []
    }

    /// The timers in the order they were added.
    private(set) var items: [TimerItem] = []

    /// Starts a timer for a length of time, running from `now`.
    ///
    /// The length must be finite and between ``minimumLength`` and ``maximumLength``; otherwise
    /// the start is refused and the board does not change. On a full board the oldest finished
    /// timer makes room; with none finished the start is refused as ``Refusal/full``.
    @discardableResult
    mutating func startLength(_ seconds: Double, label: String, now: Date, id: UUID = UUID()) -> StartResult {
        guard seconds.isFinite, seconds >= Self.minimumLength, seconds <= Self.maximumLength else {
            return .refused(.lengthOutOfRange)
        }
        guard makeRoom() else {
            return .refused(.full)
        }
        items.append(
            TimerItem(
                id: id,
                label: Self.cleanLabel(label),
                kind: .length(seconds),
                state: .running(start: now, end: now.addingTimeInterval(seconds))
            )
        )
        return .started(id)
    }

    /// Starts a countdown to a moment of the wall clock, running from `now`.
    ///
    /// The moment must lie between ``minimumLead`` seconds and ``maximumDistance`` seconds
    /// ahead of `now`; a moment that is not a finite date counts as too soon. A refusal leaves
    /// the board unchanged.
    @discardableResult
    mutating func startMoment(_ moment: Date, label: String, now: Date, id: UUID = UUID()) -> StartResult {
        let lead = moment.timeIntervalSince(now)
        guard lead.isFinite, lead >= Self.minimumLead else {
            return .refused(.momentTooSoon)
        }
        guard lead <= Self.maximumDistance else {
            return .refused(.momentTooFar)
        }
        guard makeRoom() else {
            return .refused(.full)
        }
        items.append(
            TimerItem(id: id, label: Self.cleanLabel(label), kind: .moment(moment), state: .running(start: now, end: moment))
        )
        return .started(id)
    }

    /// Starts a stopwatch that counts up from zero at `now`. The board's limit of timers
    /// applies; a stopwatch never finishes, so on a full board only a finished timer can make
    /// room.
    @discardableResult
    mutating func startStopwatch(label: String, now: Date, id: UUID = UUID()) -> StartResult {
        guard makeRoom() else {
            return .refused(.full)
        }
        items.append(TimerItem(id: id, label: Self.cleanLabel(label), kind: .stopwatch, state: .counting(since: now)))
        return .started(id)
    }

    /// Makes room for one more timer: nothing to do while the board is not full, otherwise the
    /// oldest finished timer (the one that finished first) goes. Returns whether there is room.
    private mutating func makeRoom() -> Bool {
        guard items.count >= Self.maximumItems else {
            return true
        }
        var oldest: (index: Int, at: Date)?
        for (index, item) in items.enumerated() {
            guard case .finished(let at) = item.state else {
                continue
            }
            if let current = oldest, current.at <= at {
                continue
            }
            oldest = (index, at)
        }
        guard let oldest else {
            return false
        }
        items.remove(at: oldest.index)
        return items.count < Self.maximumItems
    }

    /// Pauses a running timer of kind length and keeps the seconds left, or stops a counting
    /// stopwatch at its elapsed seconds. A countdown to a moment cannot be paused; a timer that
    /// is paused, finished or already at its end cannot either. Returns whether it was paused.
    @discardableResult
    mutating func pause(_ id: UUID, now: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        switch (items[index].kind, items[index].state) {
        case (.length(let total), .running(_, let end)) where end.timeIntervalSince(now) > 0:
            items[index].state = .paused(remaining: min(end.timeIntervalSince(now), total), total: total)
            return true
        case (.stopwatch, .counting(let since)):
            items[index].state = .halted(elapsed: Self.elapsed(since: since, now: now))
            return true
        default:
            return false
        }
    }

    /// The seconds a stopwatch has counted since `since`, kept from 0 to ``maximumElapsed``.
    private static func elapsed(since: Date, now: Date) -> Double {
        let seconds = now.timeIntervalSince(since)
        return seconds.isFinite ? min(max(seconds, 0), maximumElapsed) : 0
    }

    /// Runs a paused timer again from `now` for the seconds it had left, its start moving so
    /// that the progress stays right, or lets a stopped stopwatch count on from where it
    /// stopped. Returns whether the timer was resumed.
    @discardableResult
    mutating func resume(_ id: UUID, now: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        switch items[index].state {
        case .paused(let remaining, let total):
            items[index].state = .running(
                start: now.addingTimeInterval(remaining - total),
                end: now.addingTimeInterval(remaining)
            )
            return true
        case .halted(let elapsed):
            items[index].state = .counting(since: now.addingTimeInterval(-elapsed))
            return true
        default:
            return false
        }
    }

    /// Runs a timer of kind length again for its full length from `now`, in whatever state it
    /// is in, or sets a stopwatch back to zero and counts on. A countdown to a moment cannot
    /// restart. Returns whether the timer was restarted.
    @discardableResult
    mutating func restart(_ id: UUID, now: Date) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        switch items[index].kind {
        case .length(let seconds):
            items[index].state = .running(start: now, end: now.addingTimeInterval(seconds))
            return true
        case .stopwatch:
            items[index].state = .counting(since: now)
            return true
        case .moment:
            return false
        }
    }

    /// Removes a timer. Returns whether there was one.
    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return false
        }
        items.remove(at: index)
        return true
    }

    /// Removes every finished timer. Returns whether there was one.
    @discardableResult
    mutating func removeFinished() -> Bool {
        let before = items.count
        items.removeAll { item in
            if case .finished = item.state {
                return true
            }
            return false
        }
        return items.count != before
    }

    /// The seconds left on a timer at `now`, or `nil` for an unknown timer.
    func remaining(of id: UUID, now: Date) -> Double? {
        guard let item = items.first(where: { $0.id == id }) else {
            return nil
        }
        switch item.state {
        case .running(_, let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining, _): return remaining
        case .finished, .counting, .halted: return 0
        }
    }

    /// The seconds a stopwatch has counted at `now`, or `nil` for a timer that is not one.
    func elapsed(of id: UUID, now: Date) -> Double? {
        guard let item = items.first(where: { $0.id == id }) else {
            return nil
        }
        switch item.state {
        case .counting(let since): return Self.elapsed(since: since, now: now)
        case .halted(let elapsed): return elapsed
        case .running, .paused, .finished: return nil
        }
    }

    /// How much of a timer has elapsed at `now`, from 0 to 1, or `nil` for an unknown timer.
    /// A finished timer is at 1, and so is a span of no length.
    func fraction(of id: UUID, now: Date) -> Double? {
        guard let item = items.first(where: { $0.id == id }) else {
            return nil
        }
        switch item.state {
        case .running(let start, let end):
            let span = end.timeIntervalSince(start)
            guard span > 0, span.isFinite else {
                return 1
            }
            return min(max(now.timeIntervalSince(start) / span, 0), 1)
        case .paused(let remaining, let total):
            guard total > 0 else {
                return 1
            }
            return min(max((total - remaining) / total, 0), 1)
        case .finished:
            return 1
        case .counting, .halted:
            return 0
        }
    }

    /// Whether any timer is running.
    var hasRunning: Bool {
        items.contains { item in
            if case .running = item.state {
                return true
            }
            return false
        }
    }

    /// The timers as the tab lists them: finished first (the latest end first), then running
    /// (the soonest end first), then counting stopwatches (the oldest first), then paused
    /// timers (the least time left first), then stopped stopwatches (the longest first). Timers
    /// with an equal key keep the order they were added in.
    var ordered: [TimerItem] {
        func key(_ item: TimerItem) -> (group: Int, value: Double) {
            switch item.state {
            case .finished(let at): (0, -at.timeIntervalSince1970)
            case .running(_, let end): (1, end.timeIntervalSince1970)
            case .counting(let since): (2, since.timeIntervalSince1970)
            case .paused(let remaining, _): (3, remaining)
            case .halted(let elapsed): (4, -elapsed)
            }
        }
        return items.enumerated()
            .sorted { first, second in
                let a = key(first.element)
                let b = key(second.element)
                if a.group != b.group {
                    return a.group < b.group
                }
                if a.value != b.value {
                    return a.value < b.value
                }
                return first.offset < second.offset
            }
            .map(\.element)
    }

    /// The timer the Overview shows: the first of ``ordered``.
    var leading: TimerItem? {
        ordered.first
    }

    /// The earliest end among the running timers, or `nil` when none runs.
    var nextDeadline: Date? {
        items.compactMap { item -> Date? in
            if case .running(_, let end) = item.state {
                return end
            }
            return nil
        }
        .min()
    }

    /// Marks every running timer whose end is not after `now` as finished at its end, and
    /// reports which of them ring and which ended too long ago to ring. A timer is reported
    /// once.
    mutating func collectFinished(now: Date) -> Finished {
        var ended = [(id: UUID, end: Date)]()
        for index in items.indices {
            if case .running(_, let end) = items[index].state, end <= now {
                items[index].state = .finished(at: end)
                ended.append((items[index].id, end))
            }
        }
        var result = Finished()
        for entry in ended.sorted(by: { $0.end < $1.end }) {
            if now.timeIntervalSince(entry.end) <= Self.lateTolerance {
                result.rang.append(entry.id)
            } else {
                result.missed.append(entry.id)
            }
        }
        return result
    }

    /// A label as the board keeps it: trimmed, line breaks turned into spaces, cut to
    /// ``maximumLabelLength`` characters. An empty label stays empty.
    static func cleanLabel(_ text: String) -> String {
        let flat = String(text.map { $0.isNewline ? " " : $0 })
        let trimmed = flat.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumLabelLength)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Stored form

    /// The most bytes of stored data that are read; a board of eight timers needs far less.
    private static let maximumStoredBytes = 262_144

    /// The largest absolute number of seconds a stored date may hold (year 5138); anything
    /// beyond is damaged data.
    private static let storedDateLimit: Double = 100_000_000_000

    /// The board in its stored form, version 1: a JSON object with the keys `version` and
    /// `items`. An item has `id` (the UUID as text), `label`, `kind` (`length` with `seconds`,
    /// or `moment` with `moment`) and `state` (`running` with `start` and `end`, `paused` with
    /// `remaining` and `total`, or `finished` with `at`); a stopwatch has the kind `stopwatch`
    /// and the state `counting` with `start`, or `halted` with `elapsed`. Dates are seconds since 1970. Keys
    /// may be added later; none is renamed.
    func encoded() -> Data {
        let stored = StoredBoard(version: 1, items: items.map { StoredEntry(StoredItem($0)) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(stored)) ?? Data()
    }

    /// The board a stored form describes.
    ///
    /// Never fails and never traps: anything that is not a version 1 object gives an empty
    /// board. Every item is read on its own and kept only when it passes every limit of the
    /// rules (a known kind and state, finite numbers inside their ranges, an `end` after the
    /// `start`, an identifier not seen before); the others are dropped. At most
    /// ``maximumItems`` items are kept, the first ones.
    static func decoded(from data: Data?) -> TimerBoard {
        guard
            let data, !data.isEmpty, data.count <= maximumStoredBytes,
            let stored = try? JSONDecoder().decode(StoredBoard.self, from: data),
            stored.version == 1
        else {
            return TimerBoard()
        }
        var board = TimerBoard()
        var seen = Set<UUID>()
        for entry in stored.items {
            guard board.items.count < maximumItems else {
                break
            }
            guard let item = entry.item.flatMap(Self.timerItem(from:)), seen.insert(item.id).inserted else {
                continue
            }
            board.items.append(item)
        }
        return board
    }

    /// Whether a stored number is a date this code could have written.
    private static func isPlausible(_ seconds: Double?) -> Bool {
        guard let seconds else {
            return false
        }
        return seconds.isFinite && abs(seconds) <= storedDateLimit
    }

    private static func isValidLength(_ seconds: Double) -> Bool {
        seconds.isFinite && seconds >= minimumLength && seconds <= maximumLength
    }

    /// The timer a stored item describes, or `nil` when it breaks a rule.
    private static func timerItem(from stored: StoredItem) -> TimerItem? {
        guard let id = UUID(uuidString: stored.id) else {
            return nil
        }
        let kind: TimerItem.Kind
        switch stored.kind {
        case "length":
            guard let seconds = stored.seconds, isValidLength(seconds) else {
                return nil
            }
            kind = .length(seconds)
        case "moment":
            guard let moment = stored.moment, isPlausible(moment) else {
                return nil
            }
            kind = .moment(Date(timeIntervalSince1970: moment))
        case "stopwatch":
            kind = .stopwatch
        default:
            return nil
        }
        // A stopwatch is counting or halted and nothing else; a timer is never either.
        let isStopwatch = kind == .stopwatch
        guard isStopwatch == (stored.state == "counting" || stored.state == "halted") else {
            return nil
        }
        let state: TimerItem.State
        switch stored.state {
        case "counting":
            guard let since = stored.start, isPlausible(since) else {
                return nil
            }
            state = .counting(since: Date(timeIntervalSince1970: since))
        case "halted":
            guard let elapsed = stored.elapsed, elapsed.isFinite, elapsed >= 0, elapsed <= maximumElapsed else {
                return nil
            }
            state = .halted(elapsed: elapsed)
        case "running":
            guard
                let start = stored.start, let end = stored.end,
                isPlausible(start), isPlausible(end), end > start
            else {
                return nil
            }
            let longest: Double
            if case .length = kind {
                longest = maximumLength
            } else {
                longest = maximumDistance
            }
            guard end - start <= longest else {
                return nil
            }
            state = .running(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        case "paused":
            guard
                case .length = kind,
                let remaining = stored.remaining, let total = stored.total,
                isValidLength(total), remaining.isFinite, remaining > 0, remaining <= total
            else {
                return nil
            }
            state = .paused(remaining: remaining, total: total)
        case "finished":
            guard let at = stored.at, isPlausible(at) else {
                return nil
            }
            state = .finished(at: Date(timeIntervalSince1970: at))
        default:
            return nil
        }
        return TimerItem(id: id, label: cleanLabel(stored.label ?? ""), kind: kind, state: state)
    }
}

/// The stored form of a board: the object that is written and read as JSON.
private nonisolated struct StoredBoard: Codable {
    var version: Int
    var items: [StoredEntry]
}

/// One entry of the stored list. Reading it never throws, so one damaged item cannot take
/// the others with it: it reads as `nil`.
private nonisolated struct StoredEntry: Codable {
    var item: StoredItem?

    init(_ item: StoredItem) {
        self.item = item
    }

    init(from decoder: any Decoder) throws {
        item = try? StoredItem(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try item?.encode(to: encoder)
    }
}

/// One timer in its stored form. Every number is optional: which ones a kind and a state need
/// is checked when the item is read.
private nonisolated struct StoredItem: Codable {
    var id: String
    var label: String?
    var kind: String
    var seconds: Double?
    var moment: Double?
    var state: String
    var start: Double?
    var end: Double?
    var remaining: Double?
    var total: Double?
    var at: Double?
    var elapsed: Double?

    init(_ item: TimerItem) {
        id = item.id.uuidString
        label = item.label
        switch item.kind {
        case .length(let length):
            kind = "length"
            seconds = length
        case .moment(let date):
            kind = "moment"
            moment = date.timeIntervalSince1970
        case .stopwatch:
            kind = "stopwatch"
        }
        switch item.state {
        case .running(let startDate, let endDate):
            state = "running"
            start = startDate.timeIntervalSince1970
            end = endDate.timeIntervalSince1970
        case .paused(let kept, let all):
            state = "paused"
            remaining = kept
            total = all
        case .finished(let date):
            state = "finished"
            at = date.timeIntervalSince1970
        case .counting(let since):
            state = "counting"
            start = since.timeIntervalSince1970
        case .halted(let seconds):
            state = "halted"
            elapsed = seconds
        }
    }
}
