//
//  DockBadgeBridge.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import Foundation

/// The one file of the app that names the Dock's undocumented badge attribute.
///
/// This is the single wrapper of the named exception "Dock badges, Read badge counts" under
/// "Private API in modules" in `CLAUDE.md` (decision of 2026-11-24). macOS has no public API for
/// the badge another app shows on its Dock icon. The Dock exposes it as an undocumented
/// attribute of its application items, and the attribute is not guaranteed: a macOS update can
/// change or remove it. What protects the app:
/// - The attribute is read with public Accessibility calls only (no `dlopen`, no `dlsym`, no
///   private framework), through the permission holzBar already asks for.
/// - Nothing here runs while the module's Read badge counts switch is off, because the only
///   caller, ``DockReader``, is told by ``DockBadges`` not to reach this file then.
/// - A missing attribute or a failure is an answer, not a crash: ``label(of:)`` turns every
///   result into a ``DockLabelAnswer``, and ``DockLabelGate`` and ``PrivateFeatureGate`` decide
///   from the answers whether the part switches itself off for the session.
///
/// The file keeps no observer, starts no timer, logs nothing and never uses the network. The
/// text of a badge stays in memory.
nonisolated enum DockBadgeBridge {
    /// The name of the badge attribute of a Dock application item.
    private static let attribute = "AXStatusLabel"

    /// What the Dock answers for the badge of one application item.
    static func label(of item: AXUIElement) -> DockLabelAnswer {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(item, attribute as CFString, &value) {
        case .success:
            guard let text = value as? String else {
                return .failed
            }
            return .text(text)
        case .noValue:
            return .none
        case .attributeUnsupported:
            return .unsupported
        default:
            return .failed
        }
    }

    /// Whether an application item lists the badge attribute among its attributes, which is
    /// what the start check takes as proof that the Dock offers it.
    static func listsLabel(_ item: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(item, &names) == .success,
            let names = names as? [String]
        else {
            return false
        }
        return names.contains(attribute)
    }
}
