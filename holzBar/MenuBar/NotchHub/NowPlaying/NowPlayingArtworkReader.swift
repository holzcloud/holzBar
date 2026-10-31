//
//  NowPlayingArtworkReader.swift
//  holzBar
//

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads the artwork of a local audio file from the file's own metadata, as a small picture.
///
/// The file location comes from another app's notification, so it is untrusted: only a `file`
/// URL whose type is audio is opened, only its metadata is read, a picture above 20 MB is
/// refused, and what is kept is a thumbnail of at most 256 pixels. Nothing is written, logged,
/// retried or fetched from the network. A failure, including macOS refusing a protected folder,
/// gives no picture.
nonisolated enum NowPlayingArtworkReader {
    /// The longest side of the thumbnail in pixels.
    static let maxPixelSize = 256

    /// The largest embedded picture that is decoded, in bytes (20 MB).
    static let maxDataSize = 20 * 1_024 * 1_024

    /// A PNG thumbnail of the file's artwork, or `nil`. Runs off the main actor.
    @concurrent
    static func thumbnail(for fileURL: URL) async -> Data? {
        guard
            fileURL.isFileURL,
            let type = UTType(filenameExtension: fileURL.pathExtension),
            type.conforms(to: .audio)
        else {
            return nil
        }
        do {
            let asset = AVURLAsset(url: fileURL)
            let metadata = try await asset.load(.commonMetadata)
            let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
            guard let item = items.first else {
                return nil
            }
            var data = try await item.load(.dataValue)
            if data == nil {
                data = try await item.load(.value) as? Data
            }
            guard let data, !data.isEmpty, data.count <= maxDataSize else {
                return nil
            }
            return pngThumbnail(from: data)
        } catch {
            return nil
        }
    }

    /// Decodes the picture into a thumbnail and encodes it as PNG.
    private static func pngThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }
}
