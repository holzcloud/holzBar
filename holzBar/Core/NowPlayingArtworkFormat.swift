//
//  NowPlayingArtworkFormat.swift
//  holzBar
//

import Foundation

/// The picture formats the Now Playing module decodes from a song's file: JPEG and PNG only.
///
/// The file's location comes from another app's notification, which any process on this Mac can
/// post, so its embedded picture is untrusted. Songs carry their artwork as JPEG or PNG; every
/// other format the system's image decoders know is refused before a decoder sees it, as custom
/// icons are limited to a few formats.
nonisolated enum NowPlayingArtworkFormat: Equatable, Sendable {
    case jpeg
    case png

    /// The type identifiers the image decoder may report for an accepted picture.
    static let typeIdentifiers: Set<String> = ["public.jpeg", "public.png"]

    /// The format that the picture's first bytes name, or `nil` for any other format.
    init?(sniffing data: Data) {
        let bytes = [UInt8](data.prefix(8))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            self = .jpeg
        } else if bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
            self = .png
        } else {
            return nil
        }
    }

    /// The type identifier to give the image decoder as its hint.
    var typeIdentifier: String {
        switch self {
        case .jpeg: "public.jpeg"
        case .png: "public.png"
        }
    }
}
