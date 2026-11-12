//
//  Toast.swift
//  holzBar
//

import SwiftUI

/// A short notice that disappears on its own, plain or with one action (the undo toast).
struct Toast: View {
    private let text: Text
    private let systemImage: String?
    private let actionTitle: LocalizedStringKey?
    private let action: (() -> Void)?

    init(_ text: Text, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.actionTitle = nil
        self.action = nil
    }

    /// A toast with one button, such as Undo (concept 9a, D-13).
    init(
        _ text: Text,
        systemImage: String = "arrow.uturn.backward",
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        if let actionTitle, let action {
            HStack(spacing: HolzBarTheme.UndoToast.gap) {
                symbol
                sentence
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, HolzBarTheme.UndoToast.paddingHorizontal)
            .padding(.vertical, HolzBarTheme.UndoToast.paddingVertical)
            .holzBarGlass(in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(text)
            .accessibilityAction(named: Text(actionTitle), action)
        } else {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                symbol
                sentence
            }
            .padding(.horizontal, HolzBarTheme.Spacing.md)
            .padding(.vertical, HolzBarTheme.Spacing.xs)
            .holzBarGlass(in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        if let systemImage {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
        }
    }

    private var sentence: some View {
        text
            .font(HolzBarTheme.Typography.body)
            .foregroundStyle(HolzBarTheme.Palette.text)
    }
}

extension View {
    /// Shows a toast at the bottom of the view while `isPresented` is true and sets it back to
    /// false after the duration. With Reduce Motion it fades instead of sliding.
    func holzBarToast(
        isPresented: Binding<Bool>,
        duration: Duration = HolzBarTheme.UndoToast.plainDuration,
        toast: Toast
    ) -> some View {
        modifier(ToastModifier(isPresented: isPresented, duration: duration, toast: toast))
    }
}

private struct ToastModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool

    let duration: Duration
    let toast: Toast

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    toast
                        .padding(.bottom, HolzBarTheme.Spacing.lg)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
                value: isPresented
            )
            .task(id: isPresented) {
                guard isPresented else {
                    return
                }
                try? await Task.sleep(for: duration)
                isPresented = false
            }
    }
}

#Preview("Toast") {
    @Previewable @State var isPresented = true
    Color.clear
        .frame(width: 360, height: 160)
        .background(HolzBarTheme.Palette.ground)
        .holzBarToast(isPresented: $isPresented, toast: Toast(Text(verbatim: "Layout restored"), systemImage: "checkmark.circle"))
}
