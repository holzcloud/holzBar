//
//  SettingsFilterField.swift
//  holzBar
//

import SwiftUI

/// A compact field that narrows a list in a pane, drawn like the sidebar's search field: the
/// magnifier, the text, a clear button while it holds text; Escape empties it. It has no
/// shortcut of its own (⌘F belongs to the settings search).
struct SettingsFilterField: View {
    @Binding private var text: String
    private let prompt: Text
    private let label: Text
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(text: Binding<String>, prompt: Text, label: Text) {
        _text = text
        self.prompt = prompt
        self.label = label
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: HolzBarTheme.SettingsSidebar.searchMagnifierSize))
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt) {
                label
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(HolzBarTheme.Typography.body)
            .foregroundStyle(HolzBarTheme.Palette.text)
            .focused($isFocused)
            .onExitCommand { text = "" }
            .accessibilityLabel(label)
            if !text.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, HolzBarTheme.Spacing.xs)
        .frame(minWidth: HolzBarTheme.LayoutList.filterFieldMinWidth)
        .frame(height: HolzBarTheme.SettingsSidebar.searchFieldHeight)
        .background(HolzBarTheme.Palette.accent.opacity(fillOpacity), in: fieldShape)
        .overlay {
            if isFocused {
                fieldShape.strokeBorder(
                    HolzBarTheme.Palette.accent,
                    lineWidth: HolzBarTheme.Spacing.dropOutline
                )
            }
        }
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
}
