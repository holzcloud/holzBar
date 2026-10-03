//
//  MenuBarAppearanceConfigurationV2.swift
//  holzBar
//

import SwiftUI

struct MenuBarAppearanceConfigurationV2: Hashable {
    var lightModeConfiguration: MenuBarAppearancePartialConfiguration
    var darkModeConfiguration: MenuBarAppearancePartialConfiguration
    var staticConfiguration: MenuBarAppearancePartialConfiguration
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var isInset: Bool
    var isDynamic: Bool
    var blackBackground: MenuBarBlackBackground = .off
    var roundsScreenCorners = false
    var screenCornerRadius: Double = 10

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .noShape: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        }
    }

    /// Whether a tint follows the wallpaper in any of the configurations, so its palette
    /// is read.
    var usesWallpaperTint: Bool {
        [lightModeConfiguration, darkModeConfiguration, staticConfiguration].contains { $0.tintKind == .adaptive }
    }

    var current: MenuBarAppearancePartialConfiguration {
        if isDynamic {
            switch SystemAppearance.current {
            case .light: lightModeConfiguration
            case .dark: darkModeConfiguration
            }
        } else {
            staticConfiguration
        }
    }
}

// MARK: Default Configuration
extension MenuBarAppearanceConfigurationV2 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV2(
        lightModeConfiguration: .defaultConfiguration,
        darkModeConfiguration: .defaultConfiguration,
        staticConfiguration: .defaultConfiguration,
        shapeKind: .noShape,
        fullShapeInfo: .default,
        splitShapeInfo: .default,
        isInset: true,
        isDynamic: false
    )
}

extension MenuBarAppearanceConfigurationV2: Codable {
    private enum CodingKeys: CodingKey {
        case lightModeConfiguration
        case darkModeConfiguration
        case staticConfiguration
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case isInset
        case isDynamic
        case blackBackground
        case roundsScreenCorners
        case screenCornerRadius
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lightModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .lightModeConfiguration) ?? Self.defaultConfiguration.lightModeConfiguration,
            darkModeConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .darkModeConfiguration) ?? Self.defaultConfiguration.darkModeConfiguration,
            staticConfiguration: container.decodeIfPresent(MenuBarAppearancePartialConfiguration.self, forKey: .staticConfiguration) ?? Self.defaultConfiguration.staticConfiguration,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            isDynamic: container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? Self.defaultConfiguration.isDynamic,
            blackBackground: container.decodeIfPresent(MenuBarBlackBackground.self, forKey: .blackBackground) ?? Self.defaultConfiguration.blackBackground,
            roundsScreenCorners: container.decodeIfPresent(Bool.self, forKey: .roundsScreenCorners) ?? Self.defaultConfiguration.roundsScreenCorners,
            // Kept in the editor's range: settings can be imported or synced, and a huge
            // radius trapped where the editor turns it into an `Int`.
            screenCornerRadius: SettingsSchema.NumberRule.clamped(4...24).clamp(
                container.decodeIfPresent(Double.self, forKey: .screenCornerRadius) ?? Self.defaultConfiguration.screenCornerRadius,
                fallback: Self.defaultConfiguration.screenCornerRadius
            )
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lightModeConfiguration, forKey: .lightModeConfiguration)
        try container.encode(darkModeConfiguration, forKey: .darkModeConfiguration)
        try container.encode(staticConfiguration, forKey: .staticConfiguration)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(isDynamic, forKey: .isDynamic)
        try container.encode(blackBackground, forKey: .blackBackground)
        try container.encode(roundsScreenCorners, forKey: .roundsScreenCorners)
        try container.encode(screenCornerRadius, forKey: .screenCornerRadius)
    }
}

// MARK: - MenuBarAppearancePartialConfiguration

struct MenuBarAppearancePartialConfiguration: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: HolzBarGradient
    /// How the border is drawn: solid, dashed or dotted (THAW-17).
    var borderStyle: BorderStyle = .solid
    /// Whether the solid tint uses the system accent color instead of ``tintColor``.
    var tintFollowsAccentColor = false
}

// MARK: Default Partial Configuration
extension MenuBarAppearancePartialConfiguration {
    static let defaultConfiguration = MenuBarAppearancePartialConfiguration(
        hasShadow: false,
        hasBorder: false,
        borderColor: .black,
        borderWidth: 1,
        tintKind: .noTint,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint
    )
}

// MARK: MenuBarAppearancePartialConfiguration: Codable
extension MenuBarAppearancePartialConfiguration: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case borderColor
        case borderWidth
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case tintKind
        case tintColor
        case tintGradient
        case borderStyle
        case tintFollowsAccentColor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            borderColor: container.decodeIfPresent(HolzBarColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            // Kept in the editor's range (1 to 3 points), as settings can be imported or synced.
            borderWidth: SettingsSchema.NumberRule.clamped(1...3).clamp(
                container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
                fallback: Self.defaultConfiguration.borderWidth
            ),
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(HolzBarColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(HolzBarGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient,
            // An unknown style reads as solid, as a missing one does.
            borderStyle: (try? container.decodeIfPresent(BorderStyle.self, forKey: .borderStyle)) ?? Self.defaultConfiguration.borderStyle,
            tintFollowsAccentColor: container.decodeIfPresent(Bool.self, forKey: .tintFollowsAccentColor) ?? Self.defaultConfiguration.tintFollowsAccentColor
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(HolzBarColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(HolzBarColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
        try container.encode(borderStyle, forKey: .borderStyle)
        try container.encode(tintFollowsAccentColor, forKey: .tintFollowsAccentColor)
    }
}

// MARK: - MenuBarBlackBackground

/// Where the menu bar is drawn solid black, which hides the notch
/// (jordanbaird/Ice#82).
enum MenuBarBlackBackground: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case notchedDisplays = 1
    case allDisplays = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .notchedDisplays: "Displays with a notch"
        case .allDisplays: "All displays"
        }
    }

    /// Returns a Boolean value that indicates whether the menu bar is black on
    /// the given screen.
    func applies(to screen: NSScreen) -> Bool {
        switch self {
        case .off: false
        case .notchedDisplays: screen.hasNotch
        case .allDisplays: true
        }
    }
}
