//
//  MenuBarAppearanceEditor.swift
//  holzBar
//

import SwiftUI

struct MenuBarAppearanceEditor: View {
    enum Location {
        case settings
        case panel
    }

    @Environment(AppState.self) var appState
    @Bindable var appearanceManager: MenuBarAppearanceManager
    @State private var isResetPromptPresented = false

    let location: Location

    /// Only the groups: the host (the Settings pane or the panel) draws the scroll view, the margins
    /// and the ground.
    @ViewBuilder
    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            SettingsStateLine(.info, Text("holzBar cannot edit the appearance of automatically hidden menu bars."))
        } else {
            MoodsSection(appearanceManager: appearanceManager)
            shapeGroup
            dynamicGroup
            partialEditor
            notchAndScreenGroup
            resetGroup
        }
    }

    @ViewBuilder
    private var partialEditor: some View {
        if appearanceManager.configuration.isDynamic {
            LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .light)
            LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .dark)
        } else {
            StaticPartialEditor(configuration: $appearanceManager.configuration)
        }
    }

    private var shapeGroup: some View {
        SettingsGroup(
            SettingsCatalog.AppearancePane.shape,
            footnote: Text("On macOS 27, a shape saved as Sections is drawn as Paired.")
        ) {
            MenuBarShapePicker(configuration: $appearanceManager.configuration)
            if appearanceManager.configuration.shapeKind != .noShape {
                SettingsToggleRow(.appearanceInsetShape, isOn: $appearanceManager.configuration.isInset)
                    .settingsSubRow()
            }
            SettingsToggleRow(.appearanceAppleLogoShape, isOn: appleLogoShapeBinding)
            shapeScreenRecordingHint
        }
    }

    private var dynamicGroup: some View {
        HolzBarSection {
            isDynamicToggle
        }
    }

    private var notchAndScreenGroup: some View {
        SettingsGroup(SettingsCatalog.AppearancePane.notchAndScreen) {
            SettingsPickerRow(
                .appearanceBlackMenuBar,
                selection: $appearanceManager.configuration.blackBackground
            ) {
                ForEach(MenuBarBlackBackground.allCases) { option in
                    Text(option.localized).tag(option)
                }
            }
            SettingsToggleRow(
                .appearanceRoundCorners,
                isOn: $appearanceManager.configuration.roundsScreenCorners
            )
            SettingsSliderRow(
                .appearanceCornerRadius,
                value: $appearanceManager.configuration.screenCornerRadius,
                in: 4...24,
                step: 1
            ) { radius in
                Text("\(Int(radius)) pt")
            }
            .settingsSubRow()
            .settingsDependent(on: appearanceManager.configuration.roundsScreenCorners)
        }
    }

    /// The old callout's condition: the tip points out the panel, which only exists with the
    /// secondary context menu.
    private var showsRightClickTip: Bool {
        if case .settings = location {
            appState.settings.advanced.enableSecondaryContextMenu
        } else {
            false
        }
    }

    private var resetGroup: some View {
        SettingsGroup(
            footnote: showsRightClickTip
                ? Text("Tip: Right-click an empty area of the menu bar to edit these settings in a panel of their own.")
                : nil
        ) {
            SettingsButtonRow(.appearanceReset) {
                Button("Reset…", role: .destructive) {
                    isResetPromptPresented = true
                }
                .disabled(appearanceManager.configuration == .defaultConfiguration)
            }
            .holzBarConfirmation(
                isPresented: $isResetPromptPresented,
                title: Text("Reset Menu Bar Appearance"),
                message: Text("This action cannot be undone."),
                confirmTitle: "Reset",
                isDestructive: true
            ) {
                appearanceManager.configuration = .defaultConfiguration
            }
        }
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle("Use dynamic appearance", isOn: $appearanceManager.configuration.isDynamic)
            .annotation("Apply different settings based on the current system appearance.")
    }

    /// Whether holzBar runs on macOS 27.
    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            true
        } else {
            false
        }
    }

    /// Says that Screen Recording is missing when a shape is chosen and the wallpaper beside it
    /// cannot be read from its file (a moving wallpaper). Before macOS 27 only: on macOS 27
    /// holzBar never captures the wallpaper.
    @ViewBuilder
    private var shapeScreenRecordingHint: some View {
        if
            !isMacOS27,
            appearanceManager.configuration.shapeKind != .noShape,
            !ScreenRecordingAccess.isGranted(appState),
            !(NSScreen.main.map(DesktopPicture.isReadable(on:)) ?? false)
        {
            SettingsStateLine(.warning, Text("Moving wallpaper: needs Screen Recording")) {
                Button("Allow Screen Recording…") {
                    Task {
                        await ScreenRecordingAccess.request(for: .menuBarShape, appState: appState)
                    }
                }
            }
        }
    }

    /// The capsule behind the Apple menu, offered with every shape kind, None included, on every
    /// supported macOS.
    private var appleLogoShapeBinding: Binding<Bool> {
        Binding(
            get: { appearanceManager.configuration.appleLogoStyle == .capsule },
            set: { appearanceManager.configuration.appleLogoStyle = $0 ? .capsule : .standard }
        )
    }
}

