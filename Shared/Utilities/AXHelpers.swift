//
//  AXHelpers.swift
//  Shared
//

import ApplicationServices
import Cocoa

/// Accessibility calls for the app, made directly through the `AXUIElement` C API.
///
/// Every value read from another process is checked for its type before it is converted,
/// and every failure gives `nil` (or an empty array, or `false`), never a crash.
nonisolated enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// The system-wide element, which finds the element at a point on screen.
    ///
    /// An `AXUIElement` is an immutable reference that can be used from any thread,
    /// but the type is not marked `Sendable`, so the constant is declared unsafe.
    private nonisolated(unsafe) static let systemWideElement = AXUIElementCreateSystemWide()

    /// The attribute that holds an element's frame, an `AXValue` of type `.cgRect`.
    private static let frameAttribute = "AXFrame"

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync {
            // The value of `kAXTrustedCheckOptionPrompt`, a global variable that Swift 6
            // treats as shared mutable state.
            let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        queue.sync {
            var element: AXUIElement?
            guard
                AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element) == .success
            else {
                return nil
            }
            return element
        }
    }

    /// How long the reads of the application menu wait for an application to answer.
    ///
    /// The default timeout is 6 s. The application menu is read on every change of the
    /// frontmost application, and an application that hangs must not hold up the next read
    /// for that long.
    static let applicationMenuTimeout: Float = 0.25

    /// Returns the element of the given application.
    ///
    /// - Parameters:
    ///   - runningApp: The application.
    ///   - messagingTimeout: How long calls to the element wait for the application to
    ///     answer, or `nil` for the default timeout (6 s).
    static func application(for runningApp: NSRunningApplication, messagingTimeout: Float? = nil) -> AXUIElement? {
        queue.sync {
            guard !runningApp.isTerminated else {
                return nil
            }
            let element = AXUIElementCreateApplication(runningApp.processIdentifier)
            if let messagingTimeout {
                AXUIElementSetMessagingTimeout(element, messagingTimeout)
            }
            return element
        }
    }

    /// Sets how long calls to the given element wait for its application to answer.
    ///
    /// The timeout belongs to this element only, not to other elements of the same
    /// application. It is never set on the system-wide element: there it would become the
    /// timeout of every Accessibility call holzBar makes.
    static func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, timeout)
    }

    static func extrasMenuBar(for app: AXUIElement) -> AXUIElement? {
        queue.sync { Self.element(from: value(app, kAXExtrasMenuBarAttribute)) }
    }

    static func children(for element: AXUIElement) -> [AXUIElement] {
        queue.sync {
            guard
                let array = value(element, kAXChildrenAttribute),
                CFGetTypeID(array) == CFArrayGetTypeID(),
                let children = array as? [AnyObject]
            else {
                return []
            }
            return children.compactMap { Self.element(from: $0) }
        }
    }

    static func isEnabled(_ element: AXUIElement) -> Bool {
        queue.sync {
            guard
                let enabled = value(element, kAXEnabledAttribute),
                CFGetTypeID(enabled) == CFBooleanGetTypeID()
            else {
                return false
            }
            return CFBooleanGetValue(unsafeDowncast(enabled, to: CFBoolean.self))
        }
    }

    static func frame(for element: AXUIElement) -> CGRect? {
        queue.sync {
            guard
                let frameValue = axValue(from: value(element, frameAttribute)),
                AXValueGetType(frameValue) == .cgRect
            else {
                return nil
            }
            var frame = CGRect.zero
            guard AXValueGetValue(frameValue, .cgRect, &frame) else {
                return nil
            }
            return frame
        }
    }

    static func role(for element: AXUIElement) -> String? {
        queue.sync {
            guard
                let role = value(element, kAXRoleAttribute),
                CFGetTypeID(role) == CFStringGetTypeID()
            else {
                return nil
            }
            return role as? String
        }
    }

    /// Returns the menu bar that holds the application menus, found on the given display
    /// before macOS 27.
    ///
    /// Before macOS 27 the menu bar is the element at a point of the bar. The display's
    /// top-left pixel alone missed it on notched Macs and with Liquid Glass, so a click in
    /// the Shelf found no application menu and opened nothing (jordanbaird/Ice#911). After
    /// that pixel, points 8, 20 and 40 points right of the display's left edge, halfway
    /// down the bar, are tried in turn; a menu (the Apple menu) found there leads to its
    /// menu bar.
    ///
    /// On macOS 27 the element at a display's origin is MenuBarAgent's window,
    /// so the menu bar comes from the application that owns it. holzBar's own menus
    /// are skipped there: asking our own process from the main thread would wait
    /// for the main thread itself.
    ///
    /// The returned menu bar answers within ``applicationMenuTimeout``. This blocks, so it
    /// is called off the main thread only (see `ApplicationMenuQuery`).
    static func applicationMenuBar(in displayBounds: CGRect, menuBarHeight: CGFloat) -> AXUIElement? {
        if #available(macOS 27.0, *) {
            guard
                let owner = NSWorkspace.shared.menuBarOwningApplication,
                owner.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let app = application(for: owner, messagingTimeout: applicationMenuTimeout)
            else {
                return nil
            }
            guard let menuBar = queue.sync(execute: { Self.element(from: value(app, kAXMenuBarAttribute)) }) else {
                return nil
            }
            setMessagingTimeout(applicationMenuTimeout, for: menuBar)
            return menuBar
        }
        let points = [displayBounds.origin] + [8, 20, 40].map { (offset: CGFloat) in
            CGPoint(x: displayBounds.minX + offset, y: displayBounds.minY + menuBarHeight / 2)
        }
        for point in points {
            guard let element = element(at: point) else {
                continue
            }
            setMessagingTimeout(applicationMenuTimeout, for: element)
            switch role(for: element) {
            case kAXMenuBarRole:
                return element
            case kAXMenuBarItemRole:
                if let menuBar = parent(of: element), role(for: menuBar) == kAXMenuBarRole {
                    setMessagingTimeout(applicationMenuTimeout, for: menuBar)
                    return menuBar
                }
            default:
                break
            }
        }
        return nil
    }

    /// The parent of the given element, or `nil` when it has none.
    private static func parent(of element: AXUIElement) -> AXUIElement? {
        queue.sync { Self.element(from: value(element, kAXParentAttribute)) }
    }

    // MARK: Private

    /// The value of an attribute, or `nil` when it cannot be read.
    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// The value as an element, or `nil` when it is not one.
    private static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// The value as an `AXValue`, or `nil` when it is not one.
    private static func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
