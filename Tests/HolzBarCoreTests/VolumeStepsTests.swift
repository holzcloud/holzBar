import Foundation
import Testing
@testable import HolzBarCore

@Suite("VolumeSteps")
struct VolumeStepsTests {
    @Test("The first reading is a baseline and reports nothing")
    func firstIsBaseline() {
        var steps = VolumeSteps()
        #expect(steps.offer(level: 0.5, isMuted: false) == nil)
    }

    @Test("A change of exactly a quarter step reports, one just below does not")
    func quarterStepEdge() {
        #expect(VolumeSteps.quarterStep == 1.0 / 64)
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        #expect(steps.offer(level: 0.5 + 1.0 / 64, isMuted: false) == .level(percent: 52))
        var drifting = VolumeSteps()
        _ = drifting.offer(level: 0.5, isMuted: false)
        #expect(drifting.offer(level: 0.5 + 1.0 / 64 - 0.0001, isMuted: false) == nil)
    }

    @Test("A downward step reports too")
    func downwardStep() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        #expect(steps.offer(level: 0.5 - 1.0 / 16, isMuted: false) == .level(percent: 44))
    }

    @Test("Small drifts never add up to a flash until they pass a quarter step from the last reported level")
    func driftsDoNotAddUp() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        #expect(steps.offer(level: 0.504, isMuted: false) == nil)
        #expect(steps.offer(level: 0.508, isMuted: false) == nil)
        #expect(steps.offer(level: 0.512, isMuted: false) == nil)
        // 0.516 is 0.016 from the last reported 0.5, which passes 1/64 = 0.015625.
        #expect(steps.offer(level: 0.516, isMuted: false) == .level(percent: 52))
        // The next drift is measured from 0.516 now.
        #expect(steps.offer(level: 0.52, isMuted: false) == nil)
    }

    @Test("Reaching the end of the range reports even when the step is smaller")
    func rangeEnds() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.99, isMuted: false)
        #expect(steps.offer(level: 1.0, isMuted: false) == .level(percent: 100))
        #expect(steps.offer(level: 1.0, isMuted: false) == nil)
        var low = VolumeSteps()
        _ = low.offer(level: 0.01, isMuted: false)
        #expect(low.offer(level: 0.0, isMuted: false) == .level(percent: 0))
        #expect(low.offer(level: 0.0, isMuted: false) == nil)
    }

    @Test("A mute toggle reports Muted, then the unmuted level")
    func muteToggle() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        #expect(steps.offer(level: 0.5, isMuted: true) == .muted)
        #expect(steps.offer(level: 0.5, isMuted: true) == nil)
        #expect(steps.offer(level: 0.5, isMuted: false) == .unmuted(percent: 50))
        #expect(steps.offer(level: 0.5, isMuted: false) == nil)
    }

    @Test("A step while muted keeps saying Muted")
    func stepWhileMuted() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: true)
        #expect(steps.offer(level: 0.6, isMuted: true) == .muted)
    }

    @Test("An output without a mute reads as not muted")
    func noMute() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: nil)
        #expect(steps.offer(level: 0.6, isMuted: nil) == .level(percent: 60))
    }

    @Test("An unreadable level reports nothing and keeps the baseline")
    func unreadableLevel() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        #expect(steps.offer(level: nil, isMuted: false) == nil)
        #expect(steps.offer(level: 0.5, isMuted: false) == nil)
        #expect(steps.offer(level: 0.6, isMuted: false) == .level(percent: 60))
        var fresh = VolumeSteps()
        #expect(fresh.offer(level: nil, isMuted: false) == nil)
        // The first readable one is still the baseline.
        #expect(fresh.offer(level: 0.5, isMuted: false) == nil)
    }

    @Test("Reset makes the next reading a baseline again")
    func resetBaseline() {
        var steps = VolumeSteps()
        _ = steps.offer(level: 0.5, isMuted: false)
        steps.reset()
        #expect(steps.offer(level: 0.9, isMuted: true) == nil)
        #expect(steps.offer(level: 0.9, isMuted: false) == .unmuted(percent: 90))
    }

    @Test("The percentage is rounded half away from zero and kept in 0 to 100")
    func percent() {
        #expect(VolumeSteps.percent(0.625) == 63)
        #expect(VolumeSteps.percent(0.004) == 0)
        #expect(VolumeSteps.percent(1.7) == 100)
        #expect(VolumeSteps.percent(-1) == 0)
        #expect(VolumeSteps.percent(.nan) == 0)
        #expect(VolumeSteps.percent(.infinity) == 0)
        #expect(VolumeSteps.percent(0.5) == 50)
        #expect(VolumeSteps.percent(1) == 100)
    }
}
