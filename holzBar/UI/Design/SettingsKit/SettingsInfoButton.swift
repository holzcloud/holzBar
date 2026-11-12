//
//  SettingsInfoButton.swift
//  holzBar
//

import SwiftUI

/// The (i) button beside a setting (D-22): a drawn circle with a hit area of 28 pt that opens
/// the setting's explanation in a popover. It is reachable by keyboard and labelled
/// "Explanation" for VoiceOver; the row's control carries the same text as its hint. A click
/// elsewhere and Escape close the transient popover, and so does scrolling: a local scroll
/// monitor runs only while the popover is open, with no timer (D-46, D-51).
struct SettingsInfoButton: View {
    private let text: Text

    @State private var isPresented = false
    @State private var isHovered = false

    init(_ text: Text) {
        self.text = text
    }

    private var color: Color {
        isHovered ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textTertiary
    }

    /// The hit area is taller than the row's content; a negative padding keeps the row at its
    /// minimum height while the hit area stays whole.
    private var overhang: CGFloat {
        let content = HolzBarTheme.SettingsKit.rowMinHeight - 2 * HolzBarTheme.SettingsKit.rowPaddingVertical
        return max(0, (HolzBarTheme.SettingsKit.infoButtonHitArea - content) / 2)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Circle()
                .strokeBorder(color, lineWidth: HolzBarTheme.SettingsKit.infoButtonLineWidth)
                .frame(
                    width: HolzBarTheme.SettingsKit.infoButtonSize,
                    height: HolzBarTheme.SettingsKit.infoButtonSize
                )
                .overlay {
                    Text(verbatim: "i")
                        .font(HolzBarTheme.Typography.micro.weight(.semibold))
                        .foregroundStyle(color)
                }
                .frame(
                    width: HolzBarTheme.SettingsKit.infoButtonHitArea,
                    height: HolzBarTheme.SettingsKit.infoButtonHitArea
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -overhang)
        .focusable(true, interactions: .activate)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text("Explanation"))
        .help(text)
        .popover(isPresented: $isPresented) {
            text
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .frame(maxWidth: HolzBarTheme.SettingsKit.infoPopoverMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, HolzBarTheme.SettingsKit.infoPopoverPaddingVertical)
                .padding(.horizontal, HolzBarTheme.SettingsKit.infoPopoverPaddingHorizontal)
        }
        .localEventMonitor(mask: .scrollWheel, isEnabled: isPresented) { event in
            isPresented = false
            return event
        }
    }
}
