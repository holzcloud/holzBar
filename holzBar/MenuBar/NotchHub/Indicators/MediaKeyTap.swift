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
/// In this plan every event passes unchanged: no key is taken, decoded or acted on, and nothing
/// about an event is logged.
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
                state.filter(event)
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
