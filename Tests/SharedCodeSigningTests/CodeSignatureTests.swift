import Foundation
import Testing
@testable import SharedCodeSigning

/// On macOS 26 holzBar asks apps signed by Apple first which menu bar item window is
/// theirs. The tests use programs they start, not the test process: xctest is signed by
/// Apple when it comes with Xcode or the Command Line Tools.
@Suite("CodeSignature")
struct CodeSignatureTests {
    @Test("A running program of macOS is signed by Apple")
    func appleProgram() throws {
        try withRunningProgram(at: URL(filePath: "/bin/sleep")) { pid in
            #expect(CodeSignature.isSignedByApple(processIdentifier: pid))
        }
    }

    // Before macOS 26 an ad hoc signed arm64e program may not run on Apple silicon, and
    // only the macOS 26 backend asks for signatures.
    @Test("An ad hoc signed copy of that program is not")
    @available(macOS 26.0, *)
    func adHocCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CodeSignatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let copy = directory.appending(path: "sleep")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: copy)
        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", copy.path(percentEncoded: false)]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        try #require(codesign.terminationStatus == 0)

        try withRunningProgram(at: copy) { pid in
            #expect(!CodeSignature.isSignedByApple(processIdentifier: pid))
        }
    }

    @Test("A process that has exited is not")
    func exitedProcess() throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        #expect(!CodeSignature.isSignedByApple(processIdentifier: process.processIdentifier))
    }

    /// Starts the program at the given location, waiting 30 s, passes its process to
    /// `body` while it runs, and stops it afterwards.
    private func withRunningProgram(at url: URL, _ body: (pid_t) throws -> Void) throws {
        let process = Process()
        process.executableURL = url
        process.arguments = ["30"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }
        // The program must really run, or a "not signed by Apple" result would prove nothing.
        try #require(kill(process.processIdentifier, 0) == 0)
        try body(process.processIdentifier)
    }
}
