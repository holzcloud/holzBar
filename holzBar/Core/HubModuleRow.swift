//
//  HubModuleRow.swift
//  holzBar
//

import Foundation

/// How the Notch hub's row of module buttons fits the island (concept section 10b, "Layout").
nonisolated enum HubModuleRow {
    /// How the row is drawn.
    nonisolated struct Fit: Equatable, Sendable {
        var buttonSize: Double
        var hubWidth: Double
        var scrolls: Bool
    }

    static func rowWidth(count: Int, buttonSize: Double) -> Double {
        0
    }

    static func fit(count: Int, baseWidth: Double, maxWidth: Double) -> Fit {
        Fit(buttonSize: 0, hubWidth: 0, scrolls: false)
    }
}
