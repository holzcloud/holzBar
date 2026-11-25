//
//  SettingsChangeRow.swift
//  holzBar
//

import SwiftUI

/// One changed setting in a preview (concept B5): the setting's label, then its current value in
/// `textTertiary`, an arrow in `textSecondary` and the new value in `text`. A setting whose value
/// is a list or a structure shows the word "Changed" instead of the pair.
///
/// The label and the values are one line each; a value that does not fit is cut in the middle,
/// and VoiceOver reads the whole row as one element with the values in full.
struct SettingsChangeRow: View {
    private let label: String
    private let values: (before: String, after: String)?

    /// A setting whose value goes from `before` to `after`.
    init(_ label: String, before: String, after: String) {
        self.label = label
        values = (before, after)
    }

    /// A setting whose value is a list or a structure.
    init(compositeLabel label: String) {
        self.label = label
        values = nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: HolzBarTheme.SettingsKit.accessoryGap) {
            Text(verbatim: label)
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let values {
                Text(verbatim: values.before)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Image(systemName: "arrow.right")
                    .font(HolzBarTheme.Typography.micro)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: values.after)
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            } else {
                Text("Changed")
                    .font(HolzBarTheme.Typography.body)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .settingsRowChrome()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    /// What VoiceOver reads: "name, from X to Y", or "name, will change" for a composite value.
    private var spokenLabel: String {
        if let values {
            String(localized: "\(label), from \(values.before) to \(values.after)")
        } else {
            String(localized: "\(label), will change")
        }
    }
}

#Preview("SettingsChangeRow") {
    SettingsGroup {
        SettingsChangeRow("Show on hover", before: "Off", after: "On")
        SettingsChangeRow(compositeLabel: "Hotkeys")
    }
    .padding()
    .frame(width: 440)
    .background(HolzBarTheme.Palette.ground)
}
