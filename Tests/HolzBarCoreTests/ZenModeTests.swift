import Testing
@testable import HolzBarCore

@Suite("ZenMode")
struct ZenModeTests {
    @Test("Off allows everything")
    func offAllowsEverything() {
        let zen = ZenMode()
        #expect(!zen.isActive)
        for trigger in ZenMode.Trigger.allCases {
            #expect(zen.allows(trigger))
        }
    }

    @Test("On locks the gestures")
    func onLocksTheGestures() {
        let zen = ZenMode(isManual: true)
        #expect(zen.isActive)
        let refused: [ZenMode.Trigger] = [.hover, .clickOnEmptyBar, .scroll, .revealRule, .urlCommand, .changeReveal]
        for trigger in refused {
            #expect(!zen.allows(trigger))
        }
        #expect(zen.allows(.holzBarIcon))
        #expect(zen.allows(.sectionHotkey))
    }

    @Test("Manual and automatic add up")
    func manualAndAutomaticAddUp() {
        var zen = ZenMode()
        zen.isManual = true
        zen.isAutomatic = true
        zen.isAutomatic = false
        #expect(zen.isActive)
        zen.isManual = false
        #expect(!zen.isActive)
        zen.isAutomatic = true
        #expect(zen.isActive)
        #expect(!zen.allows(.hover))
    }

    @Test("Toggling turns it on by hand and off entirely")
    func togglingTurnsItOnAndOff() {
        let on = ZenMode().toggled()
        #expect(on.isManual)
        #expect(on.isActive)
        #expect(!on.toggled().isActive)
        let presenting = ZenMode(isManual: false, isAutomatic: true)
        let off = presenting.toggled()
        #expect(!off.isActive)
        #expect(!off.isAutomatic)
    }
}
