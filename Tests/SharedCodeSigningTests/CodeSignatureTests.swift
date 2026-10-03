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
            "failureReason \(result.failureReason), \(hashes.count) hashes, identifier \(identifier), \(taskValidation(identifier: identifier, hashes: hashes))"
        )
        #expect(
            result.requirementMatched,
            "failureReason \(result.failureReason), \(hashes.count) hashes, identifier \(identifier), \(taskValidation(identifier: identifier, hashes: hashes))"
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
        let otherHashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: URL(filePath: "/usr/bin/true"))
        #expect(Set(ownHashes).isDisjoint(with: otherHashes))
        let result = try validateThisProcess(identifier: identifier, hashes: otherHashes)
        #expect(
            !result.requirementMatched,
            "failureReason \(result.failureReason), \(otherHashes.count) hashes"
        )
    }

    @Test("Code that does not exist has no hashes")
    func missingCodeThrows() {
        let url = URL(filePath: "/nonexistent/CodeSignatureTests/missing")
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
        return try SecCodeCheckValidityWithProcessRequirement(
            code: codeOfThisProcess(),
            flags: [],
            requirement: requirement
        )
    }

    /// Returns the code of this running process, looked up by its audit token
    /// the way the system looks up an XPC peer.
    private func codeOfThisProcess() throws -> SecCode {
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        // task_self_trap() instead of the global mach_task_self_, which older
        // SDKs (macOS 15.2) do not mark as concurrency-safe in Swift 6.
        let task = task_self_trap()
        defer { mach_port_deallocate(task, task) }
        let result = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
                task_info(task, task_flavor_t(TASK_AUDIT_TOKEN), info, &count)
            }
        }
        try #require(result == KERN_SUCCESS, "task_info failed with \(result)")
        let tokenData = withUnsafeBytes(of: token) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var code: SecCode?
        let status = SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)
        try #require(status == errSecSuccess, "SecCodeCopyGuestWithAttributes failed with status \(status)")
        return try #require(code)
    }

    /// Describes how `SecTaskValidateForRequirement` judges this process
    /// against the same requirement, and which hashes were compared, for the
    /// log of a failing run.
    @available(macOS 15.0, *)
    private func taskValidation(identifier: String, hashes: [Data]) -> String {
        let hex = { (data: Data) in data.map { String(format: "%02x", $0) }.joined() }
        var running = "unknown"
        if let code = try? codeOfThisProcess() {
            var information: CFDictionary?
            let flags = SecCSFlags(rawValue: UInt32(kSecCSDynamicInformation))
            // A running process's code is passed as static code to read its dynamic information.
            let staticCode = unsafeBitCast(code, to: SecStaticCode.self)
            if SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
               let unique = (information as NSDictionary?)?[kSecCodeInfoUnique as String] as? Data {
                running = hex(unique)
            }
        }
        return "hashes \(hashes.map(hex)), running cdhash \(running), " + taskResult(identifier: identifier, hashes: hashes)
    }

    @available(macOS 15.0, *)
    private func taskResult(identifier: String, hashes: [Data]) -> String {
        do {
            let requirement = try ProcessCodeRequirement.allOf {
                SigningIdentifier(identifier)
                CodeDirectoryHash.in(hashes)
            }
            guard let task = SecTaskCreateFromSelf(nil) else {
                return "SecTaskCreateFromSelf returned nil"
            }
            return "SecTaskValidateForRequirement returned \(try SecTaskValidateForRequirement(task: task, requirement: requirement))"
        } catch {
            return "SecTaskValidateForRequirement threw \(error)"
        }
    }
}
