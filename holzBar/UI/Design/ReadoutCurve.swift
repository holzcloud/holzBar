//
//  ReadoutCurve.swift
//  holzBar
//

import SwiftUI

/// The mini curve of a readout tile (concept R1): the last two minutes as a quiet line with the
/// time on the x axis and the newest point on the right edge.
///
/// It only draws what ``ReadoutHistory`` made. Each run of the main series is a line with round
/// joins and the area under it; each run of the second series is a dashed line without an area.
/// The baseline is the ring's track. Under Increase Contrast the line is brighter and there is no
/// area. It never animates and is hidden from VoiceOver, which reads the history summary
/// instead. The hub is always dark, so the curve uses fixed white tints.
struct ReadoutCurve: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let primary: [[CurvePoint]]
    var secondary: [[CurvePoint]] = []

    private var lineAlpha: Double {
        contrast == .increased ? DesignTokens.Hub.curveLineAlphaIncreased : DesignTokens.Hub.curveLineAlpha
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(height: CGFloat(DesignTokens.Hub.curveHeight))
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let baselineWidth = CGFloat(DesignTokens.Hub.curveBaselineWidth)
        let lineWidth = CGFloat(DesignTokens.Hub.curveLineWidth)
        // The line stays inside the frame, above the baseline.
        let inset = lineWidth / 2
        let floor = size.height - baselineWidth
        let span = max(floor - inset, 0)
        func position(_ point: CurvePoint) -> CGPoint {
            CGPoint(x: CGFloat(point.x) * size.width, y: floor - CGFloat(point.y) * span)
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: size.height - baselineWidth / 2))
        baseline.addLine(to: CGPoint(x: size.width, y: size.height - baselineWidth / 2))
        context.stroke(
            baseline,
            with: .color(.white.opacity(DesignTokens.Hub.curveBaselineAlpha)),
            lineWidth: baselineWidth
        )

        for run in primary where run.count >= 2 {
            let points = run.map(position)
            var line = Path()
            line.addLines(points)
            if contrast != .increased, let first = points.first, let last = points.last {
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: floor))
                area.addLine(to: CGPoint(x: first.x, y: floor))
                area.closeSubpath()
                context.fill(area, with: .color(.white.opacity(DesignTokens.Hub.curveAreaAlpha)))
            }
            context.stroke(
                line,
                with: .color(.white.opacity(lineAlpha)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }

        for run in secondary where run.count >= 2 {
            var line = Path()
            line.addLines(run.map(position))
            context.stroke(
                line,
                with: .color(.white.opacity(lineAlpha)),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .butt,
                    lineJoin: .round,
                    dash: DesignTokens.Hub.curveDash.map { CGFloat($0) }
                )
            )
        }
    }
}

#Preview("ReadoutCurve") {
    let rising = (0...30).map { CurvePoint(x: Double($0) / 30, y: 0.1 + 0.6 * Double($0) / 30) }
    let upload = (0...30).map { CurvePoint(x: Double($0) / 30, y: 0.05 + 0.1 * Double($0 % 5) / 5) }
    return VStack(spacing: 12) {
        ReadoutCurve(primary: [rising])
        ReadoutCurve(primary: [rising], secondary: [upload])
        ReadoutCurve(primary: [])
    }
    .padding(14)
    .frame(width: 160)
    .background(Color.black)
}
