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
                HubTileGrid(tiles: tiles)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Tiles in the hub's four columns: the Overview's grid, and the body of a module that shows only
/// tiles.
struct HubTileGrid: View {
    let tiles: [(id: String, tile: HubTile)]

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: HolzBarTheme.Hub.tileGap, alignment: .top),
            count: HolzBarTheme.Hub.columns
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: HolzBarTheme.Hub.tileGap) {
            ForEach(tiles, id: \.id) { entry in
                HubWidget(tile: entry.tile)
            }
        }
    }
}
