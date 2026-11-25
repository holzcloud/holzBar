//
//  ReopenRequests.swift
//  holzBar
//

import AppKit
import OSLog

/// Reads who sent a reopen and decides, through ``ReopenGate``, whether it opens Settings.
///
/// The sender comes from the Apple event the system is delivering: the process that sent it
/// and, when the system relayed it, the process it came from. Both are mapped to bundle
/// identifiers, which never leave this type except in the gate's decision; the log keeps them
/// private and the counters hold numbers only.
///
/// The approach (read the sender attributes of the current Apple event, ignore reopens that do
/// not come from the user) follows MonitorControl 4.4.0's fix for the same problem on macOS 27
/// (MIT licence). The code is holzBar's own.
@MainActor
enum ReopenRequests {
    private static let logger = Logger(category: "ReopenRequests")

    /// How many reopens opened Settings since holzBar started.
    private(set) static var opened = 0

    /// How many reopens were ignored since holzBar started.
    private(set) static var ignored = 0

    /// When a reopen last opened Settings.
    private static var lastOpened: ContinuousClock.Instant?

    /// The sender of the Apple event being handled, or both identifiers `nil` when there is
    /// none or its senders cannot be told.
    static func currentSender() -> ReopenGate.Sender {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return ReopenGate.Sender(bundleID: nil, originalBundleID: nil)
        }
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let originalPID = event.attributeDescriptor(forKeyword: AEKeyword(keyOriginalAddressAttr))?
            .coerce(toDescriptorType: DescType(typeKernelProcessID))?
            .int32Value
        return ReopenGate.Sender(
            bundleID: bundleIdentifier(ofProcess: senderPID),
            originalBundleID: bundleIdentifier(ofProcess: originalPID)
        )
    }

    /// Whether the reopen being handled opens Settings. Counts and logs the outcome.
    static func shouldOpenSettings() -> Bool {
        let sender = currentSender()
        let now = ContinuousClock.now
        let decision = ReopenGate.decide(sender: sender, now: now, lastOpened: lastOpened)
        switch decision {
        case .openSettings:
            lastOpened = now
            opened += 1
            logger.debug("Reopen opens Settings (sender \(sender.bundleID ?? "none", privacy: .private), original \(sender.originalBundleID ?? "none", privacy: .private))")
            return true
        case .ignore(let reason):
            ignored += 1
            logger.debug("Reopen ignored: \(reason.rawValue, privacy: .public) (sender \(sender.bundleID ?? "none", privacy: .private), original \(sender.originalBundleID ?? "none", privacy: .private))")
            return false
        }
    }

    /// The bundle identifier of the running process, or `nil` for a missing, invalid or
    /// unknown process identifier.
    private static func bundleIdentifier(ofProcess processIdentifier: Int32?) -> String? {
        guard let processIdentifier, processIdentifier > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }
}
