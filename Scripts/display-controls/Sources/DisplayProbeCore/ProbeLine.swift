//
//  ProbeLine.swift
//  display-controls
//

import Foundation

/// The report format of the probe: `TAG key=value ...` in the order the caller gives, a value
/// with a space or a quote quoted, an unknown value written as `-`.
public enum ProbeLine {
    public static func line(_ tag: String, _ pairs: [(String, String?)]) -> String {
        let parts = pairs.map { key, value in "\(key)=\(render(value))" }
        return ([tag] + parts).joined(separator: " ")
    }

    /// The SUMMARY line, in the contract's key order.
    public static func summary(brightness: String?, volume: String?, listener: String?, external: String?) -> String {
        line("SUMMARY", [
            ("brightness", brightness),
            ("volume", volume),
            ("listener", listener),
            ("external", external),
        ])
    }

    /// The line that ends every report.
    public static let endOfReport = "=== end of report ==="

    private static func render(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "-"
        }
        guard value.contains(where: { $0 == " " || $0 == "\"" || $0 == "\t" }) else {
            return value
        }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
