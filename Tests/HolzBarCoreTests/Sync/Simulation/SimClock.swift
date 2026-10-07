import Foundation

/// The name of a simulated Mac: "A", "B", "C", ... Ordered, so every iteration is sorted.
struct SimMacName: Hashable, Comparable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let name: String

    init(_ name: String) { self.name = name }
    init(stringLiteral value: String) { name = value }

    static let A: SimMacName = "A"
    static let B: SimMacName = "B"
    static let C: SimMacName = "C"
    static let D: SimMacName = "D"

    static func < (lhs: SimMacName, rhs: SimMacName) -> Bool { lhs.name < rhs.name }

    var description: String { name }
}

/// Virtual time. One global clock in milliseconds that no Mac can see, plus a per-Mac offset.
/// A Mac only ever sees `wallClock(of:)`; nothing in the simulation reads the real clock.
struct SimClock: Sendable, Equatable {
    /// The wall clock of a Mac with no offset at global time 0 (an arbitrary but fixed instant).
    static let epochMilliseconds: Int64 = 1_790_000_000_000
    /// Offsets stay within plus or minus seven days (A2 section 6.3).
    static let maximumOffsetMilliseconds: Int64 = 7 * 24 * 3600 * 1000

    /// Global virtual milliseconds since the start of the run.
    private(set) var now: Int64 = 0
    private(set) var offsets: [SimMacName: Int64] = [:]

    init() {}

    /// Moves the global clock forward. Time never runs backwards globally; a Mac's clock can
    /// (through its offset), see `step(_:by:)`.
    mutating func advance(to target: Int64) {
        precondition(target >= now, "global time cannot run backwards")
        now = target
    }

    /// The per-Mac offset in milliseconds (0 when none was set).
    func offset(of mac: SimMacName) -> Int64 { offsets[mac] ?? 0 }

    mutating func setOffset(_ milliseconds: Int64, of mac: SimMacName) {
        offsets[mac] = max(-Self.maximumOffsetMilliseconds, min(Self.maximumOffsetMilliseconds, milliseconds))
    }

    /// `ClockStep`: the Mac's clock jumps by `delta` (also backwards), within the offset bounds.
    mutating func step(_ mac: SimMacName, by delta: Int64) {
        setOffset(offset(of: mac) + delta, of: mac)
    }

    /// The Mac's wall clock in milliseconds since 1970.
    func wallClockMilliseconds(of mac: SimMacName) -> Int64 {
        Self.epochMilliseconds + now + offset(of: mac)
    }

    /// The Mac's wall clock as the `Date` its code sees.
    func wallClock(of mac: SimMacName) -> Date {
        Date(timeIntervalSince1970: Double(wallClockMilliseconds(of: mac)) / 1000)
    }
}
