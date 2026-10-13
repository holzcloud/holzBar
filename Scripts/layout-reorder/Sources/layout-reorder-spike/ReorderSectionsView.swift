//
//  ReorderSectionsView.swift
//  holzBar
//

import AppKit
import LayoutReorderCore
import SwiftUI

/// The three rows of the Layout pane as SwiftUI reorderable rows of fake items, in one reorder
/// container so that items move between the rows. macOS 27 only.
@available(macOS 27.0, *)
struct ReorderSectionsView: View {
    let model: SpikeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(SpikeSection.allCases, id: \.self) { section in
                VStack(alignment: .leading) {
                    Text(section.title)
                        .font(.headline)
                        .padding(.leading, 8)
                    row(for: section)
                }
            }
        }
        .padding(20)
        .reorderContainer(for: FakeItem.self, in: SpikeSection.self) { difference in
            model.handle(ReorderRequest(difference), via: "drag")
        }
    }

    private func row(for section: SpikeSection) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(model.bar.rows[section] ?? []) { item in
                    ItemTile(item: item)
                }
                .reorderable(collectionID: section)
            }
            .padding(.horizontal, 7.5)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}

/// One fake item: its picture, dimmed when it cannot be moved.
private struct ItemTile: View {
    let item: FakeItem

    var body: some View {
        Group {
            if let symbol = item.symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .frame(width: item.width, height: 22)
        .opacity(item.isMovable && item.key != nil ? 1 : 0.67)
        .help(item.name)
    }
}

@available(macOS 27.0, *)
extension ReorderRequest {
    /// The request a drop makes, from the difference SwiftUI reports at the end of the session.
    init(_ difference: ReorderDifference<String, SpikeSection>) {
        let position: Position = switch difference.destination.position {
        case .before(let id): .before(id)
        case .end: .end
        }
        self.init(
            sources: difference.sources,
            target: difference.destination.collectionID,
            position: position
        )
    }
}
