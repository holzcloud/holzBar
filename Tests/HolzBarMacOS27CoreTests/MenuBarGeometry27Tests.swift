import CoreGraphics
import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("SyntheticWindowID27")
struct SyntheticWindowID27Tests {
    @Test("The same item always gets the same identifier")
    func stable() {
        let first = SyntheticWindowID27.make(bundleID: "eu.exelban.Stats", identifier: "Item#", occurrence: 0)
        let second = SyntheticWindowID27.make(bundleID: "eu.exelban.Stats", identifier: "Item#", occurrence: 0)
        #expect(first == second)
    }

    @Test("Items of one app that share an identifier get different identifiers")
    func distinct() {
        let occurrences = SyntheticWindowID27.occurrences(identifiers: ["Item#", "Item#"])
        #expect(occurrences == [0, 1])
        let first = SyntheticWindowID27.make(bundleID: "eu.exelban.Stats", identifier: "Item#", occurrence: occurrences[0])
        let second = SyntheticWindowID27.make(bundleID: "eu.exelban.Stats", identifier: "Item#", occurrence: occurrences[1])
        #expect(first != second)
    }

    @Test("Synthetic identifiers are recognisable and real ones are not")
    func recognisable() {
        let synthetic = SyntheticWindowID27.make(bundleID: "ru.keepcoder.Telegram", identifier: "Item-0", occurrence: 0)
        #expect(SyntheticWindowID27.isSynthetic(synthetic))
        #expect(SyntheticWindowID27.isSynthetic(SyntheticWindowID27.make(bundleID: "com.apple.MenuBarAgent", identifier: "", occurrence: 7)))
        #expect(!SyntheticWindowID27.isSynthetic(24))
        #expect(!SyntheticWindowID27.isSynthetic(100_000))
    }

    @Test("The occurrence counts each identifier on its own")
    func occurrencesPerIdentifier() {
        #expect(SyntheticWindowID27.occurrences(identifiers: ["a", "b", "a", "", "a"]) == [0, 0, 1, 0, 2])
        #expect(SyntheticWindowID27.occurrences(identifiers: ["", ""]) == [0, 1])
        #expect(SyntheticWindowID27.occurrences(identifiers: []).isEmpty)
    }

    @Test("A system item keeps its identifier when an item before it comes or goes")
    func independentOfPosition() {
        // The children of MenuBarAgent without and with one more item in front, as when the
        // overflow button or another system item appears (27-L2).
        let without = ["com.apple.menuextra.wifi", "com.apple.menuextra.clock"]
        let with = ["com.apple.menuextra.battery"] + without
        let clockWithout = SyntheticWindowID27.occurrences(identifiers: without)[1]
        let clockWith = SyntheticWindowID27.occurrences(identifiers: with)[2]
        #expect(
            SyntheticWindowID27.make(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.clock", occurrence: clockWithout)
                == SyntheticWindowID27.make(bundleID: "com.apple.MenuBarAgent", identifier: "com.apple.menuextra.clock", occurrence: clockWith)
        )
    }
}

@Suite("OverflowDetection27")
struct OverflowDetection27Tests {
    // Measured on macOS 27.0, built-in display: the overflow button sits at x −619…−602.
    let button = CGRect(x: -619, y: 99, width: 17, height: 30)

    @Test("Folded items overlap the overflow button")
    func folded() {
        #expect(OverflowDetection27.isInOverflow(itemFrame: CGRect(x: -649, y: 102, width: 47, height: 24), chevronFrame: button))
        #expect(OverflowDetection27.isInOverflow(itemFrame: CGRect(x: -634, y: 102, width: 24, height: 24), chevronFrame: button))
    }

    @Test("A drawn item next to the button is not folded")
    func drawnNextToButton() {
        #expect(!OverflowDetection27.isInOverflow(itemFrame: CGRect(x: -588, y: 102, width: 24, height: 24), chevronFrame: button))
    }

    @Test("Items shown left of the notch while expanded are not folded")
    func expanded() {
        #expect(!OverflowDetection27.isInOverflow(itemFrame: CGRect(x: -904, y: 102, width: 36, height: 24), chevronFrame: button))
    }

    @Test("Without an overflow button nothing is folded")
    func noButton() {
        #expect(!OverflowDetection27.isInOverflow(itemFrame: CGRect(x: 0, y: 0, width: 24, height: 24), chevronFrame: nil))
    }
}

