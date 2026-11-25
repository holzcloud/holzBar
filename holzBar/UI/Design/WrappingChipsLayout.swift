//
//  WrappingChipsLayout.swift
//  holzBar
//

import SwiftUI

/// Lays its views out left to right and wraps them into the next line when the line is full, so
/// a chip is never cut off, however long its translation is. Used by the new-app question on the
/// Shelf and in the Notch hub.
struct WrappingChipsLayout: Layout {
    /// The space between two chips of a line.
    var spacing: CGFloat
    /// The space between two lines.
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (line.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    /// One line of chips.
    private struct Line {
        var items = [(index: Int, size: CGSize)]()
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let gap = lines[lines.count - 1].items.isEmpty ? 0 : spacing
            if !lines[lines.count - 1].items.isEmpty, lines[lines.count - 1].width + gap + size.width > width {
                lines.append(Line())
            }
            let last = lines.count - 1
            lines[last].width += (lines[last].items.isEmpty ? 0 : spacing) + size.width
            lines[last].height = max(lines[last].height, size.height)
            lines[last].items.append((index, size))
        }
        return lines
    }
}
