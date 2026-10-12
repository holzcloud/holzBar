//
//  OverlayGeometry.swift
//  holzBar
//

import CoreGraphics

/// Where mechanism B draws its panel, handles and zones for one snapshot of the bar.
///
/// Accessibility reports frames in CoreGraphics global coordinates (origin top left of the primary
/// display, y down); AppKit places windows in global coordinates with the origin at the bottom left
/// of the primary display and y up. The layout converts between the two and into the panel's own
/// coordinates (origin bottom left of the panel).
public struct OverlayLayout: Sendable, Equatable {
    /// A drag handle over one counted item.
    public struct Handle: Sendable, Equatable {
        public let id: String
        public let kind: BarItem.Kind

        /// The item's frame in panel coordinates.
        public let rect: CGRect
    }

    /// A drop zone for a section.
    public struct Zone: Sendable, Equatable {
        public let section: BarSection

        /// In panel coordinates.
        public let rect: CGRect

        /// In CoreGraphics global coordinates, for `DropResolver.target(forDropAt:...)`.
        public let dropZone: DropZone
    }

    /// The panel's frame in AppKit global coordinates.
    public let panelFrame: CGRect
    public let handles: [Handle]
    public let zones: [Zone]

    private let displayBounds: CGRect

    /// The panel's height, which is the bar's height on this display.
    private let panelHeight: CGFloat

    /// The panel covers the bar strip of the snapshot's display; the zones sit left of the leftmost
    /// app, system or holzBar icon item, or left of the notch when they would overlap it.
    ///
    /// - Parameters:
    ///   - primaryDisplayHeight: The height of the primary display, which the y conversion needs.
    ///   - notchSpan: The span the notch covers, in CoreGraphics x, `nil` without a notch.
    ///   - zoneWidth: The width of each zone.
    ///   - zoneGap: The gap between a zone and what is right of it.
    public static func make(
        snapshot: BarSnapshot,
        primaryDisplayHeight: CGFloat,
        notchSpan: ClosedRange<CGFloat>?,
        zoneWidth: CGFloat = 76,
        zoneGap: CGFloat = 8
    ) -> OverlayLayout {
        let bounds = snapshot.displayBounds
        let height = snapshot.barMaxY - bounds.minY
        let frame = CGRect(
            x: bounds.minX,
            y: primaryDisplayHeight - snapshot.barMaxY,
            width: bounds.width,
            height: height
        )
        var layout = OverlayLayout(panelFrame: frame, handles: [], zones: [], displayBounds: bounds, panelHeight: height)

        let handles = snapshot.items.filter(\.counts).map {
            Handle(id: $0.id, kind: $0.kind, rect: layout.panelRect(fromCG: $0.frame))
        }

        let anchoredKinds: [BarItem.Kind] = [.app, .system, .holzBarIcon]
        var zoneFrames = [(BarSection, CGRect)]()
        if let leftmost = snapshot.items.filter({ $0.counts && anchoredKinds.contains($0.kind) }).map(\.frame.minX).min() {
            let top = bounds.minY + 2
            let zoneHeight = max(0, height - 4)
            func frames(anchor: CGFloat) -> [(BarSection, CGRect)] {
                let hidden = CGRect(x: anchor - zoneGap - zoneWidth, y: top, width: zoneWidth, height: zoneHeight)
                let always = hidden.offsetBy(dx: -(zoneGap + zoneWidth), dy: 0)
                return [(.hidden, hidden), (.alwaysHidden, always)]
            }
            zoneFrames = frames(anchor: leftmost)
            if let notchSpan, zoneFrames.contains(where: { $0.1.minX < notchSpan.upperBound && $0.1.maxX > notchSpan.lowerBound }) {
                zoneFrames = frames(anchor: notchSpan.lowerBound)
            }
        }
        let zones = zoneFrames.filter { $0.1.minX >= bounds.minX }.map {
            Zone(section: $0.0, rect: layout.panelRect(fromCG: $0.1), dropZone: DropZone(section: $0.0, frame: $0.1))
        }
        layout = OverlayLayout(panelFrame: frame, handles: handles, zones: zones, displayBounds: bounds, panelHeight: height)
        return layout
    }

    /// A rect in CoreGraphics global coordinates as the panel's own coordinates show it.
    public func panelRect(fromCG rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - displayBounds.minX,
            y: panelHeight - (rect.maxY - displayBounds.minY),
            width: rect.width,
            height: rect.height
        )
    }

    /// A point in the panel's coordinates as CoreGraphics global coordinates.
    public func cgPoint(fromPanel point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + displayBounds.minX, y: displayBounds.minY + (panelHeight - point.y))
    }
}

/// How far the bar moved from what the overlay shows.
public enum TrackDiff {
    /// How many counted items are not where the overlay shows them (moved by more than 2 points,
    /// or in only one of the two snapshots) and the largest of the moves.
    public static func compare(shown: BarSnapshot, fresh: BarSnapshot) -> (shifted: Int, maxShift: CGFloat) {
        let before = Dictionary(
            shown.items.filter(\.counts).map { ($0.id, $0.frame.minX) },
            uniquingKeysWith: { first, _ in first }
        )
        let after = Dictionary(
            fresh.items.filter(\.counts).map { ($0.id, $0.frame.minX) },
            uniquingKeysWith: { first, _ in first }
        )
        var shifted = 0
        var maxShift: CGFloat = 0
        for (id, minX) in before {
            guard let other = after[id] else {
                shifted += 1
                continue
            }
            let moved = abs(other - minX)
            if moved > 2 {
                shifted += 1
                maxShift = max(maxShift, moved)
            }
        }
        shifted += after.keys.filter { before[$0] == nil }.count
        return (shifted, maxShift)
    }
}
