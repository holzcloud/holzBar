//
//  Migration.swift
//  holzBar
//

import Cocoa
import OSLog

/// Takes over the settings of the original Ice.
@MainActor
enum MigrationManager {
    /// The bundle identifier of the original Ice, which names its defaults domain.
    private static let iceBundleIdentifier = "com.jordanbaird.Ice"

    /// The logger for the import.
    private static let logger = Logger(category: "Migration")

    /// Takes over the settings of the original Ice, once.
    ///
    /// holzBar has a bundle identifier of its own, so it starts out with empty
    /// defaults. Without this, a user switching from Ice would lose their
    /// layout, hotkeys and appearance. Only the settings are imported, no
    /// files. It must run before anything reads the defaults, so the app
    /// delegate calls it before it creates the app state.
    ///
    /// Settings of any Ice version are brought into the current schema while they are
    /// imported (``LegacySettingsMigration``), so nothing migrates at launch.
    static func importPreviousSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        let flag = Defaults.Key.hasImportedPreviousSettings.rawValue
        guard !defaults.bool(forKey: flag) else {
            return
        }
        let ownSettings = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        defaults.set(true, forKey: flag)
        guard
            ownSettings.isEmpty,
            let settings = defaults.persistentDomain(forName: iceBundleIdentifier),
            !settings.isEmpty
        else {
            return
        }
        // Window frames and status item positions belong to Ice's own windows
        // and items, not to holzBar's. The first launch after importing them
        // locked up a Mac on macOS 27 until it was restarted; the next launch
        // was fine.
        let candidates = settings.filter { key, _ in
            !SettingsBackup.excludedKeyPrefixes.contains { key.hasPrefix($0) }
        }
        // Only the settings holzBar stores, with the kind of value it expects, are taken
        // over; anything else in Ice's domain stays there.
        let accepted = SettingsSchema.validated(candidates, kinds: Defaults.Key.importableKinds).accepted

        var migrated = LegacySettingsMigration.migrate(accepted)
        if LegacySettingsMigration.needsAppearanceConversion(accepted) {
            convertAppearance(in: &migrated)
        }
        // Ice 0.11.13 removed the old appearance once it was converted.
        migrated.removeValue(forKey: LegacySettingsMigration.appearanceV1Key)

        // The migration writes only holzBar's own keys; checked again all the same.
        let imported = SettingsSchema.validated(migrated, kinds: Defaults.Key.importableKinds).accepted
        for (key, value) in imported {
            defaults.set(value, forKey: key)
        }
        logger.notice(
            "Imported \(imported.count, privacy: .public) of \(settings.count, privacy: .public) settings from Ice"
        )
    }

    /// Converts the menu bar appearance of Ice before 0.11.10 into the current
    /// configuration (what Ice 0.11.10 did at launch).
    ///
    /// The appearance is the same in light and dark mode, as it was then. Data that
    /// cannot be read leaves the default appearance.
    private static func convertAppearance(in settings: inout [String: Any]) {
        guard let oldData = settings[LegacySettingsMigration.appearanceV1Key] as? Data else {
            return
        }
        do {
            let oldConfiguration = try JSONDecoder().decode(MenuBarAppearanceConfigurationV1.self, from: oldData)
            let newConfiguration = withMutableCopy(of: MenuBarAppearanceConfigurationV2.defaultConfiguration) { configuration in
                let partialConfiguration = MenuBarAppearancePartialConfiguration(
                    hasShadow: oldConfiguration.hasShadow,
                    hasBorder: oldConfiguration.hasBorder,
                    borderColor: oldConfiguration.borderColor,
                    borderWidth: oldConfiguration.borderWidth,
                    tintKind: oldConfiguration.tintKind,
                    tintColor: oldConfiguration.tintColor,
                    tintGradient: oldConfiguration.tintGradient
                )
                configuration.lightModeConfiguration = partialConfiguration
                configuration.darkModeConfiguration = partialConfiguration
                configuration.staticConfiguration = partialConfiguration
                configuration.shapeKind = oldConfiguration.shapeKind
                configuration.fullShapeInfo = oldConfiguration.fullShapeInfo
                configuration.splitShapeInfo = oldConfiguration.splitShapeInfo
                configuration.isInset = oldConfiguration.isInset
            }
            settings[Defaults.Key.menuBarAppearanceConfigurationV2.rawValue] = try JSONEncoder().encode(newConfiguration)
        } catch {
            logger.error("Could not convert the old menu bar appearance: \(error, privacy: .private)")
        }
    }
}
