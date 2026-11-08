import Testing
@testable import HolzBarCore

@Suite("ItemPlaceholder")
struct ItemPlaceholderTests {
    @Test("A placeholder title is provisional while its app is young")
    func youngPlaceholderIsProvisional() {
        #expect(ItemPlaceholder.isProvisional(title: "Item-0", runningFor: .zero))
        #expect(ItemPlaceholder.isProvisional(title: "Item-0", runningFor: .seconds(10)))
        #expect(ItemPlaceholder.isProvisional(title: "Item-12", runningFor: .milliseconds(59_999)))
    }

    @Test("A placeholder title is not provisional after the period")
    func oldPlaceholderIsNotProvisional() {
        #expect(!ItemPlaceholder.isProvisional(title: "Item-0", runningFor: .seconds(60)))
        #expect(!ItemPlaceholder.isProvisional(title: "Item-0", runningFor: .seconds(61)))
        #expect(!ItemPlaceholder.isProvisional(title: "Item-3", runningFor: .seconds(3600)))
    }

    @Test("A real title is never provisional")
    func realTitleIsNotProvisional() {
        #expect(!ItemPlaceholder.isProvisional(title: "OneDrive", runningFor: .zero))
        #expect(!ItemPlaceholder.isProvisional(title: "Item-x", runningFor: .zero))
        #expect(!ItemPlaceholder.isProvisional(title: "Item-", runningFor: .zero))
        #expect(!ItemPlaceholder.isProvisional(title: "My Item-1", runningFor: .zero))
        #expect(!ItemPlaceholder.isProvisional(title: "", runningFor: .zero))
    }

    @Test("The schedule is the two launch re-checks and four provisional ones")
    func scheduleSteps() {
        #expect(ItemPlaceholder.launchRecheckDelays == [.milliseconds(1500), .seconds(2)])
        #expect(ItemPlaceholder.provisionalRecheckDelays == [.seconds(5), .seconds(15), .seconds(30), .seconds(12)])
    }

    @Test("Every delay is positive")
    func delaysArePositive() {
        for delay in ItemPlaceholder.launchRecheckDelays + ItemPlaceholder.provisionalRecheckDelays {
            #expect(delay > .zero)
        }
    }

    @Test("The last re-check falls after the provisional period, and only the last")
    func lastRecheckFollowsThePeriod() {
        let all = ItemPlaceholder.launchRecheckDelays + ItemPlaceholder.provisionalRecheckDelays
        let total = all.reduce(Duration.zero, +)
        let withoutLast = all.dropLast().reduce(Duration.zero, +)
        #expect(total > ItemPlaceholder.provisionalPeriod)
        #expect(withoutLast <= ItemPlaceholder.provisionalPeriod)
    }
}
