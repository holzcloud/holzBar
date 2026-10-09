//
//  CustomIconData.swift
//  holzBar
//

import Foundation

/// Which custom holzBar icons are decoded.
///
/// A custom icon is stored as image data in the settings (`IceIcon`), which an imported
/// file can set, and holzBar decodes it at every launch, in the process
/// that holds Accessibility. `NSImage(data:)` would hand those bytes to every parser AppKit
/// has, PDF, EPS and SVG included. holzBar decodes them with ImageIO instead, and only when
/// they are one of a few bitmap formats, within a size limit. A newly chosen icon is stored
/// as PNG (``storedPixelSize``).
nonisolated enum CustomIconData {
    /// The bitmap formats a stored icon is decoded from: PNG, which holzBar stores, and the
    /// bitmap formats earlier versions stored as they were chosen.
    static let allowedTypeIdentifiers: Set<String> = [
        "public.png",
        "public.jpeg",
        "public.tiff",
        "public.heic",
        "public.heif",
        "com.compuserve.gif",
        "com.microsoft.bmp",
        "com.apple.icns",
    ]

    /// The most bytes a stored icon may have.
    static let maximumByteCount = 8 << 20

    /// The most pixels a stored icon may have in either direction.
    static let maximumPixelSize = 4096

    /// The most pixels a newly chosen icon is stored with in either direction: plenty for a
    /// menu bar icon at 2x, which is about 34 pixels high.
    static let storedPixelSize = 256

    /// Whether data of the given size and image type is decoded.
    static func accepts(typeIdentifier: String?, byteCount: Int) -> Bool {
        guard let typeIdentifier, byteCount > 0, byteCount <= maximumByteCount else {
            return false
        }
        return allowedTypeIdentifiers.contains(typeIdentifier)
    }

    /// Whether an image of the given pixel size is decoded.
    static func accepts(pixelWidth: Int, pixelHeight: Int) -> Bool {
        (1...maximumPixelSize).contains(pixelWidth) && (1...maximumPixelSize).contains(pixelHeight)
    }
}
