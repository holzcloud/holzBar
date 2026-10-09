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
        #expect(!ScriptGate.isPlainName("a/b.sh"))
        #expect(!ScriptGate.isPlainName("a\nb.sh"))
        #expect(!ScriptGate.isPlainName(String(repeating: "a", count: 300)))
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
