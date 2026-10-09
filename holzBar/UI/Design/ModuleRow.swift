//
//  ModuleRow.swift
//  holzBar
//

import SwiftUI

/// One module of holzBar as a row of a grouped list: a tinted symbol tile, name, one-line
/// description, an optional quiet permission line and a switch.
///
/// A module that is off costs nothing: it runs no timer, holds no memory and has asked for no
/// permission. The settings of a module open under its row only while it is on, indented to
/// the title. The row is plain; the group around the rows is the glass layer.
struct ModuleRow<Settings: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let systemImage: String
    private let title: Text
    private let summary: Text
    private let permission: Text?
    private let isPermissionGranted: Bool
    @Binding private var isOn: Bool
    private let settings: Settings

    init(
        systemImage: String,
        title: Text,
        summary: Text,
        isOn: Binding<Bool>,
        permission: Text? = nil,
        isPermissionGranted: Bool = false,
        @ViewBuilder settings: () -> Settings
    ) {
        self.systemImage = systemImage
        self.title = title
        self.summary = summary
        self._isOn = isOn
        self.permission = permission
        self.isPermissionGranted = isPermissionGranted
        self.settings = settings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOn {
                settings
                    .padding(.leading, symbolSize + HolzBarTheme.Spacing.md)
                    .padding(.trailing, HolzBarTheme.Spacing.md)
                    .padding(.bottom, HolzBarTheme.Spacing.sm)
                    .transition(.opacity)
            }
        }
        .background(alignment: .leading) {
            if isOn {
                LinearGradient(
                    colors: [HolzBarTheme.Palette.accent.opacity(0.08), .clear],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.7, y: 0.5)
                )
            }
        }
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
            value: isOn
        )
    }

    private let symbolSize = CGFloat(30)

    private var header: some View {
        HStack(spacing: HolzBarTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(width: symbolSize, height: symbolSize)
                .background(
                    HolzBarTheme.Palette.accent.opacity(0.16),
                    in: HolzBarTheme.shape(9)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HolzBarTheme.Palette.text)
                summary
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let permission {
                    Label {
                        permission
                    } icon: {
                        Image(systemName: isPermissionGranted ? "checkmark" : "lock")
                    }
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: HolzBarTheme.Spacing.sm)
            Toggle(isOn: $isOn) {
                title
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(HolzBarTheme.Palette.accent)
        }
        .padding(.horizontal, HolzBarTheme.Spacing.md)
        .padding(.vertical, HolzBarTheme.Spacing.sm + 2)
        .accessibilityElement(children: .contain)
    }
}

extension ModuleRow where Settings == EmptyView {
    init(
        systemImage: String,
        title: Text,
        summary: Text,
        isOn: Binding<Bool>,
        permission: Text? = nil,
        isPermissionGranted: Bool = false
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            summary: summary,
            isOn: isOn,
            permission: permission,
            isPermissionGranted: isPermissionGranted
        ) {
            EmptyView()
        }
    }
}

#Preview("ModuleRow") {
    @Previewable @State var isOn = true
    ModuleRow(
        systemImage: "timer",
        title: Text(verbatim: "Timers"),
        summary: Text(verbatim: "Countdowns in the notch hub."),
        isOn: $isOn,
        permission: Text(verbatim: "Asks for Notifications when you switch it on")
    ) {
        Text(verbatim: "Settings of the module appear here.")
            .font(HolzBarTheme.Typography.callout)
    }
    .frame(width: 460)
    .background(HolzBarTheme.Palette.ground)
}
