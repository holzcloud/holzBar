import Foundation
import Testing
@testable import HolzBarCore

/// Every name and text here is invented by the tests.
@Suite("NotificationLog")
struct NotificationLogTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func draft(
        app: String? = "Messages",
        title: String? = "Lunch?",
        body: String? = "Are you free at noon?",
        bannerID: String? = nil
    ) -> NotificationBannerParser.Draft {
        NotificationBannerParser.Draft(app: app, title: title, body: body, bannerID: bannerID)
    }

    @discardableResult
    private func record(
        _ log: inout NotificationLog,
        _ draft: NotificationBannerParser.Draft,
        at seconds: TimeInterval = 0,
        excluding excluded: Set<String> = [],
        presenting: Bool = false
    ) -> NotificationLog.Outcome {
        log.record(
            draft,
            now: start.addingTimeInterval(seconds),
            excludedApps: excluded,
            isPresenting: presenting,
            makeID: UUID.init
        )
    }

    @Test("A first draft is recorded with the time it arrived")
    func firstDraft() {
        var log = NotificationLog()
        #expect(record(&log, draft(), at: 5) == .recorded)
        #expect(log.records.count == 1)
        #expect(log.records.first?.title == "Lunch?")
        #expect(log.records.first?.received == start.addingTimeInterval(5))
    }

    @Test("Newer records come first")
    func newestFirst() {
        var log = NotificationLog()
        record(&log, draft(title: "one"), at: 0)
        record(&log, draft(title: "two"), at: 10)
        record(&log, draft(title: "three"), at: 20)
        #expect(log.records.map(\.title) == ["three", "two", "one"])
    }

    @Test("The log keeps 20 records; the 21st drops the oldest")
    func capIsTwenty() {
        var log = NotificationLog()
        for number in 1...21 {
            record(&log, draft(title: "title \(number)"), at: Double(number) * 10)
        }
        #expect(NotificationLog.maximumRecords == 20)
        #expect(log.records.count == 20)
        #expect(log.records.first?.title == "title 21")
        #expect(log.records.last?.title == "title 2")
    }

    @Test("Clear all empties the log")
    func removeAllEmpties() {
        var log = NotificationLog()
        record(&log, draft(title: "one"), at: 0)
        record(&log, draft(title: "two"), at: 10)
        log.removeAll()
        #expect(log.records.isEmpty)
    }
}
