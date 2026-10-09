import Foundation
import Testing
@testable import HolzBarCore

@Suite("LayoutSnapshot")
struct LayoutSnapshotTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func snapshot(
        minutesAgo: Int = 0,
        daysAgo: Int = 0,
        items: [String: Int] = ["a": 0],
        applications: [String: Int] = [:],
        starred: Bool = false
    ) -> LayoutSnapshot {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let date = reference.addingTimeInterval(-Double(daysAgo * 86_400 + minutesAgo * 60))
        return LayoutSnapshot(
            date: date,
            reason: .settled,
            isStarred: starred,
            itemSections: items,
            applicationSections: applications
        )
    }

    @Test("An unchanged arrangement is not kept again")
    func dedupe() {
        let latest = snapshot(items: ["a": 0, "b": 1])
        #expect(!SnapshotPolicy.shouldKeep(snapshot(items: ["b": 1, "a": 0]), latest: latest))
        #expect(SnapshotPolicy.shouldKeep(snapshot(items: ["a": 1, "b": 1]), latest: latest))
        #expect(SnapshotPolicy.shouldKeep(snapshot(items: ["a": 0]), latest: nil))
        #expect(!SnapshotPolicy.shouldKeep(snapshot(items: [:]), latest: nil))
    }

    @Test("Known applications count as part of the arrangement")
    func knownApplicationsMatter() {
        var one = snapshot(applications: ["x": 1])
        var two = one
        one.knownApplications = ["x", "y"]
        two.knownApplications = ["x"]
        #expect(!one.hasSameArrangement(as: two))
        two.knownApplications = ["y", "x"]
        #expect(one.hasSameArrangement(as: two))
    }

    @Test("Retention keeps the newest ten and a snapshot per earlier day")
    func retentionKeepsNewestAndDays() {
        // 10 snapshots today, then two per day for 25 days.
        var all = (0..<10).map { snapshot(minutesAgo: $0) }
        for day in 1...25 {
            all.append(snapshot(minutesAgo: 10, daysAgo: day))
            all.append(snapshot(minutesAgo: 20, daysAgo: day))
        }
        let kept = SnapshotRetention.kept(from: all, calendar: calendar)
        // 10 newest, plus the newest of each of the 20 earlier days.
        #expect(kept.count == 30)
        #expect(kept.first?.date == all.first?.date)
        #expect(kept.contains { $0.date == snapshot(minutesAgo: 10, daysAgo: 20).date })
        #expect(!kept.contains { $0.date == snapshot(minutesAgo: 20, daysAgo: 1).date })
        #expect(!kept.contains { $0.date == snapshot(minutesAgo: 10, daysAgo: 21).date })
    }

    @Test("Starred snapshots always stay")
    func starredStay() {
        var all = (0..<12).map { snapshot(minutesAgo: $0) }
        all.append(snapshot(daysAgo: 400, starred: true))
        let kept = SnapshotRetention.kept(from: all, calendar: calendar)
        #expect(kept.contains { $0.isStarred })
        #expect(kept.count == 11)
    }

    @Test("Few snapshots all stay")
    func fewStay() {
        let all = [snapshot(minutesAgo: 5), snapshot(minutesAgo: 1)]
        #expect(SnapshotRetention.kept(from: all, calendar: calendar).count == 2)
    }

    @Test("The diff counts moves by target section and items that are not there")
    func diff() {
        let now = snapshot(items: ["a": 0, "b": 0, "c": 1, "d": 2], applications: ["x": 1])
        let target = snapshot(items: ["a": 1, "b": 2, "c": 1, "d": 0, "gone": 1], applications: ["x": 0])
        let diff = SnapshotDiff(from: now, to: target)
        #expect(diff.toHidden == 1)
        #expect(diff.toAlwaysHidden == 1)
        #expect(diff.toVisible == 2)
        #expect(diff.notPresent == 1)
        #expect(diff.moves == 4)
    }

    @Test("A reset layout is told from a small change")
    func lossDetector() {
        let saved = snapshot(items: ["a": 0, "b": 1, "c": 1, "d": 2, "e": 2, "f": 0, "g": 1, "h": 2])
        let reset = snapshot(items: ["a": 0, "b": 0, "c": 0, "d": 0, "e": 0, "f": 0, "g": 0, "h": 0])
        #expect(LayoutLossDetector.looksReset(current: reset, comparedWith: saved))
        let small = snapshot(items: ["a": 0, "b": 1, "c": 1, "d": 2, "e": 2, "f": 0, "g": 0, "h": 0])
        #expect(!LayoutLossDetector.looksReset(current: small, comparedWith: saved))
        let tiny = snapshot(items: ["a": 1, "b": 0])
        #expect(!LayoutLossDetector.looksReset(current: snapshot(items: ["a": 0, "b": 1]), comparedWith: tiny))
    }

    @Test("A snapshot survives a JSON round trip")
    func codable() throws {
        let original = snapshot(items: ["a": 1], applications: ["x": 2])
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(LayoutSnapshot.self, from: data) == original)
    }
}
