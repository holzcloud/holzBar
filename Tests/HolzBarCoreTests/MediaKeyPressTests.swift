import Foundation
import Testing
@testable import HolzBarCore

@Suite("MediaKeyPress")
struct MediaKeyPressTests {
    private let subtype = 8

    /// A context in which every key of the volume group is taken.
    private func readyContext() -> MediaKeyRule.Context {
        var context = MediaKeyRule.Context()
        context.replaceOn = true
        context.trusted = true
        context.hubAllowed = true
        context.outputSettable = true
        context.muteSettable = true
        return context
    }

    private func press(_ code: MediaKeyCode, isDown: Bool = true, isRepeat: Bool = false) -> MediaKeyPress {
        let state = isDown ? 0xA : 0xB
        let data1 = (code.rawValue << 16) | (state << 8) | (isRepeat ? 1 : 0)
        guard let press = MediaKeyPress(subtype: subtype, data1: data1) else {
            preconditionFailure("The press of \(code) did not decode")
        }
        return press
    }

    // MARK: Decoding

    @Test("The five keys decode with their state and repeat flag")
    func decodesTheFiveKeys() {
        let soundUp = MediaKeyPress(subtype: subtype, data1: (0 << 16) | (0xA << 8))
        #expect(soundUp?.code == .soundUp)
        #expect(soundUp?.isDown == true)
        #expect(soundUp?.isRepeat == false)

        let soundDownUp = MediaKeyPress(subtype: subtype, data1: (1 << 16) | (0xB << 8))
        #expect(soundDownUp?.code == .soundDown)
        #expect(soundDownUp?.isDown == false)

        let muteRepeat = MediaKeyPress(subtype: subtype, data1: (7 << 16) | (0xA << 8) | 1)
        #expect(muteRepeat?.code == .mute)
        #expect(muteRepeat?.isDown == true)
        #expect(muteRepeat?.isRepeat == true)

        #expect(MediaKeyPress(subtype: subtype, data1: (2 << 16) | (0xA << 8))?.code == .brightnessUp)
        #expect(MediaKeyPress(subtype: subtype, data1: (3 << 16) | (0xA << 8))?.code == .brightnessDown)
    }

    @Test("Play, next, previous and unknown keys never decode")
    func transportKeysAreNotDecoded() {
        for code in MediaKey.allCases {
            #expect(MediaKeyPress(subtype: subtype, data1: code.eventData(isDown: true)) == nil)
            #expect(MediaKeyPress(subtype: subtype, data1: code.eventData(isDown: false)) == nil)
        }
        #expect(MediaKeyPress(subtype: subtype, data1: (4 << 16) | (0xA << 8)) == nil)
        #expect(MediaKeyPress(subtype: subtype, data1: (5 << 16) | (0xA << 8)) == nil)
    }

    @Test("Another subtype and another state byte give nothing")
    func otherSubtypesAndStates() {
        #expect(MediaKeyPress(subtype: 0, data1: (0 << 16) | (0xA << 8)) == nil)
        #expect(MediaKeyPress(subtype: 7, data1: (0 << 16) | (0xA << 8)) == nil)
        #expect(MediaKeyPress(subtype: subtype, data1: (0 << 16) | (0xC << 8)) == nil)
        #expect(MediaKeyPress(subtype: subtype, data1: (0 << 16) | (0x9 << 8)) == nil)
        #expect(MediaKeyPress(subtype: subtype, data1: 0) == nil)
        #expect(MediaKeyPress(subtype: subtype, data1: -1) == nil)
    }

    @Test("The repeat bit belongs to a press, never to a release")
    func repeatIsOnlyForDowns() {
        let release = MediaKeyPress(subtype: subtype, data1: (0 << 16) | (0xB << 8) | 1)
        #expect(release?.isDown == false)
        #expect(release?.isRepeat == false)
    }

