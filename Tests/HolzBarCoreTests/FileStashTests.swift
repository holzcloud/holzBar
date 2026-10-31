import Foundation
import Testing
@testable import HolzBarCore

@Suite("FileStash")
struct FileStashTests {
    /// A generator of ids that count up, so a test knows every id.
    private final class Counter {
        var next = 0

        static func id(_ number: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
        }

        func make() -> UUID {
            next += 1
            return Counter.id(next)
        }
    }

    private func urls(_ paths: [String]) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }
    }

    private func paths(of stash: FileStash) -> [String] {
        stash.files.map(\.url.path)
    }

    @Test("Three file URLs added in one batch are kept in the batch's order")
    func batchKeepsOrder() {
        var stash = FileStash()
        let counter = Counter()
        let result = stash.add(urls(["/a/one.txt", "/a/two.txt", "/a/three.txt"]), makeID: counter.make)
        #expect(result == FileStash.AddResult(added: 3, moved: 0, ignored: 0, refusedFull: 0))
        #expect(paths(of: stash) == ["/a/one.txt", "/a/two.txt", "/a/three.txt"])
        #expect(stash.files.allSatisfy { !$0.isMissing })
    }

    @Test("A URL that is not an absolute file path is ignored and counted")
    func oddURLsAreIgnored() throws {
        var stash = FileStash()
        let odd: [URL] = try [
            #require(URL(string: "https://example.com/file.txt")),
            #require(URL(string: "file://")),
            URL(fileURLWithPath: "/"),
            #require(URL(string: "file:///")),
            URL(fileURLWithPath: "/a/.."),
            #require(URL(string: "mailto:a@example.com")),
        ]
        let result = stash.add(odd)
        #expect(result == FileStash.AddResult(added: 0, moved: 0, ignored: odd.count, refusedFull: 0))
        #expect(stash.files.isEmpty)

        let mixed = stash.add(odd + urls(["/ok.txt"]))
        #expect(mixed == FileStash.AddResult(added: 1, moved: 0, ignored: odd.count, refusedFull: 0))
        #expect(paths(of: stash) == ["/ok.txt"])
    }

    @Test("The same path in one batch counts once, and a trailing slash or dots make no difference")
    func samePathIsOneKey() {
        #expect(FileStash.key(for: URL(fileURLWithPath: "/Users/a/Docs/")) == "/Users/a/Docs")
        #expect(FileStash.key(for: URL(fileURLWithPath: "/Users/a/Docs")) == "/Users/a/Docs")
        #expect(FileStash.key(for: URL(fileURLWithPath: "/Users/a/./x/../Docs")) == "/Users/a/Docs")

        var stash = FileStash()
        let result = stash.add(urls(["/Users/a/Docs/", "/Users/a/Docs", "/Users/a/./x/../Docs", "/Users/a/b.txt"]))
        #expect(result == FileStash.AddResult(added: 2, moved: 0, ignored: 0, refusedFull: 0))
        #expect(stash.files.count == 2)
        #expect(stash.keys == ["/Users/a/Docs", "/Users/a/b.txt"])
    }

    @Test("A path that is already stashed moves to the front, keeps its id and does not grow the stash")
    func dropAgainMovesToFront() {
        var stash = FileStash()
        let counter = Counter()
        stash.add(urls(["/a/one", "/a/two", "/a/three"]), makeID: counter.make)
        let twoID = stash.files[1].id

        let result = stash.add(urls(["/a/two/"]), makeID: counter.make)
        #expect(result == FileStash.AddResult(added: 0, moved: 1, ignored: 0, refusedFull: 0))
        #expect(stash.files.count == 3)
        #expect(stash.keys == ["/a/two", "/a/one", "/a/three"])
        #expect(stash.files[0].id == twoID)
        #expect(counter.next == 3)
    }

    @Test("A later batch goes in front of an earlier one and a batch keeps its own order")
    func laterBatchComesFirst() {
        var stash = FileStash()
        stash.add(urls(["/a/one", "/a/two"]))
        stash.add(urls(["/b/one", "/b/two", "/a/two"]))
        #expect(paths(of: stash) == ["/b/one", "/b/two", "/a/two", "/a/one"])
    }

    @Test("At most fifty files: a further new path is refused and counted, a stashed one still moves")
    func limitIsFifty() {
        #expect(FileStash.maximumFiles == 50)
        var stash = FileStash()
        let first = (1...50).map { "/files/\($0)" }
        #expect(stash.add(urls(first)).added == 50)
        #expect(stash.files.count == 50)

        let refused = stash.add(urls(["/files/new"]))
        #expect(refused == FileStash.AddResult(added: 0, moved: 0, ignored: 0, refusedFull: 1))
        #expect(stash.files.count == 50)
        #expect(!stash.keys.contains("/files/new"))
        // Nothing old was dropped to make room.
        #expect(Set(stash.keys) == Set(first))

        let moved = stash.add(urls(["/files/50", "/files/new"]))
        #expect(moved == FileStash.AddResult(added: 0, moved: 1, ignored: 0, refusedFull: 1))
        #expect(stash.files.first?.url.path == "/files/50")
        #expect(stash.files.count == 50)
    }

    @Test("A batch of ten into a stash of forty-five adds five and refuses five")
    func batchIsCutAtTheLimit() {
        var stash = FileStash()
        stash.add(urls((1...45).map { "/files/\($0)" }))
        let batch = urls((1...10).map { "/batch/\($0)" })
        let result = stash.add(batch)
        #expect(result == FileStash.AddResult(added: 5, moved: 0, ignored: 0, refusedFull: 5))
        #expect(stash.files.count == 50)
        // The first five of the batch were taken, in order, at the front.
        #expect(Array(stash.keys.prefix(5)) == (1...5).map { "/batch/\($0)" })
    }

    @Test("Removing an id keeps the others in order, an unknown id changes nothing, removeAll empties")
    func removing() {
        var stash = FileStash()
        stash.add(urls(["/a/one", "/a/two", "/a/three"]))
        let middle = stash.files[1].id

        stash.remove(middle)
        #expect(paths(of: stash) == ["/a/one", "/a/three"])

        let before = stash
        stash.remove(UUID())
        #expect(stash == before)

        stash.removeAll()
        #expect(stash.files.isEmpty)
    }

    @Test("Ids come from the supplied generator")
    func idsAreDeterministic() {
        var stash = FileStash()
        let counter = Counter()
        stash.add(urls(["/a", "/b"]), makeID: counter.make)
        #expect(stash.files.map(\.id) == [Counter.id(1), Counter.id(2)])
    }
}
