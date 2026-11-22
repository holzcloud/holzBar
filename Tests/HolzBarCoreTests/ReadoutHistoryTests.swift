import Foundation
import Testing
@testable import HolzBarCore

@Suite("ReadoutHistory")
struct ReadoutHistoryTests {
    private let start = ContinuousClock.now

    private func at(_ seconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// A history with a value every `step` seconds from 0 through `end` seconds.
    private func series(step: Int, end: Int, value: (Int) -> Double?) -> ReadoutHistory {
        var history = ReadoutHistory()
        for second in stride(from: 0, through: end, by: step) {
            history.append(value(second), at: at(second))
        }
        return history
    }

    @Test("Samples older than 120 seconds before the newest drop off")
    func trimsByTime() {
        let history = series(step: 10, end: 200) { _ in 0.5 }
        // 80 through 200 stay: 13 samples.
        #expect(history.count == 13)
        #expect(history.segments(now: at(200), refreshSeconds: 10, top: 1).first?.first?.x == 0)
    }

    @Test("More than 128 samples keep the newest 128")
    func capsTheCount() {
        var history = ReadoutHistory()
        // Twenty samples a second for 20 seconds are 200 samples inside the window.
        for index in 0..<200 {
            history.append(0.5, at: start.advanced(by: .milliseconds(index * 100)))
        }
        #expect(history.count == ReadoutHistory.capacity)
    }

    @Test("A sample that arrives late is put in its place in time")
    func keepsTimeOrder() {
        var history = ReadoutHistory()
        history.append(0.1, at: at(0))
        history.append(0.3, at: at(4))
        history.append(0.2, at: at(2))
        let line = history.segments(now: at(4), refreshSeconds: 2, top: 1)
        #expect(line.count == 1)
        #expect(line[0].map(\.y) == [0.1, 0.2, 0.3])
    }

    @Test("Samples every 2 seconds for 30 seconds make one segment from x 0.75 to x 1")
    func oneSegment() throws {
        let history = series(step: 2, end: 30) { _ in 0.4 }
        let lines = history.segments(now: at(30), refreshSeconds: 2, top: 1)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.count == 16)
        #expect(line.last?.x == 1)
        #expect(line.first?.x == 0.75)
        #expect(line.allSatisfy { $0.y == 0.4 })
    }

    @Test("A gap of more than twice the refresh interval breaks the curve; exactly twice does not")
    func gapBreaks() {
        var history = ReadoutHistory()
        for second in [0, 2, 4, 14, 16, 18] {
            history.append(0.5, at: at(second))
        }
        let lines = history.segments(now: at(18), refreshSeconds: 2, top: 1)
        #expect(lines.map(\.count) == [3, 3])

        var joined = ReadoutHistory()
        for second in [0, 2, 4, 8, 10] {
            joined.append(0.5, at: at(second))
        }
        #expect(joined.segments(now: at(10), refreshSeconds: 2, top: 1).map(\.count) == [5])
    }

    @Test("A missing value breaks the curve, and a lone point is no line")
    func missingValueBreaks() {
        var history = ReadoutHistory()
        history.append(0.1, at: at(0))
        history.append(0.2, at: at(2))
        history.append(nil, at: at(4))
        history.append(0.3, at: at(6))
        history.append(0.4, at: at(8))
        history.append(nil, at: at(10))
        history.append(0.5, at: at(12))
        let lines = history.segments(now: at(12), refreshSeconds: 2, top: 1)
        #expect(lines.map(\.count) == [2, 2])
    }

    @Test("Fewer than two points give no segment")
    func tooFewPoints() {
        var history = ReadoutHistory()
        #expect(history.segments(now: at(0), refreshSeconds: 2, top: 1).isEmpty)
        history.append(0.5, at: at(0))
        #expect(history.segments(now: at(0), refreshSeconds: 2, top: 1).isEmpty)
        history.append(.nan, at: at(2))
        #expect(history.segments(now: at(2), refreshSeconds: 2, top: 1).isEmpty)
    }

    @Test("Samples older than the window at the time of drawing are left out")
    func staleSamplesAreLeftOut() {
        let history = series(step: 2, end: 30) { _ in 0.4 }
        // The hub was closed for ten minutes: nothing of the old curve is left.
        #expect(history.segments(now: at(630), refreshSeconds: 2, top: 1).isEmpty)
        #expect(history.summary(now: at(630), top: 1) == nil)
    }

