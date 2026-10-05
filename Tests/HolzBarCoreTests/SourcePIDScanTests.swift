import CoreGraphics
import Testing
@testable import HolzBarCore

/// On macOS 26 holzBar asks the running apps through Accessibility where their items are.
/// Slow apps must not keep a scan from ever finishing, and an app signed by Apple that could
/// not be asked must not hand its window to another app.
@Suite("SourcePIDScan")
struct SourcePIDScanTests {
    /// An item an app reports, and how long each call about it takes.
    struct Item {
        var frame: CGRect?
        var isEnabled = true
        var frameTime = Duration.milliseconds(1)
        var enabledTime = Duration.milliseconds(1)
    }

    /// A running app, and how long it takes to answer.
    struct App {
        var pid: pid_t
        var isSignedByApple = false
        var isValid = true
        var barTime = Duration.milliseconds(1)
        var childrenTime = Duration.milliseconds(1)
        var items = [Item]()
    }

    enum Element {
        case bar([Item], childrenTime: Duration)
        case item(Item)
    }

    /// Answers from the apps' scripts and advances its clock by each call's time.
    final class Source: SourcePIDScanSource {
        private(set) var now = ContinuousClock.now
        var isCancelled = false
        /// How often each app's extras menu bar was asked for.
        private(set) var asked = [pid_t: Int]()

        func advance(by duration: Duration) {
            now += duration
        }

        func pid(of app: App) -> pid_t {
            app.pid
        }

        func isSignedByApple(_ app: App) -> Bool {
            app.isSignedByApple
        }

        func isValidForAccessibility(_ app: App) -> Bool {
            app.isValid
        }

        func extrasMenuBar(of app: App) -> Element? {
            asked[app.pid, default: 0] += 1
            now += app.barTime
            return .bar(app.items, childrenTime: app.childrenTime)
        }

        func children(of element: Element) -> [Element] {
            guard case let .bar(items, childrenTime) = element else {
                return []
            }
            now += childrenTime
            return items.map(Element.item)
        }

        func frame(of element: Element) -> CGRect? {
            guard case let .item(item) = element else {
                return nil
            }
            now += item.frameTime
            return item.frame
        }

        func isEnabled(_ element: Element) -> Bool {
            guard case let .item(item) = element else {
                return false
            }
            now += item.enabledTime
            return item.isEnabled
        }
    }

    private let ownPID: pid_t = 100
    private let window: CGWindowID = 1
    private let center = CGPoint(x: 500, y: 12)
    /// An item at the window's centre.
    private var itemAtWindow: Item {
        Item(frame: CGRect(x: 490, y: 2, width: 20, height: 20))
    }
    /// An item elsewhere in the menu bar.
    private var itemElsewhere: Item {
        Item(frame: CGRect(x: 100, y: 2, width: 20, height: 20))
    }

    private func pids(_ apps: [App]) -> [pid_t] {
        apps.map(\.pid)
    }

    @Test("An app that answers every call just under the timeout is paused after 1 s")
    func slowAppIsPaused() {
        let slowItem = Item(frame: itemElsewhere.frame, frameTime: .milliseconds(400))
        let slow = App(pid: 30, barTime: .milliseconds(400), childrenTime: .milliseconds(400), items: Array(repeating: slowItem, count: 20))
        let owner = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        let paused = scan.run(over: [slow, owner], with: source, schedule: &schedule)

        #expect(paused == [30])
        #expect(pids(scan.skippedApps) == [30])
        #expect(!schedule.mayAsk(30, at: source.now))
        #expect(scan.isFinished)
        #expect(scan.decision(for: window) == .owner(20))
    }

    @Test("Slow apps that never time out cannot keep a continued scan from finishing")
    func continuedScanFinishes() throws {
        // Every app takes 0.9 s, under the timeout and under its budget, so one part of the
        // scan asks only two or three of them.
        let slowItem = Item(frame: itemElsewhere.frame, frameTime: .milliseconds(300))
        let slowApps = (31...35).map { App(pid: $0, barTime: .milliseconds(300), childrenTime: .milliseconds(300), items: [slowItem]) }
        let owner = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        var parts = 1
        scan.run(over: slowApps + [owner], with: source, schedule: &schedule)
        while !scan.isFinished, parts < 10 {
            #expect(scan.decision(for: window) == .unresolved)
            source.advance(by: .milliseconds(100))
            scan = try #require(scan.continued(for: [window: center], at: source.now))
            scan.run(over: slowApps + [owner], with: source, schedule: &schedule)
            parts += 1
        }

        #expect(scan.isFinished)
        #expect(parts == 3)
        #expect(scan.decision(for: window) == .owner(20))
        #expect(scan.skippedApps.isEmpty)
        // An app a part finished with is not asked again; one it stopped in is.
        #expect(source.asked[31] == 1)
        #expect(source.asked[32] == 1)
        #expect(source.asked[34] == 1)
        #expect(source.asked[20] == 1)
    }

