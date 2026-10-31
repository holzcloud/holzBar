//
//  LiveActivitiesBodyView.swift
//  holzBar
//

import SwiftUI

/// The Live activities tab: what is going on, by symbol and title.
struct LiveActivitiesBodyView: View {
    let runtime: LiveActivitiesRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            ForEach(runtime.activities) { activity in
                HStack(spacing: HolzBarTheme.Spacing.xs) {
                    Image(systemName: activity.symbol)
                        .font(HolzBarTheme.Typography.body)
                        .foregroundStyle(activity.tint.color)
                        .accessibilityHidden(true)
                    Text(verbatim: activity.title)
                        .font(HolzBarTheme.Typography.body)
                        .foregroundStyle(HolzBarTheme.Palette.text)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
    }
}
