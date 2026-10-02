import Foundation
import Testing
@testable import HolzBarCore

@Suite("ItemImageFolder")
struct ItemImageFolderTests {
    /// A folder of its own for one test, with the old and the new place of the images.
    private struct Sandbox {
        let root: URL
        var legacyParent: URL { root.appending(path: "Application Support/holzBar", directoryHint: .isDirectory) }
        var legacy: URL { legacyParent.appending(path: "ItemImages", directoryHint: .isDirectory) }
        var destination: URL { root.appending(path: "Caches/com.holzcloud.holzBar/ItemImages", directoryHint: .isDirectory) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func write(_ names: [String], in folder: URL) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in names {
                try Data(name.utf8).write(to: folder.appending(path: name))
            }
        }

        func contents(of folder: URL) throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        }

        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("Old images are moved to the caches")
    func oldImagesAreMoved() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.write(["a.png", "b.png"], in: sandbox.legacy)

        let outcome = try ItemImageFolder.moveLegacyFolder(from: sandbox.legacy, to: sandbox.destination)

        #expect(outcome == .moved)
        #expect(try sandbox.contents(of: sandbox.destination) == ["a.png", "b.png"])
        #expect(!sandbox.exists(sandbox.legacy))
    }

    @Test("Images already in the caches win over old ones")
    func imagesInTheCachesWin() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.write(["old.png"], in: sandbox.legacy)
        try sandbox.write(["new.png"], in: sandbox.destination)

        let outcome = try ItemImageFolder.moveLegacyFolder(from: sandbox.legacy, to: sandbox.destination)

        #expect(outcome == .removedOldCopy)
        #expect(try sandbox.contents(of: sandbox.destination) == ["new.png"])
        #expect(!sandbox.exists(sandbox.legacy))
    }

    @Test("Nothing happens without old images")
    func nothingHappensWithoutOldImages() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        let outcome = try ItemImageFolder.moveLegacyFolder(from: sandbox.legacy, to: sandbox.destination)

        #expect(outcome == .nothingToMove)
        #expect(try sandbox.contents(of: sandbox.root).isEmpty)
    }

    @Test("The empty old folder is removed")
    func emptyOldFolderIsRemoved() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.write(["a.png"], in: sandbox.legacy)

        _ = try ItemImageFolder.moveLegacyFolder(from: sandbox.legacy, to: sandbox.destination)

        #expect(!sandbox.exists(sandbox.legacyParent))
        #expect(sandbox.exists(sandbox.legacyParent.deletingLastPathComponent()))
    }

    @Test("A non-empty old folder is kept")
    func nonEmptyOldFolderIsKept() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.write(["a.png"], in: sandbox.legacy)
        try sandbox.write(["Other.plist"], in: sandbox.legacyParent)

        _ = try ItemImageFolder.moveLegacyFolder(from: sandbox.legacy, to: sandbox.destination)

        #expect(try sandbox.contents(of: sandbox.legacyParent) == ["Other.plist"])
    }
}
