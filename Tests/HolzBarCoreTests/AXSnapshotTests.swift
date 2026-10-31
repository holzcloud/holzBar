import Foundation
import Testing
@testable import HolzBarCore

/// All trees and texts here are synthetic: they are built by the tests and are not read from
/// any notification.
@Suite("AXSnapshot")
struct AXSnapshotTests {
    /// A chain of single children, `length` nodes long, the root first.
    private func chain(length: Int) -> AXSnapshot.Node {
        var node = AXSnapshot.Node(role: "AXGroup", text: "leaf")
        for _ in 1..<length {
            node = AXSnapshot.Node(role: "AXGroup", text: "inner", children: [node])
        }
        return node
    }

    /// The depth of the deepest node, the root being 0.
    private func depth(of node: AXSnapshot.Node) -> Int {
        1 + (node.children.map(depth(of:)).max() ?? -1)
    }

    private func count(_ node: AXSnapshot.Node) -> Int {
        1 + node.children.map(count(_:)).reduce(0, +)
    }

    @Test("A tree of depth 12 is cut to depth 8")
    func depthIsCut() {
        let snapshot = AXSnapshot.normalized(chain(length: 13))
        #expect(depth(of: snapshot.root) == AXSnapshot.maximumDepth)
        #expect(AXSnapshot.maximumDepth == 8)
    }

    @Test("A tree of 500 nodes is cut to 200 nodes in depth-first order")
    func nodesAreCut() {
        let children = (0..<499).map { AXSnapshot.Node(role: "AXStaticText", text: "text \($0)") }
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(role: "AXGroup", children: children))
        #expect(count(snapshot.root) == AXSnapshot.maximumNodes)
        #expect(AXSnapshot.maximumNodes == 200)
        // The first nodes in document order are the ones that stay.
        #expect(snapshot.root.children.first?.text == "text 0")
        #expect(snapshot.root.children.last?.text == "text 198")
    }

    @Test("A text of 800 characters is cut to 500")
    func textIsCut() {
        let long = String(repeating: "a", count: 800)
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(role: "AXStaticText", text: long))
        #expect(snapshot.root.text?.count == 500)
        #expect(AXSnapshot.maximumTextLength == 500)
    }

    @Test("Surrounding space is trimmed and control characters are removed")
    func textIsCleaned() {
        let dirty = "  Hello\u{0007} wor\u{0000}ld\u{001B}  "
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(role: "AXStaticText", text: dirty))
        #expect(snapshot.root.text == "Hello world")
    }

    @Test("A line break stays a space between words")
    func lineBreaksBecomeSpaces() {
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(text: "one\ntwo\r\nthree\tfour"))
        #expect(snapshot.root.text == "one two  three four")
    }

    @Test("Characters that reverse the direction of text are removed")
    func directionOverridesAreRemoved() {
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(text: "abc\u{202E}def\u{2066}ghi"))
        #expect(snapshot.root.text == "abcdefghi")
    }

    @Test("An empty or blank text becomes nil")
    func emptyTextIsNil() {
        #expect(AXSnapshot.normalized(AXSnapshot.Node(text: "")).root.text == nil)
        #expect(AXSnapshot.normalized(AXSnapshot.Node(text: "  \n\t ")).root.text == nil)
        #expect(AXSnapshot.normalized(AXSnapshot.Node(text: "\u{0007}")).root.text == nil)
        #expect(AXSnapshot.normalized(AXSnapshot.Node(text: nil)).root.text == nil)
    }

    @Test("An emoji and an accent are kept whole")
    func charactersSurvive() {
        let snapshot = AXSnapshot.normalized(AXSnapshot.Node(text: "Caf\u{00E9} \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"))
        #expect(snapshot.root.text == "Caf\u{00E9} \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
    }

    @Test("Roles and identifiers are kept, cut and emptied like texts")
    func attributesAreBounded() {
        let node = AXSnapshot.Node(
            role: "AXGroup", subrole: "", identifier: String(repeating: "x", count: 500)
        )
        let snapshot = AXSnapshot.normalized(node)
        #expect(snapshot.root.role == "AXGroup")
        #expect(snapshot.root.subrole == nil)
        #expect(snapshot.root.identifier?.count == AXSnapshot.maximumIdentifierLength)
    }

    @Test("Normalizing twice changes nothing")
    func normalizingIsIdempotent() {
        let once = AXSnapshot.normalized(chain(length: 20))
        #expect(AXSnapshot.normalized(once.root) == once)
    }
}
