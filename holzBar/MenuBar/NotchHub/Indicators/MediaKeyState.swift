//
//  MediaKeyState.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import OSLog
import os

/// What the media-key tap's own thread reads, and what it answers when macOS disables the tap
/// (Phase 96, D-21).
///
/// The tap of ``MediaKeyTap`` runs its callback on a thread of its own, so a busy main thread can
/// no longer make macOS disable it by timeout. Everything the callback reads lives here, behind
/// one lock, and none of it is main-actor state: a ``Snapshot`` that the main actor refreshes
/// through ``update(trusted:)``. A missing snapshot means the event passes.
///
/// This type must never name the main actor's state, directly or through a helper, and never wait
/// for the main thread: its methods run on the tap's thread, and with Swift 6 and main-actor
/// default isolation such a read would wait for the main thread (RESEARCH, Pitfall 3).
///
/// In this plan every event passes unchanged; the decoding and the keys that are taken come with
/// the next plans, here, behind the same snapshot.
nonisolated final class MediaKeyState: @unchecked Sendable {
    /// What the main actor tells the tap thread.
    struct Snapshot: Sendable {
        /// Whether the main actor holds Accessibility and keeps the tap. Without it, and before
        /// the main actor filled the snapshot in, every event passes.
        var isTrusted = false
    }

    /// How many times macOS disabled the media-key tap since holzBar started (a callback that
    /// took too long, or user input). Kept for Copy Diagnostics.
    private static let disables = OSAllocatedUnfairLock(initialState: 0)

    /// How many times macOS disabled the media-key tap since holzBar started.
    static var disableCount: Int {
        disables.withLock { $0 }
    }

    private static let logger = Logger(category: "MediaKeyTap")

    private let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())

    /// Whether holzBar holds the Accessibility permission right now.
    static func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Replaces the snapshot. Called on the main actor.
    func update(trusted: Bool) {
        snapshot.withLock { $0 = Snapshot(isTrusted: trusted) }
    }

    /// Answers macOS disabling the tap: the tap is enabled again only while holzBar still has
    /// Accessibility. Without it an enabled tap could hold input back, so it stays off, and the
    /// snapshot says so at once; the main actor then removes the tap and waits for the
    /// permission to return.
    func tapWasDisabled() -> EventTap.DisabledAction {
        Self.disables.withLock { $0 += 1 }
        guard Self.accessibilityIsTrusted() else {
            snapshot.withLock { $0 = Snapshot() }
            Self.logger.notice("Media keys: the tap was disabled and Accessibility is gone, leaving it off")
            return .stop
        }
        Self.logger.notice("Media keys: the tap was disabled, enabling it again")
        return .reenable
    }

    /// Decides what the tap does with an event: it returns it unchanged.
    ///
    /// Runs on the tap's thread, in microseconds: one lock read and nothing else. It reads no
    /// field of the event and logs nothing about it.
    func filter(_ event: CGEvent) -> CGEvent? {
        guard snapshot.withLock({ $0.isTrusted }) else {
            return event
        }
        // Every key passes in this plan; taking one needs the decoding of the next plan.
        return event
    }
}
