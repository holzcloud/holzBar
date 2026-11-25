//
//  MediaKeyTap.swift
//  holzBar
//

import CoreGraphics
import Foundation
import OSLog

/// The session event tap for the media keys, on a thread of its own (Phase 96, D-21).
///
/// The tap exists only while ``IndicatorsRuntime`` keeps it: with the Notch hub, Indicators,
/// Volume and brightness and Replace the system display on and holzBar holding Accessibility
/// (``ClosedHubWork``). ``start()`` refuses without `AXIsProcessTrusted()`, so a tap is never made
/// without the permission, and ``stop()`` takes it out of the event stream at once.
///
/// Its callback runs on the tap's own thread and reads only ``MediaKeyState``, so a busy main
/// thread cannot make macOS disable it by timeout. When macOS does disable it the state answers
/// whether to enable it again (only while Accessibility holds); when the answer is no, the tap
/// removes itself and tells the runtime, which waits for the permission to return.
///
/// The callback takes a key only where ``MediaKeyState`` says so (the one rule,
/// ``MediaKeyRule/takes(_:in:downWasTaken:)``): it returns `nil` for a taken key and starts one task
/// on the main actor that calls ``onTaken`` for a press; every other event is returned unchanged.
/// The callback never waits for the main actor. Nothing about an event is logged.
@MainActor
final class MediaKeyTap {
    /// The type of system-defined events, which carry the media keys: `NX_SYSDEFINED` (14) in
    /// IOKit's `hidsystem/IOLLEvent.h`. Core Graphics names no case for it, so it is built from its
    /// raw value; the tap refuses to start if that ever fails.
    static let systemDefinedType = CGEventType(rawValue: 14)

    /// How long after the tap was lost, and between tries, holzBar looks again for Accessibility:
    /// 2 s, then 8 s later (D-21).
    static let trustRetryDelays: [Duration] = [.seconds(2), .seconds(8)]

    /// What the tap thread reads.
    private let state = MediaKeyState()

    /// Lets the tap's callbacks, which run off the main actor, reach the tap only from a task on
    /// the main actor.
    private let box = Box()

    /// Called on the main actor when the tap removed itself because Accessibility is gone.
    private let onTrustLost: @MainActor () -> Void

    /// Called on the main actor for every press (and every repeat) of a key that was taken, with
    /// the display under the pointer and whether Option and Shift were held (the quarter step).
    /// The release of a taken key is consumed and not reported.
    var onTaken: (@MainActor (MediaKeyPress, CGDirectDisplayID, Bool) -> Void)?

    /// Called on the main actor for a brightness press that passed to macOS on an external monitor
    /// whose DDC answer is not known yet, with that display: the runtime asks it once.
    var onSurveyNeeded: (@MainActor (CGDirectDisplayID) -> Void)?

    /// The tap, while it exists. Releasing it takes it out of the event stream and ends its thread.
    private var tap: EventTap?

    private static let logger = Logger(category: "MediaKeyTap")

    /// Whether the tap exists.
    var isRunning: Bool {
        tap != nil
    }

    /// How many times macOS disabled the tap since holzBar started, for Copy Diagnostics.
    static var disableCount: Int {
        MediaKeyState.disableCount
    }

    init(onTrustLost: @escaping @MainActor () -> Void) {
        self.onTrustLost = onTrustLost
        box.tap = self
    }

    /// Creates the tap and enables it, only while Accessibility is held. Starting a tap that
    /// already runs changes nothing.
    ///
    /// - Returns: `true` when the tap runs after the call.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else {
            return true
        }
        guard MediaKeyState.accessibilityIsTrusted(), let type = Self.systemDefinedType else {
            return false
        }
        let state = state
        let box = box
        state.update(trusted: true)
        let newTap = EventTap(
            types: [type],
            location: .sessionEventTap,
            placement: .headInsertEventTap,
            option: .defaultTap,
            runLoop: .ownThread(name: "com.holzcloud.holzBar.MediaKeys"),
            disabledHandler: { _ in
                let action = state.tapWasDisabled()
                if action == .stop {
                    Task { @MainActor in
                        box.tap?.trustWasLost()
                    }
                }
                return action
            },
            callback: { event in
                switch state.decide(event) {
                case .pass:
                    return event
                case .passAndSurvey(let display):
                    Task { @MainActor in
                        box.tap?.surveyWasNeeded(display)
                    }
                    return event
                case let .take(press, display, quarter):
                    // One hand-over to the main actor; the callback does not wait for it.
                    if press.isDown {
                        Task { @MainActor in
                            box.tap?.keyWasTaken(press, display: display, quarter: quarter)
                        }
                    }
                    return nil
                }
            }
        )
        guard newTap.isValid else {
            // macOS refused the tap (the permission can be gone between the check and here).
            state.update(trusted: false)
            return false
        }
        newTap.enable()
        tap = newTap
        Self.logger.notice("Media keys: the tap runs on its own thread")
        return true
    }

    /// Hands the tap thread a new snapshot of the Mac. Does nothing while no tap exists.
    func update(_ snapshot: MediaKeyState.Snapshot) {
        guard tap != nil else {
            return
        }
        state.update(snapshot)
    }

    /// Takes the tap out of the event stream. Removing a tap that does not exist changes nothing.
    func stop() {
        state.update(trusted: false)
        guard let tap else {
            return
        }
        // Disabled first, then released: the release removes the port and ends the thread.
        tap.disable()
        self.tap = nil
        Self.logger.notice("Media keys: the tap was removed")
    }

    /// A key was taken on the tap's thread: the runtime performs it. It is performed even when the
    /// tap was removed in the meantime, because the key was already consumed.
    private func keyWasTaken(_ press: MediaKeyPress, display: CGDirectDisplayID, quarter: Bool) {
        onTaken?(press, display, quarter)
    }

    /// A brightness key passed on an external monitor nobody asked yet: the runtime asks it.
    private func surveyWasNeeded(_ display: CGDirectDisplayID) {
        onSurveyNeeded?(display)
    }

    /// The tap removed itself because macOS disabled it with Accessibility gone: it is taken out
    /// of the event stream once and the runtime is told.
    private func trustWasLost() {
        guard tap != nil else {
            return
        }
        stop()
        onTrustLost()
    }
}

extension MediaKeyTap {
    /// Lets the tap's callbacks reach the tap from the main actor only.
    nonisolated final class Box: @unchecked Sendable {
        /// Set once on the main actor when the tap is made; read only from tasks on the main actor.
        weak var tap: MediaKeyTap?
    }
}
