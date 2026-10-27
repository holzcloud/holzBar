//
//  HubOverviewView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's Overview: the cards of the modules that offer one in four columns, or, when
/// no module does, an empty state with a button to Settings.
struct HubOverviewView: View {
    let model: NotchHubModel
    let host: any HubHost

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: HolzBarTheme.Hub.tileGap, alignment: .top),
            count: HolzBarTheme.Hub.columns
        )
    }

    var body: some View {
        let tiles = model.tiles
        if tiles.isEmpty {
            EmptyState(
                systemImage: "capsule.tophalf.filled",
                title: Text("No modules yet"),
                message: Text("Switch on modules in Settings and they appear here."),
                actionTitle: "Open Settings"
            ) {
                host.openSettings(for: NotchHubController.moduleID)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: HolzBarTheme.Hub.tileGap) {
                    ForEach(tiles, id: \.id) { entry in
                        HubWidget(
                            systemImage: entry.tile.symbol,
                            title: entry.tile.title,
                            value: entry.tile.value,
                            unit: entry.tile.unit,
                            detail: entry.tile.detail,
                            fraction: entry.tile.fraction
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
