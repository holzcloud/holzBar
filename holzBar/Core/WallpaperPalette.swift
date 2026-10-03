//
//  WallpaperPalette.swift
//  holzBar
//

import Foundation

/// The dominant colors of the desktop picture under the menu bar, ordered by how much of
/// it they cover, for the "Follow Wallpaper" tint (THAW-17).
///
/// An average turns a sunset into brown; a palette keeps the colors that actually cover
/// the picture. Pure and deterministic, so it can be tested without a screen; the pixels
/// come from the desktop picture file (`DesktopPicture.palette(for:height:)`), never from a
/// capture.
///
/// Adapted from Thaw's `WallpaperPalette` (see NOTICE).
nonisolated struct WallpaperPalette: Equatable, Sendable {
    /// One dominant color.
    nonisolated struct Swatch: Equatable, Sendable {
        /// Components in the 0...1 range.
        let red: Double
        let green: Double
        let blue: Double

        /// The fraction of the samples this swatch covers, 0...1.
        let weight: Double

        /// RGB distance. Not perceptually uniform, but good enough to reject
        /// near-duplicates and easy to test.
        func distance(to other: Swatch) -> Double {
            let dr = red - other.red
            let dg = green - other.green
            let db = blue - other.blue
            return (dr * dr + dg * dg + db * db).squareRoot()
        }
    }

    /// A single observed pixel, components in the 0...1 range.
    nonisolated struct Sample: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// Most-covering first. May be empty.
    let swatches: [Swatch]

    /// The most-covering swatch.
    var primary: Swatch? {
        swatches.first
    }

    /// The second most-covering swatch, falling back to ``primary`` so a single-color
    /// wallpaper still yields a pair.
    var secondary: Swatch? {
        swatches.count > 1 ? swatches[1] : primary
    }

    /// Buckets per channel. Finer splits smooth gradients into near-identical buckets;
    /// coarser merges colors a viewer would call different.
    private static let levelsPerChannel = 32

    /// Derives a palette from raw samples.
    ///
    /// Takes buckets most-populous first, skipping any too close to one already taken, so
    /// a sky photo doesn't return five blues.
    ///
    /// - Parameters:
    ///   - samples: The observed pixels. Order does not matter.
    ///   - maximumCount: The most swatches to return.
    ///   - minimumSeparation: How far apart two swatches must be, as an RGB distance.
    static func derive(
        from samples: [Sample],
        maximumCount: Int = 5,
        minimumSeparation: Double = 0.25
    ) -> WallpaperPalette {
        guard maximumCount > 0, !samples.isEmpty else {
            return WallpaperPalette(swatches: [])
        }

        let levels = levelsPerChannel
        var counts = [Int: Int]()
        var totals = [Int: (red: Double, green: Double, blue: Double)]()

        for sample in samples {
            let key = bucketKey(for: sample, levels: levels)
            counts[key, default: 0] += 1
            var total = totals[key] ?? (0, 0, 0)
            total.red += sample.red
            total.green += sample.green
            total.blue += sample.blue
            totals[key] = total
        }

        let sampleCount = Double(samples.count)
        // Sorted by population, ties broken on the bucket key, so the result does not
        // depend on dictionary order.
        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }

        var result = [Swatch]()
        for (key, count) in ranked {
            guard result.count < maximumCount else {
                break
            }
            guard let total = totals[key] else {
                continue
            }
            // The average within the bucket rather than its center, so the swatch is a
            // color that actually appears in the picture.
            let population = Double(count)
            let swatch = Swatch(
                red: total.red / population,
                green: total.green / population,
                blue: total.blue / population,
                weight: population / sampleCount
            )
            if result.contains(where: { $0.distance(to: swatch) < minimumSeparation }) {
                continue
            }
            result.append(swatch)
        }

        return WallpaperPalette(swatches: result)
    }

    private static func bucketKey(for sample: Sample, levels: Int) -> Int {
        func level(_ value: Double) -> Int {
            let scaled = Int(min(max(value, 0), 1) * Double(levels))
            // A component of exactly 1 would land one past the top bucket.
            return min(scaled, levels - 1)
        }
        return (level(sample.red) * levels * levels)
            + (level(sample.green) * levels)
            + level(sample.blue)
    }
}
