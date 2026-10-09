//
//  HolzBarTheme.swift
//  holzBar
//

import AppKit
import SwiftUI

/// holzBar's design tokens as SwiftUI values.
///
/// Views take every colour, radius, spacing and type size from here and never use a raw
/// value of their own. The values themselves are in `DesignTokens`, where tests check them.
enum HolzBarTheme {
    // MARK: Colour

    enum Palette {
        /// The window background behind glass.
        static let ground = Color(
            light: DesignTokens.Light.ground,
            dark: DesignTokens.Dark.ground
        )
        /// Cards and grouped content.
        static let groundElevated = Color(
            light: DesignTokens.Light.groundElevated,
            dark: DesignTokens.Dark.groundElevated
        )
        /// Hairline borders.
        static let stroke = Color(
            light: DesignTokens.Light.stroke,
            dark: DesignTokens.Dark.stroke
        )
        static let text = Color(
            light: DesignTokens.Light.text,
            dark: DesignTokens.Dark.text
        )
        static let textSecondary = Color(
            light: DesignTokens.Light.textSecondary,
            dark: DesignTokens.Dark.textSecondary
        )
        static let textTertiary = Color(
            light: DesignTokens.Light.textTertiary,
            dark: DesignTokens.Dark.textTertiary
        )
        /// The one accent: tints, links and the glow of active elements.
        static let accent = Color(
            light: DesignTokens.Light.accent,
            dark: DesignTokens.Dark.accent
        )
        static let success = Color(
            light: DesignTokens.Light.success,
            dark: DesignTokens.Dark.success
        )
        static let warning = Color(
            light: DesignTokens.Light.warning,
            dark: DesignTokens.Dark.warning
        )
        static let danger = Color(
            light: DesignTokens.Light.danger,
            dark: DesignTokens.Dark.danger
        )
        /// A module that needs a permission.
        static let permission = Color(
            light: DesignTokens.Light.permission,
            dark: DesignTokens.Dark.permission
        )
        /// The warm secondary accent from the logo's plank, used rarely.
        static let wood = Color(
            light: DesignTokens.Light.wood,
            dark: DesignTokens.Dark.wood
        )
        /// The text on top of `fillGradient`.
        static let onFill = Color(DesignTokens.Fill.label)
    }

    /// The gradient of fills that carry white text: primary buttons, active chips.
    static let fillGradient = LinearGradient(
        colors: [Color(DesignTokens.Fill.start), Color(DesignTokens.Fill.end)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The gradient of decorations without text, such as the glow of a gauge.
    static let glowGradient = LinearGradient(
        colors: [Color(DesignTokens.Glow.start), Color(DesignTokens.Glow.end)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Shape and spacing

    enum Radius {
        static let keyCap = CGFloat(DesignTokens.Radius.keyCap)
        static let control = CGFloat(DesignTokens.Radius.control)
        static let card = CGFloat(DesignTokens.Radius.card)
        static let panel = CGFloat(DesignTokens.Radius.panel)
        static let hub = CGFloat(DesignTokens.Radius.hub)
    }

    enum Spacing {
        static let hairline = CGFloat(DesignTokens.Spacing.hairline)
        static let xxs = CGFloat(DesignTokens.Spacing.xxs)
        static let xs = CGFloat(DesignTokens.Spacing.xs)
        static let sm = CGFloat(DesignTokens.Spacing.sm)
        static let md = CGFloat(DesignTokens.Spacing.md)
        static let lg = CGFloat(DesignTokens.Spacing.lg)
        static let xl = CGFloat(DesignTokens.Spacing.xl)
        static let xxl = CGFloat(DesignTokens.Spacing.xxl)
        static let huge = CGFloat(DesignTokens.Spacing.huge)
    }

    /// The smallest size of anything that can be clicked.
    static let minimumTargetSize = CGFloat(DesignTokens.minimumTargetSize)

    /// A continuous (squircle) rounded rectangle with a token radius.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // MARK: Type

    enum Typography {
        static let title = Font.system(size: 22, weight: .semibold)
        static let headline = Font.system(size: 15, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let searchField = Font.system(size: 21)
        static let mono = Font.system(size: 12, design: .monospaced)
    }

    // MARK: Motion

    enum Motion {
        /// State changes of cards and panels.
        static let smooth = Animation.smooth(duration: 0.3)
        /// Switches and chips.
        static let snappy = Animation.snappy
        /// What Reduce Motion replaces every spring with.
        static let reduced = Animation.easeInOut(duration: 0.15)

        /// The animation to use, given the user's Reduce Motion setting.
        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? reduced : animation
        }
    }
}

// MARK: - Dynamic colours

private extension Color {
    /// A colour that follows the appearance of the view it is drawn in.
    init(light: DesignTokens.RGB, dark: DesignTokens.RGB) {
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light, alpha: 1)
        })
    }

    /// A colour with an opacity that follows the appearance of the view it is drawn in.
    init(light: DesignTokens.Tint, dark: DesignTokens.Tint) {
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let tint = isDark ? dark : light
            return NSColor(rgb: tint.color, alpha: tint.alpha)
        })
    }

    init(_ rgb: DesignTokens.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

private extension NSColor {
    nonisolated convenience init(rgb: DesignTokens.RGB, alpha: Double) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}
