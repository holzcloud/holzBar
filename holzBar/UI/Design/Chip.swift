//
//  Chip.swift
//  holzBar
//

import SwiftUI

/// A filter pill: a short label that can be selected, such as the filters of the launcher.
struct Chip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: LocalizedStringKey
    private let systemImage: String?
    private let isSelected: Bool
    private let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: HolzBarTheme.Spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
            }
            .font(HolzBarTheme.Typography.callout)
            .foregroundStyle(isSelected ? HolzBarTheme.Palette.onFill : HolzBarTheme.Palette.text)
            .padding(.horizontal, HolzBarTheme.Spacing.sm)
            .frame(minHeight: HolzBarTheme.minimumTargetSize)
            .background {
                if isSelected {
                    Capsule().fill(HolzBarTheme.fillGradient)
                } else {
                    Capsule().fill(HolzBarTheme.Palette.groundElevated)
                }
            }
            .overlay {
                Capsule().stroke(
                    HolzBarTheme.Palette.stroke,
                    lineWidth: HolzBarTheme.Spacing.hairline
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.snappy, reduceMotion: reduceMotion),
            value: isSelected
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Chip") {
    HStack {
        Chip(verbatim: "Files", isSelected: true) {}
        Chip(verbatim: "Apps", isSelected: false) {}
    }
    .padding()
    .background(HolzBarTheme.Palette.ground)
}

extension Chip {
    /// Creates a chip with a title that is not localized, for previews and tests.
    init(verbatim title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.init(LocalizedStringKey(title), isSelected: isSelected, action: action)
    }
}