@Suite("ClockBridgeZone27")
struct ClockBridgeZone27Tests {
    let clock = CGRect(x: 1787, y: 0, width: 113, height: 30)
    let menuBar = CGRect(x: 0, y: 0, width: 1920, height: 30)

    @Test("A click on a system item is bridged while concealing")
    func bridged() {
        #expect(ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 15), systemItemFrames: [clock], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("A click one point outside the frame still counts")
    func edgeTolerance() {
        #expect(ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1786.5, y: 15), systemItemFrames: [clock], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("A click elsewhere is not bridged")
    func elsewhere() {
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 900, y: 12), systemItemFrames: [clock], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("Nothing is bridged while nothing is concealed")
    func notConcealing() {
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 15), systemItemFrames: [clock], isConcealing: false, menuBarRect: menuBar))
    }

    @Test("A click just below the bar is not bridged")
    func belowTheBar() {
        // One point under the bar's bottom edge, still inside the clock's frame grown by a point.
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 30.5), systemItemFrames: [clock], isConcealing: true, menuBarRect: menuBar))
        let lowerBar = CGRect(x: 0, y: 0, width: 1920, height: 24)
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 25), systemItemFrames: [clock], isConcealing: true, menuBarRect: lowerBar))
    }

    @Test("A click on the overflow button is bridged while concealing")
    func overflowButtonBridged() {
        let overflowButton = CGRect(x: 1700, y: 0, width: 18, height: 30)
        #expect(ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1708, y: 15), systemItemFrames: [clock, overflowButton], isConcealing: true, menuBarRect: menuBar))
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1708, y: 15), systemItemFrames: [clock], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("A click on holzBar's own item is never bridged, even inside a system frame")
    func ownItemNotBridged() {
        let ownIcon = CGRect(x: 1097, y: 0, width: 28, height: 30)
        let stale = CGRect(x: 1090, y: 0, width: 50, height: 30)
        let click = CGPoint(x: 1107, y: 15)
        #expect(ClockBridgeZone27.shouldBridge(click: click, systemItemFrames: [stale], isConcealing: true, menuBarRect: menuBar))
        #expect(!ClockBridgeZone27.shouldBridge(click: click, systemItemFrames: [stale], ownItemFrames: [ownIcon], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("An AppKit window frame becomes the frame a click compares with")
    func appKitFrameConverted() {
        // A 24 pt high item at the top of a 1080 pt high display: AppKit says y 1056, a click says 0 to 24.
        let appKit = CGRect(x: 1097, y: 1056, width: 28, height: 24)
        let quartz = ClockBridgeZone27.quartzFrame(fromAppKit: appKit, primaryHeight: 1080)
        #expect(quartz == CGRect(x: 1097, y: 0, width: 28, height: 24))
        let stale = CGRect(x: 1090, y: 0, width: 50, height: 30)
        let click = CGPoint(x: 1107, y: 12)
        #expect(!ClockBridgeZone27.shouldBridge(click: click, systemItemFrames: [stale], ownItemFrames: [quartz], isConcealing: true, menuBarRect: menuBar))
        // The unconverted frame lies at the bottom of the screen and let the click through to the stale frame.
        #expect(ClockBridgeZone27.shouldBridge(click: click, systemItemFrames: [stale], ownItemFrames: [appKit], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("A null or infinite frame converts to no frame")
    func nullFrameConverted() {
        #expect(ClockBridgeZone27.quartzFrame(fromAppKit: .null, primaryHeight: 1080).isNull)
        #expect(ClockBridgeZone27.quartzFrame(fromAppKit: .infinite, primaryHeight: 1080).isNull)
    }

    @Test("A collapsed control item's huge frame does not block the system items")
    func hugeOwnFrameIgnored() {
        let divider = CGRect(x: -10000, y: 0, width: 11500, height: 30)
        #expect(ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 15), systemItemFrames: [clock], ownItemFrames: [divider], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("A frame spanning the bar or an empty one is no item")
    func implausibleFramesIgnored() {
        let host = CGRect(x: 0, y: 0, width: 1920, height: 30)
        let empty = CGRect(x: 900, y: 0, width: 0, height: 30)
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 900, y: 15), systemItemFrames: [host, empty], isConcealing: true, menuBarRect: menuBar))
    }

    @Test("Nothing is bridged while the bar is hidden")
    func barHidden() {
        #expect(!ClockBridgeZone27.shouldBridge(click: CGPoint(x: 1840, y: 15), systemItemFrames: [clock], isConcealing: true, menuBarRect: nil))
    }
}

