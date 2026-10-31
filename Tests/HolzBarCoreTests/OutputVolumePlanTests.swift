import Testing
@testable import HolzBarCore

@Suite("OutputVolumePlan")
struct OutputVolumePlanTests {
    private func capabilities(
        virtualMain: Bool = false,
        mainScalar: Bool = false,
        channels: [UInt32] = [],
        mute: Bool = false
    ) -> OutputVolumePlan.Capabilities {
        OutputVolumePlan.Capabilities(
            virtualMainSettable: virtualMain,
            mainScalarSettable: mainScalar,
            settableChannels: channels,
            muteSettable: mute
        )
    }

    @Test("A settable virtual main volume wins whatever else is settable")
    func virtualMainWins() {
        #expect(OutputVolumePlan.resolve(capabilities(virtualMain: true, mainScalar: true, channels: [1, 2])) == .virtualMain)
        #expect(OutputVolumePlan.resolve(capabilities(virtualMain: true)) == .virtualMain)
    }

    @Test("Without a virtual main volume a settable main scalar volume is used")
    func mainScalarNext() {
        #expect(OutputVolumePlan.resolve(capabilities(mainScalar: true, channels: [1, 2])) == .mainScalar)
    }

    @Test("Without either, the settable channels are used, sorted and without duplicates")
    func channelsNext() {
        #expect(OutputVolumePlan.resolve(capabilities(channels: [2, 1, 1])) == .channels([1, 2]))
        #expect(OutputVolumePlan.resolve(capabilities(channels: [0, 2])) == .channels([2]))
    }

    @Test("An output with nothing settable is unsupported, and element 0 alone is not a channel")
    func unsupported() {
        #expect(OutputVolumePlan.resolve(capabilities()) == .unsupported)
        #expect(OutputVolumePlan.resolve(capabilities(channels: [0])) == .unsupported)
        #expect(OutputVolumePlan.resolve(capabilities(mute: true)) == .unsupported)
    }

    @Test("The combined level is the average of the finite values, clamped to 0 through 1")
    func combined() {
        #expect(OutputVolumePlan.combined([0.2, 0.4]) == 0.3)
        #expect(OutputVolumePlan.combined([0.5, .nan]) == 0.5)
        #expect(OutputVolumePlan.combined([1.4]) == 1)
        #expect(OutputVolumePlan.combined([-0.5]) == 0)
    }

    @Test("Without a finite value there is no combined level")
    func combinedWithoutValues() {
        #expect(OutputVolumePlan.combined([]) == nil)
        #expect(OutputVolumePlan.combined([.nan]) == nil)
        #expect(OutputVolumePlan.combined([.infinity, .nan]) == nil)
    }
}