    @Test("The height of a fraction is the value, and of a rate the value over the top")
    func heights() throws {
        var fractions = ReadoutHistory()
        fractions.append(0.25, at: at(0))
        fractions.append(1.5, at: at(2))
        let fraction = try #require(fractions.segments(now: at(2), refreshSeconds: 2, top: 1).first)
        #expect(fraction.map(\.y) == [0.25, 1])

        var rates = ReadoutHistory()
        rates.append(50_000, at: at(0))
        rates.append(200_000, at: at(2))
        let rate = try #require(rates.segments(now: at(2), refreshSeconds: 2, top: 200_000).first)
        #expect(rate.map(\.y) == [0.25, 1])
    }

    @Test("The top of a rate scale is the peak of every history, never below the floor")
    func rateTop() {
        var download = ReadoutHistory()
        var upload = ReadoutHistory()
        download.append(4_000, at: at(0))
        upload.append(2_000, at: at(0))
        let scale = ReadoutHistoryScale.rate(floor: 10_000)
        #expect(ReadoutHistory.top(of: [download, upload], scale: scale, now: at(0)) == 10_000)
        upload.append(80_000, at: at(2))
        download.append(30_000, at: at(2))
        #expect(ReadoutHistory.top(of: [download, upload], scale: scale, now: at(2)) == 80_000)
        #expect(ReadoutHistory.top(of: [download, upload], scale: .fraction, now: at(2)) == 1)
        #expect(ReadoutHistory.top(of: [], scale: scale, now: at(2)) == 10_000)
        // A peak that left the window no longer counts.
        #expect(ReadoutHistory.top(of: [download, upload], scale: scale, now: at(400)) == 10_000)
    }

    // MARK: Summary

    @Test("With less than 20 seconds of history there is no summary")
    func noShortSummary() {
        let short = series(step: 2, end: 18) { _ in 0.4 }
        #expect(short.summary(now: at(18), top: 1) == nil)
        let enough = series(step: 2, end: 20) { _ in 0.4 }
        #expect(enough.summary(now: at(20), top: 1) != nil)
        #expect(ReadoutHistory().summary(now: at(0), top: 1) == nil)
    }

    @Test("Fractions that rise from 0.08 to 0.41 over two minutes are rising")
    func risingSummary() {
        let history = series(step: 2, end: 120) { 0.08 + 0.33 * Double($0) / 120 }
        let summary = history.summary(now: at(120), top: 1)
        #expect(summary?.trend == .rising)
        #expect(summary?.lowest == 0.08)
        #expect(abs((summary?.highest ?? 0) - 0.41) < 1e-9)
    }

    @Test("A flat series is steady and a falling one is falling")
    func steadyAndFalling() {
        let flat = series(step: 2, end: 120) { _ in 0.3 }
        #expect(flat.summary(now: at(120), top: 1)?.trend == .steady)
        let falling = series(step: 2, end: 120) { 0.6 - 0.4 * Double($0) / 120 }
        #expect(falling.summary(now: at(120), top: 1)?.trend == .falling)
        // A change below a tenth of the scale is steady.
        var small = ReadoutHistory()
        small.append(0.20, at: at(0))
        small.append(0.20, at: at(10))
        small.append(0.25, at: at(20))
        small.append(0.25, at: at(30))
        #expect(small.summary(now: at(30), top: 1)?.trend == .steady)
    }

    @Test("For rates the trend threshold is a tenth of the peak, with the floor")
    func rateTrend() {
        // The values move by 5 000 B/s: more than a tenth of the peak 20 000, less than of 100 000.
        let history = series(step: 2, end: 120) { 15_000 + 5_000 * Double($0) / 120 }
        #expect(history.summary(now: at(120), top: 20_000)?.trend == .rising)
        #expect(history.summary(now: at(120), top: 100_000)?.trend == .steady)
        // Nothing but quiet stays steady on the floor.
        let quiet = series(step: 2, end: 120) { _ in 100 }
        #expect(quiet.summary(now: at(120), top: 10_000)?.trend == .steady)
    }

    @Test("Missing values are left out of the summary")
    func summaryLeavesOutGaps() {
        let history = series(step: 2, end: 60) { $0 % 4 == 0 ? nil : 0.2 }
        let summary = history.summary(now: at(60), top: 1)
        #expect(summary?.lowest == 0.2)
        #expect(summary?.highest == 0.2)
        #expect(summary?.trend == .steady)
    }
}
