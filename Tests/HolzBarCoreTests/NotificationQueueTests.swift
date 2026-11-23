import Foundation
import Testing
@testable import HolzBarCore

/// Every identifier here is invented by the tests; the queue holds no text.
@Suite("NotificationQueue")
struct NotificationQueueTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("An empty queue has no count and no end")
    func empty() {
        let queue = NotificationQueue()
        #expect(queue.count == 0)
        #expect(queue.unseen.isEmpty)
        #expect(queue.lastArrival == nil)
        #expect(queue.countEnds(displayTime: 5) == nil)
    }

    @Test("Unseen is newest first and the last arrival is the newest instant")
    func ordering() {
        var queue = NotificationQueue()
        let (a, b, c) = (UUID(), UUID(), UUID())
        queue.arrived(a, at: start)
        queue.arrived(b, at: start.addingTimeInterval(1))
        queue.arrived(c, at: start.addingTimeInterval(2))
        #expect(queue.unseen == [c, b, a])
        #expect(queue.count == 3)
        #expect(queue.lastArrival == start.addingTimeInterval(2))
    }

    @Test("Marking all seen empties the queue and keeps the last arrival")
    func markAllSeen() {
        var queue = NotificationQueue()
        queue.arrived(UUID(), at: start)
        queue.markAllSeen()
        #expect(queue.count == 0)
        #expect(queue.lastArrival == start)
    }

    @Test("Forgetting removes one notification only")
    func forget() {
        var queue = NotificationQueue()
        let (a, b, c) = (UUID(), UUID(), UUID())
        queue.arrived(a, at: start)
        queue.arrived(b, at: start)
        queue.arrived(c, at: start)
        queue.forget(b)
        #expect(queue.unseen == [c, a])
        #expect(!queue.isUnseen(b))
        #expect(queue.isUnseen(c))
        queue.forget(UUID())
        #expect(queue.unseen == [c, a])
    }

    @Test("The front is the newest unseen one and the extra count is the unseen behind it")
    func frontAndExtraCount() {
        var queue = NotificationQueue()
        #expect(queue.front == nil)
        #expect(queue.extraCount == 0)
        let (a, b, c) = (UUID(), UUID(), UUID())
        queue.arrived(a, at: start)
        #expect(queue.front == a)
        #expect(queue.extraCount == 0)
        queue.arrived(b, at: start.addingTimeInterval(1))
        queue.arrived(c, at: start.addingTimeInterval(2))
        #expect(queue.front == c)
        #expect(queue.extraCount == 2)
        queue.forget(UUID())
        #expect(queue.front == c)
        #expect(queue.extraCount == 2)
        queue.forget(c)
        #expect(queue.front == b)
        #expect(queue.extraCount == 1)
        queue.forget(b)
        #expect(queue.front == a)
        #expect(queue.extraCount == 0)
        queue.forget(a)
        #expect(queue.front == nil)
        #expect(queue.extraCount == 0)
    }

    @Test("Marking all seen leaves no front and no extra count")
    func frontAfterMarkAllSeen() {
        var queue = NotificationQueue()
        queue.arrived(UUID(), at: start)
        queue.arrived(UUID(), at: start)
        queue.markAllSeen()
        #expect(queue.front == nil)
        #expect(queue.extraCount == 0)
    }

    @Test("The same identifier twice counts once and does not restart the count")
    func idempotent() {
        var queue = NotificationQueue()
        let id = UUID()
        queue.arrived(id, at: start)
        queue.arrived(id, at: start.addingTimeInterval(4))
        #expect(queue.count == 1)
        #expect(queue.lastArrival == start)
    }

    @Test("Twenty-five arrivals keep the log's twenty, the newest")
    func capped() {
        var queue = NotificationQueue()
        let ids = (0..<25).map { _ in UUID() }
        for (offset, id) in ids.enumerated() {
            queue.arrived(id, at: start.addingTimeInterval(TimeInterval(offset)))
        }
        #expect(queue.count == NotificationLog.maximumRecords)
        #expect(queue.count == 20)
        #expect(queue.unseen.first == ids[24])
        #expect(queue.unseen.last == ids[5])
    }

    @Test("The count text is empty for none, spells 1 to 9 and reads 9+ above")
    func countText() {
        #expect(NotificationQueue.countText(0) == nil)
        #expect(NotificationQueue.countText(-1) == nil)
        #expect(NotificationQueue.countText(1) == "1")
        #expect(NotificationQueue.countText(9) == "9")
        #expect(NotificationQueue.countText(10) == "9+")
        #expect(NotificationQueue.countText(250) == "9+")
    }

    @Test("The display time snaps to the nearest choice, a tie to the shorter, and clamps")
    func displayTime() {
        #expect(NotificationQueue.displayTime(4) == 3)
        #expect(NotificationQueue.displayTime(7) == 5)
        #expect(NotificationQueue.displayTime(8) == 10)
        #expect(NotificationQueue.displayTime(100) == 30)
        #expect(NotificationQueue.displayTime(-3) == 3)
        #expect(NotificationQueue.displayTime(5) == 5)
        for choice in DesignTokens.Indicator.notificationDisplayTimes {
            #expect(NotificationQueue.displayTime(choice) == choice)
        }
    }

    @Test("The count ends exactly at the last arrival plus the display time")
    func countEnds() {
        var queue = NotificationQueue()
        queue.arrived(UUID(), at: start)
        #expect(queue.countEnds(displayTime: 5) == start.addingTimeInterval(5))
        #expect(queue.countEnds(displayTime: 30) == start.addingTimeInterval(30))
        queue.arrived(UUID(), at: start.addingTimeInterval(3))
        #expect(queue.countEnds(displayTime: 5) == start.addingTimeInterval(8))
        queue.markAllSeen()
        #expect(queue.countEnds(displayTime: 5) == start.addingTimeInterval(8))
    }
}
