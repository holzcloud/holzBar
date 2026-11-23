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
            calendarAccess: true
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

    @Test("Every observer is reachable and each switch combination gives exactly what its rule names")
    func exhaustive() {
        var seen = Set<ClosedHubWork.Observer>()
        for bits in 0..<256 {
            let switches = Switches(
                hubOn: bits & 1 != 0,
                indicatorsOn: bits & 2 != 0,
                inputSourceOn: bits & 4 != 0,
                volumeBrightnessOn: bits & 8 != 0,
                gesturesOn: bits & 16 != 0,
                calendarOn: bits & 32 != 0,
                countdownOn: bits & 64 != 0,
                calendarAccess: bits & 128 != 0
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
        }
        #expect(seen == Set(ClosedHubWork.Observer.allCases))
    }
}
