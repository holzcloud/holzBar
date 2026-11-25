import Foundation
import Testing
@testable import HolzBarCore

@Suite("Closed hub work")
struct ClosedHubWorkTests {
    private typealias Switches = ClosedHubWork.Switches

    @Test("With every switch off nothing exists")
    func allOff() {
        #expect(ClosedHubWork.observers(Switches()).isEmpty)
    }

    @Test("With the hub off nothing exists, whatever the other switches say")
    func hubOff() {
        let rest = Switches(
            hubOn: false,
            indicatorsOn: true,
            inputSourceOn: true,
            volumeBrightnessOn: true,
            gesturesOn: true,
            calendarOn: true,
            countdownOn: true,
            calendarAccess: true,
            displayControlsOn: true,
            dimmedDisplays: 2
        )
        #expect(ClosedHubWork.observers(rest).isEmpty)
    }

    @Test("Input source gives the input source observer and the app activation observer")
    func inputSource() {
        let switches = Switches(hubOn: true, indicatorsOn: true, inputSourceOn: true)
        #expect(ClosedHubWork.observers(switches) == [.inputSource, .appActivation])
    }

    @Test("Volume and brightness gives the volume listener only")
    func volume() {
        let switches = Switches(hubOn: true, indicatorsOn: true, volumeBrightnessOn: true)
        #expect(ClosedHubWork.observers(switches) == [.volumeListener])
    }

    @Test("With the Indicators module off its two switches give nothing")
    func indicatorsOff() {
        let switches = Switches(hubOn: true, indicatorsOn: false, inputSourceOn: true, volumeBrightnessOn: true)
        #expect(ClosedHubWork.observers(switches).isEmpty)
    }

    @Test("Gestures give the scroll monitor only, and only with the hub on")
    func gestures() {
        #expect(ClosedHubWork.observers(Switches(hubOn: true, gesturesOn: true)) == [.scrollMonitor])
        #expect(ClosedHubWork.observers(Switches(hubOn: false, gesturesOn: true)).isEmpty)
        #expect(ClosedHubWork.observers(Switches(hubOn: true, indicatorsOn: true, gesturesOn: false)).isEmpty)
    }

    @Test("The countdown exists only with the hub, the Calendar module, the countdown on and Calendar access")
    func countdown() {
        let all = Switches(hubOn: true, calendarOn: true, countdownOn: true, calendarAccess: true)
        #expect(ClosedHubWork.observers(all) == [.countdown])
        // The lead Off.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, calendarOn: true, countdownOn: false, calendarAccess: true)).isEmpty)
        // No Calendar access.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, calendarOn: true, countdownOn: true, calendarAccess: false)).isEmpty)
        // The Calendar module off.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, calendarOn: false, countdownOn: true, calendarAccess: true)).isEmpty)
        // The hub off.
        #expect(ClosedHubWork.observers(Switches(hubOn: false, calendarOn: true, countdownOn: true, calendarAccess: true)).isEmpty)
    }

    @Test("The dim layers exist only with the hub on, Display controls on and a display dimmed")
    func dimLayers() {
        #expect(ClosedHubWork.observers(Switches(hubOn: true, displayControlsOn: true, dimmedDisplays: 1)) == [.dimLayers])
        #expect(ClosedHubWork.observers(Switches(hubOn: true, displayControlsOn: true, dimmedDisplays: 32)) == [.dimLayers])
        // No dimmed display: nothing observes.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, displayControlsOn: true, dimmedDisplays: 0)).isEmpty)
        // Display controls off: nothing observes, whatever the levels.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, displayControlsOn: false, dimmedDisplays: 3)).isEmpty)
        // Hub off: nothing exists.
        #expect(ClosedHubWork.observers(Switches(hubOn: false, displayControlsOn: true, dimmedDisplays: 3)).isEmpty)
    }

    @Test("The media-key tap exists only with the hub, Indicators, Volume and brightness, Replace the system display and trust")
    func mediaKeyTap() {
        let all = Switches(
            hubOn: true, indicatorsOn: true, volumeBrightnessOn: true,
            replaceSystemDisplayOn: true, accessibilityTrusted: true
        )
        #expect(ClosedHubWork.observers(all) == [.volumeListener, .mediaKeyTap])
        // Without Accessibility the tap never exists, the volume listener still does.
        var untrusted = all
        untrusted.accessibilityTrusted = false
        #expect(ClosedHubWork.observers(untrusted) == [.volumeListener])
        // Each other switch off removes it.
        var replaceOff = all
        replaceOff.replaceSystemDisplayOn = false
        #expect(!ClosedHubWork.observers(replaceOff).contains(.mediaKeyTap))
        var volumeOff = all
        volumeOff.volumeBrightnessOn = false
        #expect(ClosedHubWork.observers(volumeOff).isEmpty)
        var indicatorsOff = all
        indicatorsOff.indicatorsOn = false
        #expect(ClosedHubWork.observers(indicatorsOff).isEmpty)
        var hubOff = all
        hubOff.hubOn = false
        #expect(ClosedHubWork.observers(hubOff).isEmpty)
        // Trust and the replace switch alone give nothing.
        #expect(ClosedHubWork.observers(Switches(hubOn: true, replaceSystemDisplayOn: true, accessibilityTrusted: true)).isEmpty)
    }

    @Test("Every observer is reachable and each switch combination gives exactly what its rule names")
    func exhaustive() {
        var seen = Set<ClosedHubWork.Observer>()
        for bits in 0..<4096 {
            let switches = Switches(
                hubOn: bits & 1 != 0,
                indicatorsOn: bits & 2 != 0,
                inputSourceOn: bits & 4 != 0,
                volumeBrightnessOn: bits & 8 != 0,
                gesturesOn: bits & 16 != 0,
                calendarOn: bits & 32 != 0,
                countdownOn: bits & 64 != 0,
                calendarAccess: bits & 128 != 0,
                displayControlsOn: bits & 256 != 0,
                dimmedDisplays: bits & 512 != 0 ? 1 : 0,
                replaceSystemDisplayOn: bits & 1024 != 0,
                accessibilityTrusted: bits & 2048 != 0
            )
            let result = ClosedHubWork.observers(switches)
            seen.formUnion(result)
            // The hub off is always empty.
            if !switches.hubOn {
                #expect(result.isEmpty)
            }
            // The two input source observers always come and go together.
            #expect(result.contains(.inputSource) == result.contains(.appActivation))
            #expect(result.contains(.inputSource) == (switches.hubOn && switches.indicatorsOn && switches.inputSourceOn))
            #expect(result.contains(.volumeListener) == (switches.hubOn && switches.indicatorsOn && switches.volumeBrightnessOn))
            #expect(result.contains(.scrollMonitor) == (switches.hubOn && switches.gesturesOn))
            #expect(
                result.contains(.countdown)
                    == (switches.hubOn && switches.calendarOn && switches.countdownOn && switches.calendarAccess)
            )
            #expect(
                result.contains(.dimLayers)
                    == (switches.hubOn && switches.displayControlsOn && switches.dimmedDisplays > 0)
            )
            #expect(
                result.contains(.mediaKeyTap)
                    == (switches.hubOn && switches.indicatorsOn && switches.volumeBrightnessOn
                        && switches.replaceSystemDisplayOn && switches.accessibilityTrusted)
            )
        }
        #expect(seen == Set(ClosedHubWork.Observer.allCases))
    }
}
