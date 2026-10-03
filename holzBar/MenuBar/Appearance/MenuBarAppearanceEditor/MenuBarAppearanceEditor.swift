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
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isResetPromptPresented = false

    let location: Location

    var body: some View {
        if #available(macOS 26.0, *) {
            bodyContent
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        } else {
            VStack(spacing: 0) {
                bodyContent
                bottomBar
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotEdit
        } else if #available(macOS 26.0, *) {
            mainForm
                .scrollEdgeEffectStyle(.hard, for: .vertical)
        } else {
            mainForm
        }
    }

    @ViewBuilder
    private var cannotEdit: some View {
        Text("holzBar cannot edit the appearance of automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var mainForm: some View {
        HolzBarForm {
            if
                case .settings = location,
                appState.settings.advanced.enableSecondaryContextMenu
            {
                CalloutBox(
                    "Tip: You can also edit these settings by right-clicking in an empty area of the menu bar.",
                    systemImage: "lightbulb"
                )
            }
            HolzBarSection {
                isDynamicToggle
            }
            if appearanceManager.configuration.isDynamic {
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .light)
                LabeledPartialEditor(configuration: $appearanceManager.configuration, appearance: .dark)
            } else {
                StaticPartialEditor(configuration: $appearanceManager.configuration)
            }
            HolzBarSection("Menu Bar Shape") {
                shapePicker
                isInset
                shapeScreenRecordingHint
            }
            HolzBarSection("Notch and Screen") {
                blackBackgroundPicker
                screenCorners
            }
        }
    }

    @ViewBuilder
    private var blackBackgroundPicker: some View {
        HolzBarPicker("Black menu bar", selection: $appearanceManager.configuration.blackBackground) {
            ForEach(MenuBarBlackBackground.allCases) { option in
                Text(option.localized).tag(option)
            }
        }
        .annotation("Draws the menu bar solid black, so the notch blends into it. Works best in dark mode, where the menu bar text is light.")
    }

    @ViewBuilder
    private var screenCorners: some View {
        Toggle("Round the screen corners", isOn: $appearanceManager.configuration.roundsScreenCorners)
            .annotation("Draws rounded corners on every display, like the corners of a MacBook display.")
        if appearanceManager.configuration.roundsScreenCorners {
            LabeledContent {
                Slider(value: $appearanceManager.configuration.screenCornerRadius, in: 4...24, step: 1)
                    .frame(maxWidth: 200)
            } label: {
                Text("Corner radius: \(Int(appearanceManager.configuration.screenCornerRadius)) pt")
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            if case .panel = location {
                Button("Done") {
                    dismissWindow()
                }
            }

            Spacer()

            if
                !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults,
                appearanceManager.configuration != .defaultConfiguration
            {
                Button("Reset") {
                    isResetPromptPresented = true
                }
                .alert("Reset Menu Bar Appearance", isPresented: $isResetPromptPresented) {
                    Button("Cancel", role: .cancel) {
                        isResetPromptPresented = false
                    }
                    Button("Reset", role: .destructive) {
                        appearanceManager.configuration = .defaultConfiguration
                        isResetPromptPresented = false
                    }
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
        .buttonBorderShape(.capsule)
        .padding(10)
    }

    @ViewBuilder
    private var isDynamicToggle: some View {
        Toggle("Use dynamic appearance", isOn: $appearanceManager.configuration.isDynamic)
            .annotation("Apply different settings based on the current system appearance.")
    }

    @ViewBuilder
    private var shapePicker: some View {
        MenuBarShapePicker(configuration: $appearanceManager.configuration)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Whether holzBar runs on macOS 27.
    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            true
        } else {
            false
        }
    }

    /// Asks for Screen Recording when a shape is chosen without it and the wallpaper
    /// beside it cannot be read from its file (a moving wallpaper). Before macOS 27 only:
    /// on macOS 27 holzBar never captures the wallpaper.
    @ViewBuilder
    private var shapeScreenRecordingHint: some View {
        if
            !isMacOS27,
            appearanceManager.configuration.shapeKind != .noShape,
            !ScreenRecordingAccess.isGranted(appState),
            !(NSScreen.main.map(DesktopPicture.isReadable(on:)) ?? false)
        {
            ScreenRecordingHint(feature: .menuBarShape, appState: appState)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var isInset: some View {
        if appearanceManager.configuration.shapeKind != .noShape {
            Toggle(
                "Use inset shape on screens with notch",
                isOn: $appearanceManager.configuration.isInset
            )
        }
    }
}

private struct UnlabeledPartialEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    var body: some View {
        HolzBarSection {
            tintPicker
            shadowToggle
        }
        HolzBarSection {
            borderToggle
            borderColor
            borderWidth
        }
    }

    @ViewBuilder
    private var tintPicker: some View {
        LabeledContent("Tint") {
            HStack {
                HolzBarPicker("Tint", selection: $configuration.tintKind) {
                    ForEach(MenuBarTintKind.allCases) { tintKind in
                        Text(tintKind.localized).tag(tintKind)
                    }
                }
                .labelsHidden()

                switch configuration.tintKind {
                case .noTint:
                    EmptyView()
                case .solid:
                    ColorPicker(
                        configuration.tintKind.localized,
                        selection: $configuration.tintColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
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
    private var shadowToggle: some View {
        Toggle("Shadow", isOn: $configuration.hasShadow)
    }

    @ViewBuilder
    private var borderToggle: some View {
        Toggle("Border", isOn: $configuration.hasBorder)
    }

    @ViewBuilder
    private var borderColor: some View {
        if configuration.hasBorder {
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
                Text("1").tag(1.0)
                Text("2").tag(2.0)
                Text("3").tag(3.0)
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
            UnlabeledPartialEditor(configuration: $configuration.lightModeConfiguration)
        case .dark:
            UnlabeledPartialEditor(configuration: $configuration.darkModeConfiguration)
        }
    }
}

private struct StaticPartialEditor: View {
    @Binding var configuration: MenuBarAppearanceConfigurationV2

    var body: some View {
        UnlabeledPartialEditor(configuration: $configuration.staticConfiguration)
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
