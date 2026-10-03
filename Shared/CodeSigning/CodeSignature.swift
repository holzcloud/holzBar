//
//  CodeSignature.swift
//  Shared
//

import Foundation
import Security

/// The code signing facts that the XPC peer check between holzBar and its
/// menu bar item service needs.
///
/// This file uses only Security, so it compiles into the app (which still
/// launches on macOS 14.0) as well as into the service.
nonisolated enum CodeSignature {
    /// An error that says which code signing call failed, and how.
    nonisolated struct Failure: Error, CustomStringConvertible {
        /// The code signing call that failed, or a short reason.
        let operation: String

        /// The status the call returned, if it returned one.
        let status: OSStatus?

        init(_ operation: String, status: OSStatus? = nil) {
            self.operation = operation
            self.status = status
        }

        var description: String {
            if let status {
                return "\(operation) failed with status \(status)"
            }
            return operation
        }
    }

    /// The architecture slices whose code directory hashes are collected,
    /// besides the default slice.
    private static let architectures = ["arm64", "arm64e", "x86_64"]

    /// The team identifier of this process's signature.
    ///
    /// The value is `nil` when the signature has no team (ad hoc signing) or
    /// cannot be read. It is read once, the first time it is used.
    static let currentTeamIdentifier: String? = {
        guard
            let code = try? currentStaticCode(),
            let information = try? signingInformation(of: code)
        else {
            return nil
        }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    /// Returns the location of this process's code on disk.
    static func currentCodeURL() throws -> URL {
        let code = try currentStaticCode()
        var url: CFURL?
        try check(SecCodeCopyPath(code, [], &url), "SecCodeCopyPath")
        guard let url else {
            throw Failure("SecCodeCopyPath returned no path")
        }
        return url as URL
    }

    /// Returns the signing identifier of the code at the given location.
    static func signingIdentifier(ofCodeAt url: URL) throws -> String {
        let code = try staticCode(at: url)
        let information = try signingInformation(of: code)
        guard
            let identifier = information[kSecCodeInfoIdentifier as String] as? String,
            !identifier.isEmpty
        else {
            throw Failure("The code has no signing identifier")
        }
        return identifier
    }

    /// Returns the code directory hashes of the code at the given location.
    ///
    /// These are the hashes that `CodeDirectoryHash` compares for a running
    /// process: one or more per architecture slice (one per digest algorithm),
    /// so a universal app matches on every architecture it runs as. The
    /// signature is checked first, on every slice; unsigned or broken code
    /// has nothing worth pinning, so this throws for it.
    static func codeDirectoryHashes(ofCodeAt url: URL) throws -> [Data] {
        let code = try staticCode(at: url)
        let validityFlags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures))
        try check(SecStaticCodeCheckValidity(code, validityFlags, nil), "SecStaticCodeCheckValidity")

        var hashes = [Data]()

        func collectHashes(of code: SecStaticCode) throws {
            let information = try signingInformation(of: code)
            var found = [Data]()
            if let unique = information[kSecCodeInfoUnique as String] as? Data {
                found.append(unique)
            }
            if let list = information[kSecCodeInfoCdHashes as String] as? [Data] {
                found += list
            }
            for hash in found where !hash.isEmpty && !hashes.contains(hash) {
                hashes.append(hash)
            }
        }

        try collectHashes(of: code)

        for architecture in architectures {
            let attributes = [kSecCodeAttributeArchitecture as String: architecture] as CFDictionary
            var slice: SecStaticCode?
            let status = SecStaticCodeCreateWithPathAndAttributes(url as CFURL, [], attributes, &slice)
            guard status == errSecSuccess, let slice else {
                // The binary has no slice for this architecture.
                continue
            }
            try? collectHashes(of: slice)
        }

        guard !hashes.isEmpty else {
            throw Failure("The code has no code directory hash")
        }
        return hashes
    }

    // MARK: Helpers

    /// Throws a failure unless the given status is `errSecSuccess`.
    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == errSecSuccess else {
            throw Failure(operation, status: status)
        }
    }

    /// Returns the static code of this process.
    private static func currentStaticCode() throws -> SecStaticCode {
        var code: SecCode?
        try check(SecCodeCopySelf([], &code), "SecCodeCopySelf")
        guard let code else {
            throw Failure("SecCodeCopySelf returned no code")
        }
        var staticCode: SecStaticCode?
        try check(SecCodeCopyStaticCode(code, [], &staticCode), "SecCodeCopyStaticCode")
        guard let staticCode else {
            throw Failure("SecCodeCopyStaticCode returned no code")
        }
        return staticCode
    }

    /// Returns the static code at the given location.
    private static func staticCode(at url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        try check(SecStaticCodeCreateWithPath(url as CFURL, [], &code), "SecStaticCodeCreateWithPath")
        guard let code else {
            throw Failure("SecStaticCodeCreateWithPath returned no code")
        }
        return code
    }

    /// Returns the signing information of the given static code.
    private static func signingInformation(of code: SecStaticCode) throws -> [String: Any] {
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        try check(SecCodeCopySigningInformation(code, flags, &information), "SecCodeCopySigningInformation")
        guard
            let information,
            let dictionary = (information as NSDictionary) as? [String: Any]
        else {
            throw Failure("SecCodeCopySigningInformation returned no information")
        }
        return dictionary
    }
}
