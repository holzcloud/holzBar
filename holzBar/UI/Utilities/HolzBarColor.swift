//
//  HolzBarColor.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// A custom color.
struct HolzBarColor: Hashable {
    /// The color, represented as a `CGColor`.
    var cgColor: CGColor
}

// MARK: HolzBarColor: Codable
extension HolzBarColor: Codable {
    private enum CodingKeys: CodingKey {
        case components
        case colorSpace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var components = try container.decode([CGFloat].self, forKey: .components)
        let iccData = try container.decode(Data.self, forKey: .colorSpace) as CFData
        guard let colorSpace = CGColorSpace(iccData: iccData) else {
            throw DecodingError.dataCorruptedError(
                forKey: .colorSpace,
                in: container,
                debugDescription: "Invalid ICC profile data"
            )
        }
        // `CGColor` reads one component per channel of the color space plus alpha, whatever
        // the array holds, so a stored array of the wrong length, or with values that are
        // not numbers, is rejected first.
        components = ColorComponents.clamped(components)
        guard ColorComponents.isValid(components, colorSpaceComponents: colorSpace.numberOfComponents) else {
            throw DecodingError.dataCorruptedError(
                forKey: .components,
                in: container,
                debugDescription: "Expected \(colorSpace.numberOfComponents + 1) color components between 0 and 1"
            )
        }
        guard let cgColor = CGColor(colorSpace: colorSpace, components: &components) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid color space or components"
                )
            )
        }
        self.cgColor = cgColor
    }

    func encode(to encoder: Encoder) throws {
        guard let components = cgColor.components else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color components"
                )
            )
        }
        guard let colorSpace = cgColor.colorSpace else {
            throw EncodingError.invalidValue(
                cgColor,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing color space"
                )
            )
        }
        guard let iccData = colorSpace.copyICCData() else {
            throw EncodingError.invalidValue(
                colorSpace,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing ICC profile data"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(components, forKey: .components)
        try container.encode(iccData as Data, forKey: .colorSpace)
    }
}
