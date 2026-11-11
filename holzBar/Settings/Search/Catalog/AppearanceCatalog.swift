//
//  AppearanceCatalog.swift
//  holzBar
//

import Foundation

extension SettingsCatalog {
    /// The searchable settings of the Appearance pane, in the order the pane shows them. The two
    /// right-half end-cap rows repeat the labels "Leading end" and "Trailing end" and have no entry
    /// of their own: a hit on the left-half entry reveals that row, and the pair follows it.
    enum AppearancePane {
        static let moods = String(localized: "Moods")
        static let shape = String(localized: "Menu bar shape")
        static let lightAndDark = String(localized: "Light and dark")
        static let tint = String(localized: "Tint")
        static let shadowAndBorder = String(localized: "Shadow and border")
        static let notchAndScreen = String(localized: "Notch and screen")
        /// The last group has no header; the search lists its row under the pane's name.
        static let untitledGroup = String(localized: "Appearance")

        static let entries: [SettingsEntry] = [
            .appearanceSaveCurrentLook,
            .appearanceShapeKind,
            .appearanceLeadingEnd,
            .appearanceTrailingEnd,
            .appearanceInsetShape,
            .appearanceAppleLogoShape,
            .appearanceDynamic,
            .appearanceEditScope,
            .appearanceTint,
            .appearanceTintColor,
            .appearanceAccentColor,
            .appearanceTintGradient,
            .appearanceTintStrength,
            .appearanceGradientDirection,
            .appearanceGradientPerShape,
            .appearanceAppleLogoFill,
            .appearanceAppleLogoColor,
            .appearanceShadow,
            .appearanceBorder,
            .appearanceBorderFill,
            .appearanceBorderColor,
            .appearanceBorderGradient,
            .appearanceBorderWidth,
            .appearanceBorderStyle,
            .appearanceBlackMenuBar,
            .appearanceRoundCorners,
            .appearanceCornerRadius,
            .appearanceReset,
        ]
    }
}

extension SettingsEntry {
    // MARK: Moods

    static let appearanceSaveCurrentLook = SettingsEntry(
        id: "appearanceSaveCurrentLook",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.moods,
        label: String(localized: "Save Current Look…"),
        info: String(localized: "Save a look to switch back to it in one click, or from a rule.")
    )

    // MARK: Menu bar shape

