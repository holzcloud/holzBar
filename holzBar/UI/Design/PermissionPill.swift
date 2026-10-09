//
//  PermissionPill.swift
//  holzBar
//

import SwiftUI

/// The state of the permission a module needs.
enum PermissionPillState: Sendable {
    /// The permission is needed and not granted.
    case needed
    /// The permission is granted.
    case granted
}

/// A small label that tells which permission a module needs and whether it is granted.
///
/// The text is passed in, already localized, so that each module words it as the
/// permission requires ("Needs Accessibility").
struct PermissionPill: View {
    private let text: Text
    private let state: PermissionPillState

    init(_ text: Text, state: PermissionPillState) {
        self.text = text
        self.state = state
    }

    private var tint: Color {
        switch state {
        case .needed: HolzBarTheme.Palette.permission
        case .granted: HolzBarTheme.Palette.success
        }
    }

    private var symbol: String {
        switch state {
        case .needed: "lock.shield"
        case .granted: "checkmark.seal"
        }
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            text
        }
        .font(HolzBarTheme.Typography.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .padding(.vertical, HolzBarTheme.Spacing.xxs / 2)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.35), lineWidth: HolzBarTheme.Spacing.hairline)
        }
    }
}

#Preview("PermissionPill") {
    VStack(alignment: .leading) {
        PermissionPill(Text(verbatim: "Needs Accessibility"), state: .needed)
        PermissionPill(Text(verbatim: "Accessibility granted"), state: .granted)
    }
    .padding()
    .background(HolzBarTheme.Palette.ground)
}
