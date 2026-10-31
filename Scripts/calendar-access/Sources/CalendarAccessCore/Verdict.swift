//
//  Verdict.swift
//  calendar-access
//

import Foundation

/// The four signature variants of the probe.
public enum Variant: String, CaseIterable, Sendable {
    case v1, v2, v3, v4

    /// Whether the variant is signed with holzBar's release certificate (otherwise ad hoc).
    public var usesReleaseCertificate: Bool {
        self == .v3 || self == .v4
    }

    /// Whether the variant carries `com.apple.security.personal-information.calendars`.
    public var hasCalendarsEntitlement: Bool {
        self == .v2 || self == .v4
    }

    /// The bundle identifier of the variant, so macOS keeps one answer per variant.
    public var bundleIdentifier: String {
        "ch.holzcloud.holzbar.calendarprobe.\(rawValue)"
    }
}

/// What `EKEventStore.authorizationStatus(for: .event)` reported.
public enum AccessStatus: String, Sendable {
    case notDetermined, restricted, denied, writeOnly, fullAccess, other
}

/// How one variant ended.
public enum Outcome: String, Sendable {
    /// Granted, and the store could be read.
    case readable
    /// Not granted.
    case denied
    /// Granted, but reading the store failed.
    case unreadable
}

/// What one run of one variant observed.
public struct Observation: Sendable, Equatable {
    public let variant: Variant
    public let statusAfter: AccessStatus
    public let granted: Bool
    public let storeReadable: Bool

    public init(variant: Variant, statusAfter: AccessStatus, granted: Bool, storeReadable: Bool) {
        self.variant = variant
        self.statusAfter = statusAfter
        self.granted = granted
        self.storeReadable = storeReadable
    }

    /// `readable` only when the status after is full access and the request was granted;
    /// full access with a store that returned an error is `unreadable`.
    public var outcome: Outcome {
        guard statusAfter == .fullAccess, granted else { return .denied }
        return storeReadable ? .readable : .unreadable
    }
}

/// The three results of the spike, a pure function of the variants' observations.
public enum Verdict {
    public enum Result: String, Sendable {
        case entitlementNotNeeded = "ENTITLEMENT-NOT-NEEDED"
        case entitlementRequired = "ENTITLEMENT-REQUIRED"
        case noGo = "NO-GO"
    }

    /// The criteria fixed in the phase's context before any run: V1 or V3 readable means the
    /// entitlement is not needed; otherwise V2 or V4 readable means it is required; otherwise
    /// no-go. Variants that were not run (absent) never count as readable.
    public static func evaluate(_ observations: [Observation]) -> (result: Result, reason: String) {
        if observations.isEmpty {
            return (.noGo, "no run")
        }
        let readable = Set(observations.filter { $0.outcome == .readable }.map(\.variant))
        let without = readable.filter { !$0.hasCalendarsEntitlement }
        let with = readable.filter(\.hasCalendarsEntitlement)
        if !without.isEmpty {
            return (.entitlementNotNeeded, "\(names(without)) read the store without the entitlement")
        }
        if !with.isEmpty {
            return (.entitlementRequired, "\(names(with)) read the store with the entitlement, no variant without it did")
        }
        return (.noGo, "no variant was granted and could read the store")
    }

    private static func names(_ variants: Set<Variant>) -> String {
        variants.map { $0.rawValue.uppercased() }.sorted().joined(separator: " and ")
    }
}
