//
//  LiveActivitiesBodyView.swift
//  holzBar
//

import SwiftUI

/// The Live activities tab: what is going on, with the top activity first.
///
/// The list is the hub's board of every module's activities, from the hub itself
/// (``HubHost/liveActivities``): a running timer shows here as well as in Timers, and an accessory
/// alert shows for as long as it is live. Nothing is filtered by module (D-08). A finished
/// activity shows its own done title and symbol until it leaves; the view asks the system to draw
/// it again at each of those moments, so it runs no timer and refreshes nothing in between.
struct LiveActivitiesBodyView: View {
    let host: any HubHost

    var body: some View {
        TimelineView(.explicit(refreshDates)) { context in
            content(HubActivityBoard.board(host.liveActivities, now: context.date))
        }
        .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
    }

    /// Now, and each moment at which a finished activity leaves.
    private var refreshDates: [Date] {
        let now = Date.now
        let expiries = host.liveActivities
            .compactMap { activity in activity.finishedAt?.addingTimeInterval(HubActivityBoard.finishedHold) }
            .filter { $0 > now }
            .sorted()
        return [now] + expiries
    }

    @ViewBuilder
    private func content(_ board: HubActivityBoard.Board) -> some View {
        if board.listed.isEmpty {
            Text("Nothing is going on")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                ForEach(board.listed) { activity in
                    row(activity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, HolzBarTheme.Spacing.xxs)
        }
    }

    private func row(_ activity: LiveActivity) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: activity.symbol)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(activity.tint.color)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.hairline) {
                Text(verbatim: activity.title)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                if let detail = activity.detail {
                    Text(verbatim: detail)
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
