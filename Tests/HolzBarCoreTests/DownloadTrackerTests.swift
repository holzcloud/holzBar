import Foundation
import Testing
@testable import HolzBarCore

@Suite("DownloadTracker")
struct DownloadTrackerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    @Test("A mark that appears starts a running item at that moment")
    func starts() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.crdownload", "notes.txt"], now: at(0))
        #expect(tracker.running.map(\.name) == ["a.zip"])
        #expect(tracker.running.first?.startedAt == at(0))
        #expect(tracker.running.first?.finishedAt == nil)
        #expect(tracker.finished.isEmpty)
    }

    @Test("A mark that stays keeps the start of its item")
    func keepsStart() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.crdownload"], now: at(0))
        tracker.update(names: ["a.zip.crdownload"], now: at(10))
        #expect(tracker.running.count == 1)
        #expect(tracker.running.first?.startedAt == at(0))
    }

    @Test("A mark that goes while the final name is listed finishes the item")
    func finishes() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.crdownload"], now: at(0))
        tracker.update(names: ["a.zip"], now: at(12))
        #expect(tracker.running.isEmpty)
        #expect(tracker.finished.map(\.name) == ["a.zip"])
        #expect(tracker.finished.first?.startedAt == at(0))
        #expect(tracker.finished.first?.finishedAt == at(12))
        // Another listing does not finish it again.
        tracker.update(names: ["a.zip"], now: at(14))
        #expect(tracker.finished.first?.finishedAt == at(12))
    }

    @Test("A mark that goes without the final name drops the item: a cancelled download shows nothing")
    func cancelled() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.part"], now: at(0))
        tracker.update(names: [], now: at(3))
        #expect(tracker.isEmpty)
        #expect(tracker.running.isEmpty)
        #expect(tracker.finished.isEmpty)
    }

    @Test("An unnamed download that vanishes is dropped and never finished")
    func unnamedNeverFinishes() {
        var tracker = DownloadTracker()
        tracker.update(names: ["Unconfirmed 42.crdownload"], now: at(0))
        #expect(tracker.running.count == 1)
        #expect(tracker.running.first?.name == nil)
        // Chrome learns the name: the placeholder goes, the named download starts.
        tracker.update(names: ["Report.pdf.crdownload"], now: at(1))
        #expect(tracker.running.map(\.name) == ["Report.pdf"])
        #expect(tracker.finished.isEmpty)
        // Even if a file of the placeholder's name were listed, it does not finish.
        var other = DownloadTracker()
        other.update(names: ["Unconfirmed 42.crdownload"], now: at(0))
        other.update(names: ["Unconfirmed 42"], now: at(1))
        #expect(other.isEmpty)
    }

    @Test("A finished item whose mark appears again becomes a new running item")
    func restarts() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.crdownload"], now: at(0))
        tracker.update(names: ["a.zip"], now: at(5))
        tracker.update(names: ["a.zip", "a.zip.crdownload"], now: at(8))
        #expect(tracker.finished.isEmpty)
        #expect(tracker.running.count == 1)
        #expect(tracker.running.first?.startedAt == at(8))
    }

    @Test("Finished items older than sixty seconds are dropped")
    func prunesFinished() {
        var tracker = DownloadTracker()
        tracker.update(names: ["a.zip.crdownload"], now: at(0))
        tracker.update(names: ["a.zip"], now: at(5))
        tracker.update(names: ["a.zip"], now: at(64))
        #expect(tracker.finished.count == 1)
        tracker.update(names: ["a.zip"], now: at(66))
        #expect(tracker.isEmpty)
        #expect(DownloadTracker.finishedRetention == 60)
    }

    @Test("Twenty-five running items keep the newest twenty and the others stay out")
    func capsRunning() {
        var tracker = DownloadTracker()
        let early = (0..<10).map { "early-\($0).zip.crdownload" }
        let late = (0..<15).map { "late-\($0).zip.crdownload" }
        tracker.update(names: early, now: at(0))
        tracker.update(names: early + late, now: at(10))
        #expect(DownloadTracker.maximumRunning == 20)
        #expect(tracker.running.count == 20)
        // All fifteen late ones and the five early ones that sort first by name stay.
        #expect(tracker.running.filter { $0.startedAt == at(10) }.count == 15)
        let kept = tracker.running
        // A later listing with the same marks changes nothing: nothing flickers.
        tracker.update(names: early + late, now: at(20))
        #expect(tracker.running == kept)
        // One of the early ones that was left out finishes without ever having been shown.
        let leftOut = early.first { name in
            !kept.contains { $0.name == String(name.dropLast(".crdownload".count)) }
        }
        #expect(leftOut != nil)
        tracker.update(names: early.filter { $0 != leftOut } + late, now: at(30))
        #expect(tracker.running.count == 20)
    }

    @Test("An empty listing with nothing tracked changes nothing")
    func emptyStaysEmpty() {
        var tracker = DownloadTracker()
        tracker.update(names: [], now: at(0))
        #expect(tracker == DownloadTracker())
        tracker.update(names: ["readme.txt", ".DS_Store"], now: at(1))
        #expect(tracker == DownloadTracker())
    }

    @Test("The identifier does not contain the name and differs between names")
    func identifiers() {
        var tracker = DownloadTracker()
        tracker.update(names: ["Secret plans.pdf.part", "b.zip.part"], now: at(0))
        let ids = tracker.running.map(\.id)
        #expect(Set(ids).count == 2)
        for id in ids {
            #expect(!id.contains("Secret"))
            #expect(!id.isEmpty)
        }
        var again = DownloadTracker()
        again.update(names: ["Secret plans.pdf.part"], now: at(50))
        #expect(again.running.first?.id == tracker.running.first { $0.name == "Secret plans.pdf" }?.id)
    }

    @Test("Removing all forgets the items and the ones left out")
    func removeAll() {
        var tracker = DownloadTracker()
        tracker.update(names: (0..<25).map { "f-\($0).zip.part" }, now: at(0))
        tracker.removeAll()
        #expect(tracker == DownloadTracker())
    }
}
