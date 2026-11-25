//
//  NowPlayingArtworkFormatTests.swift
//  holzBarTests
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("NowPlayingArtworkFormat")
struct NowPlayingArtworkFormatTests {
    @Test("JPEG and PNG are recognised by their first bytes")
    func acceptedFormats() {
        #expect(NowPlayingArtworkFormat(sniffing: Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10])) == .jpeg)
        #expect(NowPlayingArtworkFormat(sniffing: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])) == .png)
        #expect(NowPlayingArtworkFormat.jpeg.typeIdentifier == "public.jpeg")
        #expect(NowPlayingArtworkFormat.png.typeIdentifier == "public.png")
        #expect(NowPlayingArtworkFormat.typeIdentifiers == ["public.jpeg", "public.png"])
    }

    @Test("Every other format, a short or an empty picture is refused")
    func refusedFormats() {
        let refused: [[UInt8]] = [
            [],
            [0xFF, 0xD8],
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A],
            Array("GIF89a".utf8),
            [0x49, 0x49, 0x2A, 0x00],
            [0x00, 0x00, 0x00, 0x1C] + Array("ftypheic".utf8),
            Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8),
            Array("BM".utf8) + [0, 0, 0, 0],
            Array("%PDF-1.7".utf8),
            [0x00, 0x00, 0x01, 0x00],
        ]
        for bytes in refused {
            #expect(NowPlayingArtworkFormat(sniffing: Data(bytes)) == nil, "\(bytes)")
        }
    }
}
