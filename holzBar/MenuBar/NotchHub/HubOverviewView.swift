//
//  HubOverviewView.swift
//  holzBar
//

import SwiftUI

/// The Notch hub's Overview: the cards of the modules that offer one in four columns, or, when
/// no module does, an empty state with a button to Settings.
///
/// While a new menu bar app waits for an answer and the Shelf is not used, its question is the
/// first row (D-12); the card is at most 96 pt high, so the Overview scrolls inside its own area
/// and the hub never grows.
struct HubOverviewView: View {
    let model: NotchHubModel
    let host: any HubHost

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tiles = model.tiles
        let source = model.newAppQuestionSource
        let hasQuestion = source?.hubQuestions.isEmpty == false
        if tiles.isEmpty, !hasQuestion {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: HolzBarTheme.Hub.tileGap) {
                    if hasQuestion, let source {
                        HubNewAppCardView(source: source)
                            .transition(.opacity)
                    }
                    if tiles.isEmpty {
                        emptyState
                    } else {
                        HubTileGrid(tiles: tiles)
                    }
                }
                .animation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion), value: hasQuestion)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var emptyState: some View {
        EmptyState(
            systemImage: "capsule.tophalf.filled",
            title: Text("No modules yet"),
            message: Text("Switch on modules in Settings and they appear here."),
            actionTitle: "Open Settings"
        ) {
            host.openSettings(for: NotchHubController.moduleID)
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
