//
//  MenuBarAssessmentAssertion27.swift
//  holzBar
//
//  Adapted from Barometer's MenuBarAssessmentAssertion.swift
//  (https://github.com/mackid1993/Barometer), itself adapted from Thaw's
//  PlatformRuntimeKit (https://github.com/thaw-app/Thaw). Both are licensed
//  under the GNU GPLv3, like holzBar.
//

import Foundation
import os

/// Hides applications' menu bar items through MenuBarAgent's assessment mode.
///
/// A configuration lists the numbered system items and the bundle identifiers
/// that stay on the bar. While the assertion is live, the bar removes every other
/// application's items. Only a signed application bundle can hold one (measured
/// on macOS 27.0: from a command line tool the call succeeds and hides nothing).
@available(macOS 27.0, *)
@MainActor
final class MenuBarAssessmentAssertion27: ConcealmentBackend27 {
    nonisolated enum Failure: Error, CustomStringConvertible {
        case unavailable
        case rejected(String)
        case timedOut

        var description: String {
            switch self {
            case .unavailable: "MenuBarClientCore is unavailable"
            case .rejected(let reason): "MenuBarAgent rejected the assertion: \(reason)"
            case .timedOut: "MenuBarAgent did not answer within 3 seconds"
            }
        }
    }

    private final class Token: ConcealmentToken27 {
        let assertion: AnyObject

        init(assertion: AnyObject) {
            self.assertion = assertion
        }
    }

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configureSelector = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector = NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")

    /// The system items holzBar keeps on the bar.
    ///
    /// MenuBarAgent numbers its system items, and on macOS 27.0 only 0 (battery), 2 (clock),
    /// 6 (Wi-Fi) and 8 (Control Centre) draw anything. It accepted every number up to 127,
    /// offered one at a time and all at once. holzBar keeps that whole measured range
    /// (`SystemItems27`), so a system item added by a later build is not concealed: holzBar hides
    /// applications' items, not the system's. jordanbaird/Ice#1001 (@carlossantos74) keeps 0 to
    /// 63, which lies inside it.
    ///
    /// Control Centre's capture indicator — the green camera button, orange for the microphone,
    /// indigo for screen sharing — is not one of these numbers and cannot be kept. It is drawn
    /// while no assertion is live and gone while one is, whatever the allowlist holds: every
    /// number to 127, Control Centre's bundle identifier, the capturing application's own. The
    /// small green dot beside the clock is not an item and stays either way. Measured with
    /// `Scripts/macos27/system-item-probe.swift` on macOS 27.0 (2026-09-29).
    private static let systemItems = SystemItems27.allowed.map { NSNumber(value: $0) } as NSArray

    private static let classes: (configuration: AnyClass, assertion: AnyClass)? = {
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configuration = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertion = NSClassFromString("MBAssessmentModeAssertion"),
            configuration.instancesRespond(to: configureSelector),
            assertion.instancesRespond(to: activateSelector),
            assertion.instancesRespond(to: invalidateSelector)
        else {
            return nil
        }
        return (configuration, assertion)
    }()

    /// Whether this macOS build offers the assertion.
    static var isAvailable: Bool {
        classes != nil
    }

    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27 {
        guard
            let classes = Self.classes,
            let configuration = (classes.configuration.alloc() as AnyObject)
                .perform(Self.configureSelector, with: Self.systemItems, with: allowedBundleIDs as NSArray)?
                .takeUnretainedValue(),
            let assertion = (classes.assertion.alloc() as AnyObject)
                .perform(NSSelectorFromString("init"))?
                .takeUnretainedValue()
        else {
            throw Failure.unavailable
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // The completion handler and the timeout share the continuation; the first
                // one to claim it resumes it.
                let isClaimed = OSAllocatedUnfairLock(initialState: false)
                let claim: @Sendable () -> Bool = {
                    isClaimed.withLock { isClaimed in
                        defer { isClaimed = true }
                        return !isClaimed
                    }
                }
                // MenuBarAgent may call the handler on any queue, so it is not main-actor isolated.
                let completion: @convention(block) @Sendable (Any?) -> Void = { error in
                    guard claim() else {
                        return
                    }
                    if let error {
                        continuation.resume(throwing: Failure.rejected(String(describing: error)))
                    } else {
                        continuation.resume()
                    }
                }
                _ = assertion.perform(Self.activateSelector, with: configuration, with: completion)
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard claim() else {
                        return
                    }
                    continuation.resume(throwing: Failure.timedOut)
                }
            }
        } catch {
            _ = assertion.perform(Self.invalidateSelector)
            throw error
        }
        return Token(assertion: assertion)
    }

    func invalidate(_ token: ConcealmentToken27) {
        guard let token = token as? Token else {
            return
        }
        _ = token.assertion.perform(Self.invalidateSelector)
    }
}
