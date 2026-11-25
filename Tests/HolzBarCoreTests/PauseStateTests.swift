import Testing
@testable import HolzBarCore

@Suite("Pause holzBar")
struct PauseStateTests {
    // The state is changed outside `#expect`, whose expansion cannot call a mutating method.

    @Test("A new state is not paused and passes the sets through")
    func startsResumed() {
        let state = PauseState()
        #expect(!state.isPaused)
        #expect(state.target([["a"], ["b"]]) == [["a"], ["b"]])
    }

    @Test("Pausing empties the target, resuming restores it")
    func toggleEmptiesAndRestores() {
        var state = PauseState()
        let paused = state.toggle()
        #expect(paused)
        #expect(state.isPaused)
        #expect(state.target([["a"]]).isEmpty)
        let resumed = state.toggle()
        #expect(!resumed)
        #expect(!state.isPaused)
        #expect(state.target([["a"]]) == [["a"]])
    }

    @Test("An empty target stays empty either way")
    func emptyStaysEmpty() {
        var state = PauseState()
        #expect(state.target([]).isEmpty)
        state.toggle()
        #expect(state.target([]).isEmpty)
    }
}
