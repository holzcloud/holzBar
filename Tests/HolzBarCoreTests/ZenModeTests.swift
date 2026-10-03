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

    @Test("A URL turns Zen mode on by hand")
    func urlTurnsZenModeOn() {
        let on = ZenMode().requested(byURL: .turnOn)
        #expect(on == ZenMode(isManual: true, isAutomatic: false))
        #expect(ZenMode().requested(byURL: .toggle) == on)
        let presenting = ZenMode(isAutomatic: true).requested(byURL: .turnOn)
        #expect(presenting == ZenMode(isManual: true, isAutomatic: true))
    }

    @Test("A URL never ends the automatic part")
    func urlNeverEndsAutomaticZenMode() {
        for request in [ZenMode.Request.turnOff, .toggle] {
            let presenting = ZenMode(isManual: true, isAutomatic: true).requested(byURL: request)
            #expect(presenting.isAutomatic)
            #expect(presenting.isActive)
            #expect(!presenting.isManual)
            #expect(ZenMode(isAutomatic: true).requested(byURL: request).isActive)
        }
        let manualOnly = ZenMode(isManual: true).requested(byURL: .turnOff)
        #expect(!manualOnly.isActive)
    }
}
