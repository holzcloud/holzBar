import Testing
@testable import HolzBarCore

@Suite("WallpaperPalette")
struct WallpaperPaletteTests {
    private let blue = WallpaperPalette.Sample(red: 0.1, green: 0.2, blue: 0.9)
    private let orange = WallpaperPalette.Sample(red: 0.95, green: 0.55, blue: 0.1)

    @Test("A two-colour image gives both colours, most covering first")
    func twoColoursMostCoveringFirst() throws {
        let samples = Array(repeating: blue, count: 70) + Array(repeating: orange, count: 30)
        let palette = WallpaperPalette.derive(from: samples)
        #expect(palette.swatches.count == 2)
        let first = try #require(palette.primary)
        let second = try #require(palette.secondary)
        #expect(abs(first.blue - 0.9) < 0.001)
        #expect(abs(second.red - 0.95) < 0.001)
        #expect(abs(first.weight - 0.7) < 0.001)
        #expect(abs(second.weight - 0.3) < 0.001)
    }

    @Test("Near-duplicates merge")
    func nearDuplicatesMerge() {
        let otherBlue = WallpaperPalette.Sample(red: 0.12, green: 0.25, blue: 0.85)
        let samples = Array(repeating: blue, count: 10) + Array(repeating: otherBlue, count: 8)
        let palette = WallpaperPalette.derive(from: samples)
        #expect(palette.swatches.count == 1)
        // One swatch still gives a pair.
        #expect(palette.secondary == palette.primary)
    }

    @Test("No samples give no swatches")
    func noSamplesNoSwatches() {
        let palette = WallpaperPalette.derive(from: [])
        #expect(palette.swatches.isEmpty)
        #expect(palette.primary == nil)
        #expect(palette.secondary == nil)
    }
}
