//
//  MenuBarAppearanceConfigurationV1.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// Configuration for the menu bar's appearance, as Ice stored it before 0.11.10.
///
/// Kept only to decode the appearance of old Ice settings while they are imported
/// (see `MigrationManager`).
struct MenuBarAppearanceConfigurationV1: Hashable {
    var hasShadow: Bool
    var hasBorder: Bool
    var isInset: Bool
    var borderColor: CGColor
    var borderWidth: Double
    var shapeKind: MenuBarShapeKind
    var fullShapeInfo: MenuBarFullShapeInfo
    var splitShapeInfo: MenuBarSplitShapeInfo
    var tintKind: MenuBarTintKind
    var tintColor: CGColor
    var tintGradient: HolzBarGradient

    var hasRoundedShape: Bool {
        switch shapeKind {
        case .noShape: false
        case .full: fullShapeInfo.hasRoundedShape
        case .split: splitShapeInfo.hasRoundedShape
        }
    }
}

// MARK: Default Configuration
extension MenuBarAppearanceConfigurationV1 {
    static let defaultConfiguration = MenuBarAppearanceConfigurationV1(
        hasShadow: false,
        hasBorder: false,
        isInset: true,
        borderColor: .black,
        borderWidth: 1,
        shapeKind: .noShape,
        fullShapeInfo: .default,
        splitShapeInfo: .default,
        tintKind: .noTint,
        tintColor: .black,
        tintGradient: .defaultMenuBarTint
    )
}

// MARK: MenuBarAppearanceConfigurationV1: Codable
extension MenuBarAppearanceConfigurationV1: Codable {
    private enum CodingKeys: CodingKey {
        case hasShadow
        case hasBorder
        case isInset
        case borderColor
        case borderWidth
        case shapeKind
        case fullShapeInfo
        case splitShapeInfo
        case tintKind
        case tintColor
        case tintGradient
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            hasShadow: container.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? Self.defaultConfiguration.hasShadow,
            hasBorder: container.decodeIfPresent(Bool.self, forKey: .hasBorder) ?? Self.defaultConfiguration.hasBorder,
            isInset: container.decodeIfPresent(Bool.self, forKey: .isInset) ?? Self.defaultConfiguration.isInset,
            borderColor: container.decodeIfPresent(HolzBarColor.self, forKey: .borderColor)?.cgColor ?? Self.defaultConfiguration.borderColor,
            borderWidth: container.decodeIfPresent(Double.self, forKey: .borderWidth) ?? Self.defaultConfiguration.borderWidth,
            shapeKind: container.decodeIfPresent(MenuBarShapeKind.self, forKey: .shapeKind) ?? Self.defaultConfiguration.shapeKind,
            fullShapeInfo: container.decodeIfPresent(MenuBarFullShapeInfo.self, forKey: .fullShapeInfo) ?? Self.defaultConfiguration.fullShapeInfo,
            splitShapeInfo: container.decodeIfPresent(MenuBarSplitShapeInfo.self, forKey: .splitShapeInfo) ?? Self.defaultConfiguration.splitShapeInfo,
            tintKind: container.decodeIfPresent(MenuBarTintKind.self, forKey: .tintKind) ?? Self.defaultConfiguration.tintKind,
            tintColor: container.decodeIfPresent(HolzBarColor.self, forKey: .tintColor)?.cgColor ?? Self.defaultConfiguration.tintColor,
            tintGradient: container.decodeIfPresent(HolzBarGradient.self, forKey: .tintGradient) ?? Self.defaultConfiguration.tintGradient
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasShadow, forKey: .hasShadow)
        try container.encode(hasBorder, forKey: .hasBorder)
        try container.encode(isInset, forKey: .isInset)
        try container.encode(HolzBarColor(cgColor: borderColor), forKey: .borderColor)
        try container.encode(borderWidth, forKey: .borderWidth)
        try container.encode(shapeKind, forKey: .shapeKind)
        try container.encode(fullShapeInfo, forKey: .fullShapeInfo)
        try container.encode(splitShapeInfo, forKey: .splitShapeInfo)
        try container.encode(tintKind, forKey: .tintKind)
        try container.encode(HolzBarColor(cgColor: tintColor), forKey: .tintColor)
        try container.encode(tintGradient, forKey: .tintGradient)
    }
}
