//
//  WhatsNewGrouping.swift
//  holzBar
//

import Foundation

/// The releases of one minor version, such as every `1.0.x`: a sub tab of the What's New window.
nonisolated struct WhatsNewMinorGroup: Identifiable, Equatable, Sendable {
    let major: Int
    let minor: Int
    /// The versions of this minor, newest first.
    let versions: [String]

    var id: String { "\(major).\(minor)" }

    /// The tab's name, always with three numbers (`1.0.0`, `1.2.0`).
    var label: String { "\(major).\(minor).0" }
}

/// The minors of one major version, such as every `1.x.x`: a main tab of the What's New window.
nonisolated struct WhatsNewMajorGroup: Identifiable, Equatable, Sendable {
    let major: Int
    /// The minors, oldest first, the order of the tabs.
    let minors: [WhatsNewMinorGroup]

    var id: String { "\(major)" }

    /// The tab's name, always with three numbers (`1.0.0`, `2.0.0`).
    var label: String { "\(major).0.0" }
}

/// Sorts a list of versions into main tabs (major) and sub tabs (minor); the patch versions of a
/// minor stay together, newest first, to be shown as sections one below the other.
nonisolated enum WhatsNewGrouping {
    /// The majors and minors of the given versions, both oldest first. A version that is not a
    /// number with dots is left out; a beta counts as its stable version.
    static func majors(of versions: [String]) -> [WhatsNewMajorGroup] {
        var byMinor: [Int: [Int: [(text: String, version: AppVersion)]]] = [:]
        for text in versions {
            guard let version = AppVersion(text), let numbers = numbers(of: text) else {
                continue
            }
            byMinor[numbers.major, default: [:]][numbers.minor, default: []].append((text, version))
        }
        return byMinor.keys.sorted().map { major in
            let minors = (byMinor[major] ?? [:]).keys.sorted().map { minor in
                let sorted = (byMinor[major]?[minor] ?? []).sorted { $0.version > $1.version }
                return WhatsNewMinorGroup(major: major, minor: minor, versions: sorted.map(\.text))
            }
            return WhatsNewMajorGroup(major: major, minors: minors)
        }
    }

    /// The ids of the main tab and the sub tab that hold a version, or `nil` when none does.
    static func location(of version: String?, in majors: [WhatsNewMajorGroup]) -> (major: String, minor: String)? {
        guard let version, let numbers = numbers(of: version),
            let major = majors.first(where: { $0.major == numbers.major }),
            let minor = major.minors.first(where: { $0.minor == numbers.minor }) else {
            return nil
        }
        return (major.id, minor.id)
    }

    private static func numbers(of text: String) -> (major: Int, minor: Int)? {
        let core = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard let first = parts.first, let major = first else {
            return nil
        }
        return (major, parts.count > 1 ? (parts[1] ?? 0) : 0)
    }
}
