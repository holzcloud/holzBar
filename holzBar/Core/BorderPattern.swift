//
//  BorderPattern.swift
//  holzBar
//

import Foundation

/// How the menu bar's border is drawn (THAW-17).
///
/// The raw values are stored in the appearance configuration; new styles go at the end.
nonisolated enum BorderStyle: Int, Codable, CaseIterable, Sendable {
    case solid = 0
    case dashed = 1
    case dotted = 2
}

/// The dash pattern of a border style, scaled with the border's width.
nonisolated enum BorderPattern {
    /// The lengths of the dashes and gaps, in points, or `nil` for a solid line.
    ///
    /// Dashed: dashes six widths long with gaps of three. Dotted: dots of zero length with
    /// round caps (``usesRoundCaps(_:)``), one width wide, every two widths.
    static func dashes(for style: BorderStyle, width: Double) -> [Double]? {
        let width = max(width, 0.5)
        switch style {
        case .solid:
            return nil
        case .dashed:
            return [6 * width, 3 * width]
        case .dotted:
            return [0, 2 * width]
        }
    }

    /// Whether the line ends are round, which turns zero-length dashes into dots.
    static func usesRoundCaps(_ style: BorderStyle) -> Bool {
        style == .dotted
    }
}