    /// The info text is the Screen Recording reason before macOS 27 only, exactly when the row's
    /// popover shows it; the app's macOS does not change while it runs.
    static let appearanceShapeKind = SettingsEntry(
        id: "appearanceShapeKind",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shape,
        label: String(localized: "Shape"),
        info: {
            if #available(macOS 27.0, *) {
                nil
            } else {
                String(localized: "A menu bar shape draws the wallpaper beside the shape. holzBar reads most wallpapers from their file; a moving wallpaper can be read only with Screen Recording.")
            }
        }()
    )

    static let appearanceLeadingEnd = SettingsEntry(
        id: "appearanceLeadingEnd",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shape,
        label: String(localized: "Leading end"),
        info: String(localized: "With Paired and Sections, these two ends shape the left half of the menu bar, and the right half has two of its own.")
    )

    static let appearanceTrailingEnd = SettingsEntry(
        id: "appearanceTrailingEnd",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shape,
        label: String(localized: "Trailing end")
    )

    static let appearanceInsetShape = SettingsEntry(
        id: "appearanceInsetShape",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shape,
        label: String(localized: "Inset shape at the notch"),
        info: String(localized: "On a display with a notch, the shape is drawn a little smaller, with a margin to the edges of the menu bar.")
    )

    static let appearanceAppleLogoShape = SettingsEntry(
        id: "appearanceAppleLogoShape",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shape,
        label: String(localized: "Own shape for the Apple logo"),
        info: String(localized: "Works with every shape, and with none. Choose its fill with Apple logo in Tint.")
    )

    // MARK: Light and dark

    static let appearanceDynamic = SettingsEntry(
        id: "appearanceDynamic",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.lightAndDark,
        label: String(localized: "Dynamic appearance"),
        info: String(localized: "Apply different settings based on the current system appearance.")
    )

    static let appearanceEditScope = SettingsEntry(
        id: "appearanceEditScope",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.lightAndDark,
        label: String(localized: "Edit"),
        info: String(localized: "Hold to Preview shows the chosen appearance in the menu bar while it is not the current one. With the keyboard or VoiceOver, it turns the preview on and off.")
    )

    // MARK: Tint

    static let appearanceTint = SettingsEntry(
        id: "appearanceTint",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Tint"),
        info: String(localized: "Follow Wallpaper uses the main colors of your wallpaper, read from its file. With Reduce Transparency or Increase Contrast, System Glass is drawn opaque with a border.")
    )

    static let appearanceTintColor = SettingsEntry(
        id: "appearanceTintColor",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Color")
    )

    static let appearanceAccentColor = SettingsEntry(
        id: "appearanceAccentColor",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Use accent color"),
        info: String(localized: "Follows the accent color chosen in System Settings, Appearance.")
    )

    static let appearanceTintGradient = SettingsEntry(
        id: "appearanceTintGradient",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Gradient")
    )

    static let appearanceTintStrength = SettingsEntry(
        id: "appearanceTintStrength",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Tint strength")
    )

    static let appearanceGradientDirection = SettingsEntry(
        id: "appearanceGradientDirection",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Gradient direction")
    )

    static let appearanceGradientPerShape = SettingsEntry(
        id: "appearanceGradientPerShape",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "One gradient per shape"),
        info: String(localized: "Off: one gradient runs across the whole menu bar.")
    )

    static let appearanceAppleLogoFill = SettingsEntry(
        id: "appearanceAppleLogoFill",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Apple logo"),
        info: String(localized: "The fill of the Apple logo's own shape. Switch the shape on with Own shape for the Apple logo in Menu bar shape.")
    )

    static let appearanceAppleLogoColor = SettingsEntry(
        id: "appearanceAppleLogoColor",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.tint,
        label: String(localized: "Apple logo color")
    )

    // MARK: Shadow and border

    static let appearanceShadow = SettingsEntry(
        id: "appearanceShadow",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Shadow")
    )

    static let appearanceBorder = SettingsEntry(
        id: "appearanceBorder",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border")
    )

    static let appearanceBorderFill = SettingsEntry(
        id: "appearanceBorderFill",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border fill")
    )

    static let appearanceBorderColor = SettingsEntry(
        id: "appearanceBorderColor",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border color")
    )

    static let appearanceBorderGradient = SettingsEntry(
        id: "appearanceBorderGradient",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border gradient")
    )

    static let appearanceBorderWidth = SettingsEntry(
        id: "appearanceBorderWidth",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border width")
    )

    static let appearanceBorderStyle = SettingsEntry(
        id: "appearanceBorderStyle",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.shadowAndBorder,
        label: String(localized: "Border style")
    )

    // MARK: Notch and screen

    static let appearanceBlackMenuBar = SettingsEntry(
        id: "appearanceBlackMenuBar",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.notchAndScreen,
        label: String(localized: "Black menu bar"),
        info: String(localized: "Draws the menu bar solid black, so the notch blends into it. Works best in dark mode, where the menu bar text is light.")
    )

    static let appearanceRoundCorners = SettingsEntry(
        id: "appearanceRoundCorners",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.notchAndScreen,
        label: String(localized: "Round the screen corners"),
        info: String(localized: "Draws rounded corners on every display, like the corners of a MacBook display.")
    )

    static let appearanceCornerRadius = SettingsEntry(
        id: "appearanceCornerRadius",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.notchAndScreen,
        label: String(localized: "Corner radius")
    )

    // MARK: Reset

    static let appearanceReset = SettingsEntry(
        id: "appearanceReset",
        pane: .appearance,
        group: SettingsCatalog.AppearancePane.untitledGroup,
        label: String(localized: "Reset appearance"),
        info: String(localized: "Sets every appearance setting back to its default. Saved moods stay. This cannot be undone.")
    )
}
