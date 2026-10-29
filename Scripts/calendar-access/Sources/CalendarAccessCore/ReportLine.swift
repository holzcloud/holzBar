//
//  ReportLine.swift
//  calendar-access
//

import Foundation

/// The report format of the probe: `TAG key=value ...` in the order the caller gives, a value
/// with a space or a quote quoted, an unknown value written as `-`.
public enum ReportLine {
    public static func format(tag: String, _ pairs: [(String, String?)]) -> String {
        let parts = pairs.map { key, value in "\(key)=\(render(value))" }
        return ([tag] + parts).joined(separator: " ")
    }

    private static func render(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        guard value.contains(where: { $0 == " " || $0 == "\"" || $0 == "\t" }) else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
