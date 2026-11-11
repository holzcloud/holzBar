//
//  SettingsGroup.swift
//  holzBar
//

import SwiftUI

/// A group of settings (D-16): a short header, a rounded list on the elevated ground with a
/// hairline stroke and hairlines between its rows, and an optional footnote. The rows draw their
/// own hairline above them through `settingsRowChrome`; the list moves up by one hairline and
/// clips to its shape, so only the first row's line disappears, without private SwiftUI API
/// (D-51). The title is already localised by the catalogue.
struct SettingsGroup<Content: View>: View {
    private let title: String?
    private let footnote: Text?
    private let content: Content

    init(_ title: String? = nil, footnote: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(HolzBarTheme.Typography.callout.weight(.semibold))
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .padding(.leading, HolzBarTheme.SettingsKit.groupHeaderInset)
                    .padding(.bottom, HolzBarTheme.SettingsKit.groupHeaderGap)
                    .accessibilityAddTraits(.isHeader)
            }
            list
            if let footnote {
                footnote
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, HolzBarTheme.SettingsKit.footnoteGap)
                    .padding(.leading, HolzBarTheme.SettingsKit.footnoteInset)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.top, -HolzBarTheme.Spacing.hairline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HolzBarTheme.Palette.groundElevated)
        .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.list))
        .overlay {
            HolzBarTheme.shape(HolzBarTheme.Radius.list)
                .strokeBorder(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
        }
    }
}
