//
//  CodeSignature.swift
//  Shared
//

import Foundation
import Security

/// Reads the code signatures of running processes.
///
/// Bundle identifiers and process names are chosen by the app itself, so they cannot tell
/// whether a process belongs to macOS. Its code signature can: only code that Apple signed
/// satisfies the requirement `anchor apple`. Third-party apps, also those from the App
/// Store or signed with a Developer ID, do not.
///
/// The calls block while they read the signature, so call them off the main thread.
nonisolated enum CodeSignature {
    /// Whether the running process with the given identifier is signed by Apple.
    ///
    /// The process's code is looked up by its process identifier and checked against the
    /// requirement `anchor apple`. `false` when the process does not exist (any more), its
    /// code is not valid, or it is signed by anyone else, ad hoc included.
    static func isSignedByApple(processIdentifier: pid_t) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
        guard
            SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
            let code
        else {
            return false
        }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
