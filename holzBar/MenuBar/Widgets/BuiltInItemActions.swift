//
//  BuiltInItemActions.swift
//  holzBar
//

import AppKit
import OSLog
import UniformTypeIdentifiers

/// What a click on a built-in item does (``BuiltInItem``). Everything here uses public API and
/// asks for no permission of its own.
@MainActor
final class BuiltInItemActions {
    private let logger = Logger(category: "BuiltInItems")

    // MARK: Apple's own items

    /// Opens Apple's item for Focus, AirDrop or fast user switching when it is in the menu bar,
    /// hidden or not, through the one open path (a hidden item is pressed without being shown).
    /// When the Mac has no such item in the bar, the item falls back to what stands in for it:
    /// the System Settings pane, or Finder's AirDrop window.
    func openAppleItem(for item: BuiltInItem, in appState: AppState?) {
        if let manager = appState?.itemManager {
            let keys = manager.itemCache.managedItems.map { manager.identityKey(for: $0) }
            if let key = item.appleItemKey(in: keys) {
                manager.openItem(withIdentityKey: key)
                return
            }
        }
        if let url = item.settingsPaneURL {
            NSWorkspace.shared.open(url)
            return
        }
        if item == .airDrop, !openFinderAirDrop() {
            logger.notice("AirDrop has no window to open")
            NSSound.beep()
        }
    }

    /// Finder's AirDrop window, where the system still has it.
    private func openFinderAirDrop() -> Bool {
        let path = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
        return true
    }

    /// Offers the dropped files to AirDrop. The system shows its own picker; nothing is sent
    /// until the user chooses a person.
    func shareWithAirDrop(_ files: [URL]) {
        guard
            !files.isEmpty,
            let service = NSSharingService(named: .sendViaAirDrop),
            service.canPerform(withItems: files)
        else {
            NSSound.beep()
            return
        }
        service.perform(withItems: files)
    }

    // MARK: Media

    /// Presses and releases a media key. Whatever app answers the media keys on the keyboard
    /// answers this too.
    func press(_ key: MediaKey) {
        guard CGPreflightPostEventAccess() else {
            logger.notice("Posting a media key needs Accessibility")
            NSSound.beep()
            return
        }
        for isDown in [true, false] {
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: MediaKey.modifierBits(isDown: isDown)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: Int16(MediaKey.systemDefinedSubtype),
                data1: key.eventData(isDown: isDown),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Shows the menu of the media item: previous, play or pause, next.
    func showMediaMenu(from statusItem: NSStatusItem) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, key) in [
            (String(localized: "Previous"), MediaKey.previous),
            (String(localized: "Play or Pause"), MediaKey.playPause),
            (String(localized: "Next"), MediaKey.next),
        ] {
            let entry = NSMenuItem(title: title, action: #selector(MediaMenuTarget.pressed(_:)), keyEquivalent: "")
            let target = MediaMenuTarget { [weak self] in
                self?.press(key)
            }
            entry.target = target
            // The menu holds its items, and an item holds its target weakly.
            entry.representedObject = target
            menu.addItem(entry)
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private final class MediaMenuTarget: NSObject {
        let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func pressed(_ sender: NSMenuItem) {
            action()
        }
    }

    // MARK: Launchers

    /// The application with the given bundle identifier, if it is installed.
    static func applicationURL(forBundleID bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The name of the application as the Finder shows it, or `nil` when it is not installed.
    static func applicationName(forBundleID bundleID: String) -> String? {
        applicationURL(forBundleID: bundleID).map {
            FileManager.default.displayName(atPath: $0.path(percentEncoded: false))
        }
    }

    /// The icon of the application at the height of a menu bar item, or `nil` when it is not
    /// installed.
    static func applicationIcon(forBundleID bundleID: String) -> NSImage? {
        guard let url = applicationURL(forBundleID: bundleID) else {
            return nil
        }
        return ItemIconStore.sizedForMenuBar(NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
    }

    /// The bundle identifier of the application at a URL, if it is an application bundle.
    static func bundleID(ofApplicationAt url: URL) -> String? {
        guard
            let bundle = Bundle(url: url),
            let identifier = bundle.bundleIdentifier,
            SharedProfile.isValidBundleIdentifier(identifier)
        else {
            return nil
        }
        return identifier
    }

    /// Asks the user for an application with the open panel.
    ///
    /// - Returns: Its bundle identifier, or `nil` when the panel was cancelled or the choice has
    ///   no bundle identifier.
    static func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.message = String(localized: "Choose the app this icon opens.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return bundleID(ofApplicationAt: url)
    }

    /// Opens the application and brings it forward.
    ///
    /// - Returns: `false` when it is not installed.
    @discardableResult
    func openApplication(withBundleID bundleID: String) -> Bool {
        guard let url = Self.applicationURL(forBundleID: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        return true
    }
}

/// The view over an AirDrop item that takes the files dropped on it. A click still opens
/// AirDrop; ⌘-clicks are left to the menu bar, which moves the item.
final class AirDropDropView: NSView {
    var onClick: (() -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.mouseDown(with: event)
        } else {
            onClick?()
        }
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        files(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let dropped = files(in: sender)
        guard !dropped.isEmpty else {
            return false
        }
        onDrop?(dropped)
        return true
    }

    private func files(in sender: any NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }
}
