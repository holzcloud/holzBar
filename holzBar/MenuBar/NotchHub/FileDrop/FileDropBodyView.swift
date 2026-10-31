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
            VStack(spacing: HolzBarTheme.Spacing.xxs) {
                grid
                footer
            }
        }
    }

    private var grid: some View {
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
                    FileDropTile(
                        file: file,
                        onRemove: { runtime.remove(file.id) },
                        onShowInFinder: { runtime.showInFinder(file.id) },
                        onDragFinished: { completed in
                            runtime.dragFinished(id: file.id, completed: completed)
                        }
                    )
                }
            }
            .padding(.vertical, HolzBarTheme.Spacing.xxs)
        }
    }

    /// The notice of a full stash and the button that empties it. Neither needs a timer: the
    /// notice shows for as long as the stash is full.
    @ViewBuilder
    private var footer: some View {
        let count = runtime.stash.files.count
        let isFull = count >= FileStash.maximumFiles
        if isFull || count >= 2 {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                if isFull {
                    Text("The stash is full")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Hub.pillText)
                }
                Spacer(minLength: 0)
                if count >= 2 {
                    Button {
                        runtime.removeAll()
                    } label: {
                        Text("Remove all")
                            .font(HolzBarTheme.Typography.caption)
                            .foregroundStyle(HolzBarTheme.Hub.pillText)
                            .frame(minHeight: HolzBarTheme.minimumTargetSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
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

/// One stashed file: its type icon and name, a drag source over it, and two buttons that show it
/// in the Finder and take it out of the stash.
///
/// A file that no longer exists is drawn at half strength with the caption "Missing" and cannot
/// be dragged. Everything a pointer does has a keyboard and a VoiceOver alternative: Delete
/// removes the focused tile, Return shows it in the Finder, and both are named actions.
private struct FileDropTile: View {
    let file: StashedFile
    let onRemove: () -> Void
    let onShowInFinder: () -> Void
    let onDragFinished: @MainActor (_ completed: Bool) -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        let icon = FileDropIcons.icon(for: file.url)
        ZStack {
            content(icon: icon)
            if !file.isMissing {
                FileDropDragSource(url: file.url, icon: icon, onFinished: onDragFinished)
            }
        }
        .frame(width: CGFloat(DesignTokens.Hub.fileTileWidth), height: CGFloat(DesignTokens.Hub.fileTileHeight), alignment: .top)
        .overlay(alignment: .topLeading) {
            if !file.isMissing {
                showInFinderButton
            }
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
        .onKeyPress(.return) {
            guard !file.isMissing else {
                return .ignored
            }
            onShowInFinder()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: file.url.lastPathComponent))
        .accessibilityValue(file.isMissing ? Text("Missing") : Text(verbatim: ""))
        .accessibilityAction(named: Text("Remove"), onRemove)
        .modifier(ShowInFinderAction(isAvailable: !file.isMissing, action: onShowInFinder))
    }

    /// The icon, the name and, for a missing file, the caption.
    private func content(icon: NSImage) -> some View {
        VStack(spacing: HolzBarTheme.Spacing.xxs) {
            VStack(spacing: HolzBarTheme.Spacing.xxs) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: CGFloat(DesignTokens.Hub.fileIconSize), height: CGFloat(DesignTokens.Hub.fileIconSize))
                    .accessibilityHidden(true)
                Text(verbatim: file.url.lastPathComponent)
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.pillText)
                    .lineLimit(file.isMissing ? 1 : 2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
            .opacity(file.isMissing ? DesignTokens.Hub.fileMissingAlpha : 1)
            if file.isMissing {
                Text("Missing")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Hub.pillText)
            }
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
    }

    /// The remove button: an 18 pt circle with a cross inside a 24 pt hit area, shown while the
    /// pointer is over the tile or the tile has focus.
    private var removeButton: some View {
        cornerButton(systemImage: "xmark", label: Text("Remove"), action: onRemove)
    }

    /// The Show in Finder button, on the other corner.
    private var showInFinderButton: some View {
        cornerButton(systemImage: "magnifyingglass", label: Text("Show in Finder"), action: onShowInFinder)
    }

    private func cornerButton(systemImage: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(HolzBarTheme.Typography.micro)
                .foregroundStyle(HolzBarTheme.Hub.pillText)
                .frame(width: CGFloat(DesignTokens.Hub.fileRemoveSize), height: CGFloat(DesignTokens.Hub.fileRemoveSize))
                .background(HolzBarTheme.Hub.pillFill, in: Circle())
                .frame(width: HolzBarTheme.minimumTargetSize, height: HolzBarTheme.minimumTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(label)
        .opacity(isHovered || isFocused ? 1 : 0)
    }
}

/// Adds the named VoiceOver action "Show in Finder" while the file can be shown.
private struct ShowInFinderAction: ViewModifier {
    let isAvailable: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if isAvailable {
            content.accessibilityAction(named: Text("Show in Finder"), action)
        } else {
            content
        }
    }
}
