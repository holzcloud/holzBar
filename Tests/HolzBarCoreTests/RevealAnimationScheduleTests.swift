import Foundation
import Testing
@testable import HolzBarCore

@Suite("RevealAnimationSchedule")
struct RevealAnimationScheduleTests {
    @Test("A reveal from 800 to 18 has 11 steps that fall and end exactly at 18")
    func revealSteps() {
        let schedule = RevealAnimationSchedule.make(direction: .reveal, from: 800, to: 18)
        #expect(schedule.steps.count == 11)
        #expect(!schedule.isInstant)
        #expect(schedule.steps.last?.length == 18)
        #expect(abs((schedule.steps.last?.time ?? 0) - RevealAnimationSchedule.duration) < 1e-9)
        for (earlier, later) in zip(schedule.steps, schedule.steps.dropFirst()) {
            #expect(later.time > earlier.time)
            #expect(later.length <= earlier.length)
        }
        #expect(schedule.steps.allSatisfy { $0.length >= 18 && $0.length <= 800 })
    }

    @Test("A hide from 18 to 800 has 11 steps that rise and end exactly at 800")
    func hideSteps() {
        let schedule = RevealAnimationSchedule.make(direction: .hide, from: 18, to: 800)
        #expect(schedule.steps.count == 11)
        #expect(schedule.steps.last?.length == 800)
        for (earlier, later) in zip(schedule.steps, schedule.steps.dropFirst()) {
            #expect(later.time > earlier.time)
            #expect(later.length >= earlier.length)
        }
    }

    @Test("A schedule never runs longer than the design allows")
    func duration() {
        #expect(RevealAnimationSchedule.duration <= 0.4)
        let schedule = RevealAnimationSchedule.make(direction: .reveal, from: 100, to: 0)
        #expect((schedule.steps.last?.time ?? 0) <= 0.4)
    }

    @Test("The curves start at 0, end at 1 and never decrease")
    func easing() {
        for direction in [RevealAnimationSchedule.Direction.reveal, .hide] {
            #expect(RevealAnimationSchedule.eased(0, direction: direction) == 0)
            #expect(RevealAnimationSchedule.eased(1, direction: direction) == 1)
            let samples = (0...100).map { RevealAnimationSchedule.eased(Double($0) / 100, direction: direction) }
            for (earlier, later) in zip(samples, samples.dropFirst()) {
                #expect(later >= earlier)
            }
        }
        #expect(RevealAnimationSchedule.eased(0.5, direction: .reveal) > 0.5)
        #expect(RevealAnimationSchedule.eased(0.5, direction: .hide) < 0.5)
    }

    @Test("A fraction outside 0 through 1 is clamped")
    func easingClamps() {
        #expect(RevealAnimationSchedule.eased(-3, direction: .reveal) == 0)
        #expect(RevealAnimationSchedule.eased(7, direction: .hide) == 1)
    }

    @Test("Equal lengths, no duration, a wrong direction or a number that is not finite give no steps")
    func instantCases() {
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: 50, to: 50).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: 800, to: 18, duration: 0).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: 800, to: 18, duration: -1).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: 18, to: 800).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .hide, from: 800, to: 18).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: .nan, to: 18).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .reveal, from: 800, to: .infinity).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .hide, from: 18, to: .nan).isInstant)
        #expect(RevealAnimationSchedule.make(direction: .hide, from: 18, to: 800, duration: .nan).isInstant)
    }

    @Test("A very short duration still has one step that ends at the target")
    func shortDuration() {
        let schedule = RevealAnimationSchedule.make(direction: .reveal, from: 100, to: 10, duration: 0.001)
        #expect(schedule.steps.count == 1)
        #expect(schedule.steps.first?.length == 10)
    }

    @Test("The expanded length is the documented 10 000 points")
    func expandedLength() {
        #expect(RevealAnimationSchedule.expandedLength == 10_000)
    }

    @Test("The start length is the space between the application menus and the divider's right edge")
    func startLength() {
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 1400, applicationMenuMaxX: 600, endLength: 18) == 800)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 1400, applicationMenuMaxX: 600, endLength: 0) == 800)
    }

    @Test("There is no start length when there is nothing to travel")
    func startLengthNothingToTravel() {
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 618, applicationMenuMaxX: 600, endLength: 18) == nil)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 500, applicationMenuMaxX: 600, endLength: 18) == nil)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 600, applicationMenuMaxX: 600, endLength: 0) == nil)
    }

    @Test("A start length is at most the expanded length")
    func startLengthCapped() {
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 20_000, applicationMenuMaxX: 0, endLength: 18) == 10_000)
    }

    @Test("A start length from a number that is not finite, or an end below 0, is nil")
    func startLengthInvalid() {
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: .nan, applicationMenuMaxX: 600, endLength: 18) == nil)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 1400, applicationMenuMaxX: .infinity, endLength: 18) == nil)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 1400, applicationMenuMaxX: 600, endLength: .nan) == nil)
        #expect(RevealAnimationSchedule.startLength(dividerMaxX: 1400, applicationMenuMaxX: 600, endLength: -1) == nil)
    }
}
