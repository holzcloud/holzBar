//
//  NowPlayingSettingsView.swift
//  holzBar
//

import SwiftUI

/// The Now Playing module's settings, in the open area of the module's row: which of Apple Music
/// and Spotify it follows, and the switch Read all apps.
///
/// The last source that is on cannot be switched off, so the module always follows one; a state
/// line says so. Read all apps is off by default and labelled as a private interface; its popover
/// says what it does, and a state line says when it switched itself off because that interface
/// changed.
struct NowPlayingSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings.nowPlaying
        SettingsRow(.modulesNowPlayingAppleMusic) {
            SettingsSwitch(
                isOn: follows(.music, settings: settings),
                label: Text(SettingsEntry.modulesNowPlayingAppleMusic.label)
            )
            .disabled(settings.players == .music)
        }
        SettingsRow(.modulesNowPlayingSpotify) {
            SettingsSwitch(
                isOn: follows(.spotify, settings: settings),
                label: Text(SettingsEntry.modulesNowPlayingSpotify.label)
            )
            .disabled(settings.players == .spotify)
        }
        if settings.players == .music || settings.players == .spotify {
            SettingsStateLine(.info, Text("The last source stays on"))
        }
        SettingsToggleRow(
            .modulesNowPlayingReadsAllApps,
            isOn: $settings.readsAllApps,
            small: Text("private interface")
        )
        if settings.readsAllApps, settings.remoteIsUnavailable {
            SettingsStateLine(.warning, Text("Read all apps is not available on this Mac"))
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
