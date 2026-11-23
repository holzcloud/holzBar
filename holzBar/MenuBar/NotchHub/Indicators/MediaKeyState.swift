//
//  MediaKeyState.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import AppKit
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
/// ``decide(_:)`` is the only place an event is read: it takes the subtype, `data1` and the Option
/// and Shift flags of a system-defined event, decodes ``MediaKeyPress`` (only the five keys of
/// ``MediaKeyCode``; play, next, previous and every other key decode to nothing and pass), and asks
/// ``MediaKeyRule/takes(_:in:downWasTaken:)``, the one rule. The tap records which key-downs it took,
/// so the key-up and every repeat of a held key follow their down exactly (D-21). Nothing about an
/// event is logged.
nonisolated final class MediaKeyState: @unchecked Sendable {
    /// What the tap does with an event.
    enum Decision: Equatable, Sendable {
        /// The key is taken: the event is consumed and, for a press, the display under the pointer
        /// and the step size (Option and Shift held) go to the main actor.
        case take(MediaKeyPress, display: CGDirectDisplayID, quarter: Bool)
        /// The event goes to macOS unchanged.
        case pass
        /// The event goes to macOS unchanged, and the main actor asks the external monitor under
        /// the pointer once whether it answers DDC brightness (the key was a first press on a
        /// monitor whose answer is not known yet).
        case passAndSurvey(display: CGDirectDisplayID)
    }

    /// What the main actor tells the tap thread.
    struct Snapshot: Sendable {
        /// One display, where the pointer may be.
        struct Display: Sendable {
            /// The display's identifier.
            var id: CGDirectDisplayID
            /// The display's bounds in the coordinates of a CGEvent's location (global, origin at
            /// the top left of the main display).
            var bounds: CGRect
            /// A hub may show an indicator on it.
            var hubAllowed: Bool
            /// What a brightness key would change on it.
            var target: MediaKeyRule.Target
            /// It is dimmed by software only.
            var softwareDimmedOnly: Bool

            init(
                id: CGDirectDisplayID,
                bounds: CGRect,
                hubAllowed: Bool,
                target: MediaKeyRule.Target = .unknown,
                softwareDimmedOnly: Bool = false
            ) {
                self.id = id
                self.bounds = bounds
                self.hubAllowed = hubAllowed
                self.target = target
                self.softwareDimmedOnly = softwareDimmedOnly
            }
        }

        /// Whether the main actor holds Accessibility and keeps the tap. Without it, and before
        /// the main actor filled the snapshot in, every event passes.
        var isTrusted = false
        /// Replace the system display is on.
        var replaceOn = false
        /// A full-screen Space is active.
        var fullScreenSpace = false
        /// The menu bar is hidden by the system.
        var menuBarHidden = false
        /// The screen is mirrored or shared.
        var mirroredOrShared = false
        /// When the Mac last woke or its displays last changed; the wake wait runs from it.
        var wakeGate = DDCWakeGate()
        /// The default output has a volume that can be set.
        var outputSettable = false
        /// The default output has a mute that can be set.
        var muteSettable = false
        /// Display controls' Brightness switch.
        var brightnessSwitchOn = false
        /// Display controls' External monitors (DDC) switch.
        var externalSwitchOn = false
        /// The Display controls module is on.
        var displayControlsOn = false
        /// The displays and what is true about each.
        var displays = [Display]()

        /// The context of the rule for a display, at a moment.
        func context(for display: Display, at instant: ContinuousClock.Instant) -> MediaKeyRule.Context {
            var context = MediaKeyRule.Context()
            context.replaceOn = replaceOn
            context.trusted = isTrusted
            context.hubAllowed = display.hubAllowed
            context.fullScreenSpace = fullScreenSpace
            context.menuBarHidden = menuBarHidden
            context.mirroredOrShared = mirroredOrShared
            context.inWakeWait = !wakeGate.isOpen(at: instant)
            context.outputSettable = outputSettable
            context.muteSettable = muteSettable
            context.brightnessSwitchOn = brightnessSwitchOn
            context.externalSwitchOn = externalSwitchOn
            context.displayControlsOn = displayControlsOn
            context.softwareDimmedOnly = display.softwareDimmedOnly
            context.target = display.target
            return context
        }
    }

    /// Everything the tap's thread reads and writes, behind one lock.
    private struct Shared {
        var snapshot = Snapshot()
        /// The keys whose down was taken and whose up has not come yet.
        var taken = Set<MediaKeyCode>()
    }

    /// How many times macOS disabled the media-key tap since holzBar started (a callback that
    /// took too long, or user input). Kept for Copy Diagnostics.
    private static let disables = OSAllocatedUnfairLock(initialState: 0)

    /// How many times macOS disabled the media-key tap since holzBar started.
    static var disableCount: Int {
        disables.withLock { $0 }
    }

    private static let logger = Logger(category: "MediaKeyTap")

    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    /// Whether holzBar holds the Accessibility permission right now.
    static func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Replaces the snapshot. Called on the main actor. The record of taken key-downs stays, so a
    /// key held while the snapshot is refreshed still pairs with its up.
    func update(_ snapshot: Snapshot) {
        shared.withLock { $0.snapshot = snapshot }
    }

    /// Replaces the snapshot with one that takes nothing (the tap starts or stops), and forgets
    /// the taken key-downs: with no tap there is no up to pair.
    func update(trusted: Bool) {
        shared.withLock {
            var snapshot = Snapshot()
            snapshot.isTrusted = trusted
            $0 = Shared(snapshot: snapshot)
        }
    }

    /// Answers macOS disabling the tap: the tap is enabled again only while holzBar still has
    /// Accessibility. Without it an enabled tap could hold input back, so it stays off, and the
    /// snapshot says so at once; the main actor then removes the tap and waits for the
    /// permission to return.
    func tapWasDisabled() -> EventTap.DisabledAction {
        Self.disables.withLock { $0 += 1 }
        guard Self.accessibilityIsTrusted() else {
            shared.withLock { $0 = Shared() }
            Self.logger.notice("Media keys: the tap was disabled and Accessibility is gone, leaving it off")
            return .stop
        }
        Self.logger.notice("Media keys: the tap was disabled, enabling it again")
        return .reenable
    }

    /// Decides what the tap does with an event.
    ///
    /// Runs on the tap's thread, in microseconds: it makes the event's `NSEvent` here, reads the
    /// subtype, `data1` and the Option and Shift flags, decodes the press and takes one lock, in
    /// which it reads the snapshot, asks the rule and records the taken down. It waits for nothing
    /// and logs nothing about the event. Every event that is not one of the five keys, and every
    /// case without a snapshot, passes.
    func decide(_ event: CGEvent) -> Decision {
        // Cheap before anything is allocated: nothing is trusted, nothing is taken.
        guard shared.withLock({ $0.snapshot.isTrusted }) else {
            return .pass
        }
        guard
            let nsEvent = NSEvent(cgEvent: event),
            nsEvent.type == .systemDefined,
            let press = MediaKeyPress(subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1)
        else {
            return .pass
        }
        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let quarter = flags.contains(.option) && flags.contains(.shift)
        let location = event.location
        let instant = ContinuousClock.now
        return shared.withLock { state in
            let downWasTaken = state.taken.contains(press.code)
            let display = state.snapshot.displays.first { $0.bounds.contains(location) }
            let takes: Bool
            var surveys = false
            if let display {
                let context = state.snapshot.context(for: display, at: instant)
                takes = MediaKeyRule.takes(press, in: context, downWasTaken: downWasTaken)
                surveys = !takes && MediaKeyRule.needsSurvey(press, in: context)
            } else {
                // No display under the pointer: a press passes, and a release or repeat follows
                // its press as the rule says.
                takes = (!press.isDown || press.isRepeat) && downWasTaken
            }
            if press.isDown, !press.isRepeat {
                if takes {
                    state.taken.insert(press.code)
                } else {
                    state.taken.remove(press.code)
                }
            } else if !press.isDown {
                state.taken.remove(press.code)
            }
            guard takes else {
                if surveys, let display {
                    return .passAndSurvey(display: display.id)
                }
                return .pass
            }
            return .take(press, display: display?.id ?? CGDirectDisplayID(0), quarter: quarter)
        }
    }
}
