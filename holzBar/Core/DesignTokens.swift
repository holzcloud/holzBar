//
//  DesignTokens.swift
//  holzBar
//

import Foundation

/// The values of holzBar's design system: colours, radii, spacing and type sizes.
///
/// The values live here, apart from SwiftUI, so that a test can check them: every text
/// colour must keep its contrast over the ground it is drawn on. The views read them
/// through `HolzBarTheme`; no view uses a raw colour, radius or spacing of its own.
nonisolated enum DesignTokens {
    /// A colour in the sRGB colour space with components from 0 to 1.
    nonisolated struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Creates a colour from a value written as 0xRRGGBB.
        init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }

        static let white = RGB(hex: 0xFFFFFF)
        static let black = RGB(hex: 0x000000)

        /// The colour that results from drawing this colour with the given opacity over a
        /// background.
        func blended(over background: RGB, alpha: Double) -> RGB {
            RGB(
                red: red * alpha + background.red * (1 - alpha),
                green: green * alpha + background.green * (1 - alpha),
                blue: blue * alpha + background.blue * (1 - alpha)
            )
        }

        /// The relative luminance as WCAG 2.2 defines it.
        var relativeLuminance: Double {
            func linear(_ component: Double) -> Double {
                component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    /// A colour with an opacity, such as white at 70 % for secondary text.
    nonisolated struct Tint: Equatable, Sendable {
        let color: RGB
        let alpha: Double

        /// The colour as it appears over a background.
        func over(_ background: RGB) -> RGB {
            color.blended(over: background, alpha: alpha)
        }
    }

    /// The contrast ratio of two colours, from 1 to 21, as WCAG 2.2 defines it.
    static func contrastRatio(_ first: RGB, _ second: RGB) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: Colours

    /// The colours of the dark appearance, which is designed first.
    nonisolated enum Dark {
        static let ground = RGB(hex: 0x0A1426)
        static let groundBottom = RGB(hex: 0x070D1A)
        static let groundElevated = RGB(hex: 0x101C33)
        static let stroke = Tint(color: .white, alpha: 0.10)
        static let text = RGB.white
        static let textSecondary = Tint(color: .white, alpha: 0.70)
        static let textTertiary = Tint(color: .white, alpha: 0.50)
        static let accent = RGB(hex: 0x5EC0F2)
        static let success = RGB(hex: 0x4ADE80)
        static let warning = RGB(hex: 0xFBBF24)
        static let danger = RGB(hex: 0xF87171)
        static let permission = RGB(hex: 0xA78BFA)
        static let wood = RGB(hex: 0xC98B4F)
    }

    /// The colours of the light appearance.
    nonisolated enum Light {
        static let ground = RGB(hex: 0xF3F7FB)
        /// The bottom of the window ground's vertical gradient.
        static let groundBottom = RGB(hex: 0xEAF1F8)
        static let groundElevated = RGB(hex: 0xFFFFFF)
        static let stroke = Tint(color: .black, alpha: 0.08)
        static let text = RGB(hex: 0x0B1220)
        static let textSecondary = Tint(color: .black, alpha: 0.62)
        static let textTertiary = Tint(color: .black, alpha: 0.58)
        static let accent = RGB(hex: 0x1A6FA2)
        static let success = RGB(hex: 0x15803D)
        static let warning = RGB(hex: 0x92400E)
        static let danger = RGB(hex: 0xDC2626)
        static let permission = RGB(hex: 0x6D28D9)
        static let wood = RGB(hex: 0xA66F3A)
    }

    /// The values that replace their counterparts in `Dark` and `Light` while Increase
    /// Contrast is on: a stronger border and stronger secondary and tertiary text.
    nonisolated enum IncreasedContrast {
        nonisolated enum Dark {
            static let stroke = Tint(color: .white, alpha: 0.50)
            static let textSecondary = Tint(color: .white, alpha: 0.85)
            static let textTertiary = Tint(color: .white, alpha: 0.75)
        }

        nonisolated enum Light {
            static let stroke = Tint(color: .black, alpha: 0.50)
            static let textSecondary = Tint(color: .black, alpha: 0.80)
            static let textTertiary = Tint(color: .black, alpha: 0.75)
        }
    }

    /// The opacity of the Preview badge's tint behind its text.
    static let badgeFillAlpha: Double = 0.15

    /// The Notch hub, which is always dark: its ground, its parts and the strength of its small
    /// texts. The sizes and alphas are the design's numbers for the hub and its widget card.
    nonisolated enum Hub {
        /// The silhouette at the top: pure black, one object with the hardware notch.
        static let top = RGB.black
        /// The silhouette at the bottom: a dark blue-grey. Tuned on a Mac.
        static let bottom = RGB(hex: 0x111A2B)
        /// How opaque the silhouette is at the bottom where glass shows through. Tuned on a Mac.
        static let bottomAlphaOnGlass: Double = 0.55
        /// An icon strip tab.
        static let tabWidth: Double = 30
        static let tabHeight: Double = 24
        static let tabRadius: Double = 8
        /// The widths the whole row of tabs steps down through before any tab goes into the More
        /// menu: 30 points, then 28, then 26, the smallest. The height stays 24 and the hit area
        /// stays the whole top row.
        static let tabWidthSteps: [Double] = [30, 28, 26]
        /// The space between two tabs of the row.
        static let tabGap: Double = 2
        /// The round settings button of the right wing.
        static let settingsButtonSize: Double = 24
        /// What a status pill is estimated to need, so that the row of tabs can leave room for the
        /// pills without measuring them: a conservative width per character of the pill's text
        /// (11 point semibold with monospaced digits is about 6.6 points wide), the symbol, the
        /// space between symbol and text, and the padding on both sides of the pill.
        static let pillCharacterWidth: Double = 7
        static let pillSymbolWidth: Double = 14
        static let pillInnerSpacing = Spacing.xxs
        static let pillPadding = Spacing.xs
        /// The space between the parts of the right group: the pills and the settings button.
        static let pillSpacing = Spacing.xs
        /// The fill of a status pill: white at 9 percent.
        static let pillFillAlpha: Double = 0.09
        /// The fill of a tab: tinted when selected, white at 8 percent otherwise.
        static let selectedTabFillAlpha: Double = 0.18
        static let idleTabFillAlpha: Double = 0.08
        /// The symbol of a tab that is not selected.
        static let idleTabSymbolAlpha: Double = 0.6
        /// The colour of a module without one of its own: white at 70 percent.
        static let neutralAlpha: Double = 0.7
        /// The type sizes of the wings' parts.
        static let pillTextSize: Double = 11
        static let tabSymbolSize: Double = 13
        /// The type sizes of the compact live-activity capsule: the symbol and the phrase.
        static let compactSymbolSize: Double = 16
        static let compactTitleSize: Double = 12
        /// The widget card: radius, padding, the gap between cards and the columns of a row.
        static let tileRadius: Double = 14
        static let tilePadding: Double = 10
        static let tileGap: Double = 6
        static let columns = 4
        /// The small texts of a widget card: the name and the quiet line, normally and under
        /// Increase Contrast, which strengthens them.
        static let tileLabelAlpha: Double = 0.45
        static let tileDetailAlpha: Double = 0.40
        static let tileLabelAlphaIncreased: Double = 0.70
        static let tileDetailAlphaIncreased: Double = 0.70
        /// The fill of a widget card, normally and under Reduce Transparency.
        static let tileFillAlpha: Double = 0.045
        static let tileFillAlphaOpaque: Double = 0.10
        /// The File drop tab's file tile: its size, the type icon, the remove button's circle and
        /// the border (white at 6 percent). A missing file is drawn at half strength.
        static let fileTileWidth: Double = 72
        static let fileTileHeight: Double = 84
        static let fileIconSize: Double = 40
        static let fileRemoveSize: Double = 18
        static let fileTileBorderAlpha: Double = 0.06
        static let fileMissingAlpha: Double = 0.5
        /// The outline of the File drop tab while a file is dragged over it: its width, the
        /// lengths of dash and gap, and the words in it (12 pt, white at 85 percent).
        static let fileDropOutlineWidth: Double = 1.5
        static let fileDropOutlineDash: [Double] = [6, 4]
        static let fileDropOutlineAlpha: Double = 0.8
        static let fileDropLabelSize: Double = 12
        static let fileDropLabelAlpha: Double = 0.85
        /// The black behind those words, so they read over the tiles.
        static let fileDropScrimAlpha: Double = 0.6
    }

    /// The gradient of fills that carry white text, the same in both appearances.
    nonisolated enum Fill {
        static let start = RGB(hex: 0x1C78AE)
        static let end = RGB(hex: 0x165F8F)
        static let label = RGB.white
    }

    /// The gradient of decorations without text, such as the glow of a progress bar.
    nonisolated enum Glow {
        static let start = RGB(hex: 0x1C78AE)
        static let end = RGB(hex: 0x5EC0F2)
    }

    // MARK: Shapes and spacing

    /// Corner radii in points. A shape inside another shape uses the outer radius minus
    /// the padding between them.
    nonisolated enum Radius {
        static let keyCap: Double = 6
        static let control: Double = 8
        static let card: Double = 16
        static let panel: Double = 22
        static let hub: Double = 28
    }

    /// The spacing scale in points.
    nonisolated enum Spacing {
        static let scale: [Double] = [4, 8, 12, 16, 20, 24, 32, 48]
        static let hairline: Double = 1
        /// The outline of the Shelf while a dragged menu bar item is over it.
        static let dropOutline: Double = 2
        static let xxs: Double = 4
        static let xs: Double = 8
        static let sm: Double = 12
        static let md: Double = 16
        static let lg: Double = 20
        static let xl: Double = 24
        static let xxl: Double = 32
        static let huge: Double = 48
    }

    /// The shadow of the floating bar (the holzBar Shelf, detached): black at 30 %, a blur of
    /// 20 points (SwiftUI's radius is half of it) and a drop of 4. It is tighter than the
    /// popover and hub shadow because a bar is small and close to the bar above it. The panel's
    /// transparent insets hold it.
    nonisolated enum Shadow {
        static let barOpacity: Double = 0.30
        static let barRadius: Double = 10
        static let barOffsetY: Double = 4
    }

    // MARK: Type

    /// The type sizes in points. The first seven are the main scale of the design; the others
    /// exist because screens built earlier use them, and new screens use the main seven.
    nonisolated enum TypeSize {
        static let title: Double = 22
        static let headline: Double = 15
        static let body: Double = 13
        static let callout: Double = 12
        static let caption: Double = 11
        static let searchField: Double = 21
        static let mono: Double = 12
        /// Badges.
        static let micro: Double = 10
        /// The About pane's lines.
        static let lead: Double = 14
        /// The version line of the About pane; the size of `headline`, in regular weight.
        static let subtitle: Double = 15
        /// The title of the Permissions window.
        static let titleLarge: Double = 40
        /// The title of the About pane.
        static let display: Double = 64
        /// Acknowledgement texts and other small monospaced text.
        static let monoMicro: Double = 10
    }

    /// Spacing that the form components keep from the design of Ice and that is not on the
    /// scale. Each is named, so that no raw number is left in the components, and pinned by a
    /// test, so that it stays what it was.
    nonisolated enum Layout {
        /// The space between the rows of a form.
        static let formRowSpacing: Double = 10
        /// The space between the rows of a section on macOS 26 and later.
        static let sectionRowSpacing: Double = 11
        /// The space between the rows of a section before macOS 26.
        static let sectionRowSpacingLegacy: Double = 10
        /// The gap between a header or footer and the card it belongs to.
        static let headerGap: Double = 2
    }

    /// The smallest size of anything the pointer or a finger must hit, in points.
    static let minimumTargetSize: Double = 24

    /// The sizes of a picture card (a small picture with a name under it) and of the widest
    /// picture drawn on one, so a row of cards keeps its cards from ever being narrower than
    /// their pictures.
    nonisolated enum PictureCard {
        /// The space between the card's edge and its picture's well.
        static let padding = Spacing.xs
        /// The width of the animation picture's strip: four items with a gap between them and
        /// room on both sides. It is the widest picture of a card.
        static let animationStripWidth = Spacing.sm * 2 + Spacing.sm * 4 + Spacing.xs * 3
        /// The narrowest a card may be: its widest picture and the padding on both sides.
        static let minimumWidth = animationStripWidth + padding * 2
        /// The space between the cards of a row.
        static let gap = Spacing.sm
    }

    /// The minimum contrast ratios the design asks for.
    nonisolated enum RequiredContrast {
        /// Body text and anything smaller than 18 pt.
        static let text: Double = 4.5
        /// Large text and the borders of controls.
        static let component: Double = 3.0
    }
}
