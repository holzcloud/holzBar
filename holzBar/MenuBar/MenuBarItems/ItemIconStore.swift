//
//  ItemIconStore.swift
//  holzBar
//

import AppKit
import ImageIO
import Observation
import OSLog
import UniformTypeIdentifiers

/// Images of the user's choice for menu bar items, and the app icon as the fallback when
/// there is no picture of an item (THAW-16, jordanbaird/Ice#912, Thaw #1087).
///
/// The choices are stored by item identity in the `ItemIcons` setting; the images themselves
/// stay on this Mac, in Application Support/holzBar/ItemIcons.
/// A chosen file is read once from the open panel, scaled off the main thread to at most
/// 64 points high at 2x and stored as a PNG with a new name. A choice whose file is missing
/// falls back to the next one (``ItemIconChoice``).
@MainActor
@Observable
final class ItemIconStore {
    /// The stored choices, by item identity key.
    private(set) var choices = [String: String]()

    /// The images read from the folder, by file name.
    @ObservationIgnored private var loadedImages = [String: NSImage]()

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    private let logger = Logger(category: "ItemIconStore")

    /// The height the chosen images and app icons are drawn at, like a menu bar item.
    static let drawnHeight: CGFloat = 18

    /// The folder of the chosen images.
    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: "ItemIcons", directoryHint: .isDirectory)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        choices = Defaults.dictionary(forKey: .itemIcons) as? [String: String] ?? [:]
    }

    // MARK: Choices

    /// The stored key of the given item's choice, if it has one.
    private func storedKey(for item: MenuBarItem) -> String? {
        guard let itemManager = appState?.itemManager else {
            return nil
        }
        let key = itemManager.identityKey(for: item)
        if choices[key] != nil {
            return key
        }
        return choices.keys.first { itemManager.storedIdentityKey($0) == key }
    }

    /// The user's choice for the item.
    func choice(for item: MenuBarItem) -> ItemIconChoice.Stored? {
        storedKey(for: item).flatMap { ItemIconChoice.parse(choices[$0]) }
    }

    /// Stores a choice for the item, or removes it (`nil`), and deletes an image file the
    /// item no longer uses.
    private func setChoice(_ stored: ItemIconChoice.Stored?, for item: MenuBarItem) {
        guard let itemManager = appState?.itemManager else {
            return
        }
        let previous = choice(for: item)
        if let key = storedKey(for: item) {
            choices[key] = nil
        }
        if let stored {
            choices[itemManager.identityKey(for: item)] = ItemIconChoice.storedValue(stored)
        }
        Defaults.set(choices, forKey: .itemIcons)
        if case .file(let name) = previous, previous != stored {
            deleteFile(named: name)
        }
    }

    /// Shows the item's app icon instead of its picture.
    func useAppIcon(for item: MenuBarItem) {
        setChoice(.appIcon, for: item)
    }

    /// Goes back to the item's own picture.
    func reset(for item: MenuBarItem) {
        setChoice(nil, for: item)
    }

    /// Lets the user choose an image file for the item.
    func chooseImage(for item: MenuBarItem) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose an image for \u{201C}\(item.displayName)\u{201D}.")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task {
            guard let name = await storeImage(from: url) else {
                NSSound.beep()
                return
            }
            setChoice(.file(name), for: item)
        }
    }

    /// Reads, scales and stores the image at the URL, and returns its new file name.
    func storeImage(from url: URL) async -> String? {
        // Decoding and scaling run off the main actor.
        let data = await Self.scaledPNG(from: url)
        guard let data, let folder = Self.folder else {
            logger.error("Could not read the chosen image")
            return nil
        }
        let name = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appending(path: name), options: .atomic)
            return name
        } catch {
            logger.error("Could not store the chosen image: \(error, privacy: .private)")
            return nil
        }
    }

    /// The image scaled to at most 128 pixels high (64 points at 2x) as PNG data.
    ///
    /// `@concurrent` runs it on the concurrent pool, whoever awaits it.
    @concurrent
    private nonisolated static func scaledPNG(from url: URL) async -> Data? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double,
            width > 0,
            height > 0
        else {
            return nil
        }
        // At most 128 pixels high; a wide image may be up to four times as wide.
        let maxPixelSize = min(max(128, 128 * width / height), 512)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    /// Deletes an image file, unless a group or another item still uses it.
    func deleteFile(named name: String) {
        guard ItemIconChoice.isValidFileName(name), let folder = Self.folder else {
            return
        }
        let isUsed = choices.values.contains { ItemIconChoice.parse($0) == .file(name) }
            || (appState?.itemGroups.groups.contains { $0.imageFile == name } ?? false)
        guard !isUsed else {
            return
        }
        loadedImages[name] = nil
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    // MARK: Images

    /// The image stored under the given file name, read once.
    func storedImage(named name: String) -> NSImage? {
        if let image = loadedImages[name] {
            return image
        }
        guard
            ItemIconChoice.isValidFileName(name),
            let folder = Self.folder,
            let image = NSImage(contentsOf: folder.appending(path: name))
        else {
            return nil
        }
        loadedImages[name] = image
        return image
    }

    /// The icon of the item's app.
    func appIcon(for item: MenuBarItem) -> NSImage? {
        guard let application = item.sourceApplication else {
            return nil
        }
        if let icon = application.icon {
            return icon
        }
        return application.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
    }

    /// What the item shows, in the order of ``ItemIconChoice``: its chosen image, its
    /// picture, its app's icon, or `nil` for its name.
    ///
    /// - Parameter captured: The item's picture, if the caller has one; by default the one
    ///   in the image cache.
    func image(for item: MenuBarItem, captured: NSImage? = nil) -> NSImage? {
        let captured = captured ?? appState?.imageCache.images[item.tag]?.nsImage
        let stored = choice(for: item)
        var custom: NSImage?
        if case .file(let name) = stored {
            custom = storedImage(named: name)
        }
        let source = ItemIconChoice.source(
            stored: stored,
            hasCustomImage: custom != nil,
            hasCapture: captured != nil,
            hasAppIcon: item.sourceApplication != nil
        )
        switch source {
        case .custom:
            return custom.map(Self.sizedForMenuBar)
        case .captured:
            return captured
        case .appIcon:
            return appIcon(for: item).map(Self.sizedForMenuBar)
        case .name:
            return nil
        }
    }

    /// A copy of the image drawn at the height of a menu bar item.
    static func sizedForMenuBar(_ image: NSImage) -> NSImage {
        guard image.size.height > 0, let copy = image.copy() as? NSImage else {
            return image
        }
        let scale = drawnHeight / image.size.height
        copy.size = CGSize(width: (image.size.width * scale).rounded(), height: drawnHeight)
        return copy
    }
}
