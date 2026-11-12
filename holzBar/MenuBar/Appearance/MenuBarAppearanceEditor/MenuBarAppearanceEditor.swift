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
    @Environment(\.colorScheme) private var colorScheme
    @State private var isResetPromptPresented = false
    /// The appearance Tint and Shadow and border edit while Dynamic appearance is on. View state,
    /// not stored (D-13).
    @State private var editedAppearance = SystemAppearance.current
    @State private var currentAppearance = SystemAppearance.current

    let location: Location

    /// Only the groups: the host (the Settings pane or the panel) draws the scroll view, the margins
    /// and the ground.
    @ViewBuilder
    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            AutoHiddenMenuBarState(kind: .appearance)
        } else {
            MoodsSection(appearanceManager: appearanceManager, place: location == .settings ? .settings : .appearanceEditor)
            shapeGroup
            dynamicGroup
            partialEditor
            notchAndScreenGroup
            resetGroup
        }
    }

    /// The partial configuration Tint and Shadow and border edit: the static one, or the Light or
    /// Dark one the scope chooses.
    private var editedPartial: Binding<MenuBarAppearancePartialConfiguration> {
        guard appearanceManager.configuration.isDynamic else {
            return $appearanceManager.configuration.staticConfiguration
        }
        switch editedAppearance {
        case .light:
            return $appearanceManager.configuration.lightModeConfiguration
        case .dark:
            return $appearanceManager.configuration.darkModeConfiguration
        }
    }

    private var partialEditor: some View {
        AppearancePartialEditor(
            configuration: editedPartial,
            drawsShape: appearanceManager.configuration.shapeKind.drawnKind != .noShape,
            drawsAppleLogo: appearanceManager.configuration.appleLogoStyle == .capsule
        )
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
        SettingsGroup(
            SettingsCatalog.AppearancePane.lightAndDark,
            footnote: Text("With Dynamic appearance on, Tint and Shadow and border apply to the appearance chosen in Edit.")
        ) {
            SettingsToggleRow(.appearanceDynamic, isOn: $appearanceManager.configuration.isDynamic)
            // The generic slot, not SettingsSegmentedRow: Hold to Preview sits beside the scope.
            SettingsRow(.appearanceEditScope) {
                HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                    if appearanceManager.configuration.isDynamic, editedAppearance != currentAppearance {
                        PreviewButton(appearance: editedAppearance)
                    }
                    Picker(selection: $editedAppearance) {
                        Text("Light").tag(SystemAppearance.light)
                        Text("Dark").tag(SystemAppearance.dark)
                    } label: {
                        Text(verbatim: SettingsEntry.appearanceEditScope.label)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .settingsSubRow()
            .settingsDependent(on: appearanceManager.configuration.isDynamic)
        }
        .onChange(of: colorScheme) {
            // The view's colour scheme follows the app's effective appearance.
            currentAppearance = .current
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

/// Tint, and Shadow and border, of one appearance: the static one, or the Light or Dark one the
/// scope chooses (D-33). Rows that apply to one value of a pop-up are built only while it is
/// chosen (D-71); rows that depend on a switch stay and dim (D-17).
private struct AppearancePartialEditor: View {
    @Binding var configuration: MenuBarAppearancePartialConfiguration

    /// Whether the bar draws a shape (Single, Paired or Sections), so a gradient can run over
    /// each shape.
    let drawsShape: Bool
    /// Whether the Apple menu has a capsule of its own, so its fill can be chosen.
    let drawsAppleLogo: Bool

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

    private var gradientPerShape: Binding<Bool> {
        Binding(
            get: { configuration.style.gradientSpan == .eachShape },
            set: { configuration.style.gradientSpan = $0 ? .eachShape : .acrossBar }
        )
    }

    var body: some View {
        tintGroup
        shadowAndBorderGroup
    }

    private var tintGroup: some View {
        SettingsGroup(SettingsCatalog.AppearancePane.tint) {
            SettingsPickerRow(.appearanceTint, selection: $configuration.tintKind) {
                // System Glass needs macOS 26; an older system shows no tint for it.
                ForEach(MenuBarTintKind.allCases.filter(\.isAvailable)) { tintKind in
                    Text(tintKind.localized).tag(tintKind)
                }
            }
            if configuration.tintKind == .solid {
                SettingsColorRow(.appearanceTintColor, color: $configuration.tintColor)
                    .settingsSubRow()
                    .settingsDependent(on: !configuration.tintFollowsAccentColor)
                SettingsToggleRow(.appearanceAccentColor, isOn: $configuration.tintFollowsAccentColor)
                    .settingsSubRow()
            }
            if configuration.tintKind == .gradient {
                SettingsGradientRow(.appearanceTintGradient, gradient: $configuration.tintGradient)
                    .settingsSubRow()
            }
            if tintHasStrength {
                SettingsSliderRow(
                    .appearanceTintStrength,
                    value: $configuration.style.tintStrength,
                    in: MenuBarPartialStyle.tintStrengthRange,
                    step: 0.05
                ) { strength in
                    Text(strength, format: .percent.precision(.fractionLength(0)))
                }
                .settingsSubRow()
            }
            if tintHasDirection {
                SettingsPickerRow(
                    .appearanceGradientDirection,
                    selection: $configuration.style.gradientDirection
                ) {
                    Text("Horizontal").tag(MenuBarGradientDirection.horizontal)
                    Text("Vertical").tag(MenuBarGradientDirection.vertical)
                }
                .settingsSubRow()
                if drawsShape {
                    SettingsToggleRow(.appearanceGradientPerShape, isOn: gradientPerShape)
                        .settingsSubRow()
                }
            }
            SettingsPickerRow(.appearanceAppleLogoFill, selection: $configuration.style.appleLogoFill) {
                Text("Bar Tint").tag(MenuBarAppleLogoFill.barTint)
                Text("Accent Color").tag(MenuBarAppleLogoFill.accentColor)
                Text("Follow Wallpaper").tag(MenuBarAppleLogoFill.wallpaper)
                Text("Color").tag(MenuBarAppleLogoFill.color)
            }
            .settingsDependent(on: drawsAppleLogo)
            if configuration.style.appleLogoFill == .color {
                SettingsColorRow(.appearanceAppleLogoColor, color: $configuration.appleLogoColor)
                    .settingsSubRow()
                    .settingsDependent(on: drawsAppleLogo)
            }
        }
    }

    private var shadowAndBorderGroup: some View {
        SettingsGroup(SettingsCatalog.AppearancePane.shadowAndBorder) {
            SettingsToggleRow(.appearanceShadow, isOn: $configuration.hasShadow)
            SettingsToggleRow(.appearanceBorder, isOn: $configuration.hasBorder)
            SettingsPickerRow(.appearanceBorderFill, selection: $configuration.style.borderFill) {
                Text("Color").tag(MenuBarBorderFill.color)
                Text("Accent Color").tag(MenuBarBorderFill.accentColor)
                Text("Gradient").tag(MenuBarBorderFill.gradient)
            }
            .settingsSubRow()
            .settingsDependent(on: configuration.hasBorder)
            if configuration.style.borderFill == .color {
                SettingsColorRow(
                    .appearanceBorderColor,
                    color: $configuration.borderColor,
                    supportsOpacity: true
                )
                .settingsSubRow()
                .settingsDependent(on: configuration.hasBorder)
            }
            if configuration.style.borderFill == .gradient {
                SettingsGradientRow(
                    .appearanceBorderGradient,
                    gradient: $configuration.borderGradient,
                    supportsOpacity: true
                )
                .settingsSubRow()
                .settingsDependent(on: configuration.hasBorder)
            }
            SettingsPickerRow(.appearanceBorderWidth, selection: $configuration.borderWidth) {
                ForEach([1.0, 2.0, 3.0], id: \.self) { width in
                    Text("\(Int(width)) pt").tag(width)
                }
            }
            .settingsSubRow()
            .settingsDependent(on: configuration.hasBorder)
            SettingsPickerRow(.appearanceBorderStyle, selection: $configuration.borderStyle) {
                Text("Solid").tag(BorderStyle.solid)
                Text("Dashed").tag(BorderStyle.dashed)
                Text("Dotted").tag(BorderStyle.dotted)
            }
            .settingsSubRow()
            .settingsDependent(on: configuration.hasBorder)
        }
    }
}

/// Previews the chosen appearance in the menu bar (D-56). A pointer press holds the preview while
/// it lasts; Space on the focused button and the VoiceOver press turn it on and off.
private struct PreviewButton: View {
    @Environment(AppState.self) private var appState
    /// The press state the style reports, from the pointer or from a key.
    @State private var isHeld = false
    @State private var isLatched = false

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

    /// What the menu bar shows now: the edited appearance while held or turned on, so edits made
    /// during a preview show at once.
    private var effectivePreview: MenuBarAppearancePartialConfiguration? {
        isHeld || isLatched ? previewConfiguration : nil
    }

    var body: some View {
        Button("Hold to Preview") {
            // A pointer press is the hold and never latches; Space and VoiceOver latch.
            switch NSApp.currentEvent?.type {
            case .leftMouseDown, .leftMouseUp:
                break
            default:
                isLatched.toggle()
            }
        }
        .buttonStyle(PreviewButtonStyle(isPressed: $isHeld, isOn: isLatched))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isLatched ? Text("On") : Text("Off"))
        .onChange(of: effectivePreview) {
            manager.previewConfiguration = effectivePreview
        }
        .onChange(of: manager.previewConfiguration) {
            // The panel clears the preview when it hides.
            if manager.previewConfiguration == nil {
                isLatched = false
            }
        }
        .onDisappear {
            isLatched = false
            isHeld = false
            manager.previewConfiguration = nil
        }
    }
}

private struct PreviewButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    let isOn: Bool

    private var borderShape: some InsettableShape {
        if #available(macOS 26.0, *) {
            AnyInsettableShape(Capsule(style: .continuous))
        } else {
            AnyInsettableShape(HolzBarTheme.shape(HolzBarTheme.Radius.control))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let isActive = configuration.isPressed || isOn
        return configuration.label
            .padding(.horizontal, HolzBarTheme.Spacing.xs)
            .padding(.vertical, HolzBarTheme.SettingsKit.rowPaddingVertical)
            .background {
                borderShape
                    .fill(isActive ? .tertiary : .quaternary)
                    .opacity(isActive ? 0.5 : 0.75)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}
