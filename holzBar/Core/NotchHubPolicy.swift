//
//  NotchHubPolicy.swift
//  holzBar
//

import Foundation

/// When the Notch hub opens and closes, as pure decisions.
///
/// The hub opens when the pointer rests in its hover zone for ``openDelay`` or when the hotkey
/// asks, and it does not open where it would be wrong: on a display the setting excludes, in a
/// fullscreen space, with the menu bar hidden by the system, or while the screen is mirrored
/// or shared (the hub will show calendar events and what plays). A hub that hover opened
/// closes ``closeDelay`` after the pointer left both the hub and the zone. What the
/// environment is, is read once, when the hub would open, never followed.
nonisolated enum NotchHubPolicy {
    /// What asks the hub to open.
    nonisolated enum Trigger: Equatable, Sendable {
        /// The pointer rested in the hover zone.
        case hover
        /// The user pressed the hotkey.
        case hotkey
        /// The pointer rested on the live-activity capsule, or the user clicked it. It follows the
        /// rules of ``hover`` in every way.
        case compact

        /// Whether a hub opened by this trigger closes when the pointer leaves it: the pointer
        /// asked for it, so the pointer takes it back.
        var closesOnLeave: Bool {
            switch self {
            case .hover, .compact: true
            case .hotkey: false
            }
        }
    }

    /// What a pointer move asks the hub to do.
    nonisolated enum HoverAction: Equatable, Sendable {
        case open
        case close
    }

    /// What is true about the Mac at the moment the hub would open.
    nonisolated struct Environment: Equatable, Sendable {
        /// A fullscreen space is active.
        var isFullscreenSpace: Bool
        /// The menu bar is hidden by the system, always or automatically.
        var isMenuBarHiddenBySystem: Bool
        /// The screen is mirrored or shared (``PresentationSignals``).
        var isPresenting: Bool
        /// The setting allows the hub on this display.
        var isDisplayAllowed: Bool
    }

    /// Why the hub does not open.
    nonisolated enum BlockReason: String, Equatable, Sendable {
        case displayNotAllowed
        case fullscreen
        case menuBarHidden
        case presenting
    }

    /// Where the pointer is.
    nonisolated struct Pointer: Equatable, Sendable {
        /// In the hover zone.
        var isInZone: Bool
        /// In the open hub.
        var isInHub: Bool
    }

    /// What to do about a pointer move.
    nonisolated enum HoverDecision: Equatable, Sendable {
        /// Start waiting to do the action; a different pending action is replaced.
        case schedule(HoverAction)
        /// The pointer no longer asks for the pending action.
        case cancelPending
        /// Nothing changes.
        case none
    }

    /// How long the pointer rests in the zone before the hub opens.
    static let openDelay = Duration.milliseconds(250)

    /// How long the pointer is away before a hub opened by hover closes.
    static let closeDelay = Duration.milliseconds(400)

    /// Whether the hotkey opens the hub in a fullscreen space or with the menu bar hidden.
    /// It does not: the hub does not open where the menu bar is not shown, because it would
    /// hide a video, a game or a presentation (decided as the recommended answer).
    static let hotkeyOpensInFullscreen = false

    /// Whether the hub stays closed while the screen is mirrored or shared. It does (decided
    /// as the recommended answer).
    static let blocksWhilePresenting = true

    /// The first reason the hub must not open, or `nil` when it may.
    ///
    /// In order: the display is not allowed; a fullscreen space (hover always, the hotkey too
    /// unless ``hotkeyOpensInFullscreen``); the menu bar hidden by the system (the same rule);
    /// the screen presented while ``blocksWhilePresenting``. The live-activity capsule's
    /// ``Trigger/compact`` is judged exactly as ``Trigger/hover`` is.
    static func blockReason(_ environment: Environment, trigger: Trigger) -> BlockReason? {
        if !environment.isDisplayAllowed {
            return .displayNotAllowed
        }
        let barRuleApplies = trigger != .hotkey || !hotkeyOpensInFullscreen
        if environment.isFullscreenSpace, barRuleApplies {
            return .fullscreen
        }
        if environment.isMenuBarHiddenBySystem, barRuleApplies {
            return .menuBarHidden
        }
        if environment.isPresenting, blocksWhilePresenting {
            return .presenting
        }
        return nil
    }

    /// What the pointer asks for: to open the closed hub when it is in the zone, to close an
    /// open hub that closes on leaving when it is in neither the hub nor the zone, and nothing
    /// otherwise.
    static func hoverDesired(pointer: Pointer, isOpen: Bool, closesOnLeave: Bool) -> HoverAction? {
        if !isOpen {
            return pointer.isInZone ? .open : nil
        }
        if closesOnLeave, !pointer.isInZone, !pointer.isInHub {
            return .close
        }
        return nil
    }

    /// Turns what the pointer asks for into a decision, given the action already waiting.
    static func hoverDecision(
        pointer: Pointer,
        isOpen: Bool,
        closesOnLeave: Bool,
        pending: HoverAction?
    ) -> HoverDecision {
        guard let desired = hoverDesired(pointer: pointer, isOpen: isOpen, closesOnLeave: closesOnLeave) else {
            return pending == nil ? .none : .cancelPending
        }
        return desired == pending ? .none : .schedule(desired)
    }

    /// An AppKit global point in the display's coordinates: origin at the top-left, y downward,
    /// as ``NotchHubGeometry`` has them. A pointer on the display's top edge gets y 0.
    static func localPoint(
        globalX: Double,
        globalY: Double,
        displayMinX: Double,
        displayMaxY: Double
    ) -> (x: Double, y: Double) {
        (globalX - displayMinX, displayMaxY - globalY)
    }
}
