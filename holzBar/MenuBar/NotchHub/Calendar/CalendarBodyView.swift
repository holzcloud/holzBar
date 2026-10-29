//
//  CalendarBodyView.swift
//  holzBar
//

import SwiftUI

/// The Calendar tab: what is on now and the next events of today and tomorrow, each with its
/// calendar's colour, or a sentence that says why there is nothing to show.
struct CalendarBodyView: View {
    let runtime: CalendarRuntime

    var body: some View {
        Group {
            if runtime.authorization == .granted {
                list
            } else {
                missingAccess
            }
        }
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if runtime.rows.isEmpty {
            Text("No events today or tomorrow")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: HolzBarTheme.Spacing.xs) {
                    ForEach(runtime.rows) { row in
                        self.row(row)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ row: NextEvents.Row) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            CalendarColorDot(color: row.event.calendarColor)
            when(row)
                .font(HolzBarTheme.Typography.callout.monospacedDigit())
                .foregroundStyle(row.phase == .happening ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(verbatim: row.event.title.isEmpty ? String(localized: "Untitled") : row.event.title)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.phase != .allDay {
                Text(row.event.end, style: .time)
                    .font(HolzBarTheme.Typography.caption.monospacedDigit())
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Now", the start time, or "All day".
    @ViewBuilder
    private func when(_ row: NextEvents.Row) -> some View {
        switch row.phase {
        case .happening: Text("Now")
        case .upcoming: Text(row.event.start, style: .time)
        case .allDay: Text("All day")
        }
    }

    // MARK: Missing access

    private var missingAccess: some View {
        VStack(spacing: HolzBarTheme.Spacing.sm) {
            Text("Calendar access is off")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            Button("Open System Settings") {
                runtime.openSystemSettings()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