@Suite("ItemHitTest27")
struct ItemHitTest27Tests {
    // Measured on macOS 27.0 with the external menu bar active.
    let stats = ItemHitTest27.Item(frame: CGRect(x: 1478, y: 2, width: 33, height: 24), ownerPID: 100, isOnScreen: true)
    let clock = CGRect(x: 1787, y: 0, width: 113, height: 30)
    // Built-in display: an item folded behind the overflow button, and the button itself.
    let folded = ItemHitTest27.Item(frame: CGRect(x: -649, y: 102, width: 47, height: 24), ownerPID: 200, isOnScreen: false)
    let overflowButton = CGRect(x: -619.5, y: 99, width: 17.5, height: 30)

    @Test("The pointer on a drawn item is inside an item")
    func drawnItem() {
        #expect(ItemHitTest27.isInsideItem(point: CGPoint(x: 1497, y: 14), items: [stats], concealedPIDs: [], systemFrames: [clock]))
    }

    @Test("An empty spot is not inside an item")
    func emptySpot() {
        #expect(!ItemHitTest27.isInsideItem(point: CGPoint(x: 900, y: 12), items: [stats], concealedPIDs: [], systemFrames: [clock]))
    }

    @Test("A concealed item's stale frame does not count")
    func concealed() {
        #expect(!ItemHitTest27.isInsideItem(point: CGPoint(x: 1497, y: 14), items: [stats], concealedPIDs: [100], systemFrames: []))
    }

    @Test("A folded item does not count, but the overflow button does")
    func overflow() {
        #expect(!ItemHitTest27.isInsideItem(point: CGPoint(x: -640, y: 114), items: [folded], concealedPIDs: [], systemFrames: []))
        #expect(ItemHitTest27.isInsideItem(point: CGPoint(x: -611, y: 114), items: [folded], concealedPIDs: [], systemFrames: [overflowButton]))
    }

    @Test("On the inactive display drawn frames count")
    func drawnFramesOnTheInactiveDisplay() {
        // The built-in display's bar is not active: no cached item lies on it, but
        // MenuBarAgent draws an item there.
        let display = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let drawn = CGRect(x: -400, y: 6, width: 30, height: 24)
        #expect(ItemHitTest27.isInsideItem(point: CGPoint(x: -385, y: 18), items: [stats], concealedPIDs: [], systemFrames: [], drawnFramesOnDisplay: [drawn]))
        #expect(!ItemHitTest27.isInsideItem(point: CGPoint(x: -700, y: 18), items: [stats], concealedPIDs: [], systemFrames: [], drawnFramesOnDisplay: [drawn]))
        #expect(ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: -390, y: 18),
            displayBounds: display,
            items: [stats],
            concealedPIDs: [],
            systemFrames: [],
            rememberedLeftEdge: nil,
            drawnFramesOnDisplay: [drawn]
        ))
        #expect(!ItemHitTest27.isInsideItemsArea(
            point: CGPoint(x: -700, y: 18),
            displayBounds: display,
            items: [stats],
            concealedPIDs: [],
            systemFrames: [],
            rememberedLeftEdge: nil,
            drawnFramesOnDisplay: [drawn]
        ))
    }

    @Test("System items count on either display")
    func systemItems() {
        #expect(ItemHitTest27.isInsideItem(point: CGPoint(x: 1843, y: 12), items: [], concealedPIDs: [], systemFrames: [clock]))
    }
}

@Suite("AccessibilityScanSchedule27")
struct AccessibilityScanSchedule27Tests {
    @Test("A process is asked with the normal timeout")
    func normal() {
        let schedule = AccessibilityScanSchedule27()
        #expect(schedule.timeout(for: 10, now: 0) == AccessibilityScanSchedule27.normalTimeout)
    }

