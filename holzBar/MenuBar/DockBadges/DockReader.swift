//
//  DockReader.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import AppKit
import Foundation

/// Reads the applications the Dock lists, through public Accessibility attributes only, and, when
/// asked, the badge of the chosen ones through ``DockBadgeBridge``.
///
/// The Dock's application element has a list among its children, and every application in the
/// Dock is an item of that list with the subrole `AXApplicationDockItem`. ``applicationItems()``
/// copies the role, subrole, title, URL and running state of those items and nothing else: no
/// badge, no window, no document. ``labels(of:readsLabels:)`` walks the same list and asks the
/// bridge for the badge of the items of the chosen apps only, and never touches the bridge when
/// it is told not to. It runs off the main actor, one read at a time. Every call into the Dock
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

    /// What one pass over the Dock's items found when it asked for badges.
    struct LabelPass: Sendable {
        /// What the gate decides from: whether the Dock was readable, whether an item lists the
        /// badge attribute and the answers for the chosen apps that are in the Dock.
        let pass: DockLabelGate.Pass
        /// The answer for each chosen app that is in the Dock, by bundle identifier. An app that
        /// is not in the Dock has none, which counts as no badge.
        let answers: [String: DockLabelAnswer]
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

    /// Reads the Dock's applications and, when `readsLabels` is true, the badge of the items of
    /// the chosen apps. With `readsLabels` false the bridge is never called, so a part that
    /// switched itself off reads nothing of the badge.
    ///
    /// - Parameters:
    ///   - chosen: The bundle identifiers of the apps whose badge is wanted.
    ///   - readsLabels: Whether the badge may be read at all.
    @concurrent
    static func labels(of chosen: Set<String>, readsLabels: Bool) async -> LabelPass {
        readLabels(of: chosen, readsLabels: readsLabels)
    }

    // MARK: Reading

    /// The Dock's application list: the entries and the time the walk must end by.
    private enum Listing {
        case entries([AXUIElement], deadline: UInt64)
        case dockMissing
        case failed
    }

    private static func listing() -> Listing {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return .dockMissing
        }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let deadline = DispatchTime.now().uptimeNanoseconds + readDeadline
        guard let children = elements(of: application, kAXChildrenAttribute),
            let list = children.first(where: { string($0, kAXRoleAttribute) == kAXListRole }),
            let entries = elements(of: list, kAXChildrenAttribute)
        else {
            return .failed
        }
        return .entries(entries, deadline: deadline)
    }

    /// The bundle identifier of an application item, or `nil` for any other entry.
    private static func appBundleIdentifier(
        of entry: AXUIElement,
        cache: inout [URL: String?]
    ) -> String? {
        guard string(entry, kAXSubroleAttribute) == kAXApplicationDockItemSubrole,
            let url = url(entry, kAXURLAttribute)
        else {
            return nil
        }
        if let known = cache[url] {
            return known
        }
        let bundleID = Bundle(url: url)?.bundleIdentifier
        cache[url] = bundleID
        return bundleID
    }

    private static func readLabels(of chosen: Set<String>, readsLabels: Bool) -> LabelPass {
        let unreadable = LabelPass(pass: DockLabelGate.Pass(dockReadable: false, listed: false, answers: []), answers: [:])
        guard case .entries(let entries, let deadline) = listing() else {
            return unreadable
        }
        guard readsLabels else {
            return LabelPass(pass: DockLabelGate.Pass(dockReadable: true, listed: false, answers: []), answers: [:])
        }
        var cache = [URL: String?]()
        var answers = [String: DockLabelAnswer]()
        var listed = false
        for entry in entries.prefix(maximumItems) {
            guard !Task.isCancelled, DispatchTime.now().uptimeNanoseconds < deadline else {
                return unreadable
            }
            guard let bundleID = appBundleIdentifier(of: entry, cache: &cache) else {
                continue
            }
            // The Dock may list the attribute only on an item that shows a badge, so every
            // application item is asked until one lists it, not only the first.
            if !listed {
                listed = DockBadgeBridge.listsLabel(entry)
            }
            if chosen.contains(bundleID), answers[bundleID] == nil {
                answers[bundleID] = DockBadgeBridge.label(of: entry)
            }
            // Every chosen app has its answer and the attribute was found listed: nothing later
            // in the Dock can change the pass, so no further bundle lookups are made. Stopping
            // before `listed` is true would lose the proof the start check takes from a later item.
            if listed, answers.count == chosen.count {
                break
            }
        }
        return LabelPass(
            pass: DockLabelGate.Pass(dockReadable: true, listed: listed, answers: Array(answers.values)),
            answers: answers
        )
    }

    private static func read() -> Result {
        switch listing() {
        case .dockMissing:
            return .dockMissing
        case .failed:
            return .failed
        case .entries(let entries, let deadline):
            return items(in: entries, deadline: deadline)
        }
    }

    private static func items(in entries: [AXUIElement], deadline: UInt64) -> Result {
        var cache = [URL: String?]()
        var items = [DockAppItem]()
        for entry in entries.prefix(maximumItems) {
            guard !Task.isCancelled, DispatchTime.now().uptimeNanoseconds < deadline else {
                return .failed
            }
            guard let bundleID = appBundleIdentifier(of: entry, cache: &cache) else {
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