    @Test("A scan that is not continued asks the same apps again and never finishes")
    func scanWithoutContinuing() {
        let slowItem = Item(frame: itemElsewhere.frame, frameTime: .milliseconds(300))
        let slowApps = (31...35).map { App(pid: $0, barTime: .milliseconds(300), childrenTime: .milliseconds(300), items: [slowItem]) }
        let owner = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        for _ in 1...3 {
            var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)
            scan.run(over: slowApps + [owner], with: source, schedule: &schedule)
            #expect(!scan.isFinished)
        }
    }

    @Test("A paused app signed by Apple keeps another app from its window")
    func pausedAppleApp() {
        let controlCenter = App(pid: 10, isSignedByApple: true, items: [itemElsewhere])
        let loginItem = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        schedule.record(10, timedOut: true, at: source.now)

        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)
        scan.run(over: [controlCenter, loginItem], with: source, schedule: &schedule)
        #expect(scan.isFinished)
        #expect(scan.skippedAppleApp)
        #expect(pids(scan.skippedApps) == [10])
        #expect(scan.decision(for: window) == .unresolved)

        // Once Control Center can be asked and has no item there, the window is the other app's.
        source.advance(by: SourcePIDLookupSchedule.firstPause)
        var later = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)
        later.run(over: [controlCenter, loginItem], with: source, schedule: &schedule)
        #expect(!later.skippedAppleApp)
        #expect(later.decision(for: window) == .owner(20))
    }

    @Test("An app signed by Apple that is not ready keeps another app from its window")
    func unresponsiveAppleApp() {
        let controlCenter = App(pid: 10, isSignedByApple: true, isValid: false, items: [itemAtWindow])
        let loginItem = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        scan.run(over: [controlCenter, loginItem], with: source, schedule: &schedule)

        #expect(scan.isFinished)
        #expect(scan.decision(for: window) == .unresolved)
    }

    @Test("An app signed by Apple that times out partway keeps another app from its window")
    func appleAppTimesOut() {
        let stalled = Item(frame: itemElsewhere.frame, frameTime: .milliseconds(500))
        let controlCenter = App(pid: 10, isSignedByApple: true, items: [stalled, itemAtWindow])
        let loginItem = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        let paused = scan.run(over: [controlCenter, loginItem], with: source, schedule: &schedule)

        #expect(paused == [10])
        #expect(scan.isFinished)
        #expect(scan.skippedAppleApp)
        #expect(scan.decision(for: window) == .unresolved)
    }

    @Test("Control Center's claim settles its window, so no other app is asked about it")
    func appleClaimSettles() {
        let controlCenter = App(pid: 10, isSignedByApple: true, items: [itemAtWindow])
        let loginItem = App(pid: 20, items: [itemAtWindow])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        scan.run(over: [controlCenter, loginItem], with: source, schedule: &schedule)

        #expect(scan.isFinished)
        #expect(scan.decision(for: window) == .owner(10))
        #expect(source.asked[20] == nil)
    }

    @Test("holzBar's own process is not waited for after a timeout")
    func ownProcessIsNotSkipped() {
        let stalled = Item(frame: itemElsewhere.frame, frameTime: .milliseconds(500))
        let holzBar = App(pid: ownPID, items: [stalled])
        let source = Source()
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        let paused = scan.run(over: [holzBar], with: source, schedule: &schedule)

        #expect(paused.isEmpty)
        #expect(scan.skippedApps.isEmpty)
        #expect(schedule.mayAsk(ownPID, at: source.now))
        #expect(scan.isFinished)
    }

    @Test("A cancelled scan stops at once and is not finished")
    func cancelled() {
        let source = Source()
        source.isCancelled = true
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)

        scan.run(over: [App(pid: 20, items: [itemAtWindow])], with: source, schedule: &schedule)

        #expect(!scan.isFinished)
        #expect(source.asked.isEmpty)
    }

    @Test("A scan is continued only while unfinished, recent, and for windows it knows where they are")
    func continuation() throws {
        let other: CGWindowID = 2
        let otherCenter = CGPoint(x: 600, y: 12)
        let source = Source()
        source.isCancelled = true
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var scan = SourcePIDScan<App>(centers: [window: center, other: otherCenter], startedAt: source.now)
        scan.run(over: [App(pid: 20)], with: source, schedule: &schedule)
        #expect(!scan.isFinished)

        // Fewer windows: the rest is continued.
        let narrowed = try #require(scan.continued(for: [window: center], at: source.now))
        #expect(narrowed.centers == [window: center])
        // A new window or a moved one: the apps already asked were not asked about it.
        #expect(scan.continued(for: [window: center, 3: CGPoint(x: 700, y: 12)], at: source.now) == nil)
        #expect(scan.continued(for: [window: CGPoint(x: 501, y: 12)], at: source.now) == nil)
        // Too old.
        #expect(scan.continued(for: [window: center], at: source.now + SourcePIDLookupSchedule.scanLifetime) == nil)

        // Finished.
        source.isCancelled = false
        var finished = SourcePIDScan<App>(centers: [window: center], startedAt: source.now)
        finished.run(over: [], with: source, schedule: &schedule)
        #expect(finished.isFinished)
        #expect(finished.continued(for: [window: center], at: source.now) == nil)
    }
}