    @Test("A process that timed out is skipped for a minute, then retried briefly")
    func backoff() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0)
        #expect(schedule.timeout(for: 10, now: 1) == nil)
        #expect(schedule.timeout(for: 10, now: 59) == nil)
        #expect(schedule.timeout(for: 10, now: 60) == AccessibilityScanSchedule27.retryTimeout)
        schedule.record(pid: 10, timedOut: true, now: 60)
        #expect(schedule.timeout(for: 10, now: 179) == nil)
        #expect(schedule.timeout(for: 10, now: 180) == AccessibilityScanSchedule27.retryTimeout)
    }

    @Test("The pause stops growing at ten minutes")
    func cap() {
        var schedule = AccessibilityScanSchedule27()
        var now: TimeInterval = 0
        for _ in 0..<8 {
            schedule.record(pid: 10, timedOut: true, now: now)
            while schedule.timeout(for: 10, now: now) == nil {
                now += 1
            }
        }
        schedule.record(pid: 10, timedOut: true, now: now)
        #expect(schedule.timeout(for: 10, now: now + 599) == nil)
        #expect(schedule.timeout(for: 10, now: now + 600) == AccessibilityScanSchedule27.retryTimeout)
    }

    @Test("A process that answers is asked normally again")
    func recovery() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0)
        schedule.record(pid: 10, timedOut: false, now: 60)
        #expect(schedule.timeout(for: 10, now: 61) == AccessibilityScanSchedule27.normalTimeout)
    }

    @Test("A process that has shown items is never skipped")
    func itemOwners() {
        var schedule = AccessibilityScanSchedule27()
        schedule.recordItems(pid: 10)
        schedule.record(pid: 10, timedOut: true, now: 0)
        #expect(schedule.timeout(for: 10, now: 1) == AccessibilityScanSchedule27.normalTimeout)
    }

    @Test("An exited item owner is forgotten too")
    func exitedItemOwner() {
        var schedule = AccessibilityScanSchedule27()
        schedule.recordItems(pid: 10)
        schedule.retain(running: [11])
        schedule.record(pid: 10, timedOut: true, now: 0)
        #expect(schedule.timeout(for: 10, now: 1) == nil)
    }

    @Test("A young process that may own an item is retried at the normal timeout")
    func youngProcessIsNotPaused() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0, isYoung: true)
        #expect(schedule.timeout(for: 10, now: 0) == AccessibilityScanSchedule27.normalTimeout)
        #expect(schedule.youngRetries == 1)
        schedule.record(pid: 10, timedOut: true, now: 2, isYoung: true)
        #expect(schedule.timeout(for: 10, now: 2) == AccessibilityScanSchedule27.normalTimeout)
        #expect(schedule.youngRetries == 2)
        // An answer is no retry.
        schedule.record(pid: 10, timedOut: false, now: 4, isYoung: true)
        #expect(schedule.youngRetries == 2)
    }

    @Test("An old process keeps today's pause of 60 s, then 120 s")
    func oldProcessKeepsThePause() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0, isYoung: false)
        #expect(schedule.timeout(for: 10, now: 59) == nil)
        #expect(schedule.timeout(for: 10, now: 60) == AccessibilityScanSchedule27.retryTimeout)
        schedule.record(pid: 10, timedOut: true, now: 60, isYoung: false)
        #expect(schedule.timeout(for: 10, now: 179) == nil)
        #expect(schedule.timeout(for: 10, now: 180) == AccessibilityScanSchedule27.retryTimeout)
        #expect(schedule.youngRetries == 0)
    }

    @Test("A process that grows old after young timeouts is paused from its first old timeout")
    func youngThenOld() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0, isYoung: true)
        schedule.record(pid: 10, timedOut: true, now: 31, isYoung: false)
        #expect(schedule.timeout(for: 10, now: 90) == nil)
        #expect(schedule.timeout(for: 10, now: 91) == AccessibilityScanSchedule27.retryTimeout)
    }

    @Test("A young process that reports items becomes an item owner")
    func youngProcessBecomesItemOwner() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0, isYoung: true)
        schedule.recordItems(pid: 10)
        schedule.record(pid: 10, timedOut: true, now: 60, isYoung: false)
        #expect(schedule.timeout(for: 10, now: 61) == AccessibilityScanSchedule27.normalTimeout)
        // An item owner that times out is no young retry either.
        #expect(schedule.youngRetries == 1)
    }

    @Test("A young process counts as young for 30 s")
    func youngAge() {
        #expect(AccessibilityScanSchedule27.youngAge == 30)
    }

    @Test("Exited processes are forgotten, so a reused identifier starts fresh")
    func forgetting() {
        var schedule = AccessibilityScanSchedule27()
        schedule.record(pid: 10, timedOut: true, now: 0)
        schedule.retain(running: [11])
        #expect(schedule.timeout(for: 10, now: 1) == AccessibilityScanSchedule27.normalTimeout)
    }
}
