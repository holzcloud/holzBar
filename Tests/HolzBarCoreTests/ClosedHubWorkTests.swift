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
            gesturesOn: true
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

    @Test("Every observer is reachable and each switch combination gives exactly what its rule names")
    func exhaustive() {
        var seen = Set<ClosedHubWork.Observer>()
        for bits in 0..<32 {
            let switches = Switches(
                hubOn: bits & 1 != 0,
                indicatorsOn: bits & 2 != 0,
                inputSourceOn: bits & 4 != 0,
                volumeBrightnessOn: bits & 8 != 0,
                gesturesOn: bits & 16 != 0
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
        }
        #expect(seen == Set(ClosedHubWork.Observer.allCases))
    }
}
