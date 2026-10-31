//
//  NowPlayingBodyView.swift
//  holzBar
//

import SwiftUI

/// The Now Playing tab: the song that plays, with its artist, album and state; or a quiet
/// sentence when nothing plays.
///
/// The view draws what the runtime holds as plain text and holds nothing itself. The elapsed
/// time and the progress bar are drawn by the system from a start and an end date, so the view
/// runs no timer; it starts them over on every event.
struct NowPlayingBodyView: View {
    let runtime: NowPlayingRuntime

    private static let artworkSize: CGFloat = 96

    var body: some View {
        Group {
            if let event = runtime.current?.event, event.state != .stopped {
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
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            summary(event)
            if let progress = runtime.progress {
                progressRow(progress)
                    .id(runtime.revision)
            }
            controls(event)
        }
    }

    private func summary(_ event: NowPlayingEvent) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.md) {
            artworkTile
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

    /// The song's artwork when it has one, else a symbol on a quiet tile.
    @ViewBuilder
    private var artworkTile: some View {
        if let artwork = runtime.artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: Self.artworkSize, height: Self.artworkSize)
                .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.control))
                .accessibilityHidden(true)
        } else {
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
    }

    // MARK: Controls

    /// Previous, play or pause, and next. The buttons post the media keys only when clicked,
    /// and are off while there is no song or holzBar lacks Accessibility.
    private func controls(_ event: NowPlayingEvent) -> some View {
        let isOn = event.track != nil && runtime.canControl
        let isPlaying = event.state == .playing
        return HStack(spacing: HolzBarTheme.Spacing.lg) {
            Spacer(minLength: 0)
            controlButton(symbol: "backward.fill", label: Text("Previous"), isOn: isOn) {
                runtime.send(.previous)
            }
            controlButton(
                symbol: isPlaying ? "pause.fill" : "play.fill",
                label: isPlaying ? Text("Pause") : Text("Play"),
                isOn: isOn
            ) {
                runtime.send(.playPause)
            }
            controlButton(symbol: "forward.fill", label: Text("Next"), isOn: isOn) {
                runtime.send(.next)
            }
            Spacer(minLength: 0)
        }
    }

    private func controlButton(
        symbol: String,
        label: Text,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(HolzBarTheme.Hub.compactSymbolFont)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .frame(minWidth: HolzBarTheme.minimumTargetSize, minHeight: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn)
        .opacity(isOn ? 1 : 0.4)
        .accessibilityLabel(label)
        .help(runtime.canControl ? label : Text("Needs Accessibility access"))
    }

    // MARK: Progress

    /// The elapsed time, the bar and the length. While the song plays, the system updates the
    /// time and the bar between a start and an end date; while it is paused they are still.
    @ViewBuilder
    private func progressRow(_ progress: NowPlayingProgress) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            if let end = progress.end {
                if progress.isPlaying {
                    Text(timerInterval: progress.start...end, pauseTime: nil, countsDown: false, showsHours: false)
                        .font(HolzBarTheme.Typography.caption.monospacedDigit())
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    ProgressView(timerInterval: progress.start...end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(HolzBarTheme.Palette.accent)
                } else {
                    Text(verbatim: Self.format(progress.position))
                        .font(HolzBarTheme.Typography.caption.monospacedDigit())
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    ProgressView(value: progress.position, total: max(progress.duration ?? 1, 1))
                        .tint(HolzBarTheme.Palette.accent)
                }
                Text(verbatim: Self.format(progress.duration ?? 0))
                    .font(HolzBarTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            } else if progress.isPlaying {
                // No length is known: only the time since the start, counted up by the system.
                Text(progress.start, style: .timer)
                    .font(HolzBarTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            } else {
                Text(verbatim: Self.format(progress.position))
                    .font(HolzBarTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Minutes and seconds, such as 3:05.
    private static func format(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    // MARK: State

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
