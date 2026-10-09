//
//  ItemFrame27.swift
//  holzBar
//

import CoreGraphics

/// Checks the frames other processes report for their items through Accessibility on macOS 27.
nonisolated enum ItemFrame27 {
    /// The largest coordinate or length a frame may hold. Displays span a few thousand
    /// points each, so anything beyond this is not a place on the bar.
    static let maximumMagnitude: CGFloat = 1_000_000

    /// The frame with the given origin and size, or `nil` when it is not one a bar can hold.
    ///
    /// The owning process reports the values, and a NaN, an infinity or a huge value would
    /// trap later where holzBar converts or compares them (an `Int` conversion, a range).
    static func validated(origin: CGPoint, size: CGSize) -> CGRect? {
        let values = [origin.x, origin.y, size.width, size.height]
        guard
            values.allSatisfy({ $0.isFinite && abs($0) < maximumMagnitude }),
            size.width >= 0,
            size.height >= 0
        else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}
