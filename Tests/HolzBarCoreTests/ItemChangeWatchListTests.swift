import Foundation
import Testing
@testable import HolzBarCore

// `#expect` cannot take a mutating call, so results are bound first.
@Suite("ItemChangeWatchList")
struct ItemChangeWatchListTests {
    /// An item's location in the window with the given identifier.
    private func at(_ windowID: UInt32, pid: pid_t = 100) -> ItemChangeWatchList.Location {
        ItemChangeWatchList.Location(windowID: windowID, pid: pid)
    }

    @Test("A new list removes the observers and registers every item")
    func newList() throws {
        var list = ItemChangeWatchList()
        let update = list.update(windows: ["a": at(1), "b": at(2)], retrying: false)
        #expect(update.removesObservers)
        let registration = try #require(update.registration)
        #expect(registration.keys == ["a", "b"])
        let isCurrent = list.finish(registration, observed: ["a", "b"])
        #expect(isCurrent)
        #expect(list.watchedWindows == ["a": at(1), "b": at(2)])
    }

    @Test("An unchanged list registers nothing again")
    func unchanged() throws {
        var list = ItemChangeWatchList()
        let registration = try #require(list.update(windows: ["a": at(1)], retrying: false).registration)
        _ = list.finish(registration, observed: ["a"])
        let update = list.update(windows: ["a": at(1)], retrying: false)
        #expect(!update.removesObservers)
        #expect(update.registration == nil)
    }

    @Test("Only observed items count as watched; a retry tries the others alone (F-71)")
    func onlyObservedCount() throws {
        var list = ItemChangeWatchList()
        let first = try #require(list.update(windows: ["a": at(1), "b": at(2)], retrying: false).registration)
        _ = list.finish(first, observed: ["a"])
        #expect(list.watchedWindows == ["a": at(1)])
        let retries = list.takeRetry()
        #expect(retries)
        let retry = list.update(windows: ["a": at(1), "b": at(2)], retrying: true)
        #expect(!retry.removesObservers)
        let second = try #require(retry.registration)
        #expect(second.keys == ["b"])
        _ = list.finish(second, observed: ["b"])
        #expect(list.watchedWindows == ["a": at(1), "b": at(2)])
        let retriesAgain = list.takeRetry()
        #expect(!retriesAgain)
    }

    @Test("A registration of an older list is discarded")
    func outdated() throws {
        var list = ItemChangeWatchList()
        let old = try #require(list.update(windows: ["a": at(1)], retrying: false).registration)
        // The item's window changed while the registration was under way.
        let new = try #require(list.update(windows: ["a": at(3)], retrying: false).registration)
        let isOldCurrent = list.finish(old, observed: ["a"])
        #expect(!isOldCurrent)
        #expect(list.watchedWindows.isEmpty)
        let isNewCurrent = list.finish(new, observed: ["a"])
        #expect(isNewCurrent)
        #expect(list.watchedWindows == ["a": at(3)])
    }

    @Test("Retries stop after three for one list and start over for a new one")
    func retryLimit() throws {
        var list = ItemChangeWatchList()
        var registration = try #require(list.update(windows: ["a": at(1)], retrying: false).registration)
        for _ in 0..<ItemChangeWatchList.maximumRetries {
            _ = list.finish(registration, observed: [])
            let retries = list.takeRetry()
            #expect(retries)
            registration = try #require(list.update(windows: ["a": at(1)], retrying: true).registration)
        }
        _ = list.finish(registration, observed: [])
        let retriesAfterLimit = list.takeRetry()
        #expect(!retriesAfterLimit)
        let next = try #require(list.update(windows: ["a": at(2)], retrying: false).registration)
        _ = list.finish(next, observed: [])
        let retriesNewList = list.takeRetry()
        #expect(retriesNewList)
    }

    @Test("An empty list removes the observers and registers nothing")
    func emptyList() throws {
        var list = ItemChangeWatchList()
        let registration = try #require(list.update(windows: ["a": at(1)], retrying: false).registration)
        _ = list.finish(registration, observed: ["a"])
        let update = list.update(windows: [:], retrying: false)
        #expect(update.removesObservers)
        #expect(update.registration == nil)
        let retries = list.takeRetry()
        #expect(!retries)
    }

    @Test("A relaunched app's item keeps its window but is registered again (F-71)")
    func relaunchKeepsWindow() throws {
        var list = ItemChangeWatchList()
        let registration = try #require(list.update(windows: ["a": at(1, pid: 100)], retrying: false).registration)
        _ = list.finish(registration, observed: ["a"])
        // On macOS 27 the synthetic window identifier does not depend on the process.
        let update = list.update(windows: ["a": at(1, pid: 200)], retrying: false)
        #expect(update.removesObservers)
        let again = try #require(update.registration)
        #expect(again.keys == ["a"])
        _ = list.finish(again, observed: ["a"])
        #expect(list.watchedWindows == ["a": at(1, pid: 200)])
    }
}
