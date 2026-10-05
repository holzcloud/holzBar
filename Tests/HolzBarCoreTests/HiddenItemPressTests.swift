import Testing
@testable import HolzBarCore

@Suite("HiddenItemPress")
struct HiddenItemPressTests {
    @Test("A press the app performed is taken")
    func successIsTaken() {
        #expect(HiddenItemPress.isTaken(.success, elapsed: .milliseconds(5)))
    }

    @Test("A press blocked by the menu it opened is taken")
    func timedOutPressIsTaken() {
        #expect(HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(251)))
        #expect(HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(200)))
    }

    @Test("A press the app refused at once is not taken")
    func immediateCannotCompleteIsNotTaken() {
        #expect(!HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(3)))
        #expect(!HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(199)))
    }

    @Test("Other errors are not taken, however long they took")
    func otherErrorsAreNotTaken() {
        // `AXError.actionUnsupported`, `.failure` and `.invalidUIElement`, and no element.
        #expect(!HiddenItemPress.isTaken(.failed, elapsed: .milliseconds(1)))
        #expect(!HiddenItemPress.isTaken(.failed, elapsed: .milliseconds(250)))
    }

    @Test("The threshold follows the timeout")
    func thresholdFollowsTimeout() {
        #expect(!HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(300), timeout: .seconds(1)))
        #expect(HiddenItemPress.isTaken(.cannotComplete, elapsed: .milliseconds(800), timeout: .seconds(1)))
    }
}
