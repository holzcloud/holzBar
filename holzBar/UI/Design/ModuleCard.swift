//
//  ModuleCard.swift
//  holzBar
//

import SwiftUI

/// One module of holzBar in the settings gallery: its symbol, name and one-line description,
/// a switch and, if it needs one, the permission it asks for when it is switched on.
///
/// A module that is off costs nothing: it runs no timer, holds no memory and has asked for no
/// permission. The settings of a module are shown below the header only while it is on.
struct ModuleCard<Settings: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let systemImage: String
    private let title: Text
    private let summary: Text
    private let permission: PermissionPill?
    @Binding private var isOn: Bool
    private let settings: Settings

    init(
        systemImage: String,
        title: Text,
        summary: Text,
        isOn: Binding<Bool>,
        permission: PermissionPill? = nil,
        @ViewBuilder settings: () -> Settings
    ) {
        self.systemImage = systemImage
        self.title = title
        self.summary = summary
        self._isOn = isOn
        self.permission = permission
        self.settings = settings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            header
            if let permission {
                permission
            }
            if isOn {
                settings
                    .transition(.opacity)
            }
        }
        .padding(HolzBarTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            HolzBarTheme.Palette.groundElevated,
            in: HolzBarTheme.shape(HolzBarTheme.Radius.card)
        )
        .overlay {
            HolzBarTheme.shape(HolzBarTheme.Radius.card)
                .stroke(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
        }
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
            value: isOn
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: HolzBarTheme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .frame(width: HolzBarTheme.Spacing.xxl, height: HolzBarTheme.Spacing.xxl)
                .background(
                    HolzBarTheme.Palette.accent.opacity(0.12),
                    in: HolzBarTheme.shape(HolzBarTheme.Radius.control)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs / 2) {
                title
                    .font(HolzBarTheme.Typography.headline)
                    .foregroundStyle(HolzBarTheme.Palette.text)
                summary
                    .font(HolzBarTheme.Typography.callout)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: HolzBarTheme.Spacing.sm)
            Toggle(isOn: $isOn) {
                title
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(HolzBarTheme.Palette.accent)
        }
        .accessibilityElement(children: .contain)
    }
}

extension ModuleCard where Settings == EmptyView {
    init(
        systemImage: String,
        title: Text,
        summary: Text,
        isOn: Binding<Bool>,
        permission: PermissionPill? = nil
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            summary: summary,
            isOn: isOn,
            permission: permission
        ) {
            EmptyView()
        }
    }
}

#Preview("ModuleCard") {
    @Previewable @State var isOn = true
    ModuleCard(
        systemImage: "clock",
        title: Text(verbatim: "Timers"),
        summary: Text(verbatim: "Countdowns in the notch hub."),
        isOn: $isOn,
        permission: PermissionPill(Text(verbatim: "Needs Notifications"), state: .needed)
    ) {
        Text(verbatim: "Settings of the module appear here.")
            .font(HolzBarTheme.Typography.callout)
    }
    .padding()
    .frame(width: 420)
    .background(HolzBarTheme.Palette.ground)
}
