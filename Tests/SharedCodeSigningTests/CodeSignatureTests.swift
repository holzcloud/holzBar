import Foundation
import LightweightCodeRequirements
import Security
import Testing
@testable import SharedCodeSigning

/// Proves that the code directory hashes `CodeSignature` reads from disk are the
/// ones `CodeDirectoryHash` compares for a running process. The menu bar item
/// service pins holzBar's ad hoc build with exactly such a requirement.
@Suite("CodeSignature")
struct CodeSignatureTests {
    @Test("The hashes of this process's code are distinct 20-byte hashes")
    func hashesOfThisProcess() throws {
        let hashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: CodeSignature.currentCodeURL())
        #expect(!hashes.isEmpty)
        #expect(hashes.allSatisfy { $0.count == 20 }, "hash sizes: \(hashes.map(\.count))")
        #expect(Set(hashes).count == hashes.count, "\(hashes.count) hashes")
    }

    @Test("This process's code has a signing identifier")
    func signingIdentifierOfThisProcess() throws {
        let identifier = try CodeSignature.signingIdentifier(ofCodeAt: CodeSignature.currentCodeURL())
        #expect(!identifier.isEmpty)
    }

    @Test("A requirement on identifier and hashes matches this process")
    @available(macOS 15.0, *)
    func requirementMatchesThisProcess() throws {
        let url = try CodeSignature.currentCodeURL()
        let identifier = try CodeSignature.signingIdentifier(ofCodeAt: url)
        let hashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: url)
        let result = try validateThisProcess(identifier: identifier, hashes: hashes)
        #expect(
            result.signatureIsValid,
            "failureReason \(result.failureReason), \(hashes.count) hashes, identifier \(identifier)"
        )
        #expect(
            result.requirementMatched,
            "failureReason \(result.failureReason), \(hashes.count) hashes, identifier \(identifier)"
        )
    }

    @Test("Another signing identifier does not match")
    @available(macOS 15.0, *)
    func otherIdentifierDoesNotMatch() throws {
        let hashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: CodeSignature.currentCodeURL())
        let result = try validateThisProcess(identifier: "com.example.not-this-process", hashes: hashes)
        #expect(
            !result.requirementMatched,
            "failureReason \(result.failureReason), \(hashes.count) hashes"
        )
    }

    @Test("Another program's hashes do not match")
    @available(macOS 15.0, *)
    func otherProgramsHashesDoNotMatch() throws {
        let url = try CodeSignature.currentCodeURL()
        let identifier = try CodeSignature.signingIdentifier(ofCodeAt: url)
        let ownHashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: url)
        let otherHashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: URL(fileURLWithPath: "/usr/bin/true"))
        #expect(Set(ownHashes).isDisjoint(with: otherHashes))
        let result = try validateThisProcess(identifier: identifier, hashes: otherHashes)
        #expect(
            !result.requirementMatched,
            "failureReason \(result.failureReason), \(otherHashes.count) hashes"
        )
    }

    @Test("Code that does not exist has no hashes")
    func missingCodeThrows() {
        let url = URL(fileURLWithPath: "/nonexistent/CodeSignatureTests/missing")
        #expect(throws: CodeSignature.Failure.self) {
            try CodeSignature.codeDirectoryHashes(ofCodeAt: url)
        }
    }

    /// Checks this running process against a requirement on the given signing
    /// identifier and code directory hashes.
    @available(macOS 15.0, *)
    private func validateThisProcess(identifier: String, hashes: [Data]) throws -> ValidationResult {
        let requirement = try ProcessCodeRequirement.allOf {
            SigningIdentifier(identifier)
            CodeDirectoryHash.in(hashes)
        }
        var selfCode: SecCode?
        let status = SecCodeCopySelf([], &selfCode)
        try #require(status == errSecSuccess, "SecCodeCopySelf failed with status \(status)")
        let code = try #require(selfCode)
        return SecCodeCheckValidityWithProcessRequirement(code: code, flags: [], requirement: requirement)
    }
}
