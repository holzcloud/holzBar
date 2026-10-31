//
//  AXTreeTests.swift
//  notifications
//

import Testing
@testable import NotificationProbeCore

private func bannerFixture() -> RawNode {
    RawNode(
        role: "AXGroup",
        subrole: "AXNotificationCenterBanner",
        identifier: "banner",
        texts: [],
        children: [
            RawNode(role: "AXStaticText", texts: ["Build done."]),
            RawNode(role: "AXStaticText", texts: ["The nightly build finished."]),
            RawNode(role: "AXImage"),
        ]
    )
}

@Test("A banner subtree is summarised into roles, subroles, identifiers and text lengths, keeping no text")
func summariseBanner() {
    let nodes = AXTree.summarise(bannerFixture())
    #expect(nodes.count == 4)
    #expect(nodes[0] == NodeInfo(
        depth: 0, role: "AXGroup", subrole: "AXNotificationCenterBanner", identifier: "banner", textLength: nil
    ))
    #expect(nodes[1] == NodeInfo(depth: 1, role: "AXStaticText", subrole: nil, identifier: nil, textLength: 11))
    #expect(nodes[2].textLength == 27)
    #expect(nodes[3].textLength == nil)
    #expect(AXTree.textNodeCount(nodes) == 2)
}

@Test("The first non-empty text of a node gives its length")
func textLengthFromFirstNonEmpty() {
    let node = RawNode(role: "AXStaticText", texts: ["", "abc", "defgh"])
    #expect(AXTree.summarise(node).first?.textLength == 3)
    #expect(AXTree.summarise(RawNode(role: "AXStaticText", texts: [""])).first?.textLength == nil)
}

@Test("The summary stops at 200 nodes and at depth 8")
func summariseCaps() {
    let wide = RawNode(role: "AXGroup", children: Array(repeating: RawNode(role: "AXStaticText", texts: ["x"]), count: 500))
    #expect(AXTree.summarise(wide).count == 200)

    var chain = RawNode(role: "AXGroup")
    for _ in 0..<20 {
        chain = RawNode(role: "AXGroup", children: [chain])
    }
    let nodes = AXTree.summarise(chain)
    #expect(nodes.count == 9)
    #expect(nodes.last?.depth == 8)
}

@Test("The texts of a subtree are collected under the same caps, in order")
func allTextsOrder() {
    #expect(AXTree.allTexts(bannerFixture()) == ["Build done.", "The nightly build finished."])
}

@Test("The text matcher trims, ignores case and accents, and looks for the text inside the candidate")
func matcherContains() {
    #expect(TextMatcher.matches("Build finished", expected: "build FINISHED"))
    #expect(TextMatcher.matches("Messages, Anna, Build finished, now", expected: "  build finished "))
    #expect(TextMatcher.matches("Café", expected: "cafe"))
}

@Test("The text matcher never matches an empty candidate or an empty expected text")
func matcherEmpty() {
    #expect(!TextMatcher.matches("", expected: "x"))
    #expect(!TextMatcher.matches("anything", expected: ""))
    #expect(!TextMatcher.matches("anything", expected: "   "))
}

@Test("An identifier is printed only when it is a short system-style word, never a bundle identifier or a sentence")
func identifierRedaction() {
    #expect(AXTree.printableIdentifier("notification-banner_1") == "notification-banner_1")
    #expect(AXTree.printableIdentifier("com.apple.MobileSMS") == "other(19)")
    #expect(AXTree.printableIdentifier("Hello there") == "other(11)")
    #expect(AXTree.printableIdentifier(String(repeating: "a", count: 49)) == "other(49)")
    #expect(AXTree.printableIdentifier(nil) == nil)
    #expect(AXTree.printableIdentifier("") == nil)
}
