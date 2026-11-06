//
//  WhatsNewReleaseBody.swift
//  holzBar
//

import SwiftUI

/// What one release brought: the New, Improved and Fixed groups, as rows on the ground.
///
/// A row is an SF Symbol, a title and one sentence, read by VoiceOver as one element; a fix is
/// a check and one sentence. A group without lines is left out. The texts are English String
/// Catalog keys, localized here.
struct WhatsNewReleaseBody: View {
    let release: WhatsNewRelease
    /// Whether the release starts with its version as a heading, so several releases read as
    /// sections one below the other.
    var showsVersion = false
    /// Whether this release is the installed version, which gets a small "Installed" tag.
    var isInstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            if showsVersion {
                versionHeading
            }
            itemGroup("New", items: release.new)
            itemGroup("Improved", items: release.improved)
            fixedGroup(release.fixed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var versionHeading: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Text(verbatim: release.version)
                .font(HolzBarTheme.Typography.title)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityLabel(String(localized: "Version \(release.version)"))
                .accessibilityAddTraits(.isHeader)
            if isInstalled {
                installedTag
            }
        }
    }

    /// The small tag next to the installed version: the wood dot and the word.
    private var installedTag: some View {
        HStack(spacing: HolzBarTheme.Spacing.xxs) {
            Circle()
                .fill(HolzBarTheme.Palette.wood)
                .frame(width: HolzBarTheme.Spacing.xs, height: HolzBarTheme.Spacing.xs)
                .accessibilityHidden(true)
            Text("Installed")
                .font(HolzBarTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        }
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .padding(.vertical, HolzBarTheme.Spacing.xxs)
        .background(HolzBarTheme.Palette.groundElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline))
    }

    @ViewBuilder
    private func itemGroup(_ title: LocalizedStringKey, items: [WhatsNewItem]) -> some View {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(fixes.enumerated()), id: \.element.id) { index, fix in
                        if index > 0 {
                            Divider()
                        }
                        fixRow(fix)
                            .padding(.horizontal, HolzBarTheme.Spacing.md)
                            .padding(.vertical, HolzBarTheme.Spacing.sm)
                    }
                }
                .background(HolzBarTheme.Palette.groundElevated, in: HolzBarTheme.shape(HolzBarTheme.Radius.control))
                .overlay(
                    HolzBarTheme.shape(HolzBarTheme.Radius.control)
                        .strokeBorder(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
                )
            }
        }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(HolzBarTheme.Typography.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(HolzBarTheme.Palette.textTertiary)
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fixRow(_ fix: WhatsNewFix) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.success)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(fix.text))
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("WhatsNewReleaseBody") {
    WhatsNewReleaseBody(
        release: WhatsNewRelease(
            version: "1.0.1",
            new: [WhatsNewItem(symbol: "sparkles", title: "What's New window", detail: "Opens after an update.")],
            improved: [WhatsNewItem(symbol: "bolt", title: "Faster", detail: "Starts sooner.")],
            fixed: [WhatsNewFix(text: "The Shelf no longer flickers.")]
        )
    )
    .padding(HolzBarTheme.Spacing.xl)
    .frame(width: 560)
    .background(HolzBarTheme.Palette.ground)
}
