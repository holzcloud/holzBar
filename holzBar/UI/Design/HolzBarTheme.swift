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
        /// The bottom of the window ground's vertical gradient, a little deeper than `ground`.
        static let groundBottom = Color(
            light: DesignTokens.Light.groundBottom,
            dark: DesignTokens.Dark.groundBottom
        )
        /// Cards and grouped content.
        static let groundElevated = Color(
            light: DesignTokens.Light.groundElevated,
            dark: DesignTokens.Dark.groundElevated
        )
        /// Hairline borders; stronger while Increase Contrast is on.
        static let stroke = Color(
            light: DesignTokens.Light.stroke,
            dark: DesignTokens.Dark.stroke,
            increasedLight: DesignTokens.IncreasedContrast.Light.stroke,
            increasedDark: DesignTokens.IncreasedContrast.Dark.stroke
        )
        static let text = Color(
            light: DesignTokens.Light.text,
            dark: DesignTokens.Dark.text
        )
        /// Secondary text; stronger while Increase Contrast is on.
        static let textSecondary = Color(
            light: DesignTokens.Light.textSecondary,
            dark: DesignTokens.Dark.textSecondary,
            increasedLight: DesignTokens.IncreasedContrast.Light.textSecondary,
            increasedDark: DesignTokens.IncreasedContrast.Dark.textSecondary
        )
        /// Tertiary text; stronger while Increase Contrast is on.
        static let textTertiary = Color(
            light: DesignTokens.Light.textTertiary,
            dark: DesignTokens.Dark.textTertiary,
            increasedLight: DesignTokens.IncreasedContrast.Light.textTertiary,
            increasedDark: DesignTokens.IncreasedContrast.Dark.textTertiary
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

    /// The shadows the design uses.
    enum Shadow {
        /// The tight shadow of the floating bar.
        static let barOpacity = DesignTokens.Shadow.barOpacity
        static let barRadius = CGFloat(DesignTokens.Shadow.barRadius)
        static let barOffsetY = CGFloat(DesignTokens.Shadow.barOffsetY)
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

    /// Spacing the form components keep from the design of Ice; it is not on the scale.
    enum Layout {
        /// The space between the rows of a form.
        static let formRowSpacing = CGFloat(DesignTokens.Layout.formRowSpacing)
        /// The space between the rows of a section: macOS 26 and later spaces them wider.
        static let sectionRowSpacing: CGFloat = if #available(macOS 26.0, *) {
            CGFloat(DesignTokens.Layout.sectionRowSpacing)
        } else {
            CGFloat(DesignTokens.Layout.sectionRowSpacingLegacy)
        }
        /// The gap between a header or footer and the card it belongs to.
        static let headerGap = CGFloat(DesignTokens.Layout.headerGap)
    }

    /// The smallest size of anything that can be clicked.
    static let minimumTargetSize = CGFloat(DesignTokens.minimumTargetSize)

    /// The opacity of the Preview badge's tint behind its text.
    static let badgeFillOpacity = DesignTokens.badgeFillAlpha

    /// A continuous (squircle) rounded rectangle with a token radius.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    // MARK: Type

    enum Typography {
        static let title = Font.system(size: CGFloat(DesignTokens.TypeSize.title), weight: .semibold)
        static let headline = Font.system(size: CGFloat(DesignTokens.TypeSize.headline), weight: .semibold)
        static let body = Font.system(size: CGFloat(DesignTokens.TypeSize.body))
        static let callout = Font.system(size: CGFloat(DesignTokens.TypeSize.callout))
        static let caption = Font.system(size: CGFloat(DesignTokens.TypeSize.caption))
        static let searchField = Font.system(size: CGFloat(DesignTokens.TypeSize.searchField))
        static let mono = Font.system(size: CGFloat(DesignTokens.TypeSize.mono), design: .monospaced)

        // The sizes below exist because screens built earlier use them; new screens use the
        // seven above.

        /// Badges.
        static let micro = Font.system(size: CGFloat(DesignTokens.TypeSize.micro), weight: .medium)
        /// The About pane's lines.
        static let lead = Font.system(size: CGFloat(DesignTokens.TypeSize.lead))
        /// The version line of the About pane.
        static let subtitle = Font.system(size: CGFloat(DesignTokens.TypeSize.subtitle))
        /// The title of the Permissions window.
        static let titleLarge = Font.system(size: CGFloat(DesignTokens.TypeSize.titleLarge), weight: .medium)
        /// The title of the About pane.
        static let display = Font.system(size: CGFloat(DesignTokens.TypeSize.display))
        /// Acknowledgement texts and other small monospaced text.
        static let monoMicro = Font.system(size: CGFloat(DesignTokens.TypeSize.monoMicro), design: .monospaced)

        /// The text of the Settings sidebar. Its size is not a token: it follows the sidebar
        /// icon size the user chose in System Settings, so the size is a parameter.
        static func sidebar(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.system(size: size, weight: weight)
        }
    }

    // MARK: Notch hub

    /// The Notch hub is always dark; these values are drawn on its ground.
    enum Hub {
        /// The silhouette's colour at the top, pure black, and at the bottom, a dark blue-grey.
        static let top = Color(DesignTokens.Hub.top)
        static let bottom = Color(DesignTokens.Hub.bottom)
        /// Black fading to a dark blue-grey, from the top to the bottom.
        static let silhouetteGradient = LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
        /// The same fade with a bottom that lets glass show through.
        static let translucentGradient = LinearGradient(
            colors: [top, bottom.opacity(DesignTokens.Hub.bottomAlphaOnGlass)],
            startPoint: .top,
            endPoint: .bottom
        )
        /// Text on the hub's ground.
        static let pillText = Color.white
        /// White at 70 percent, the colour of a module without one of its own.
        static let neutral = Color.white.opacity(DesignTokens.Hub.neutralAlpha)
        static let tabSize = CGSize(width: DesignTokens.Hub.tabWidth, height: DesignTokens.Hub.tabHeight)
        static let tabRadius = CGFloat(DesignTokens.Hub.tabRadius)
        static let settingsButtonSize = CGFloat(DesignTokens.Hub.settingsButtonSize)
        static let pillFill = Color.white.opacity(DesignTokens.Hub.pillFillAlpha)
        static let selectedTabFillOpacity = DesignTokens.Hub.selectedTabFillAlpha
        static let idleTabFill = Color.white.opacity(DesignTokens.Hub.idleTabFillAlpha)
        static let idleTabSymbol = Color.white.opacity(DesignTokens.Hub.idleTabSymbolAlpha)
        static let pillFont = Font.system(size: CGFloat(DesignTokens.Hub.pillTextSize), weight: .semibold)
        static let tabSymbolFont = Font.system(size: CGFloat(DesignTokens.Hub.tabSymbolSize))
        /// The compact live-activity capsule: the activity's symbol and its phrase.
        static let compactSymbolFont = Font.system(size: CGFloat(DesignTokens.Hub.compactSymbolSize))
        static let compactTitleFont = Font.system(size: CGFloat(DesignTokens.Hub.compactTitleSize), weight: .semibold)
        static let columns = DesignTokens.Hub.columns
        static let tileGap = CGFloat(DesignTokens.Hub.tileGap)
    }

    // MARK: Motion

    enum Motion {
        /// State changes of cards and panels.
        static let smooth = Animation.smooth(duration: 0.3)
        /// Switches and chips.
        static let snappy = Animation.snappy
        /// The Notch hub opening, the one place the design uses a bounce.
        static let hub = Animation.bouncy(duration: 0.4, extraBounce: 0.1)
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

    /// A colour with an opacity that follows the appearance of the view it is drawn in and
    /// takes stronger values while Increase Contrast is on. macOS draws with one of the two
    /// high-contrast appearances then, which is how a custom colour learns about the setting.
    init(
        light: DesignTokens.Tint,
        dark: DesignTokens.Tint,
        increasedLight: DesignTokens.Tint,
        increasedDark: DesignTokens.Tint
    ) {
        self.init(nsColor: NSColor(name: nil) { @Sendable appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua
            ])
            let tint = switch match {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: increasedLight
            case .accessibilityHighContrastDarkAqua: increasedDark
            default: light
            }
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
