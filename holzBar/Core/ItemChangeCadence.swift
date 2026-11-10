//
//  ItemChangeCadence.swift
//  holzBar
//

import Foundation

/// When events that may have changed the menu bar items force a read of the item list (D-18).
///
/// The list is read again once the events pause for a second; while they keep coming, a read is
/// forced ``forcedAfter`` seconds after the first event of the burst, so they cannot hold it up.
/// On macOS 27 every read asks every running process through Accessibility, and an item owner
/// that creates or destroys elements all the time (a busy Electron app such as Slack) would
/// force one every few seconds. So an app whose event would force a read can do so at most once
/// every ``forcedGapPerApp`` seconds; its events still wait for a quiet second, and the slow
/// fallback read still catches what they held back. Events without an app (a launch, a change
/// of space or screens) keep the 5 s rule, and so does another app that has not forced a read
/// lately. A process that launches or quits but cannot own an item itself, such as the helper
/// of a browser or an Electron app, which come and go with its tabs and windows, keeps the 5 s
/// rule too, except while an app of the burst is held back: it never forces the read the busy
/// app may not. The burst is shared, as before: a read reads every app.
///
/// Times are seconds of a monotonic clock, passed in, so the rules can be tested.
nonisolated struct ItemChangeCadence: Sendable {
    /// How long after the first event of a burst a read is forced while the events keep coming.
    static let forcedAfter: TimeInterval = 5

    /// The shortest time between two reads forced by the events of one app.
    static let forcedGapPerApp: TimeInterval = 30

    /// Where an event comes from.
    enum Source: Equatable, Sendable {
        /// An item owner whose elements changed, by process identifier.
        case app(Int32)
        /// An event that may change the items of any app: an app that may own an item launched
        /// or quit, the space or the screens changed.
        case system
        /// A process that cannot own an item itself launched or quit.
        case helper
    }

    /// What to do about one event.
    enum Decision: Equatable, Sendable {
        /// Read once the events pause for a second.
        case waitForQuiet
        /// Read now.
        case readNow
    }

    /// When the first event since the last read came, `nil` while none waits.
    private var burstStart: TimeInterval?

    /// Whether a forced read was held back in this burst, which is counted once.
    private var burstHeldBack = false

    /// The apps whose elements changed in this burst.
    private var burstApps = Set<Int32>()

    /// When each app last forced a read, by process identifier; only the last
    /// ``forcedGapPerApp`` seconds are kept.
    private var lastForcedReads = [Int32: TimeInterval]()

    /// How many reads the events forced. For diagnostics.
    private(set) var forcedReads = 0

    /// How many bursts had a forced read held back by the per-app gap. For diagnostics.
    private(set) var heldBack = 0

    /// How many apps forced a read in the last ``forcedGapPerApp`` seconds.
    var rememberedApps: Int {
        lastForcedReads.count
    }

    /// Notes an event that may have changed the items.
    ///
    /// - Parameters:
    ///   - pid: The process whose elements changed, `nil` for an event without an app.
    ///   - now: When the event came.
    /// - Returns: Whether to read now or once the events pause.
    mutating func noteEvent(pid: Int32?, at now: TimeInterval) -> Decision {
        noteEvent(pid.map(Source.app) ?? .system, at: now)
    }

    /// Notes an event that may have changed the items.
    ///
    /// - Parameters:
    ///   - source: Where the event comes from.
    ///   - now: When the event came.
    /// - Returns: Whether to read now or once the events pause.
    mutating func noteEvent(_ source: Source, at now: TimeInterval) -> Decision {
        lastForcedReads = lastForcedReads.filter { now - $0.value < Self.forcedGapPerApp }
        let start = burstStart ?? now
        if case .app(let pid) = source {
            burstApps.insert(pid)
        }
        guard now - start >= Self.forcedAfter else {
            burstStart = start
            return .waitForQuiet
        }
        switch source {
        case .app(let pid):
            guard lastForcedReads[pid] == nil else {
                return holdBack(start: start)
            }
            lastForcedReads[pid] = now
        case .helper:
            // A busy app of this burst may not force yet: neither may the helpers that come and
            // go with it.
            guard !burstApps.contains(where: { lastForcedReads[$0] != nil }) else {
                return holdBack(start: start)
            }
        case .system:
            break
        }
        forcedReads += 1
        didRead()
        return .readNow
    }

    /// Holds a forced read back; the burst goes on, and it is counted once.
    private mutating func holdBack(start: TimeInterval) -> Decision {
        burstStart = start
        if !burstHeldBack {
            burstHeldBack = true
            heldBack += 1
        }
        return .waitForQuiet
    }

    /// Notes that the list was read once the events paused, which ends the burst.
    mutating func didRead() {
        burstStart = nil
        burstHeldBack = false
        burstApps.removeAll()
    }
}
