//
//  DesktopPicture.swift
//  holzBar
//

import Cocoa
import ImageIO
import OSLog

/// The desktop picture under a display's menu bar, read from its file.
///
/// A menu bar shape draws the wallpaper beside the shape. holzBar used to capture the
/// wallpaper window for it, which needs Screen Recording and, on macOS 27, lights the
/// screen-recording indicator on every update. The picture is read from the file macOS
/// shows instead (`NSWorkspace.desktopImageURL(for:)`), laid out as the desktop lays it
/// out, and the strip under the menu bar is cut from it. A moving (aerial) wallpaper has no
/// such file; then there is no strip.
@MainActor
enum DesktopPicture {
    /// How the desktop lays a picture out on a screen.
    private nonisolated struct Layout: Sendable, Equatable {
        /// The picture's file.
        let url: URL
        /// When the file was last changed, so a rewritten file is read again.
        let modificationDate: Date?
        /// The screen's size, in points.
        let screenSize: CGSize
        /// The screen's scale factor.
        let scale: CGFloat
        /// The height of the strip under the menu bar, in points.
        let stripHeight: CGFloat
        /// `NSImageScaling` raw value.
        let scaling: UInt
        /// Whether a proportionally scaled picture fills the screen and is clipped.
        let allowsClipping: Bool
        /// The colour around a picture that does not fill the screen: sRGB red, green, blue
        /// and alpha.
        let fillComponents: [CGFloat]?
    }

    /// A strip handed from the decoding queue to the main actor. Nothing else holds the
    /// image, so it crosses the boundary once.
    private nonisolated struct DecodedStrip: @unchecked Sendable {
        let image: CGImage?
    }

    /// The decoding queue: a large picture takes a moment to decode, off the main thread.
    private nonisolated static let queue = DispatchQueue(label: "com.holzcloud.holzBar.DesktopPicture", qos: .utility)

    /// The last strip of each display, with the layout it was made for.
    private static var cache = [CGDirectDisplayID: (layout: Layout, strip: CGImage)]()

    private static let logger = Logger(category: "DesktopPicture")

    /// Returns the strip of the desktop picture under the menu bar of the given screen, or
    /// `nil` when the picture cannot be read from a file (a moving wallpaper).
    ///
    /// - Parameters:
    ///   - screen: The screen.
    ///   - height: The height of the menu bar, in points.
    static func strip(for screen: NSScreen, height: CGFloat) async -> CGImage? {
        guard let layout = layout(for: screen, height: height) else {
            return nil
        }
        let displayID = screen.displayID
        if let cached = cache[displayID], cached.layout == layout {
            return cached.strip
        }
        let strip = await withCheckedContinuation { (continuation: CheckedContinuation<DecodedStrip, Never>) in
            queue.async {
                continuation.resume(returning: DecodedStrip(image: makeStrip(layout: layout)))
            }
        }.image
        if let strip {
            cache[displayID] = (layout, strip)
        } else {
            cache[displayID] = nil
            logger.debug("The desktop picture could not be read from its file")
        }
        return strip
    }

    /// The dominant colors of the desktop picture under the menu bar of the given screen,
    /// for the "Follow Wallpaper" tint, or `nil` when the picture cannot be read from a
    /// file. Read from the same strip, with no capture (THAW-17).
    static func palette(for screen: NSScreen, height: CGFloat) async -> WallpaperPalette? {
        guard let strip = await strip(for: screen, height: height) else {
            return nil
        }
        let decoded = DecodedStrip(image: strip)
        return await withCheckedContinuation { (continuation: CheckedContinuation<WallpaperPalette?, Never>) in
            queue.async {
                continuation.resume(returning: decoded.image.map(samplePalette))
            }
        }
    }

    /// Samples the strip on a small grid and derives its palette. Runs on ``queue``.
    private nonisolated static func samplePalette(_ image: CGImage) -> WallpaperPalette {
        let width = 64
        let height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let samples = pixels.withUnsafeMutableBytes { buffer -> [WallpaperPalette.Sample] in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return []
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return stride(from: 0, to: buffer.count, by: 4).map { index in
                WallpaperPalette.Sample(
                    red: Double(buffer[index]) / 255,
                    green: Double(buffer[index + 1]) / 255,
                    blue: Double(buffer[index + 2]) / 255
                )
            }
        }
        return WallpaperPalette.derive(from: samples)
    }

