//
//  MediaKeyPress.swift
//  holzBar
//

import Foundation

/// The five keys holzBar may take from macOS while Replace the system display is on (Phase 96,
/// D-02, D-21).
///
/// These are the values of `NX_KEYTYPE_SOUND_UP`, `NX_KEYTYPE_SOUND_DOWN`,
/// `NX_KEYTYPE_BRIGHTNESS_UP`, `NX_KEYTYPE_BRIGHTNESS_DOWN` and `NX_KEYTYPE_MUTE` of IOKit's
/// `hidsystem/ev_keymap.h`. It is a type of its own and not a set of new cases on ``MediaKey``,
/// because that enum is the poster of play, next and previous and is iterated as such. The
/// transport keys are never taken, never decoded and never listed here: every other key of a
/// system-defined event passes through unchanged.
nonisolated enum MediaKeyCode: Int, CaseIterable, Sendable {
    /// `NX_KEYTYPE_SOUND_UP`.
    case soundUp = 0
    /// `NX_KEYTYPE_SOUND_DOWN`.
    case soundDown = 1
    /// `NX_KEYTYPE_BRIGHTNESS_UP`.
    case brightnessUp = 2
    /// `NX_KEYTYPE_BRIGHTNESS_DOWN`.
    case brightnessDown = 3
    /// `NX_KEYTYPE_MUTE`.
    case mute = 7
}