    @Test("Only the five keys are ever listed, and the poster's keys are different")
    func theFiveCodes() {
        #expect(MediaKeyCode.allCases.map(\.rawValue).sorted() == [0, 1, 2, 3, 7])
        let transport = Set(MediaKey.allCases.map(\.rawValue))
        #expect(transport.isDisjoint(with: Set(MediaKeyCode.allCases.map(\.rawValue))))
        #expect(MediaKeyPress.systemDefinedType == 14)
        #expect(MediaKeyPress.auxControlSubtype == MediaKey.systemDefinedSubtype)
    }

    // MARK: Taking

    @Test("With every condition met the volume keys and mute are taken")
    func takesTheVolumeGroup() {
        let context = readyContext()
        for code in [MediaKeyCode.soundUp, .soundDown, .mute] {
            #expect(MediaKeyRule.takes(press(code), in: context, downWasTaken: false))
        }
    }

    @Test("Each missing condition passes every key")
    func eachConditionPasses() {
        let breakers: [(String, (inout MediaKeyRule.Context) -> Void)] = [
            ("replace off", { $0.replaceOn = false }),
            ("not trusted", { $0.trusted = false }),
            ("hub not allowed", { $0.hubAllowed = false }),
            ("full-screen Space", { $0.fullScreenSpace = true }),
            ("menu bar hidden", { $0.menuBarHidden = true }),
            ("mirrored or shared", { $0.mirroredOrShared = true }),
            ("wake wait", { $0.inWakeWait = true }),
        ]
        for (name, breaker) in breakers {
            var context = readyContext()
            breaker(&context)
            for code in MediaKeyCode.allCases {
                #expect(
                    !MediaKeyRule.takes(press(code), in: context, downWasTaken: false),
                    "\(name) must pass \(code)"
                )
            }
        }
    }

    @Test("A volume key passes when the output has no settable volume, mute when it has no mute")
    func outputWithoutVolume() {
        var context = readyContext()
        context.outputSettable = false
        for code in [MediaKeyCode.soundUp, .soundDown, .mute] {
            #expect(!MediaKeyRule.takes(press(code), in: context, downWasTaken: false))
        }
        context = readyContext()
        context.muteSettable = false
        #expect(MediaKeyRule.takes(press(.soundUp), in: context, downWasTaken: false))
        #expect(!MediaKeyRule.takes(press(.mute), in: context, downWasTaken: false))
    }

    @Test("Brightness on the built-in display needs Display controls, its switch and a settable display")
    func builtInBrightness() {
        var context = readyContext()
        context.displayControlsOn = true
        context.brightnessSwitchOn = true
        context.target = .builtIn(canChange: true)
        #expect(MediaKeyRule.takes(press(.brightnessUp), in: context, downWasTaken: false))
        #expect(MediaKeyRule.takes(press(.brightnessDown), in: context, downWasTaken: false))

        var off = context
        off.displayControlsOn = false
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.brightnessSwitchOn = false
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.target = .builtIn(canChange: false)
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
    }

    @Test("Brightness on an external monitor needs DDC to answer, the switch and no software dimming only")
    func externalBrightness() {
        var context = readyContext()
        context.displayControlsOn = true
        context.externalSwitchOn = true
        context.target = .external(answersBrightness: true)
        #expect(MediaKeyRule.takes(press(.brightnessUp), in: context, downWasTaken: false))

        var off = context
        off.externalSwitchOn = false
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.softwareDimmedOnly = true
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.displayControlsOn = false
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.target = .external(answersBrightness: false)
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
        off = context
        off.target = .external(answersBrightness: nil)
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: off, downWasTaken: false))
    }

    @Test("An unknown target passes the brightness keys whatever else is on")
    func unknownTargetPasses() {
        var context = readyContext()
        context.displayControlsOn = true
        context.brightnessSwitchOn = true
        context.externalSwitchOn = true
        context.target = .unknown
        #expect(!MediaKeyRule.takes(press(.brightnessUp), in: context, downWasTaken: false))
        #expect(!MediaKeyRule.takes(press(.brightnessDown), in: context, downWasTaken: false))
        // The volume keys do not depend on the target.
        #expect(MediaKeyRule.takes(press(.soundUp), in: context, downWasTaken: false))
    }

    @Test("A release is taken exactly when its press was, whatever the context says")
    func releasePairsWithPress() {
        let context = readyContext()
        #expect(MediaKeyRule.takes(press(.soundUp, isDown: false), in: context, downWasTaken: true))
        #expect(!MediaKeyRule.takes(press(.soundUp, isDown: false), in: context, downWasTaken: false))
        // The context changed between the press and the release: the release still follows.
        let empty = MediaKeyRule.Context()
        #expect(MediaKeyRule.takes(press(.soundUp, isDown: false), in: empty, downWasTaken: true))
        #expect(!MediaKeyRule.takes(press(.mute, isDown: false), in: context, downWasTaken: false))
    }

    @Test("A repeat follows its press: one more step, never a second decision")
    func repeatFollowsPress() {
        let context = readyContext()
        #expect(MediaKeyRule.takes(press(.soundUp, isRepeat: true), in: context, downWasTaken: true))
        #expect(!MediaKeyRule.takes(press(.soundUp, isRepeat: true), in: context, downWasTaken: false))
        #expect(MediaKeyRule.takes(press(.soundUp, isRepeat: true), in: MediaKeyRule.Context(), downWasTaken: true))
    }

    @Test("An empty context takes nothing")
    func emptyContextPasses() {
        let context = MediaKeyRule.Context()
        for code in MediaKeyCode.allCases {
            #expect(!MediaKeyRule.takes(press(code), in: context, downWasTaken: false))
            #expect(!MediaKeyRule.takes(press(code, isDown: false), in: context, downWasTaken: false))
        }
    }

    // MARK: Steps

    @Test("The steps are binary fractions")
    func stepValues() {
        #expect(MediaKeyRule.fullStep == 0.0625)
        #expect(MediaKeyRule.quarterStep == 0.015625)
        #expect(MediaKeyRule.brightnessFloor == 0.02)
    }

    @Test("The volume steps by 1/16 or 1/64")
    func volumeSteps() {
        #expect(MediaKeyRule.next(level: 0.5, code: .soundUp, quarter: false) == 0.5625)
        #expect(MediaKeyRule.next(level: 0.5, code: .soundUp, quarter: true) == 0.515625)
        #expect(MediaKeyRule.next(level: 0.5, code: .soundDown, quarter: false) == 0.4375)
        #expect(MediaKeyRule.next(level: 0.5, code: .soundDown, quarter: true) == 0.484375)
    }

    @Test("The volume stops at 0 and at 1")
    func volumeBounds() {
        #expect(MediaKeyRule.next(level: 0.03, code: .soundDown, quarter: false) == 0)
        #expect(MediaKeyRule.next(level: 0, code: .soundDown, quarter: false) == 0)
        #expect(MediaKeyRule.next(level: 0.97, code: .soundUp, quarter: false) == 1)
        #expect(MediaKeyRule.next(level: 1, code: .soundUp, quarter: true) == 1)
    }

    @Test("The brightness stops at the 2 % floor and at 1")
    func brightnessBounds() {
        #expect(MediaKeyRule.next(level: 0.05, code: .brightnessDown, quarter: false) == 0.02)
        #expect(MediaKeyRule.next(level: 0.02, code: .brightnessDown, quarter: true) == 0.02)
        #expect(MediaKeyRule.next(level: 0.99, code: .brightnessUp, quarter: false) == 1)
        #expect(MediaKeyRule.next(level: 0.5, code: .brightnessUp, quarter: false) == 0.5625)
    }

    @Test("A held key walks the whole range without drifting")
    func heldKeyDoesNotDrift() {
        var level = 0.0
        for _ in 0..<16 {
            level = MediaKeyRule.next(level: level, code: .soundUp, quarter: false)
        }
        #expect(level == 1)
        for _ in 0..<64 {
            level = MediaKeyRule.next(level: level, code: .soundDown, quarter: true)
        }
        #expect(level == 0)
    }

    @Test("Mute moves no level")
    func muteKeepsTheLevel() {
        #expect(MediaKeyRule.next(level: 0.4, code: .mute, quarter: false) == 0.4)
    }
}
