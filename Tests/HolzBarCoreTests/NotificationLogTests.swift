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

    // MARK: Privacy rules

    @Test("A draft that arrives while the screen is shared is not kept")
    func presentingKeepsNothing() {
        var log = NotificationLog()
        record(&log, draft(title: "kept"), at: 0)
        let before = log
        #expect(record(&log, draft(title: "shared"), at: 10, presenting: true) == .presenting)
        #expect(log == before)
    }

    @Test("A draft with neither a title nor a body is empty and not kept")
    func emptyDraft() {
        var log = NotificationLog()
        #expect(record(&log, draft(title: nil, body: nil)) == .empty)
        #expect(log.records.isEmpty)
        // A title alone, or a body alone, is enough.
        #expect(record(&log, draft(title: "only a title", body: nil), at: 10) == .recorded)
        #expect(record(&log, draft(title: nil, body: "only a body"), at: 20) == .recorded)
    }

    @Test("An app on the exclusion list is never recorded, compared trimmed and without regard to case")
    func excludedApp() {
        var log = NotificationLog()
        let excluded: Set<String> = ["Anna's Mail"]
        #expect(record(&log, draft(app: "Anna's Mail"), excluding: excluded) == .excluded)
        #expect(record(&log, draft(app: "  anna's mail "), at: 10, excluding: excluded) == .excluded)
        #expect(record(&log, draft(app: "ANNA'S MAIL"), at: 20, excluding: ["  anna's mail  "]) == .excluded)
        #expect(log.records.isEmpty)
        // Another app, and a banner that names no app, are not excluded.
        #expect(record(&log, draft(app: "Messages"), at: 30, excluding: excluded) == .recorded)
        #expect(record(&log, draft(app: nil, title: "no app"), at: 40, excluding: excluded) == .recorded)
    }

    @Test("The same app, title and body within 1.9 seconds is one record; at 2.0 seconds it is a new one")
    func duplicateWindow() {
        var log = NotificationLog()
        #expect(record(&log, draft(), at: 0) == .recorded)
        #expect(record(&log, draft(), at: 1.9) == .duplicate)
        #expect(log.records.count == 1)
        #expect(record(&log, draft(), at: 2.0) == .recorded)
        #expect(log.records.count == 2)
        #expect(NotificationLog.duplicateWindow == 2)
    }

    @Test("A different title, body or app is not a duplicate")
    func differentIsNotDuplicate() {
        var log = NotificationLog()
        record(&log, draft(), at: 0)
        #expect(record(&log, draft(title: "Dinner?"), at: 0.5) == .recorded)
        #expect(record(&log, draft(title: "Dinner?", body: "Tonight?"), at: 1) == .recorded)
        #expect(record(&log, draft(app: "Mail", title: "Dinner?", body: "Tonight?"), at: 1.5) == .recorded)
        #expect(log.records.count == 4)
    }

    @Test("The same banner firing again later is still one record, even after it was removed")
    func sameBannerIsOneRecord() throws {
        var log = NotificationLog()
        let banner = draft(bannerID: "351C5328-0000-4000-8000-000000000001")
        #expect(record(&log, banner, at: 0) == .recorded)
        #expect(record(&log, banner, at: 30) == .duplicate)
        let id = try #require(log.records.first?.id)
        log.remove(id)
        #expect(record(&log, banner, at: 60) == .duplicate)
        #expect(log.records.isEmpty)
    }

    @Test("The rules apply in the order presenting, empty, excluded, duplicate")
    func ruleOrder() {
        var log = NotificationLog()
        record(&log, draft(), at: 0)
        // Excluded and presenting: presenting wins.
        #expect(record(&log, draft(app: "Mail"), at: 10, excluding: ["mail"], presenting: true) == .presenting)
        // Empty and excluded: empty wins.
        #expect(record(&log, draft(app: "Mail", title: nil, body: nil), at: 10, excluding: ["mail"]) == .empty)
        // Excluded and a duplicate: excluded wins.
        #expect(record(&log, draft(), at: 0.5, excluding: ["messages"]) == .excluded)
    }

    @Test("Removing one record keeps the others in order; an unknown identifier changes nothing")
    func removeOne() throws {
        var log = NotificationLog()
        record(&log, draft(title: "one"), at: 0)
        record(&log, draft(title: "two"), at: 10)
        record(&log, draft(title: "three"), at: 20)
        let middle = try #require(log.records.first { $0.title == "two" }?.id)
        log.remove(middle)
        #expect(log.records.map(\.title) == ["three", "one"])
        let before = log
        log.remove(UUID())
        #expect(log == before)
    }

    @Test("Excluding an app removes its records and no other")
    func removeAllOfOneApp() {
        var log = NotificationLog()
        record(&log, draft(app: "Mail", title: "one"), at: 0)
        record(&log, draft(app: "Messages", title: "two"), at: 10)
        record(&log, draft(app: nil, title: "three"), at: 20)
        record(&log, draft(app: "mail ", title: "four"), at: 30)
        log.removeAll(fromApp: " MAIL")
        #expect(log.records.map(\.title) == ["three", "two"])
    }

    @Test("The stored exclusion list is trimmed, deduplicated without regard to case and capped at 50")
    func cleanedExclusions() {
        #expect(NotificationLog.cleanedExclusions(["  Mail ", "mail", "", "  ", "Messages", "MESSAGES"]) == ["Mail", "Messages"])
        let many = (0..<80).map { "App \($0)" }
        #expect(NotificationLog.cleanedExclusions(many).count == NotificationLog.maximumExcludedApps)
        #expect(NotificationLog.maximumExcludedApps == 50)
        #expect(NotificationLog.cleanedExclusions([]).isEmpty)
    }
}