private struct UnlabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    /// Whether the bar draws a shape (Single, Paired or Sections), so a gradient can run over
    /// each shape.
    let drawsShape: Bool
    /// Whether the Apple menu has a capsule of its own, so its fill can be chosen.
    let drawsAppleLogo: Bool

    var body: some View {
        HolzBarSection {
            tintPicker
            accentColorToggle
            tintStrength
            gradientOptions
            appleLogoFill
            shadowToggle
        }
        HolzBarSection {
            borderToggle
            borderFill
            borderColor
            borderWidth
            borderStyle
        }
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                HolzBarPicker("Tint", selection: $configuration.tintKind) {
                    // System Glass needs macOS 26; an older system shows no tint for it.
                    ForEach(MenuBarTintKind.allCases.filter(\.isAvailable)) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint, .adaptive, .systemGlass:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        configuration.tintKind.localized,
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .disabled(configuration.tintFollowsAccentColor)
                case .gradient:
                    HolzBarGradientPicker(
                        configuration.tintKind.localized,
                        gradient: $configuration.tintGradient,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                }
            }
            .frame(height: 24)
        }
    }

    @ViewBuilder
    private var accentColorToggle: some View {
        if configuration.tintKind == .solid {
            Toggle("Use Accent Color", isOn: $configuration.tintFollowsAccentColor)
                .annotation("Follows the accent color chosen in System Settings, Appearance.")
        } else if configuration.tintKind == .adaptive {
            Text("Tints the menu bar with the main colors of your wallpaper, read from its file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if configuration.tintKind == .systemGlass {
            // A fact about the system's options; there is no switch for it.
            Text("With Reduce Transparency or Increase Contrast on in System Settings (Accessibility, Display), System Glass is drawn opaque with a border.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Whether the tint is one that has a strength and, for the last two, a direction.
    private var tintHasStrength: Bool {
        switch configuration.tintKind {
        case .solid, .gradient, .adaptive: true
        case .noTint, .systemGlass: false
        }
    }

    private var tintHasDirection: Bool {
        switch configuration.tintKind {
        case .gradient, .adaptive: true
        case .noTint, .solid, .systemGlass: false
        }
    }

    @ViewBuilder
    private var tintStrength: some View {
        if tintHasStrength {
            LabeledContent {
                Slider(
                    value: $configuration.style.tintStrength,
                    in: MenuBarPartialStyle.tintStrengthRange,
                    step: 0.05
                ) {
                    Text("Tint Strength")
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                .accessibilityValue(
                    Text(configuration.style.tintStrength, format: .percent.precision(.fractionLength(0)))
                )
            } label: {
                Text("Tint Strength")
            }
        }
    }

    @ViewBuilder
    private var gradientOptions: some View {
        if tintHasDirection {
            HolzBarPicker(selection: $configuration.style.gradientDirection) {
                Text("Horizontal").tag(MenuBarGradientDirection.horizontal)
                Text("Vertical").tag(MenuBarGradientDirection.vertical)
            } label: {
                Text("Gradient Direction")
            }
            if drawsShape {
                Toggle(isOn: gradientPerShape) {
                    Text("One gradient per shape")
                }
            }
        }
    }

    private var gradientPerShape: Binding<Bool> {
        Binding(
            get: { configuration.style.gradientSpan == .eachShape },
            set: { configuration.style.gradientSpan = $0 ? .eachShape : .acrossBar }
        )
    }

    @ViewBuilder
    private var appleLogoFill: some View {
        if drawsAppleLogo {
            LabeledContent {
                HStack {
                    HolzBarPicker("Apple Logo", selection: $configuration.style.appleLogoFill) {
                        Text("Bar Tint").tag(MenuBarAppleLogoFill.barTint)
                        Text("Accent Color").tag(MenuBarAppleLogoFill.accentColor)
                        Text("Follow Wallpaper").tag(MenuBarAppleLogoFill.wallpaper)
                        Text("Color").tag(MenuBarAppleLogoFill.color)
                    }
                    .labelsHidden()

                    if configuration.style.appleLogoFill == .color {
                        ColorPicker(
                            "Apple Logo",
                            selection: $configuration.appleLogoColor,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }
                .frame(height: 24)
            } label: {
                Text("Apple Logo")
            }
        }
    }

    @ViewBuilder
    private var shadowToggle: some View {
        Toggle("Shadow", isOn: $configuration.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: $configuration.hasBorder)
    }

    @ViewBuilder
    private var borderFill: some View {
        if configuration.hasBorder {
            LabeledContent {
                HStack {
                    HolzBarPicker("Border Fill", selection: $configuration.style.borderFill) {
                        Text("Color").tag(MenuBarBorderFill.color)
                        Text("Accent Color").tag(MenuBarBorderFill.accentColor)
                        Text("Gradient").tag(MenuBarBorderFill.gradient)
                    }
                    .labelsHidden()

                    if configuration.style.borderFill == .gradient {
                        HolzBarGradientPicker(
                            "Border Fill",
                            gradient: $configuration.borderGradient,
                            supportsOpacity: true
                        )
                        .labelsHidden()
                    }
                }
                .frame(height: 24)
            } label: {
                Text("Border Fill")
            }
        }
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder, configuration.style.borderFill == .color {
            ColorPicker(
                "Border Color",
                selection: $configuration.borderColor,
                supportsOpacity: true
            )
        }
    }

    @ViewBuilder
    private var borderWidth: some View {
        if configuration.hasBorder {
            HolzBarPicker(
                "Border Width",
                selection: $configuration.borderWidth
            ) {
                Text(verbatim: "1").tag(1.0)
                Text(verbatim: "2").tag(2.0)
                Text(verbatim: "3").tag(3.0)
            }
        }
    }

    @ViewBuilder
    private var borderStyle: some View {
        if configuration.hasBorder {
            HolzBarPicker("Border Style", selection: $configuration.borderStyle) {
                Text("Solid").tag(BorderStyle.solid)
                Text("Dashed").tag(BorderStyle.dashed)
                Text("Dotted").tag(BorderStyle.dotted)
            }
        }
    }
}

private struct LabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentAppearance = SystemAppearance.current
    @State private var textFrame = CGRect.zero

    let appearance: SystemAppearance

    var body: some View {
        HolzBarSection(options: .plain) {
            labelStack
        } content: {
            partialEditor
        }
        .onChange(of: colorScheme) {
            // The view's colour scheme follows the app's effective appearance.
            currentAppearance = .current
        }
    }

    @ViewBuilder
    private var labelStack: some View {
        HStack {
            Text(appearance.titleKey)
                .font(.headline)
                .onFrameChange(update: $textFrame)

            if currentAppearance != appearance {
                PreviewButton(appearance: appearance)
            }
        }
        .frame(height: textFrame.height)
    }

    @ViewBuilder
    private var partialEditor: some View {
        switch appearance {
        case .light:
            UnlabeledPartialEditor(
                configuration: $configuration.lightModeConfiguration,
                drawsShape: configuration.shapeKind.drawnKind != .noShape,
                drawsAppleLogo: configuration.appleLogoStyle == .capsule
            )
        case .dark:
            UnlabeledPartialEditor(
                configuration: $configuration.darkModeConfiguration,
                drawsShape: configuration.shapeKind.drawnKind != .noShape,
                drawsAppleLogo: configuration.appleLogoStyle == .capsule
            )
        }
    }
}

private struct StaticPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledPartialEditor(
            configuration: $configuration.staticConfiguration,
            drawsShape: configuration.shapeKind.drawnKind != .noShape,
            drawsAppleLogo: configuration.appleLogoStyle == .capsule
        )
    }
}

private struct PreviewButton: View {
    @Environment(AppState.self) private var appState
    @State private var isPressed = false

    let appearance: SystemAppearance

    private var manager: MenuBarAppearanceManager {
        appState.appearanceManager
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration {
        switch appearance {
        case .light:
            manager.configuration.lightModeConfiguration
        case .dark:
            manager.configuration.darkModeConfiguration
        }
    }

    var body: some View {
        Button("Hold to Preview") { }
            .buttonStyle(PreviewButtonStyle(isPressed: $isPressed))
            .onChange(of: isPressed) {
                manager.previewConfiguration = isPressed ? previewConfiguration : nil
            }
    }
}

private struct PreviewButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            AnyInsettableShape(Capsule(style: .continuous))
        } else {
            AnyInsettableShape(RoundedRectangle(cornerRadius: 6, style: .circular))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(configuration.isPressed ? 0.5 : 0.75)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
