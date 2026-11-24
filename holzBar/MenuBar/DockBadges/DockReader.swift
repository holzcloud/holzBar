//
//  DockReader.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import AppKit
import Foundation

/// Reads the applications the Dock lists, through public Accessibility attributes only.
///
/// The Dock's application element has a list among its children, and every application in the
/// Dock is an item of that list with the subrole `AXApplicationDockItem`. The reader copies the
/// role, subrole, title, URL and running state of those items and nothing else: no badge, no
/// window, no document. It runs off the main actor, one read at a time. Every call into the Dock
/// waits at most ``messagingTimeout`` seconds, and a read gives up after ``readDeadline``, so a
/// busy Dock cannot hold anything up for long. The names and bundle identifiers are returned as
/// values; the reader keeps none, logs none and writes none.
nonisolated enum DockReader {
    /// How a read ended.
    enum Result: Sendable {
        /// The applications in the Dock, in the Dock's order. Empty when the Dock lists none.
        case items([DockAppItem])
        /// The Dock is not running.
        case dockMissing
        /// The Dock did not answer in time, or its tree was not what the reader expects.
        case failed
    }

    /// The bundle identifier of the Dock.
    static let bundleIdentifier = "com.apple.dock"

    /// How long each call into the Dock waits for an answer, in seconds.
    private static let messagingTimeout: Float = 0.25

    /// How long a whole read may take, in nanoseconds.
    private static let readDeadline: UInt64 = 2_000_000_000

    /// The most items one read looks at, far above what a Dock holds.
    private static let maximumItems = 256

    /// Reads the applications in the Dock now.
    @concurrent
    static func applicationItems() async -> Result {
        read()
    }

    // MARK: Reading

    private static func read() -> Result {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return .dockMissing
        }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let deadline = DispatchTime.now().uptimeNanoseconds + readDeadline
        guard let children = elements(of: application, kAXChildrenAttribute) else {
            return .failed
        }
        guard let list = children.first(where: { string($0, kAXRoleAttribute) == kAXListRole }) else {
            return .failed
        }
        guard let entries = elements(of: list, kAXChildrenAttribute) else {
            return .failed
        }
        var bundleIdentifiers = [URL: String?]()
        var items = [DockAppItem]()
        for entry in entries.prefix(maximumItems) {
            guard !Task.isCancelled, DispatchTime.now().uptimeNanoseconds < deadline else {
                return .failed
            }
            guard string(entry, kAXSubroleAttribute) == kAXApplicationDockItemSubrole else {
                continue
            }
            guard let url = url(entry, kAXURLAttribute) else {
                continue
            }
            let bundleID: String?
            if let known = bundleIdentifiers[url] {
                bundleID = known
            } else {
                bundleID = Bundle(url: url)?.bundleIdentifier
                bundleIdentifiers[url] = bundleID
            }
            guard let bundleID else {
                continue
            }
            items.append(DockAppItem(
                bundleID: bundleID,
                name: string(entry, kAXTitleAttribute) ?? "",
                isRunning: bool(entry, kAXIsApplicationRunningAttribute) ?? false
            ))
        }
        return .items(items)
    }

    // MARK: Attributes

    /// The elements an attribute holds, or `nil` when the Dock did not answer.
    private static func elements(of element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func url(_ element: AXUIElement, _ attribute: String) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? URL
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }
}
