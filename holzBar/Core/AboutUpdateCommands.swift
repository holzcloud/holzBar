//
//  AboutUpdateCommands.swift
//  holzBar
//

import Foundation

/// The commands that update holzBar through Homebrew, as About shows them (D-60).
///
/// The commands are shown as text for the user to copy. holzBar never runs them and never looks
/// for updates, because it never connects to the network. An alpha or beta shows the beta
/// channel's command first.
nonisolated enum AboutUpdateCommands {
    /// The Homebrew channel a command updates.
    nonisolated enum Channel: Sendable, Equatable {
        case stable
        case beta
    }

    /// One command and the channel it updates.
    nonisolated struct Command: Sendable, Equatable {
        let channel: Channel
        let text: String
    }

    static let stable = Command(channel: .stable, text: "brew update && brew upgrade --cask holzbar")
    static let beta = Command(channel: .beta, text: "brew update && brew upgrade --cask holzbar@beta")

    /// Both commands, the beta one first for a pre-release.
    static func commands(isPrerelease: Bool) -> [Command] {
        isPrerelease ? [beta, stable] : [stable, beta]
    }

    /// Both commands in the order that fits the version; a string that is no version counts as
    /// a stable release.
    static func commands(forVersion version: String) -> [Command] {
        commands(isPrerelease: AppVersion(version)?.isPrerelease ?? false)
    }
}
