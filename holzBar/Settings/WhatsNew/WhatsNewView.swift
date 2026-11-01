//
//  WhatsNewView.swift
//  holzBar
//

import SwiftUI

/// The content of the What's New window: the release of the installed version, or the newest
/// one on a development build, as New, Improved and Fixed groups on the calm ground.
struct WhatsNewView: View {
    @Environment(AppState.self) private var appState

    /// The release to show: the installed version's, else the newest.
    private var release: WhatsNewRelease? {
        let tabs = WhatsNewPolicy.tabs(
            knownVersions: WhatsNewHistory.releases.map(\.version),
            current: Bundle.main.versionString
        )
        let version = tabs.installed ?? tabs.versions.first
        return WhatsNewHistory.releases.first { $0.version == version } ?? WhatsNewHistory.releases.first
    }

    var body: some View {
        ZStack {
            HolzBarGround()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.lg) {
                        if let release {
                            group("New", items: release.new)
                            group("Improved", items: release.improved)
                            fixedGroup(release.fixed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(HolzBarTheme.Spacing.xl)
                }
                Button("Done") {
                    appState.dismissWindow(.whatsNew)
                }
                .keyboardShortcut(.defaultAction)
                .padding(HolzBarTheme.Spacing.md)
            }
        }
        .frame(width: 560)
        .frame(minHeight: 460, idealHeight: 640, maxHeight: 800)
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, items: [WhatsNewItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                heading(title)
                ForEach(items) { item in
                    itemRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func fixedGroup(_ fixes: [WhatsNewFix]) -> some View {
        if !fixes.isEmpty {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
                heading("Fixed")
                ForEach(fixes) { fix in
                    HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HolzBarTheme.Palette.success)
                            .accessibilityHidden(true)
                        Text(LocalizedStringKey(fix.text))
                            .font(HolzBarTheme.Typography.callout)
                            .foregroundStyle(HolzBarTheme.Palette.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(HolzBarTheme.Typography.headline)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func itemRow(_ item: WhatsNewItem) -> some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: item.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(width: HolzBarTheme.Spacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text(LocalizedStringKey(item.title))
                    .font(HolzBarTheme.Typography.body.weight(.semibold))
                    .foregroundStyle(HolzBarTheme.Palette.text)
                Text(LocalizedStringKey(item.detail))
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
