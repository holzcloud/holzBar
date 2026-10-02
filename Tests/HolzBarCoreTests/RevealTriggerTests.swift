import Testing
@testable import HolzBarCore

@Suite("RevealTrigger")
struct RevealTriggerTests {
    @Test("A rule fires when its condition starts")
    func firesWhenTheConditionStarts() {
        var trigger = RevealTrigger()
        #expect(trigger.update(true))
        #expect(trigger.isActive)
    }

    @Test("A rule does not fire again while its condition lasts")
    func doesNotFireAgainWhileTheConditionLasts() {
        var trigger = RevealTrigger()
        _ = trigger.update(true)
        #expect(!trigger.update(true))
    }

    @Test("A rule fires again after its condition ended")
    func firesAgainAfterTheConditionEnded() {
        var trigger = RevealTrigger()
        _ = trigger.update(true)
        #expect(!trigger.update(false))
        #expect(trigger.update(true))
    }

    @Test("The battery level is a whole percentage")
    func batteryLevelIsAWholePercentage() {
        #expect(RevealTrigger.percent(current: 37, maximum: 50) == 74)
        #expect(RevealTrigger.percent(current: 1, maximum: 3) == 33)
    }

    @Test("A battery without a maximum has no level")
    func batteryWithoutAMaximumHasNoLevel() {
        #expect(RevealTrigger.percent(current: 10, maximum: 0) == nil)
    }
}
