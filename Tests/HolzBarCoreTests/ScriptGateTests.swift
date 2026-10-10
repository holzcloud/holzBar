import Foundation
import Testing
@testable import HolzBarCore

@Suite("ScriptGate")
struct ScriptGateTests {
    private func info(
        name: String = "backup.sh",
        regular: Bool = true,
        symlink: Bool = false,
        owned: Bool = true,
        mode: UInt16 = 0o755,
        quarantine: Bool = false,
        size: Int = 200,
        hash: String = "abc"
    ) -> ScriptFileInfo {
        ScriptFileInfo(
            name: name,
            isRegularFile: regular,
            isSymbolicLink: symlink,
            isOwnedByCurrentUser: owned,
            mode: mode,
            hasQuarantineAttribute: quarantine,
            size: size,
            sha256: hash
        )
    }

    @Test("An approved plain script is allowed")
    func allowed() {
        #expect(ScriptGate.decide(info(), approvedHash: "abc") == .allowed(.executable))
        #expect(ScriptGate.decide(info(name: "x.scpt", mode: 0o644), approvedHash: "abc") == .allowed(.appleScript))
    }

    @Test("An unapproved script, or one that changed, needs approval")
    func needsApproval() {
        #expect(ScriptGate.decide(info(), approvedHash: nil) == .needsApproval)
        #expect(ScriptGate.decide(info(hash: "changed"), approvedHash: "abc") == .needsApproval)
    }

    @Test("Every unsafe file is refused, whatever was approved")
    func refusals() {
        #expect(ScriptGate.decide(info(name: "../x.sh"), approvedHash: "abc") == .refused(.badName))
        #expect(ScriptGate.decide(info(name: ".hidden.sh"), approvedHash: "abc") == .refused(.badName))
        #expect(ScriptGate.decide(info(symlink: true), approvedHash: "abc") == .refused(.symbolicLink))
        #expect(ScriptGate.decide(info(regular: false), approvedHash: "abc") == .refused(.notRegularFile))
        #expect(ScriptGate.decide(info(owned: false), approvedHash: "abc") == .refused(.notOwnedByUser))
        #expect(ScriptGate.decide(info(mode: 0o775), approvedHash: "abc") == .refused(.writableByOthers))
        #expect(ScriptGate.decide(info(mode: 0o757), approvedHash: "abc") == .refused(.writableByOthers))
        #expect(ScriptGate.decide(info(quarantine: true), approvedHash: "abc") == .refused(.quarantined))
        #expect(ScriptGate.decide(info(size: ScriptGate.maximumSize + 1), approvedHash: "abc") == .refused(.tooLarge))
        #expect(ScriptGate.decide(info(mode: 0o644), approvedHash: "abc") == .refused(.notExecutable))
    }

    @Test("Names are plain or refused")
    func names() {
        #expect(ScriptGate.isPlainName("backup.sh"))
        #expect(!ScriptGate.isPlainName(""))
        #expect(!ScriptGate.isPlainName(".x"))
        #expect(!ScriptGate.isPlainName("a/b.sh"))
        #expect(!ScriptGate.isPlainName("a\nb.sh"))
        #expect(!ScriptGate.isPlainName(String(repeating: "a", count: 300)))
        #expect(!ScriptGate.isPlainName(String(repeating: "a", count: 256)))
        #expect(ScriptGate.isPlainName(String(repeating: "a", count: 255)))
    }

    @Test("Names with spaces, accents and common punctuation are accepted")
    func ordinaryNames() {
        #expect(ScriptGate.isPlainName("Caf\u{E9} 2.sh"))
        #expect(ScriptGate.isPlainName("Mail-Check.applescript"))
        #expect(ScriptGate.isPlainName("backup (daily).sh"))
        #expect(ScriptGate.isPlainName("e\u{301}.sh"))
    }

    @Test("Names that can fake an extension or hide characters are refused")
    func deceptiveNames() {
        // A right-to-left override makes "x\u{202E}hs.txt" display as "xtxt.sh".
        #expect(!ScriptGate.isPlainName("x\u{202E}hs.txt"))
        // A zero-width space is invisible.
        #expect(!ScriptGate.isPlainName("backup\u{200B}.sh"))
        // A line separator and a next line break the pane's line.
        #expect(!ScriptGate.isPlainName("backup\u{2028}.sh"))
        #expect(!ScriptGate.isPlainName("backup\u{2029}.sh"))
        #expect(!ScriptGate.isPlainName("backup\u{85}.sh"))
        // Private use characters have no meaning.
        #expect(!ScriptGate.isPlainName("backup\u{E000}.sh"))
        // The delete character and other C0 and C1 controls.
        #expect(!ScriptGate.isPlainName("backup\u{7F}.sh"))
        #expect(!ScriptGate.isPlainName("backup\u{9B}.sh"))
        #expect(!ScriptGate.isPlainName("\u{FEFF}backup.sh"))
    }

