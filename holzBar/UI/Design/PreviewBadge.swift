//
//  PreviewBadge.swift
//  holzBar
//

import SwiftUI

/// Marks a feature that is built but not yet tested on a Mac. It goes away once the feature
/// has been tested.
struct PreviewBadge: View {
    var body: some View {
        Text("Preview")
            .font(HolzBarTheme.Typography.caption.weight(.semibold))
            .foregroundStyle(HolzBarTheme.Palette.warning)
            .padding(.horizontal, HolzBarTheme.Spacing.xs + 2)
            .padding(.vertical, 2)
            .background(HolzBarTheme.Palette.warning.opacity(0.15), in: Capsule())
            .help("Preview: not tested on a Mac yet. Please report problems.")
    }
}

#Preview("PreviewBadge") {
    PreviewBadge()
        .padding()
        .background(HolzBarTheme.Palette.ground)
}