    /// The strip for the given screen from the last read, when the picture has not changed
    /// since; it never decodes, so it can be used where no wait is allowed.
    static func cachedStrip(for screen: NSScreen, height: CGFloat) -> CGImage? {
        guard
            let layout = layout(for: screen, height: height),
            let cached = cache[screen.displayID],
            cached.layout == layout
        else {
            return nil
        }
        return cached.strip
    }

    /// Whether the desktop picture of the given screen can be read from its file.
    ///
    /// Reads only the file's header.
    static func isReadable(on screen: NSScreen) -> Bool {
        guard
            let url = NSWorkspace.shared.desktopImageURL(for: screen),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    /// Forgets the strips, so the next request reads the pictures again.
    static func invalidate() {
        cache.removeAll()
    }

    // MARK: Private

    /// How the desktop shows its picture on the given screen.
    private static func layout(for screen: NSScreen, height: CGFloat) -> Layout? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.desktopImageURL(for: screen), url.isFileURL else {
            return nil
        }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let scaling = (options[.imageScaling] as? NSNumber)?.uintValue ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue
        let allowsClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true
        let fillComponents = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB).map { color in
            [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
        }
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return Layout(
            url: url,
            modificationDate: modificationDate,
            screenSize: screen.frame.size,
            scale: screen.backingScaleFactor,
            stripHeight: height,
            scaling: scaling,
            allowsClipping: allowsClipping,
            fillComponents: fillComponents
        )
    }

    /// Decodes the picture and cuts the strip under the menu bar. Runs on ``queue``.
    private nonisolated static func makeStrip(layout: Layout) -> CGImage? {
        let pixelWidth = Int((layout.screenSize.width * layout.scale).rounded())
        let pixelHeight = Int((layout.stripHeight * layout.scale).rounded())
        guard
            pixelWidth > 0,
            pixelHeight > 0,
            let source = CGImageSourceCreateWithURL(layout.url as CFURL, nil),
            CGImageSourceGetCount(source) > 0
        else {
            return nil
        }
        // A thumbnail no larger than the screen: a huge picture is never decoded in full.
        // A dynamic HEIC wallpaper gives its first image.
        let maxPixelSize = max(layout.screenSize.width, layout.screenSize.height) * layout.scale
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded()),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        let imageRect = pictureRect(imageSize: CGSize(width: image.width, height: image.height), layout: layout)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        if let fill = layout.fillComponents, fill.count == 4 {
            context.setFillColor(CGColor(srgbRed: fill[0], green: fill[1], blue: fill[2], alpha: fill[3]))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        // The context covers the top of the screen; its origin is at the bottom left.
        let scale = layout.scale
        let drawRect = CGRect(
            x: imageRect.minX * scale,
            y: CGFloat(pixelHeight) - imageRect.maxY * scale,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
        context.draw(image, in: drawRect)
        return context.makeImage()
    }

    /// Where the desktop puts a picture of the given size, in points from the screen's
    /// top-left corner.
    private nonisolated static func pictureRect(imageSize: CGSize, layout: Layout) -> CGRect {
        let screen = layout.screenSize
        // The decoded pixels stand for the picture at its natural size in points.
        let naturalSize = CGSize(width: imageSize.width / layout.scale, height: imageSize.height / layout.scale)
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            return CGRect(origin: .zero, size: screen)
        }
        func centred(_ size: CGSize) -> CGRect {
            CGRect(x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2, width: size.width, height: size.height)
        }
        let widthRatio = screen.width / naturalSize.width
        let heightRatio = screen.height / naturalSize.height
        switch NSImageScaling(rawValue: layout.scaling) {
        case .scaleAxesIndependently:
            return CGRect(origin: .zero, size: screen)
        case .scaleNone:
            return centred(naturalSize)
        case .scaleProportionallyDown:
            let ratio = min(1, min(widthRatio, heightRatio))
            return centred(CGSize(width: naturalSize.width * ratio, height: naturalSize.height * ratio))
        default:
            // Fill the screen (clipping) or fit inside it.
            let ratio = layout.allowsClipping ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
            return centred(CGSize(width: naturalSize.width * ratio, height: naturalSize.height * ratio))
        }
    }
}
