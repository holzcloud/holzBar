import Testing
@testable import HolzBarCore

@Suite("BarClickTrace")
struct BarClickTraceTests {
    @Test("Only the newest clicks are kept")
    func capacity() {
        var trace = BarClickTrace()
        for index in 0..<(BarClickTrace.capacity + 3) {
            trace.record("click \(index)")
        }
        #expect(trace.lines.count == BarClickTrace.capacity)
        #expect(trace.lines.first == "click 3")
        #expect(trace.lines.last == "click \(BarClickTrace.capacity + 2)")
    }

    @Test("A bar click names the system item and the extents")
    func barClick() {
        let line = BarClickTrace.barClick(
            seconds: 120, x: 570, concealing: true, item: "com.apple.menuextra.wifi", bridged: false,
            systemItems: [595...677, 700...730], ownItems: [1121...1156]
        )
        #expect(line == "t 120, bar click x 570, concealing yes, item wifi, bridged no, system 595-677 700-730, own 1121-1156")
    }

    @Test("A third-party item is never named, and no item reads none")
    func names() {
        let other = BarClickTrace.barClick(
            seconds: 1, x: 1, concealing: false, item: "com.example.secret", bridged: false, systemItems: [], ownItems: []
        )
        #expect(!other.contains("example"))
        #expect(other.contains("item other"))
        let none = BarClickTrace.barClick(
            seconds: 1, x: 1, concealing: false, item: nil, bridged: false, systemItems: [], ownItems: []
        )
        #expect(none.contains("item none, bridged no, system none, own none"))
    }

    @Test("A click on the holzBar icon says which section and whether it was hidden")
    func controlClick() {
        #expect(BarClickTrace.controlClick(seconds: 9, section: "hidden", wasHidden: true)
            == "t 9, holzBar icon clicked, section hidden, was hidden yes")
    }

    @Test("The report prints the clicks unchanged and none without a click")
    func report() {
        var input = DiagnosticsInput()
        #expect(!DiagnosticsReport.make(input).contains("Click 1"))
        let line = BarClickTrace.barClick(
            seconds: 120, x: 570, concealing: true, item: "com.apple.menuextra.wifi", bridged: false,
            systemItems: [595...677, 700...730, 740...790, 800...850, 860...900, 910...950], ownItems: [1121...1156, 1302...1303]
        )
        input.barClicks = [line]
        let report = DiagnosticsReport.make(input)
        #expect(report.contains("Click 1: \(line)"))
        #expect(line.count <= DiagnosticsReport.maximumClickLength)
    }
}
