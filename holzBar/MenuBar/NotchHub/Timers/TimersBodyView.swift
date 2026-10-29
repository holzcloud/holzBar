//
//  TimersBodyView.swift
//  holzBar
//

import SwiftUI

/// The Timers tab: a preset to start a timer, and one row per timer.
///
/// The remaining time is drawn by the system from a date range, so the view runs no timer of
/// its own and refreshes nothing every second.
struct TimersBodyView: View {
    let runtime: TimersRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Chip("5 minutes", systemImage: "timer", isSelected: false) {
                runtime.startLength(300)
            }
            if runtime.board.items.isEmpty {
                Text("No timers yet")
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            } else {
                ForEach(runtime.board.items) { item in
                    row(item)
                }
            }
        }
        .padding(HolzBarTheme.Spacing.xs)
    }

    private func row(_ item: TimerItem) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            if item.label.isEmpty {
                Text("Timer")
            } else {
                Text(verbatim: item.label)
            }
            Spacer(minLength: 0)
            status(of: item)
        }
        .font(HolzBarTheme.Typography.body)
        .foregroundStyle(HolzBarTheme.Palette.text)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func status(of item: TimerItem) -> some View {
        switch item.state {
        case .running(let start, let end):
            Text(timerInterval: start...end, countsDown: true)
                .font(HolzBarTheme.Typography.mono)
                .monospacedDigit()
        case .paused(let remaining, _):
            Text(verbatim: Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond)))
                .font(HolzBarTheme.Typography.mono)
                .monospacedDigit()
        case .finished:
            Text("Done")
                .foregroundStyle(HolzBarTheme.Palette.danger)
        }
    }
}