/// A press, repeat or release of one of the five keys, decoded from a system-defined event.
///
/// Only the subtype and `data1` of the event are read, and only the five codes of
/// ``MediaKeyCode`` are kept: any other key, such as play, next or previous, decodes to `nil`
/// (D-02, T-96-36). Nothing here reads or keeps anything else of an event.
nonisolated struct MediaKeyPress: Equatable, Sendable {
    /// `NX_SYSDEFINED`: the type of the events that carry these keys (`IOLLEvent.h`).
    static let systemDefinedType: UInt32 = 14

    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`: the subtype of such an event that carries a media or
    /// function key.
    static let auxControlSubtype = 8

    /// The state byte of a press and of a release, in the second byte of the key's flags.
    private static let downState = 0xA
    private static let upState = 0xB

    /// The bit of the key's flags that marks an automatic repeat of a held key.
    private static let repeatBit = 0x1

    /// Which of the five keys.
    let code: MediaKeyCode

    /// Whether the key went down (`true`) or came up (`false`).
    let isDown: Bool

    /// Whether this down is an automatic repeat of a held key.
    let isRepeat: Bool

    /// Decodes the subtype and `data1` of a system-defined event. The result is `nil` for another
    /// subtype, for a key that is not one of the five and for a state that is neither down nor up.
    ///
    /// `data1` holds the key code in its upper 16 bits and the flags in its lower 16: the state
    /// (0xA down, 0xB up) in the second byte and the repeat marker in the lowest bit.
    init?(subtype: Int, data1: Int) {
        guard subtype == Self.auxControlSubtype else {
            return nil
        }
        let keyCode = (data1 >> 16) & 0xFFFF
        let flags = data1 & 0xFFFF
        guard let code = MediaKeyCode(rawValue: keyCode) else {
            return nil
        }
        let state = (flags >> 8) & 0xFF
        guard state == Self.downState || state == Self.upState else {
            return nil
        }
        self.code = code
        isDown = state == Self.downState
        isRepeat = isDown && flags & Self.repeatBit != 0
    }
}

/// The one rule that decides whether holzBar takes a key, and the steps a taken key makes
/// (Phase 96, D-02, D-20, D-21, D-22).
///
/// holzBar takes a key only when it can perform it and show its own indicator for it. The same
/// answer decides the consumption and the indicator, so no key is swallowed without being
/// performed and no indicator shows for a key that was passed (T-96-29). Every case that is not
/// known to be fine passes the key to macOS unchanged. A release is taken exactly when its press
/// was, so the system's display never sees half a press.
nonisolated enum MediaKeyRule {
    /// What a brightness key would change on the display under the pointer.
    nonisolated enum Target: Equatable, Sendable {
        /// The built-in display, whose brightness holzBar can change or not.
        case builtIn(canChange: Bool)
        /// An external monitor: whether it answers a DDC brightness read (`nil` until it was
        /// asked).
        case external(answersBrightness: Bool?)
        /// Not known: the keys that need a target pass.
        case unknown
    }

    /// Everything the rule depends on, read from one snapshot of the Mac.
    nonisolated struct Context: Equatable, Sendable {
        /// Replace the system display is on.
        var replaceOn = false
        /// holzBar holds Accessibility and the tap is trusted.
        var trusted = false
        /// A hub may show on the display under the pointer.
        var hubAllowed = false
        /// A full-screen Space is active.
        var fullScreenSpace = false
        /// The menu bar is hidden by the system.
        var menuBarHidden = false
        /// The screen is mirrored or shared.
        var mirroredOrShared = false
        /// The Mac woke, or its displays changed, less than the wake wait ago.
        var inWakeWait = false
        /// The default output has a volume holzBar can set.
        var outputSettable = false
        /// The default output has a mute holzBar can set.
        var muteSettable = false
        /// Display controls' Brightness switch is on.
        var brightnessSwitchOn = false
        /// Display controls' External monitors (DDC) switch is on.
        var externalSwitchOn = false
        /// The Display controls module is on.
        var displayControlsOn = false
        /// The display under the pointer is dimmed by software only (it has no DDC brightness).
        var softwareDimmedOnly = false
        /// What the brightness keys would change.
        var target = Target.unknown

        init() {}
    }

    /// Apple's step of a volume or brightness key: 1/16. A binary fraction, so a held key never
    /// drifts.
    static let fullStep = 1.0 / 16

    /// The step with Option and Shift held: 1/64, also a binary fraction.
    static let quarterStep = 1.0 / 64

    /// The lowest brightness a key sets: 2 %, so a held key never switches a display to black.
    static let brightnessFloor = 0.02

    /// Whether holzBar takes the key.
    ///
    /// - Parameters:
    ///   - press: The decoded press.
    ///   - context: What is true about the Mac.
    ///   - downWasTaken: Whether the matching press was taken (a release, and a repeat of a held
    ///     key, follow it exactly), `false` when there is no record of one.
    static func takes(_ press: MediaKeyPress, in context: Context, downWasTaken: Bool) -> Bool {
        // A release and a repeat follow the press they belong to: the decision is made once.
        guard press.isDown, !press.isRepeat else {
            return downWasTaken
        }
        guard
            context.replaceOn,
            context.trusted,
            context.hubAllowed,
            !context.fullScreenSpace,
            !context.menuBarHidden,
            !context.mirroredOrShared,
            !context.inWakeWait
        else {
            return false
        }
        switch press.code {
        case .soundUp, .soundDown:
            return context.outputSettable
        case .mute:
            return context.outputSettable && context.muteSettable
        case .brightnessUp, .brightnessDown:
            return brightnessIsPerformable(context)
        }
    }

    /// Whether a brightness key that passes should make holzBar ask the external monitor under the
    /// pointer once whether it answers DDC brightness: a first press, with everything else in
    /// place, on a monitor whose answer is not known yet in this session. The key itself passes to
    /// macOS (holzBar never swallows a key it might not perform); the asking is the user's own
    /// request for a change, which the DDC rules allow (D-22).
    static func needsSurvey(_ press: MediaKeyPress, in context: Context) -> Bool {
        guard
            press.isDown,
            !press.isRepeat,
            press.code == .brightnessUp || press.code == .brightnessDown,
            context.replaceOn,
            context.trusted,
            context.hubAllowed,
            !context.fullScreenSpace,
            !context.menuBarHidden,
            !context.mirroredOrShared,
            !context.inWakeWait,
            context.displayControlsOn,
            context.externalSwitchOn
        else {
            return false
        }
        return context.target == .external(answersBrightness: nil)
    }

    /// Whether a held key repeats its action. The volume and brightness keys move one step per
    /// repeat; the mute key acts once per press, so holding it never toggles the sound back and
    /// forth (a repeat of a taken mute is consumed and does nothing).
    static func repeatsWhileHeld(_ code: MediaKeyCode) -> Bool {
        switch code {
        case .soundUp, .soundDown, .brightnessUp, .brightnessDown:
            true
        case .mute:
            false
        }
    }

    /// Whether holzBar can change the brightness of the display under the pointer.
    private static func brightnessIsPerformable(_ context: Context) -> Bool {
        guard context.displayControlsOn else {
            return false
        }
        switch context.target {
        case .builtIn(let canChange):
            return canChange && context.brightnessSwitchOn
        case .external(let answersBrightness):
            return answersBrightness == true && context.externalSwitchOn && !context.softwareDimmedOnly
        case .unknown:
            return false
        }
    }

    /// The level after one press of a key: a step up or down, kept in 0 to 1 for the volume and
    /// between the 2 % floor and 1 for the brightness. The mute key does not move a level.
    ///
    /// - Parameter quarter: Option and Shift are held: the step is 1/64, not 1/16.
    static func next(level: Double, code: MediaKeyCode, quarter: Bool) -> Double {
        let step = quarter ? quarterStep : fullStep
        switch code {
        case .soundUp:
            return min(max(level + step, 0), 1)
        case .soundDown:
            return min(max(level - step, 0), 1)
        case .brightnessUp:
            return min(max(level + step, brightnessFloor), 1)
        case .brightnessDown:
            return min(max(level - step, brightnessFloor), 1)
        case .mute:
            return level
        }
    }
}
