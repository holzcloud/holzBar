//
//  SearchField.swift
//  holzBar
//

import SwiftUI

/// The big search field of the launcher, the command palette and searches: a magnifier, the
/// field in the `searchField` type and, while it holds text, a button that clears it.
///
/// The field only edits the text it is bound to. What the text means, the selection and the
/// keys that move through the results stay with the screen that uses it.
struct SearchField: View {
    @Binding private var text: String
    private let prompt: Text
    private let isFocused: FocusState<Bool>.Binding?
    private let accessibilityLabel: Text?
    private let accessibilityValue: Text?

    /// Creates a search field.
    ///
    /// - Parameters:
    ///   - text: The text the user typed.
    ///   - prompt: The localized text shown while the field is empty. It also labels the field
    ///     for VoiceOver.
    ///   - isFocused: The focus of the field, when the screen sets or reads it.
    ///   - accessibilityLabel: A label for VoiceOver when the prompt is not the right one.
    ///   - accessibilityValue: A value for VoiceOver, such as the number of results.
    init(
        text: Binding<String>,
        prompt: Text,
        isFocused: FocusState<Bool>.Binding? = nil,
        accessibilityLabel: Text? = nil,
        accessibilityValue: Text? = nil
    ) {
        _text = text
        self.prompt = prompt
        self.isFocused = isFocused
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }

    var body: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .imageScale(.large)
                .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                .accessibilityHidden(true)
            field
            if !text.isEmpty {
                clearButton
            }
        }
        .padding(HolzBarTheme.Spacing.md)
    }

    @ViewBuilder
    private var field: some View {
        let textField = TextField(text: $text, prompt: prompt) {
            prompt
        }
        .labelsHidden()
        .textFieldStyle(.plain)
        .font(HolzBarTheme.Typography.searchField)
        .foregroundStyle(HolzBarTheme.Palette.text)

        Group {
            if let isFocused {
                textField.focused(isFocused)
            } else {
                textField
            }
        }
        .labelled(accessibilityLabel)
        .valued(accessibilityValue)
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

private extension View {
    /// Sets the VoiceOver label when there is one and leaves the view's own label otherwise.
    @ViewBuilder
    func labelled(_ label: Text?) -> some View {
        if let label {
            accessibilityLabel(label)
        } else {
            self
        }
    }

    /// Sets the VoiceOver value when there is one and leaves the view's own value otherwise.
    @ViewBuilder
    func valued(_ value: Text?) -> some View {
        if let value {
            accessibilityValue(value)
        } else {
            self
        }
    }
}

private struct SearchFieldPreview: View {
    @State private var empty = ""
    @State private var filled = "Wi-Fi"

    var body: some View {
        VStack(spacing: HolzBarTheme.Spacing.md) {
            SearchField(text: $empty, prompt: Text(verbatim: "Search…"))
            SearchField(text: $filled, prompt: Text(verbatim: "Search…"))
        }
        .frame(width: 480)
        .padding(HolzBarTheme.Spacing.md)
        .background(HolzBarTheme.Palette.ground)
    }
}

#Preview("SearchField") {
    SearchFieldPreview()
}
