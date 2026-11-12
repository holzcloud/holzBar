//
//  SettingsSearchField.swift
//  holzBar
//

import SwiftUI

/// The compact search field at the top of the Settings sidebar (D-25). It shows the hint ⌘F while
/// it is empty and a clear button while it holds text; ⌘F focuses it and Escape empties it.
/// The field only edits the text it is bound to; what the text finds stays with the window.
struct SettingsSearchField: View {
    @Binding private var text: String
    private let isFocused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
        _text = text
        self.isFocused = isFocused
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: HolzBarTheme.SettingsSidebar.searchMagnifierSize))
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text("Search")) {
                Text("Search settings")
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(HolzBarTheme.Typography.body)
            .foregroundStyle(HolzBarTheme.Palette.text)
            .focused(isFocused)
            .onExitCommand { text = "" }
            .accessibilityLabel(Text("Search settings"))
            if text.isEmpty {
                Text(verbatim: "⌘F")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                    .accessibilityHidden(true)
            } else {
                clearButton
            }
        }
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .frame(height: HolzBarTheme.SettingsSidebar.searchFieldHeight)
        .background(HolzBarTheme.Palette.accent.opacity(fillOpacity), in: fieldShape)
        .overlay {
            if isFocused.wrappedValue {
                fieldShape.strokeBorder(
                    HolzBarTheme.Palette.accent,
                    lineWidth: HolzBarTheme.Spacing.dropOutline
                )
            }
        }
        .background(focusShortcut)
    }

    private var fieldShape: RoundedRectangle {
        HolzBarTheme.shape(HolzBarTheme.Radius.control)
    }

    private var fillOpacity: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.accentFillDark
            : HolzBarTheme.SettingsKit.accentFillLight
    }

    private var clearButton: some View {
        Button {
            text = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                .accessibilityLabel(Text("Clear"))
                .frame(
                    width: HolzBarTheme.minimumTargetSize,
                    height: HolzBarTheme.minimumTargetSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear")
    }

    /// Cmd-F focuses the field. A hidden button would switch its shortcut off, so the button is
    /// invisible and zero-sized instead.
    private var focusShortcut: some View {
        Button("Search") {
            isFocused.wrappedValue = true
        }
        .keyboardShortcut("f", modifiers: .command)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
