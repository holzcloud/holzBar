//
//  Toast.swift
//  holzBar
//

import SwiftUI

/// A short notice that disappears on its own.
struct Toast: View {
    private let text: Text
    private let systemImage: String?

    init(_ text: Text, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                    .accessibilityHidden(true)
            }
            text
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(HolzBarTheme.Palette.text)
        }
        .padding(.horizontal, HolzBarTheme.Spacing.md)
        .padding(.vertical, HolzBarTheme.Spacing.xs)
        .holzBarGlass(in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows a toast at the bottom of the view while `isPresented` is true and sets it back to
    /// false after the duration. With Reduce Motion it fades instead of sliding.
    func holzBarToast(
        isPresented: Binding<Bool>,
        duration: Duration = .seconds(3),
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
