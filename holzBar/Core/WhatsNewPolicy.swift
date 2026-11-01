//
//  WhatsNewPolicy.swift
//  holzBar
//

import Foundation

/// When the What's New window opens by itself, and which versions it lists.
///
/// The window opens after an update, once per version: when the core version of the running
/// app (`1.0.1` for `1.0.1-beta1`) is greater than the core version last seen. A beta and the
/// stable release of one version therefore share a single showing, a downgrade shows nothing,
/// and a fresh install shows nothing. All inputs are plain strings, so this file does not
/// depend on the release history model.
nonisolated enum WhatsNewPolicy {
    /// The version an install without a stored value counts as having seen: the release
    /// before the window existed.
    static let baselineVersion = "1.0.0"

    /// What to do at launch.
    nonisolated struct Decision: Equatable, Sendable {
        /// Whether to open the window.
        var show: Bool
        /// The core version to store as the last seen one, or `nil` to leave the stored value.
        var record: String?
    }

    /// The versions the window lists.
    nonisolated struct Tabs: Equatable, Sendable {
        /// The versions to list, in the order of the input.
        var versions: [String]
        /// The listed version the running app is, which gets the wood dot; `nil` for none.
        var installed: String?
    }

    /// Whether the window opens at launch, and which version to record.
    ///
    /// - Parameters:
    ///   - lastSeen: The stored last-seen version; `nil` or unparsable counts as ``baselineVersion``.
    ///   - current: The version of the running app.
    ///   - isFreshInstall: Whether this launch is the first one of a new install.
    ///   - showsAfterUpdate: The user's switch. Off still records, so switching it on later
    ///     does not replay old releases.
    ///   - knownVersions: The versions that have an entry in the history.
    static func decide(
        lastSeen: String?,
        current: String?,
        isFreshInstall: Bool,
        showsAfterUpdate: Bool,
        knownVersions: [String]
    ) -> Decision {
        guard let core = current.flatMap(AppVersion.init)?.core,
            knownVersions.contains(where: { AppVersion($0) == core }) else {
            return Decision(show: false, record: nil)
        }
        if isFreshInstall {
            return Decision(show: false, record: core.displayString)
        }
        let seen = lastSeen.flatMap(AppVersion.init)?.core ?? AppVersion(baselineVersion)
        guard let seen, core > seen else {
            return Decision(show: false, record: nil)
        }
        return Decision(show: showsAfterUpdate, record: core.displayString)
    }

    /// The versions to list and the one to mark as installed.
    ///
    /// Versions newer than the running app are left out. When the running version is unknown
    /// (a development build) or leaves nothing, every version is listed and none is marked.
    static func tabs(knownVersions: [String], current: String?) -> Tabs {
        guard let core = current.flatMap(AppVersion.init)?.core else {
            return Tabs(versions: knownVersions, installed: nil)
        }
        let versions = knownVersions.filter { version in
            AppVersion(version).map { $0 <= core } ?? false
        }
        guard !versions.isEmpty else {
            return Tabs(versions: knownVersions, installed: nil)
        }
        return Tabs(versions: versions, installed: versions.first { AppVersion($0) == core })
    }
}
