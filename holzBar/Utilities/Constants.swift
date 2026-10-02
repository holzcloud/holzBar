//
//  Constants.swift
//  holzBar
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

    /// The holzBar repository.
    static let repositoryURL = URL(string: "https://github.com/holzcloud/holzBar")!

    /// The holzBar issue tracker.
    static let issuesURL = repositoryURL.appending(path: "issues")

    /// The holzBar releases.
    static let releasesURL = repositoryURL.appending(path: "releases")

    /// The holzBar website.
    static let websiteURL = URL(string: "https://holzcloud.ch/holzbar")!

    /// The original Ice by Jordan Baird, which holzBar is a fork of.
    static let originalIceURL = URL(string: "https://github.com/jordanbaird/Ice")!

    // swiftlint:enable force_unwrapping
}
