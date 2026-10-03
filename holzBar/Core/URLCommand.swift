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
        /// Apply the layout profile with the given name.
        case applyProfile(String)
        case unknown

        /// Whether holzBar asks the user before it performs the action.
        ///
        /// Any app can open a `holzbar://` URL without the user knowing. Applying a profile
        /// rearranges the menu bar, so it asks first; every other action changes nothing
        /// lasting (show, hide, search, settings) or flips a setting the same command flips
        /// back (the toggles).
        var needsConfirmation: Bool {
            switch self {
            case .applyProfile:
                true
            case .toggle, .show, .hide, .search, .settings, .toggleShelf, .toggleAutoRehide, .toggleApplicationMenus, .unknown:
                false
            }
        }
    }

    /// The command, lower-cased.
    let name: String

    /// The command's arguments: the path components, percent-decoded, case kept.
    let arguments: [String]

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
    /// hidden one. `ice-bar` is another name for `shelf`. `profile` needs a name.
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
        case "profile":
            arguments.first.map(Action.applyProfile) ?? .unknown
        default:
            .unknown
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
