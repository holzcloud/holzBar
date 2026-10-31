//
//  FileDropBodyView.swift
//  holzBar
//

import SwiftUI

/// The File drop tab: the stashed files as tiles, and the place to drop more.
///
/// The whole body takes a drop of files from the Finder or any other app. While a drag is over
/// it, a dashed outline in the accent colour and the words "Drop to keep" say so; under
/// Increase Contrast the outline is solid and at full strength, and under Reduce Motion it
/// fades in instead of springing. The hub is always dark, so the tiles use fixed white tints.
struct FileDropBodyView: View {
    let runtime: FileDropRuntime

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: CGFloat(NotchHubGeometry.bodyHeight), alignment: .top)
            .contentShape(Rectangle())
            .overlay { dropOutline }
            .dropDestination(for: URL.self) { urls, _ in
                let result = runtime.add(urls: urls)
                return result.added + result.moved > 0
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }

    @ViewBuilder
    private var content: some View {
        if runtime.stash.files.isEmpty {
            EmptyState(
                systemImage: "tray.and.arrow.down",
                title: Text("Drop files here"),
                message: Text("They stay here until you drag them out or remove them.")
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: CGFloat(DesignTokens.Hub.fileTileWidth), maximum: CGFloat(DesignTokens.Hub.fileTileWidth)),
                            spacing: HolzBarTheme.Hub.tileGap
                        ),
                    ],
                    alignment: .leading,
                    spacing: HolzBarTheme.Hub.tileGap
                ) {
                    ForEach(runtime.stash.files) { file in
                        FileDropTile(file: file) {
                            runtime.remove(file.id)
                        }
                    }
                }
                .padding(.vertical, HolzBarTheme.Spacing.xxs)
            }
        }
    }

    /// The outline and the words that show while a drag is over the body.
    private var dropOutline: some View {
        let radius = CGFloat(DesignTokens.Hub.tileRadius)
        let dash = contrast == .increased ? [] : DesignTokens.Hub.fileDropOutlineDash.map { CGFloat($0) }
        let strength = contrast == .increased ? 1 : DesignTokens.Hub.fileDropOutlineAlpha
        return ZStack {
            HolzBarTheme.shape(radius)
                .strokeBorder(
                    HolzBarTheme.Palette.accent.opacity(strength),
                    style: StrokeStyle(lineWidth: CGFloat(DesignTokens.Hub.fileDropOutlineWidth), dash: dash)
                )
            Text("Drop to keep")
                .font(HolzBarTheme.Hub.fileDropLabelFont)
                .foregroundStyle(.white.opacity(contrast == .increased ? 1 : DesignTokens.Hub.fileDropLabelAlpha))
                .padding(HolzBarTheme.Spacing.xs)
                .background(HolzBarTheme.Hub.top.opacity(DesignTokens.Hub.fileDropScrimAlpha), in: Capsule())
        }
        .opacity(isTargeted ? 1 : 0)
        .animation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.snappy, reduceMotion: reduceMotion), value: isTargeted)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One stashed file: its type icon and name, and a button that takes it out of the stash.
private struct FileDropTile: View {
    let file: StashedFile
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: HolzBarTheme.Spacing.xxs) {
            Image(nsImage: FileDropIcons.icon(for: file.url))
                .resizable()
                .scaledToFit()
                .frame(width: CGFloat(DesignTokens.Hub.fileIconSize), height: CGFloat(DesignTokens.Hub.fileIconSize))
                .accessibilityHidden(true)
            Text(verbatim: file.url.lastPathComponent)
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
        }
        .padding(HolzBarTheme.Spacing.xxs)
        .frame(width: CGFloat(DesignTokens.Hub.fileTileWidth), height: CGFloat(DesignTokens.Hub.fileTileHeight), alignment: .top)
        .background(
            .white.opacity(reduceTransparency ? DesignTokens.Hub.tileFillAlphaOpaque : DesignTokens.Hub.tileFillAlpha),
            in: HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
        )
        .overlay {
            HolzBarTheme.shape(CGFloat(DesignTokens.Hub.tileRadius))
                .stroke(.white.opacity(DesignTokens.Hub.fileTileBorderAlpha), lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .overlay(alignment: .topTrailing) {
            removeButton
        }
        .focusable()
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .onKeyPress(.delete) {
            onRemove()
            return .handled
        }
        .onKeyPress(.deleteForward) {
            onRemove()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: file.url.lastPathComponent))
        .accessibilityAction(named: Text("Remove"), onRemove)
    }

    /// The remove button: an 18 pt circle with a cross inside a 24 pt hit area, shown while the
    /// pointer is over the tile or the tile has focus.
    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(HolzBarTheme.Typography.micro)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .frame(width: CGFloat(DesignTokens.Hub.fileRemoveSize), height: CGFloat(DesignTokens.Hub.fileRemoveSize))
                .background(HolzBarTheme.Hub.pillFill, in: Circle())
                .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove"))
        .opacity(isHovered || isFocused ? 1 : 0)
    }
}
