//
//  SettingsBackup.swift
//  holzBar
//

import AppKit
import OSLog
import UniformTypeIdentifiers

/// Exports holzBar's settings to a file and imports them from one
/// (jordanbaird/Ice#326).
///
/// The file is a property list of holzBar's own settings (the `Defaults.Key` keys), so it
/// holds the layout, hotkeys, appearance and the macOS 27 layout, but no window frames or
/// other keys AppKit keeps in the defaults domain. Importing replaces the current settings
/// with the ones that are holzBar's and have the expected kind (``SettingsSchema``), and
/// relaunches the app, as every model reads its settings once at launch.
@MainActor
enum SettingsBackup {
    private static let logger = Logger(category: "SettingsBackup")

    /// Keys that describe this Mac or a particular app's windows rather than
    /// the user's choices.
    static let excludedKeyPrefixes = [
        "NSWindow Frame",
        "NSStatusItem Preferred Position",
        "NSStatusItem Visible",
        // The original Ice updated itself with Sparkle, whose keys start with "SU"; holzBar
        // updates through Homebrew, so they are neither exported nor imported from Ice.
        "SU",
        // This Mac's sync state (its sync id and the date of the last sync). A copied id
        // would make two Macs ignore each other's changes, so these keys are never
        // exported, imported, replaced or synced.
        "SettingsSync",
    ]

    /// Returns a Boolean value that indicates whether the key is never exported,
    /// imported, replaced or synced.
    private static func isExcluded(_ key: String) -> Bool {
        excludedKeyPrefixes.contains { key.hasPrefix($0) }
    }

    /// The settings that are exported and synced: holzBar's own keys only.
    static func currentSettings() -> [String: Any] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return [:]
        }
        let domain = UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]
        return domain.filter { key, _ in
            Defaults.Key.importableKinds[key] != nil && !isExcluded(key)
        }
    }

    /// Replaces the current settings with the given ones.
    ///
    /// Only holzBar's own keys with a value of the expected kind are applied; every other
    /// key is ignored, counted in the log and returned.
    ///
    /// - Parameter settings: The settings from a file or from iCloud Drive.
    /// - Returns: The keys that were ignored, sorted.
    @discardableResult
    static func apply(_ settings: [String: Any]) -> [String] {
        let defaults = UserDefaults.standard
        let incoming = settings.filter { key, _ in !isExcluded(key) }
        let (accepted, ignored) = SettingsSchema.validated(incoming, kinds: Defaults.Key.importableKinds)
        for (key, _) in currentSettings() where accepted[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in accepted {
            defaults.set(value, forKey: key)
        }
        // Don't import a previous app's settings again on the next launch.
        defaults.set(true, forKey: Defaults.Key.hasImportedPreviousSettings.rawValue)
        if !ignored.isEmpty {
            let names = ignored.joined(separator: ", ")
            logger.warning(
                "Ignored \(ignored.count, privacy: .public) settings that are not holzBar's or have an unexpected type: \(names, privacy: .private)"
            )
        }
        return ignored
    }

    /// Asks for a location and writes the settings there.
    static func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "holzBar Settings.plist"
        panel.title = String(localized: "Export holzBar Settings")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: currentSettings(), format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            logger.notice("Exported settings to \(url.path(percentEncoded: false), privacy: .private)")
        } catch {
            show(error, message: String(localized: "The settings could not be exported."))
        }
    }

    /// Asks for a settings file, applies it and relaunches the app.
    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "Import holzBar Settings")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            // Data(contentsOf:) would fetch an http(s) URL; holzBar reads only files.
            guard url.isFileURL else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let data = try Data(contentsOf: url)
            guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let alert = NSAlert()
            alert.messageText = String(localized: "Replace your settings?")
            alert.informativeText = String(localized: "holzBar will replace its current settings with the ones from “\(url.lastPathComponent)” and restart.")
            alert.addButton(withTitle: String(localized: "Import and Restart"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
            apply(settings)
            logger.notice("Imported settings from \(url.path(percentEncoded: false), privacy: .private)")
            relaunch()
        } catch {
            show(error, message: String(localized: "The settings could not be imported."))
        }
    }

    /// Starts a new instance of the app and quits this one.
    ///
    /// The new instance gets this one's process identifier (``Relaunch``) and waits until
    /// this one has quit before it sets up. When the new instance cannot be started, this one
    /// keeps running and says so.
    static func relaunch() {
        // The new instance reads the settings at once, so write them out first.
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        configuration.environment = Relaunch.environment(previousPID: ProcessInfo.processInfo.processIdentifier)

        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { @Sendable _, error in
            Task { @MainActor in
                if let error {
                    Self.show(error, message: String(localized: "holzBar could not restart itself. Quit holzBar and open it again."))
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func show(_ error: Error, message: String) {
        logger.error("\(message, privacy: .private) \(error, privacy: .private)")
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
