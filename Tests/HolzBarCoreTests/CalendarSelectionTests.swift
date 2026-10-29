import Testing
@testable import HolzBarCore

@Suite("CalendarSelection")
struct CalendarSelectionTests {
    @Test("A calendar is shown unless its identifier is in the hidden set")
    func visibility() {
        #expect(CalendarSelection.isVisible("a", hidden: ["b"]))
        #expect(!CalendarSelection.isVisible("a", hidden: ["a"]))
        #expect(CalendarSelection.isVisible("a", hidden: []))
    }

    @Test("Toggling adds an identifier that was shown and removes one that was hidden")
    func toggling() {
        #expect(CalendarSelection.toggled("a", in: ["b"]) == ["a", "b"])
        #expect(CalendarSelection.toggled("a", in: ["a", "b"]) == ["b"])
        #expect(CalendarSelection.toggled("a", in: []) == ["a"])
    }

    @Test("A stored list drops duplicates, empty and over-long identifiers and keeps at most 200")
    func cleaning() {
        let tooLong = String(repeating: "x", count: CalendarSelection.maximumLength + 1)
        let limit = String(repeating: "y", count: CalendarSelection.maximumLength)
        #expect(CalendarSelection.cleaned(["a", "a", "", tooLong, "b", limit]) == ["a", "b", limit])
        #expect(CalendarSelection.cleaned([]).isEmpty)
        let many = (0..<500).map { "calendar-\($0)" }
        let kept = CalendarSelection.cleaned(many)
        #expect(kept.count == CalendarSelection.maximumCount)
        #expect(kept == CalendarSelection.cleaned(many.reversed()))
    }
}
