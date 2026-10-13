//
//  LayoutBar.swift
//  holzBar
//

import SwiftUI

/// One section of the menu bar layout: the strip of its items, which can be dragged, inside a
/// card that the pane draws (``HolzBarSection``).
///
/// The strip keeps the colour of the real menu bar, because the pictures of the items are
/// captured from it and are only legible on it. Everything around the strip follows the
/// design concept: the card is the glass layer, the strip a plain inset well in it.
struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection.Name
        @Binding var isDropTarget: Bool

        func makeNSView(context: Context) -> LayoutBarScrollView {
            let scrollView = LayoutBarScrollView(appState: appState, section: section)
            scrollView.onDropTargetChange = { isDropTarget in
                self.isDropTarget = isDropTarget
            }
            return scrollView
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) { }
    }

    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var imageCache: MenuBarItemImageCache

    let section: MenuBarSection.Name

    /// Whether an item is being dragged over the strip.
    @State private var isDropTarget = false

    /// The strip's height, empty or not.
    private static let stripHeight: CGFloat = 40

    /// Concentric to the card from macOS 26 on (the card gives its shape as the container
    /// shape); the `control` radius before.
    private var stripShape: AnyShape {
        if #available(macOS 26.0, *) {
            AnyShape(ConcentricRectangle())
        } else {
            AnyShape(HolzBarTheme.shape(HolzBarTheme.Radius.control))
        }
    }

    /// Whether the section holds no items.
    private var isEmpty: Bool {
        appState.itemManager.itemCache[section].isEmpty
    }

    var body: some View {
        mainContent
            .frame(maxWidth: .infinity)
            .frame(height: Self.stripHeight)
            .modifier(StripBackground(appState: appState, isEmpty: isEmpty))
            .overlay {
                stripShape
                    .fill(HolzBarTheme.Palette.accent.opacity(isDropTarget ? 0.16 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                // Twice the width: the clip below cuts away the outer half, which leaves the
                // border inside the shape.
                stripShape
                    .stroke(
                        isDropTarget ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.stroke,
                        lineWidth: 2 * (isDropTarget ? 2 : HolzBarTheme.Spacing.hairline)
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(stripShape)
            .contentShape([.interaction, .focusEffect], stripShape)
            .animation(HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion), value: isDropTarget)
    }

    @ViewBuilder
    private var mainContent: some View {
        if imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .padding(HolzBarTheme.Spacing.sm)
        } else {
            // The hint lets every pointer event through to the strip.
            Representable(appState: appState, section: section, isDropTarget: $isDropTarget)
                .overlay {
                    if isEmpty {
                        CompactEmptyState(message: Text("Drag an item here to move it to this section."))
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

/// The strip's background: the menu bar's colour behind items, nothing behind the empty
/// hint, so the hint reads on the card in light and dark.
private struct StripBackground: ViewModifier {
    let appState: AppState
    let isEmpty: Bool

    func body(content: Content) -> some View {
        if isEmpty {
            content
        } else {
            content.menuBarItemContainer(appState: appState)
        }
    }
}
