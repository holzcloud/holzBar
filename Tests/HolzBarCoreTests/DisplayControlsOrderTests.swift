import Testing
@testable import HolzBarCore

@Suite("DisplayControlsOrder")
struct DisplayControlsOrderTests {
    typealias Order = DisplayControlsOrder

    @Test("The display the hub opened on comes first, the others keep their order")
    func firstComesFirst() {
        #expect(Order.ordered([1, 2, 3], first: 2) == [2, 1, 3])
        #expect(Order.ordered([1, 2, 3], first: 1) == [1, 2, 3])
        #expect(Order.ordered([1, 2, 3], first: 3) == [3, 1, 2])
    }

    @Test("Without a first display the order is the one given")
    func noFirst() {
        #expect(Order.ordered([1, 2, 3], first: nil) == [1, 2, 3])
    }

    @Test("A first display that is not listed changes nothing")
    func unlistedFirst() {
        #expect(Order.ordered([1, 2, 3], first: 9) == [1, 2, 3])
    }

    @Test("A repeated identifier keeps its first place")
    func duplicates() {
        #expect(Order.ordered([1, 2, 1, 3], first: 3) == [3, 1, 2])
        #expect(Order.ordered([1, 2, 1, 3], first: nil) == [1, 2, 3])
    }

    @Test("No displays give no order")
    func empty() {
        #expect(Order.ordered([], first: 1) == [])
        #expect(Order.ordered([], first: nil) == [])
    }
}
