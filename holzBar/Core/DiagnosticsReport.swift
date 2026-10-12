//
//  DiagnosticsReport.swift
//  holzBar
//

import Foundation

/// The facts of a bug report, already reduced to what is safe to share.
///
/// Every text field holds a version or an identifier of the system, never a name the user
/// chose; ``DiagnosticsReport`` still cleans each of them. The numbers count things (items,
/// profiles) and name none.
nonisolated struct DiagnosticsInput: Equatable, Sendable {
    var appVersion = ""
    var appBuild = ""
    var macOSVersion = ""
    var macOSBuild = ""
    /// The Mac's model identifier, such as `Mac15,6`; never the serial number or the name.
    var modelIdentifier = ""
    var architecture = ""
    /// The way items are read and moved, which depends on the macOS generation.
    var backend = ""
    var displayCount = 0
    var displaysWithNotch = 0
    var accessibilityGranted = false
    var screenRecordingGranted = false
    var launchesAtLogin = false
    var visibleItems = 0
    var hiddenItems = 0
    var alwaysHiddenItems = 0
    var profileCount = 0
    var groupCount = 0
    var spacerCount = 0
    var automationRuleCount = 0
    var snapshotCount = 0
}

/// Writes the text a user can copy into a bug report. It holds an allowlist of facts and
/// nothing else: no item or application names, no profile, rule or network names, no paths,
/// no user or computer name.
nonisolated enum DiagnosticsReport {
    /// The longest text kept for a field.
    static let maximumFieldLength = 40

    /// The report as plain text, in English: it is meant for an issue.
    static func make(_ input: DiagnosticsInput) -> String {
        let lines = [
            "holzBar: \(field(input.appVersion)) (\(field(input.appBuild)))",
            "macOS: \(field(input.macOSVersion)) (\(field(input.macOSBuild)))",
            "Mac: \(field(input.modelIdentifier)), \(field(input.architecture))",
            "Backend: \(field(input.backend))",
            "Displays: \(input.displayCount), with a notch: \(input.displaysWithNotch)",
            "Accessibility: \(yesNo(input.accessibilityGranted))",
            "Screen Recording: \(yesNo(input.screenRecordingGranted))",
            "Launch at login: \(yesNo(input.launchesAtLogin))",
            "Items: \(input.visibleItems) visible, \(input.hiddenItems) hidden, \(input.alwaysHiddenItems) always hidden",
            "Profiles: \(input.profileCount), groups: \(input.groupCount), spacers: \(input.spacerCount)",
            "Automation rules: \(input.automationRuleCount), snapshots: \(input.snapshotCount)",
        ]
        return lines.joined(separator: "\n")
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "granted or on" : "not granted or off"
    }

    /// The text of a field: only letters, digits and the punctuation of versions and model
    /// identifiers, shortened. Anything else, such as a path or a line break, is dropped.
    static func field(_ text: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,-_")
        let cleaned = String(text.filter { allowed.contains($0) }.prefix(maximumFieldLength))
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}
