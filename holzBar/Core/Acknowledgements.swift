//
//  Acknowledgements.swift
//  holzBar
//

import Foundation

/// A project holzBar is based on or links, shown under Settings, About, Acknowledgements.
nonisolated struct Acknowledgement: Identifiable, Hashable, Sendable {
    /// The name of the project.
    let name: String
    /// The project's repository, as an https URL string.
    let repository: String
    /// The version holzBar links, or `nil` for adapted code.
    let version: String?
    /// One sentence on what holzBar uses the project for.
    let use: String
    /// The names of the project's licenses.
    let license: String
    /// The base name of the project's license text in `holzBar/Resources/Acknowledgements`
    /// (with the `txt` extension), or `nil` when its license is holzBar's own.
    let licenseFile: String?

    var id: String { repository }
}

/// The code holzBar is adapted from and the Swift packages it links (none since 05.1).
///
/// The lists are pure data so `swift test` can check them against `Package.resolved` and
/// the license files; the app shows them in `AcknowledgementsView`.
nonisolated enum Acknowledgements {
    /// The name of holzBar's own license, which the adapted code shares.
    static let gplLicense = "GNU General Public License v3.0"

    /// The projects holzBar adapts code from, all licensed under the GNU GPL v3.
    static let adaptedCode: [Acknowledgement] = [
        Acknowledgement(
            name: "Ice",
            repository: "https://github.com/jordanbaird/Ice",
            version: nil,
            use: "holzBar is a fork of Ice by Jordan Baird: its design, features and almost all of its code.",
            license: gplLicense,
            licenseFile: nil
        ),
        Acknowledgement(
            name: "Barometer",
            repository: "https://github.com/mackid1993/Barometer",
            version: nil,
            use: "holzBar's macOS 27 assertion code is adapted from the MenuBarAssessmentAssertion of Barometer by mackid1993.",
            license: gplLicense,
            licenseFile: nil
        ),
        Acknowledgement(
            name: "Thaw",
            repository: "https://github.com/thaw-app/Thaw",
            version: nil,
            use: "Barometer's assertion code is adapted from the PlatformRuntimeKit of Thaw by thaw-app.",
            license: gplLicense,
            licenseFile: nil
        ),
    ]

    /// The Swift packages holzBar links, sorted by name, with the versions in `Package.resolved`.
    ///
    /// Empty: since 05.1 holzBar links no Swift package (its sliders, launch at login and
    /// event lock are its own or the system's). The list stays so a package added later
    /// must be acknowledged here; `swift test` checks it against `Package.resolved`.
    static let packages: [Acknowledgement] = []
}
