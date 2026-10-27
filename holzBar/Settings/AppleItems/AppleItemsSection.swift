//
//  AppleItemsSection.swift
//  holzBar
//

import SwiftUI

/// The settings of the Apple Items module (macOS 27): which of Apple's system items to hide.
/// The Modules pane shows it under the module's row while the module is on.
struct AppleItemsSection: View {
    var appleItems: AppleItems

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            Toggle("Hide the clock", isOn: binding(for: .clock))
        }
        .toggleStyle(.switch)
        .tint(HolzBarTheme.Palette.accent)
    }

    private func binding(for item: SystemItem27) -> Binding<Bool> {
        Binding(
            get: { appleItems.isHidden(item) },
            set: { appleItems.setHidden(item, $0) }
        )
    }
}
