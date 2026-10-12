//
//  DesignTokens.swift
//  holzBar
//

import Foundation

/// The values of holzBar's design system: colours, radii and spacing.
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
        static let groundElevated = RGB(hex: 0xFFFFFF)
        static let stroke = Tint(color: .black, alpha: 0.08)
        static let text = RGB(hex: 0x0B1220)
        static let textSecondary = Tint(color: .black, alpha: 0.62)
        static let textTertiary = Tint(color: .black, alpha: 0.58)
        static let accent = RGB(hex: 0x1A6FA2)
        static let success = RGB(hex: 0x15803D)
        static let warning = RGB(hex: 0xB45309)
        static let danger = RGB(hex: 0xDC2626)
        static let permission = RGB(hex: 0x6D28D9)
        static let wood = RGB(hex: 0xA66F3A)
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
        static let xxs: Double = 4
        static let xs: Double = 8
        static let sm: Double = 12
        static let md: Double = 16
        static let lg: Double = 20
        static let xl: Double = 24
        static let xxl: Double = 32
        static let huge: Double = 48
    }

    /// The smallest size of anything the pointer or a finger must hit, in points.
    static let minimumTargetSize: Double = 24

    /// The minimum contrast ratios the design asks for.
    nonisolated enum RequiredContrast {
        /// Body text and anything smaller than 18 pt.
        static let text: Double = 4.5
        /// Large text and the borders of controls.
        static let component: Double = 3.0
    }
}