    @Test("A scptd bundle is a folder, so it is refused even when approved")
    func bundleIsRefused() {
        #expect(ScriptGate.kind(forName: "x.scptd") == .executable)
        #expect(
            ScriptGate.decide(info(name: "x.scptd", regular: false, mode: 0o755), approvedHash: "abc")
                == .refused(.notRegularFile)
        )
    }

    private func folder(
        directory: Bool = true,
        symlink: Bool = false,
        owned: Bool = true,
        mode: UInt16 = 0o700
    ) -> ScriptFolderInfo {
        ScriptFolderInfo(isDirectory: directory, isSymbolicLink: symlink, isOwnedByCurrentUser: owned, mode: mode)
    }

    @Test("A folder the user owns and nobody else can write is fine")
    func safeFolder() {
        #expect(ScriptGate.folderRefusal(folder(mode: 0o700)) == nil)
        #expect(ScriptGate.folderRefusal(folder(mode: 0o755)) == nil)
    }

    @Test("A folder that others can write, that is not the user's, or that is not a folder is refused")
    func unsafeFolder() {
        #expect(ScriptGate.folderRefusal(folder(mode: 0o775)) == .writableByOthers)
        #expect(ScriptGate.folderRefusal(folder(mode: 0o757)) == .writableByOthers)
        #expect(ScriptGate.folderRefusal(folder(owned: false)) == .notOwnedByUser)
        #expect(ScriptGate.folderRefusal(folder(directory: false)) == .notDirectory)
        #expect(ScriptGate.folderRefusal(folder(symlink: true)) == .symbolicLink)
    }

    @Test("A link is refused first, even when it also fails the other rules")
    func linkFirst() {
        let everythingWrong = folder(directory: false, symlink: true, owned: false, mode: 0o777)
        #expect(ScriptGate.folderRefusal(everythingWrong) == .symbolicLink)
        let notOwnedAndWritable = folder(owned: false, mode: 0o777)
        #expect(ScriptGate.folderRefusal(notOwnedAndWritable) == .notOwnedByUser)
    }

    // MARK: The folder on disk

    /// A scratch folder with a real folder `real` and a symbolic link `link` to it.
    private func withLinkedFolders(_ body: (_ real: URL, _ link: URL) throws -> Void) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: "holzbar-gate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            try? manager.removeItem(at: root)
        }
        let real = root.appending(path: "real", directoryHint: .isDirectory)
        try manager.createDirectory(at: real, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let link = root.appending(path: "link", directoryHint: .notDirectory)
        try manager.createSymbolicLink(at: link, withDestinationURL: real)
        try body(real, link)
    }

    @Test("Trailing slashes are cut for lstat, the root stays")
    func linkCheckPath() {
        #expect(ScriptGate.pathForLinkCheck("/a/b/") == "/a/b")
        #expect(ScriptGate.pathForLinkCheck("/a/b///") == "/a/b")
        #expect(ScriptGate.pathForLinkCheck("/a/b") == "/a/b")
        #expect(ScriptGate.pathForLinkCheck("/") == "/")
        #expect(ScriptGate.pathForLinkCheck("") == "")
    }

    @Test("A link is seen as a link, also when its path ends in a slash (T-11-M6)")
    func linkOnDisk() throws {
        try withLinkedFolders { real, link in
            // What the store has: the path of a URL made as a directory, which ends in "/".
            let asDirectoryURL = URL(filePath: link.path(percentEncoded: false), directoryHint: .isDirectory)
            let withSlash = asDirectoryURL.path(percentEncoded: false)
            #expect(withSlash.hasSuffix("/"))
            for path in [link.path(percentEncoded: false), withSlash] {
                let found = try #require(ScriptGate.folderInfo(atPath: path))
                #expect(found.isSymbolicLink)
                #expect(ScriptGate.folderRefusal(found) == .symbolicLink)
            }
            let folder = try #require(ScriptGate.folderInfo(atPath: URL(filePath: real.path(percentEncoded: false), directoryHint: .isDirectory).path(percentEncoded: false)))
            #expect(folder.isDirectory)
            #expect(!folder.isSymbolicLink)
            #expect(folder.isOwnedByCurrentUser)
            #expect(folder.mode == 0o700)
            #expect(ScriptGate.folderRefusal(folder) == nil)
        }
    }

    @Test("A folder that others can write and a file in the folder's place are refused on disk")
    func unsafeOnDisk() throws {
        try withLinkedFolders { real, _ in
            let path = real.path(percentEncoded: false)
            #expect(chmod(path, 0o777) == 0)
            let open = try #require(ScriptGate.folderInfo(atPath: path + "/"))
            #expect(ScriptGate.folderRefusal(open) == .writableByOthers)
            let file = real.appending(path: "plain.txt", directoryHint: .notDirectory)
            #expect(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data()))
            let notFolder = try #require(ScriptGate.folderInfo(atPath: file.path(percentEncoded: false)))
            #expect(ScriptGate.folderRefusal(notFolder) == .notDirectory)
            #expect(ScriptGate.folderInfo(atPath: path + "/missing") == nil)
        }
    }

    @Test("At most ten runs a minute")
    func rateLimit() {
        var limiter = ScriptRateLimiter()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<ScriptRateLimiter.maximumRuns {
            let allowed = limiter.allowRun(at: start.addingTimeInterval(Double(index)))
            #expect(allowed)
        }
        let blocked = limiter.allowRun(at: start.addingTimeInterval(30))
        #expect(!blocked)
        let later = limiter.allowRun(at: start.addingTimeInterval(ScriptRateLimiter.window + 1))
        #expect(later)
    }
}
