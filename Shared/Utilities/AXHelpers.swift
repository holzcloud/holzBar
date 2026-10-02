//
//  AXHelpers.swift
//  Shared
//

import ApplicationServices
import Cocoa

/// Accessibility calls for the app and the XPC service, made directly through the
/// `AXUIElement` C API.
///
/// Every value read from another process is checked for its type before it is converted,
/// and every failure gives `nil` (or an empty array, or `false`), never a crash.
enum AXHelpers {
    private static let queue = DispatchQueue.targetingGlobal(
        label: "AXHelpers.queue",
        qos: .userInteractive,
        attributes: .concurrent
    )

    /// The system-wide element, which finds the element at a point on screen.
    ///
    /// An `AXUIElement` is an immutable reference that can be used from any thread.
    private nonisolated(unsafe) static let systemWideElement = AXUIElementCreateSystemWide()

    /// The attribute that holds an element's frame, an `AXValue` of type `.cgRect`.
    private static let frameAttribute = "AXFrame"

    @discardableResult
    static func isProcessTrusted(prompt: Bool = false) -> Bool {
        queue.sync {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
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

    static func application(for runningApp: NSRunningApplication) -> AXUIElement? {
        queue.sync {
            guard !runningApp.isTerminated else {
                return nil
            }
            return AXUIElementCreateApplication(runningApp.processIdentifier)
        }
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

    /// Returns the menu bar that holds the application menus, found at the
    /// given point before macOS 27.
    ///
    /// On macOS 27 the element at a display's origin is MenuBarAgent's window,
    /// so the menu bar comes from the application that owns it. holzBar's own menus
    /// are skipped there: asking our own process from the main thread would wait
    /// for the main thread itself.
    static func applicationMenuBar(at point: CGPoint) -> AXUIElement? {
        if #available(macOS 27.0, *) {
            guard
                let owner = NSWorkspace.shared.menuBarOwningApplication,
                owner.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let app = application(for: owner)
            else {
                return nil
            }
            return queue.sync { Self.element(from: value(app, kAXMenuBarAttribute)) }
        }
        guard let element = element(at: point), role(for: element) == kAXMenuBarRole else {
            return nil
        }
        return element
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
