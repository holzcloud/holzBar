//
//  SettingsBackup.swift
//  holzBar
//

import AppKit
import OSLog
import UniformTypeIdentifiers

/// Exports holzIce's settings to a file and imports them from one
/// (jordanbaird/Ice#326).
///
/// The file is a property list of the app's defaults domain, so it holds
/// everything: layout, hotkeys, appearance and the macOS 27 layout. Importing
/// replaces the current settings and relaunches the app, as every model reads
/// its settings once at launch.
@MainActor
enum SettingsBackup {
    private static let logger = Logger(category: "SettingsBackup")

    /// Keys that describe this Mac or a particular app's windows rather than
    /// the user's choices.
    static let excludedKeyPrefixes = [
        "NSWindow Frame",
        "NSStatusItem Preferred Position",
        "NSStatusItem Visible",
        "SU",
    ]

    /// The settings that are exported.
    static func currentSettings() -> [String: Any] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return [:]
        }
        let domain = UserDefaults.standard.persistentDomain(forName: bundleIdentifier) ?? [:]
        return domain.filter { key, _ in
            !excludedKeyPrefixes.contains { key.hasPrefix($0) }
        }
    }

    /// Replaces the current settings with the given ones.
    static func apply(_ settings: [String: Any]) {
        let defaults = UserDefaults.standard
        for (key, _) in currentSettings() where settings[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings where !excludedKeyPrefixes.contains(where: { key.hasPrefix($0) }) {
            defaults.set(value, forKey: key)
        }
        // Don't import the Ice settings again on the next launch.
        defaults.set(true, forKey: Defaults.Key.hasImportedIceSettings.rawValue)
    }

    /// Asks for a location and writes the settings there.
    static func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = "holzIce Settings.plist"
        panel.title = "Export holzIce Settings"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: currentSettings(), format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            logger.notice("Exported settings to \(url.path, privacy: .public)")
        } catch {
            show(error, message: "The settings could not be exported.")
        }
    }

    /// Asks for a settings file, applies it and relaunches the app.
    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.title = "Import holzIce Settings"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let data = try Data(contentsOf: url)
            guard let settings = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let alert = NSAlert()
            alert.messageText = "Replace your settings?"
            alert.informativeText = "holzIce will replace its current settings with the ones from “\(url.lastPathComponent)” and restart."
            alert.addButton(withTitle: "Import and Restart")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
            apply(settings)
            logger.notice("Imported settings from \(url.path, privacy: .public)")
            relaunch()
        } catch {
            show(error, message: "The settings could not be imported.")
        }
    }

    /// Starts a new instance of the app and quits this one.
    static func relaunch() {
        UserDefaults.standard.synchronize()
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func show(_ error: Error, message: String) {
        logger.error("\(message, privacy: .public) \(error, privacy: .public)")
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
