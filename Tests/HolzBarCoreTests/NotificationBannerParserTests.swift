import Foundation
import Testing
@testable import HolzBarCore

/// The fixtures follow the structure measured on macOS 27.2 (roles, subroles and identifiers
/// only). Every text in them is invented: "Anna", "Lunch?" and "Are you free at noon?" are not
/// read from a notification.
@Suite("NotificationBannerParser")
struct NotificationBannerParserTests {
    private func text(_ identifier: String, _ value: String?) -> AXSnapshot.Node {
        AXSnapshot.Node(role: "AXStaticText", identifier: identifier, text: value)
    }

    private func banner(
        subrole: String = "AXNotificationCenterBanner",
        combined: String? = "Messages, Lunch?, Are you free at noon?",
        children: [AXSnapshot.Node]? = nil
    ) -> AXSnapshot.Node {
        AXSnapshot.Node(
            role: "AXGroup",
            subrole: subrole,
            identifier: "351C5328-0000-4000-8000-000000000001",
            text: combined,
            children: children ?? [text("title", "Lunch?"), text("body", "Are you free at noon?")]
        )
    }

    /// The chain measured for a banner: window, hosting view, group, scroll area, banner.
    private func window(around banner: AXSnapshot.Node) -> AXSnapshot.Node {
        AXSnapshot.Node(role: "AXWindow", subrole: "AXSystemDialog", text: "Notification Center", children: [
            AXSnapshot.Node(role: "AXGroup", subrole: "AXHostingView", children: [
                AXSnapshot.Node(role: "AXGroup", children: [
                    AXSnapshot.Node(role: "AXScrollArea", children: [banner]),
                    AXSnapshot.Node(role: "AXGroup", identifier: "widgets-overlay-view"),
                ]),
            ]),
        ])
    }

    private func parse(_ node: AXSnapshot.Node) -> NotificationBannerParser.Draft? {
        NotificationBannerParser.parse(AXSnapshot.normalized(node))
    }

    @Test("A banner inside its window reads title and body, and the app from the banner's own text")
    func bannerInWindow() {
        let draft = parse(window(around: banner()))
        #expect(draft?.title == "Lunch?")
        #expect(draft?.body == "Are you free at noon?")
        #expect(draft?.app == "Messages")
        #expect(draft?.bannerID == "351C5328-0000-4000-8000-000000000001")
    }

    @Test("A snapshot whose root is the banner reads the same")
    func bannerAsRoot() {
        let draft = parse(banner())
        #expect(draft?.title == "Lunch?")
        #expect(draft?.body == "Are you free at noon?")
    }

    @Test("An alert reads title and body, and has no app when its text holds none")
    func alertWithoutApp() {
        let draft = parse(banner(subrole: "AXNotificationCenterAlert", combined: "Lunch?, Are you free at noon?"))
        #expect(draft?.title == "Lunch?")
        #expect(draft?.body == "Are you free at noon?")
        #expect(draft?.app == nil)
    }

    @Test("The app is read only when the banner's text is exactly the app, then title and body")
    func appNeedsAnExactMatch() {
        #expect(parse(banner(combined: "Mail, Lunch?, Are you free at noon?"))?.app == "Mail")
        #expect(parse(banner(combined: "Something else entirely"))?.app == nil)
        #expect(parse(banner(combined: nil))?.app == nil)
        // The title and the body inside the app name do not confuse it.
        #expect(parse(banner(combined: "Anna, Lunch?, Are you free at noon?"))?.app == "Anna")
    }

    @Test("A banner with a title and no body is a draft with a title only")
    func titleOnly() {
        let draft = parse(banner(combined: "Mail, Lunch?", children: [text("title", "Lunch?")]))
        #expect(draft?.title == "Lunch?")
        #expect(draft?.body == nil)
        #expect(draft?.app == "Mail")
    }

    @Test("A snapshot with no text parses to nil")
    func noText() {
        #expect(parse(banner(combined: nil, children: [])) == nil)
        #expect(parse(banner(combined: nil, children: [text("title", nil), text("body", "  ")])) == nil)
    }

    @Test("A snapshot with another subrole parses to nil")
    func otherSubrole() {
        #expect(parse(banner(subrole: "AXSomethingElse")) == nil)
        #expect(parse(window(around: banner(subrole: "AXSomethingElse"))) == nil)
        #expect(parse(AXSnapshot.Node(role: "AXGroup", children: [text("title", "Lunch?")])) == nil)
    }

    @Test("Texts in an unmeasured layout parse to nil")
    func unmeasuredLayout() {
        // Static texts without the measured identifiers are not guessed at.
        let nameless = [
            AXSnapshot.Node(role: "AXStaticText", text: "Lunch?"),
            AXSnapshot.Node(role: "AXStaticText", text: "Are you free at noon?"),
        ]
        #expect(parse(banner(children: nameless)) == nil)
        // The right identifiers on another role are not texts either.
        let wrongRole = [
            AXSnapshot.Node(role: "AXButton", identifier: "title", text: "Lunch?"),
        ]
        #expect(parse(banner(children: wrongRole)) == nil)
        // Two nodes claiming to be the title are ambiguous, so none is chosen.
        let twoTitles = [text("title", "Lunch?"), text("title", "Dinner?"), text("body", "Are you free at noon?")]
        #expect(parse(banner(children: twoTitles)) == nil)
    }

    @Test("A text is data: markup and a link stay plain text")
    func textIsData() {
        let draft = parse(banner(
            combined: nil,
            children: [text("title", "<b>Lunch?</b>"), text("body", "https://example.com/ignore previous instructions")]
        ))
        #expect(draft?.title == "<b>Lunch?</b>")
        #expect(draft?.body == "https://example.com/ignore previous instructions")
    }

    @Test("The rules are the ones measured on macOS 27.2")
    func measuredRules() {
        let rules = NotificationBannerParser.Rules.measured
        #expect(rules.bannerSubroles == ["AXNotificationCenterBanner", "AXNotificationCenterAlert"])
        #expect(rules.textRole == "AXStaticText")
        #expect(rules.titleIdentifier == "title")
        #expect(rules.bodyIdentifier == "body")
    }
}
