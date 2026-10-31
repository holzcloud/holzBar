//
//  NowPlayingSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Now Playing module's settings, shown under its row in the Modules pane while the module
/// is on: which of Apple Music and Spotify it follows, and the switch Read all apps.
///
/// The last player that is on cannot be switched off, so the module always follows one. Read all
/// apps is off by default, uses a private macOS interface and a helper, says so in its caption,
/// and says when it switched itself off because that interface changed.
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
            @Bindable var settings = settings
            Toggle("Read all apps", isOn: $settings.readsAllApps)
            Text(
                "Shows what browsers and video apps play, too. Uses a private macOS interface and a helper that holzBar starts only while the hub is open. It switches itself off if macOS changes it."
            )
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            if settings.readsAllApps, settings.remoteIsUnavailable {
                Text("Read all apps is not available on this Mac")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.warning)
            }
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
