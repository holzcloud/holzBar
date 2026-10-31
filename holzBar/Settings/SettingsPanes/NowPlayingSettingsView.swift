//
//  NowPlayingSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Now Playing module's settings, shown under its row in the Modules pane while the module
/// is on: which of Apple Music and Spotify it follows.
///
/// The last player that is on cannot be switched off, so the module always follows one.
struct NowPlayingSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let settings = appState.settings.nowPlaying
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Music", isOn: follows(.music, settings: settings))
            Toggle("Spotify", isOn: follows(.spotify, settings: settings))
            Text("Music and Spotify tell holzBar what they play.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        }
    }

    /// Whether a player is followed. A switch that would leave the set empty is refused.
    private func follows(_ player: NowPlayingPlayers, settings: NowPlayingSettings) -> Binding<Bool> {
        Binding {
            settings.players.isSuperset(of: player)
        } set: { isOn in
            var players = settings.players
            if isOn {
                players.formUnion(player)
            } else {
                players.subtract(player)
            }
            if !players.isEmpty {
                settings.players = players
            }
        }
    }
}
