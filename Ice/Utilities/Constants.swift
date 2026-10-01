//
//  Constants.swift
//  Ice
//

import Foundation

enum Constants {
    // swiftlint:disable force_unwrapping

    /// The version string in the app's bundle.
    static let versionString = Bundle.main.versionString!

    /// The build string in the app's bundle.
    static let buildString = Bundle.main.buildString!

    /// The user-readable copyright string in the app's bundle.
    static let copyrightString = Bundle.main.copyrightString!

    /// The app's bundle identifier.
    static let bundleIdentifier = Bundle.main.bundleIdentifier!

    /// The app's display name.
    static let displayName = Bundle.main.displayName!

    /// The holzIce repository.
    static let repositoryURL = URL(string: "https://github.com/holzcloud/holzIce")!

    /// The holzIce issue tracker.
    static let issuesURL = repositoryURL.appendingPathComponent("issues")

    /// The holzIce website.
    ///
    /// holzIce has no website of its own yet, so this is the repository for now.
    static let websiteURL = repositoryURL

    /// The original Ice by Jordan Baird, which holzIce is a fork of.
    static let originalIceURL = URL(string: "https://github.com/jordanbaird/Ice")!

    // swiftlint:enable force_unwrapping
}
