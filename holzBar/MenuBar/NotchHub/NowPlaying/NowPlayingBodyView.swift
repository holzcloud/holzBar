//
//  NowPlayingBodyView.swift
//  holzBar
//

import SwiftUI

/// The Now Playing tab: the song that plays, with its artist, album and state; or a quiet
/// sentence when nothing plays.
///
/// The view draws what the runtime holds as plain text and holds nothing itself.
struct NowPlayingBodyView: View {
    let runtime: NowPlayingRuntime

    private static let artworkSize: CGFloat = 96

    var body: some View {
        Group {
            if let event = runtime.event, event.state != .stopped {
                playing(event)
            } else {
                Text("Nothing is playing")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    private func playing(_ event: NowPlayingEvent) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.md) {
            symbolTile
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                title(of: event.track)
                    .font(HolzBarTheme.Typography.headline)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                if let artist = event.track?.artist {
                    Text(verbatim: artist)
                        .font(HolzBarTheme.Typography.callout)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .lineLimit(1)
                }
                if let album = event.track?.album {
                    Text(verbatim: album)
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                        .lineLimit(1)
                }
                stateLabel(event.state)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The song's title, or "Unknown title".
    private func title(of track: NowPlayingTrack?) -> Text {
        if let title = track?.title {
            Text(verbatim: title)
        } else {
            Text("Unknown title")
        }
    }

    /// A symbol on a quiet tile, until a song's artwork replaces it.
    private var symbolTile: some View {
        ZStack {
            HolzBarTheme.shape(HolzBarTheme.Radius.control)
                .fill(HolzBarTheme.Hub.idleTabFill)
            Image(systemName: "music.note")
                .font(HolzBarTheme.Hub.compactSymbolFont)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
    }

    /// The state as a symbol and a word.
    @ViewBuilder
    private func stateLabel(_ state: NowPlaybackState) -> some View {
        switch state {
        case .playing: Label("Playing", systemImage: "play.fill")
        case .paused: Label("Paused", systemImage: "pause.fill")
        case .stopped: Label("Nothing is playing", systemImage: "stop.fill")
        }
    }
}
