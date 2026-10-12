//
//  MenuBarStyleOptions.swift
//  holzBar
//

import Foundation

/// How the Apple menu end of the menu bar is styled.
///
/// The raw values are stored in the appearance configuration; new cases go at the end.
nonisolated enum MenuBarAppleLogoStyle: Int, Codable, CaseIterable, Sendable {
    /// The Apple menu is part of the bar, as it is today.
    case standard = 0
    /// A capsule of its own behind the Apple menu.
    case capsule = 1

    /// Decodes a style; one this version does not know (from a newer version or a damaged
    /// file) reads as the first case instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .standard
    }
}

/// What fills the capsule behind the Apple menu.
///
/// The raw values are stored in the appearance configuration; new cases go at the end.
nonisolated enum MenuBarAppleLogoFill: Int, Codable, CaseIterable, Sendable {
    /// The tint of the bar.
    case barTint = 0
    /// The system accent color.
    case accentColor = 1
    /// The dominant color of the wallpaper.
    case wallpaper = 2
    /// A color the user chose.
    case color = 3

    /// Decodes a fill; one this version does not know (from a newer version or a damaged
    /// file) reads as the first case instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .barTint
    }
}

/// What the border of the menu bar shapes is drawn with.
///
/// The raw values are stored in the appearance configuration; new cases go at the end.
nonisolated enum MenuBarBorderFill: Int, Codable, CaseIterable, Sendable {
    /// The border color of the appearance.
    case color = 0
    /// The system accent color.
    case accentColor = 1
    /// A gradient of its own.
    case gradient = 2

    /// Decodes a fill; one this version does not know (from a newer version or a damaged
    /// file) reads as the first case instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .color
    }
}

/// The direction of a gradient over the menu bar.
///
/// The raw values are stored in the appearance configuration; new cases go at the end.
nonisolated enum MenuBarGradientDirection: Int, Codable, CaseIterable, Sendable {
    /// From the leading to the trailing edge, as the tint gradient is drawn today.
    case horizontal = 0
    /// From the top to the bottom.
    case vertical = 1

    /// The angle `NSGradient.draw(in:angle:)` takes in the overlay's unflipped view: 0 draws
    /// left to right, 270 draws top to bottom.
    var angle: Double {
        switch self {
        case .horizontal: 0
        case .vertical: 270
        }
    }

    /// Decodes a direction; one this version does not know (from a newer version or a
    /// damaged file) reads as the first case instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .horizontal
    }
}

/// Over what a gradient runs when the menu bar has more than one shape.
///
/// The raw values are stored in the appearance configuration; new cases go at the end.
nonisolated enum MenuBarGradientSpan: Int, Codable, CaseIterable, Sendable {
    /// One gradient over the whole bar, as it is drawn today.
    case acrossBar = 0
    /// Each shape gets the whole gradient.
    case eachShape = 1

    /// Decodes a span; one this version does not know (from a newer version or a damaged
    /// file) reads as the first case instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = Self(rawValue: rawValue) ?? .acrossBar
    }
}

/// The look values of one appearance (light, dark or static), added in 0.0.8-beta4.
///
/// Every default draws what 0.0.8-beta3 drew. It is stored nested under the key `style` of
/// the partial configuration; a field that is absent or cannot be read takes its default
/// alone, and the others keep what was stored.
nonisolated struct MenuBarPartialStyle: Codable, Hashable, Sendable {
    /// How strongly a solid, gradient or wallpaper tint covers the bar, from
    /// ``tintStrengthRange``.
    var tintStrength: Double
    /// The direction of the gradients.
    var gradientDirection: MenuBarGradientDirection
    /// Whether one gradient runs across the bar or each shape gets its own.
    var gradientSpan: MenuBarGradientSpan
    /// What the border is drawn with.
    var borderFill: MenuBarBorderFill
    /// What fills the capsule behind the Apple menu.
    var appleLogoFill: MenuBarAppleLogoFill

    /// The range a tint strength is kept in.
    static let tintStrengthRange: ClosedRange<Double> = 0.1...0.6
    /// The alpha every tint used so far.
    static let defaultTintStrength: Double = 0.2

    /// The values that draw what 0.0.8-beta3 drew.
    static let `default` = MenuBarPartialStyle(
        tintStrength: defaultTintStrength,
        gradientDirection: .horizontal,
        gradientSpan: .acrossBar,
        borderFill: .color,
        appleLogoFill: .barTint
    )

    /// `value` kept in ``tintStrengthRange``; the default when it is not finite.
    static func clampedTintStrength(_ value: Double) -> Double {
        SettingsSchema.NumberRule.clamped(tintStrengthRange).clamp(value, fallback: defaultTintStrength)
    }

    init(
        tintStrength: Double,
        gradientDirection: MenuBarGradientDirection,
        gradientSpan: MenuBarGradientSpan,
        borderFill: MenuBarBorderFill,
        appleLogoFill: MenuBarAppleLogoFill
    ) {
        self.tintStrength = tintStrength
        self.gradientDirection = gradientDirection
        self.gradientSpan = gradientSpan
        self.borderFill = borderFill
        self.appleLogoFill = appleLogoFill
    }

    private enum CodingKeys: CodingKey {
        case tintStrength
        case gradientDirection
        case gradientSpan
        case borderFill
        case appleLogoFill
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default
        self.init(
            tintStrength: Self.clampedTintStrength(
                (try? container.decodeIfPresent(Double.self, forKey: .tintStrength)) ?? defaults.tintStrength
            ),
            gradientDirection: (try? container.decodeIfPresent(MenuBarGradientDirection.self, forKey: .gradientDirection))
                ?? defaults.gradientDirection,
            gradientSpan: (try? container.decodeIfPresent(MenuBarGradientSpan.self, forKey: .gradientSpan))
                ?? defaults.gradientSpan,
            borderFill: (try? container.decodeIfPresent(MenuBarBorderFill.self, forKey: .borderFill))
                ?? defaults.borderFill,
            appleLogoFill: (try? container.decodeIfPresent(MenuBarAppleLogoFill.self, forKey: .appleLogoFill))
                ?? defaults.appleLogoFill
        )
    }
}
