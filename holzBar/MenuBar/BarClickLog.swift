//
//  BarClickLog.swift
//  holzBar
//

import Foundation

/// The last clicks in the menu bar, kept in memory for the diagnostics (see ``BarClickTrace``).
/// Nothing is written to disk or to a log.
enum BarClickLog {
    static var trace = BarClickTrace()

    /// Whole seconds of system uptime, to order the lines.
    static var seconds: Int {
        Int(ProcessInfo.processInfo.systemUptime)
    }
}
