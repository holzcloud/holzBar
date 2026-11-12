//
//  SettingsStateLines.swift
//  holzBar
//

import SwiftUI

/// What a state line states (D-19).
enum SettingsStateKind {
    case info
    case warning
    case success

    var symbolName: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .success: "checkmark"
        }
    }

    var color: Color {
        switch self {
        case .info: HolzBarTheme.Palette.textSecondary
        case .warning: HolzBarTheme.Palette.warning
        case .success: HolzBarTheme.Palette.success
        }
    }
}

/// A row that states a condition with its symbol and at most one button, and never explains
/// (D-19, D-46); explanations live in the info popover. It dims like a row inside a dependent
/// group.
struct SettingsStateLine<Action: View>: View {
    private let kind: SettingsStateKind
    private let text: Text
    private let action: Action

    @Environment(\.settingsParentIsOn) private var parentIsOn

    init(_ kind: SettingsStateKind, _ text: Text, @ViewBuilder action: () -> Action) {
        self.kind = kind
        self.text = text
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.stateLineGap) {
            symbol
            text
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(kind.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            action
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome()
        .accessibilityElement(children: .contain)
    }

    /// Only the warning symbol is read by VoiceOver; the text of the other kinds says the state.
    private var symbol: some View {
        Image(systemName: kind.symbolName)
            .font(HolzBarTheme.Typography.callout)
            .foregroundStyle(kind.color)
            .accessibilityLabel(Text("Warning"))
            .accessibilityHidden(kind != .warning)
    }
}

extension SettingsStateLine where Action == EmptyView {
    init(_ kind: SettingsStateKind, _ text: Text) {
        self.init(kind, text) {
            EmptyView()
        }
    }
}

/// A line that points out something without stating a condition: the accent info symbol and a
/// quiet text, with padding 8 x 12 (D-19).
struct SettingsNoteLine: View {
    private let text: Text

    @Environment(\.settingsParentIsOn) private var parentIsOn

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HolzBarTheme.SettingsKit.stateLineGap) {
            Image(systemName: "info.circle")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
            text
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(parentIsOn ? 1 : HolzBarTheme.SettingsKit.dependentOpacity)
        .settingsRowChrome(
            verticalPadding: HolzBarTheme.SettingsKit.noteLinePaddingVertical,
            trailingPadding: HolzBarTheme.SettingsKit.noteLinePaddingHorizontal
        )
        .accessibilityElement(children: .contain)
    }
}
