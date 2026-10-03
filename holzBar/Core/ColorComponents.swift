//
//  ColorComponents.swift
//  holzBar
//

import CoreGraphics

/// Validation of the color components holzBar stores with its appearance settings.
///
/// `CGColor(colorSpace:components:)` reads one component for each channel of the color
/// space and one for alpha, whatever the array holds. Anything can write holzBar's
/// preferences, so a stored array that is too short made it read past its end
/// (jordanbaird/Ice#985).
nonisolated enum ColorComponents {
    /// Returns whether the components fit a color space with the given number of channels:
    /// one value per channel plus alpha, each finite and between 0 and 1.
    static func isValid(_ components: [CGFloat], colorSpaceComponents: Int) -> Bool {
        guard colorSpaceComponents > 0, components.count == colorSpaceComponents + 1 else {
            return false
        }
        return components.allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    /// Returns the components with every finite value clamped to 0 through 1; values that
    /// are not finite stay as they are, so ``isValid(_:colorSpaceComponents:)`` rejects them.
    ///
    /// A color picked in an extended color space can be stored slightly outside that range,
    /// and the color space read back from its ICC profile is not extended; drawing clamped
    /// such a value before, so clamping it keeps the color the user saw.
    static func clamped(_ components: [CGFloat]) -> [CGFloat] {
        components.map { value in
            value.isFinite ? min(max(value, 0), 1) : value
        }
    }
}
