//
//  URLCommand.swift
//  holzBar
//

import Foundation

/// A command another app sends to holzBar with a URL such as `holzbar://toggle/hidden`.
///
/// The host names the command and the path holds its arguments. The parse only reads the
/// URL; ``action`` says which action the command asks for, and `URLCommands` performs it.
nonisolated struct URLCommand: Equatable, Sendable {
    /// A menu bar section a command can show, hide or toggle.
    nonisolated enum Section: Equatable, Sendable {
        case hidden
        case alwaysHidden
    }

    /// The action a command asks for.
    nonisolated enum Action: Equatable, Sendable {
        case toggle(Section)
        case show(Section)
        case hide(Section)
        case search
        case settings
        case toggleShelf
        case toggleAutoRehide
        case toggleApplicationMenus
        /// Turn Zen mode on, off, or the other way round.
        case zenMode(ZenMode.Request)
        /// Apply the layout profile with the given name.
        case applyProfile(String)
        /// Turn the automation rule with the given name on or off.
        case automationRule(name: String, isEnabled: Bool)
        case unknown

        /// What holzBar does with the action, given Zen mode now.
        ///
        /// Any app can open a `holzbar://` URL without the user knowing, and a web page can
        /// once the browser has asked. So:
        ///
        /// - Showing and hiding change nothing lasting and run at once. Zen mode refuses
        ///   `show` and `toggle` of a hidden section where they are performed.
        /// - The search and Settings change nothing lasting either, but list or reveal the
        ///   hidden items, so Zen mode refuses them. So are the application menus: toggling
        ///   them changes nothing lasting, but shows the Dock icon and the menus, which Zen
        ///   mode keeps quiet.
        /// - Applying a profile rearranges the menu bar, the Shelf and auto-rehide
        ///   toggles change settings that last, and turning an automation rule on or off
        ///   changes what holzBar does by itself: holzBar
        ///   asks first, and refuses them while Zen mode is on.
        /// - Another app may always turn Zen mode on; it only hides. Turning it off needs
        ///   the user's answer, and is refused while the screen is shared (the automatic
        ///   part, ``ZenMode/isAutomatic``), which only the user ends.
        func decision(zenMode: ZenMode) -> Decision {
            switch self {
            case .toggle, .show, .hide, .unknown:
                return .perform
            case .search, .settings, .toggleApplicationMenus:
                return zenMode.isActive ? .refuse : .perform
            case .toggleShelf, .toggleAutoRehide, .applyProfile, .automationRule:
                return zenMode.isActive ? .refuse : .ask
            case .zenMode(let request):
                guard zenMode.isActive, request != .turnOn else {
                    // Turns Zen mode on, or leaves it off.
                    return .perform
                }
                return zenMode.isAutomatic ? .refuse : .ask
            }
        }
    }

    /// What holzBar does with a command from another app.
    nonisolated enum Decision: Equatable, Sendable {
        /// Performs it at once.
        case perform
        /// Asks the user first, and performs it only when they agree.
        case ask
        /// Ignores it.
        case refuse
    }

    /// Limits how many commands from other apps holzBar performs.
    ///
    /// Any app, script or web page can send commands, as often as it likes (URLs and Apple
    /// events of the AppleScript dictionary). A burst must not run a stream of reveals or
    /// questions, so at most ``limit`` commands run within any ``window``; the others are
    /// ignored. A refused command is not recorded, so a flood cannot keep the window full
    /// for longer than it lasts.
    nonisolated struct Throttle: Sendable {
        /// The most commands performed within ``window``.
        static let limit = 8

        /// The length of the sliding window.
        static let window: Duration = .seconds(2)

        /// When the commands inside the window were performed.
        private var performed: [ContinuousClock.Instant] = []

        /// Decides whether a command arriving `now` may run, and records it when it may.
        mutating func allows(at now: ContinuousClock.Instant) -> Bool {
            performed.removeAll { now >= $0.advanced(by: Self.window) }
            guard performed.count < Self.limit else {
                return false
            }
            performed.append(now)
            return true
        }
    }

    /// The command, lower-cased.
    let name: String

    /// The command's arguments: the path components, percent-decoded, case kept.
    let arguments: [String]

    /// A command that does not come from a URL, such as one from an Apple event. It goes
    /// through the same decision as a URL command (`Action.decision(zenMode:)`).
    init(name: String, arguments: [String]) {
        self.name = name.lowercased()
        self.arguments = arguments
    }

    /// Reads the command in `url`.
    ///
    /// - Parameters:
    ///   - url: The URL to read.
    ///   - scheme: The scheme holzBar accepts, compared case-insensitively.
    /// - Returns: `nil` for another scheme or a URL without a command.
    init?(url: URL, scheme: String) {
        guard
            let urlScheme = url.scheme,
            urlScheme.lowercased() == scheme.lowercased(),
            let host = url.host(percentEncoded: false),
            !host.isEmpty
        else {
            return nil
        }
        self.name = host.lowercased()
        self.arguments = url.path(percentEncoded: true)
            .split(separator: "/")
            .map { component in
                component.removingPercentEncoding ?? String(component)
            }
    }

    /// The action the command asks for.
    ///
    /// `show`, `hide` and `toggle` take the section as their argument: `always-hidden` (or
    /// `alwayshidden`) for the always-hidden section, anything else or nothing for the
    /// hidden one. `ice-bar` is another name for `shelf`. `zen` takes `on`, `off` or
    /// `toggle` (also nothing). `profile` needs a name.
    var action: Action {
        switch name {
        case "toggle":
            .toggle(section)
        case "show":
            .show(section)
        case "hide":
            .hide(section)
        case "search":
            .search
        case "settings":
            .settings
        case "shelf", "ice-bar":
            .toggleShelf
        case "auto-rehide":
            .toggleAutoRehide
        case "application-menus":
            .toggleApplicationMenus
        case "zen":
            .zenMode(zenRequest)
        case "profile":
            arguments.first.map(Action.applyProfile) ?? .unknown
        case "automation":
            automationAction
        default:
            .unknown
        }
    }

    /// `automation/enable/<name>` or `automation/disable/<name>`. Creating, editing and
    /// listing rules are not possible by URL: a URL has no way to answer.
    private var automationAction: Action {
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            return .unknown
        }
        switch arguments[0].lowercased() {
        case "enable":
            return .automationRule(name: arguments[1], isEnabled: true)
        case "disable":
            return .automationRule(name: arguments[1], isEnabled: false)
        default:
            return .unknown
        }
    }

    /// The Zen mode request named by the first argument.
    private var zenRequest: ZenMode.Request {
        switch arguments.first?.lowercased() {
        case "on":
            .turnOn
        case "off":
            .turnOff
        default:
            .toggle
        }
    }

    /// The section named by the first argument.
    private var section: Section {
        switch arguments.first?.lowercased() {
        case "always-hidden", "alwayshidden":
            .alwaysHidden
        default:
            .hidden
        }
    }
}
