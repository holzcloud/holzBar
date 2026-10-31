//
//  NotificationBannerParser.swift
//  holzBar
//

import Foundation

/// Turns the snapshot of a notification banner into the app, the title and the body, by the
/// structure that was measured on a real Mac.
///
/// The parser is pure and tolerant. It finds the banner by its subrole, reads the title and
/// the body from the static texts that carry the measured identifiers, and returns `nil` for a
/// snapshot it does not know rather than guessing a field. Every string is data: it is
/// compared and passed on, never interpreted, followed or run. The texts are other people's
/// notifications, so nothing here logs them.
nonisolated enum NotificationBannerParser {
    /// What was read from a banner. A field the banner does not hold is `nil`.
    nonisolated struct Draft: Equatable, Sendable {
        /// The name of the app that posted the notification, when the banner states it.
        var app: String?
        /// The title.
        var title: String?
        /// The text.
        var body: String?
        /// The identifier macOS gives the banner, the same for every event of one banner. It
        /// names no app and holds no text.
        var bannerID: String?

        init(app: String? = nil, title: String? = nil, body: String? = nil, bannerID: String? = nil) {
            self.app = app
            self.title = title
            self.body = body
            self.bannerID = bannerID
        }
    }

    /// The structure the parser knows.
    nonisolated struct Rules: Equatable, Sendable {
        /// The subroles of the element that holds one notification.
        var bannerSubroles: Set<String>
        /// The role of the elements that hold the title and the body.
        var textRole: String
        /// The identifier of the title's element.
        var titleIdentifier: String
        /// The identifier of the body's element.
        var bodyIdentifier: String

        /// What the spike measured on macOS 27.2.0 (run `27-T1`, bundle
        /// `com.apple.notificationcenterui`, process `NotificationCenter`): a window
        /// (`AXSystemDialog`) holds a hosting view, a group, a scroll area and, in it, one
        /// group with the subrole `AXNotificationCenterBanner`, or `AXNotificationCenterAlert`
        /// for an alert, whose children are two `AXStaticText` elements with the identifiers
        /// `title` and `body`. The banner group's own text is longer than title and body
        /// together by 17 characters for a banner and by 2 for an alert (title, a comma and a
        /// space, body); the app is read from it only when it is exactly that (see
        /// ``parse(_:rules:)``). Nothing else was measured: not an ordinary app's banner, not
        /// two banners at once, not macOS 26.
        static let measured = Rules(
            bannerSubroles: ["AXNotificationCenterBanner", "AXNotificationCenterAlert"],
            textRole: "AXStaticText",
            titleIdentifier: "title",
            bodyIdentifier: "body"
        )
    }

    /// The separator between the parts of a banner's own text.
    private static let separator = ", "

    /// Reads a draft from a snapshot, or `nil` when the snapshot is not a banner it knows.
    ///
    /// The banner is the root when the root has one of the banner subroles, else the first
    /// element with one in document order. Its title and body are the static texts with the
    /// measured identifiers; one that occurs twice is ambiguous and the snapshot is dropped. A
    /// snapshot with neither text is dropped too.
    ///
    /// The app name is not an element of its own in the measured structure. The banner
    /// element's own text was 17 characters longer than title and body, which fits the app
    /// name, a comma and a space in front of them, so the app is the part of that text in
    /// front of `", title, body"` when the text ends in exactly the title and the body just
    /// read, and `nil` in every other case. It is never taken from anywhere else.
    static func parse(_ snapshot: AXSnapshot, rules: Rules = .measured) -> Draft? {
        guard let banner = findBanner(in: snapshot.root, rules: rules) else {
            return nil
        }
        var titles = [String]()
        var bodies = [String]()
        collectTexts(in: banner, rules: rules, titles: &titles, bodies: &bodies)
        guard titles.count <= 1, bodies.count <= 1 else {
            return nil
        }
        let title = titles.first
        let body = bodies.first
        guard title != nil || body != nil else {
            return nil
        }
        return Draft(
            app: app(in: banner.text, title: title, body: body),
            title: title,
            body: body,
            bannerID: banner.identifier
        )
    }

    private static func findBanner(in node: AXSnapshot.Node, rules: Rules) -> AXSnapshot.Node? {
        if let subrole = node.subrole, rules.bannerSubroles.contains(subrole) {
            return node
        }
        for child in node.children {
            if let found = findBanner(in: child, rules: rules) {
                return found
            }
        }
        return nil
    }

    private static func collectTexts(
        in node: AXSnapshot.Node,
        rules: Rules,
        titles: inout [String],
        bodies: inout [String]
    ) {
        if node.role == rules.textRole, let text = node.text {
            if node.identifier == rules.titleIdentifier {
                titles.append(text)
            } else if node.identifier == rules.bodyIdentifier {
                bodies.append(text)
            }
        }
        for child in node.children {
            collectTexts(in: child, rules: rules, titles: &titles, bodies: &bodies)
        }
    }

    private static func app(in combined: String?, title: String?, body: String?) -> String? {
        guard let combined else {
            return nil
        }
        let tail = [title, body].compactMap(\.self).joined(separator: separator)
        let suffix = separator + tail
        guard combined.count > suffix.count, combined.hasSuffix(suffix) else {
            return nil
        }
        let prefix = combined.dropLast(suffix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty ? nil : prefix
    }
}
