//
//  AXSnapshot.swift
//  holzBar
//

import Foundation

/// A plain value copy of part of another process's Accessibility tree, with the caps that
/// keep a hostile or oversized tree from costing anything.
///
/// The notification reader copies the subtree of a banner into ``Node`` values off the main
/// thread and hands the root through ``normalized(_:)``; from then on nothing touches
/// Accessibility, so the parser and the tests work on values. Every string in a snapshot is
/// data: it is only ever compared and drawn as plain text, never interpreted. A snapshot can
/// hold the text of someone's notification, so it lives in memory only and is never logged.
nonisolated struct AXSnapshot: Equatable, Sendable {
    /// One element of the tree.
    nonisolated struct Node: Equatable, Sendable {
        /// The element's role, such as `AXGroup`.
        var role: String?
        /// The element's subrole.
        var subrole: String?
        /// The element's identifier, such as the name macOS gives a banner's title.
        var identifier: String?
        /// The first non-empty string among the element's value, title and description.
        var text: String?
        /// The element's children in the order Accessibility lists them.
        var children: [Node]

        init(
            role: String? = nil,
            subrole: String? = nil,
            identifier: String? = nil,
            text: String? = nil,
            children: [Node] = []
        ) {
            self.role = role
            self.subrole = subrole
            self.identifier = identifier
            self.text = text
            self.children = children
        }
    }

    /// The deepest level kept, the root being level 0.
    static let maximumDepth = 8

    /// The most nodes kept, counted in depth-first order from the root.
    static let maximumNodes = 200

    /// The most characters a text keeps.
    static let maximumTextLength = 500

    /// The most characters a role, a subrole or an identifier keeps.
    static let maximumIdentifierLength = 100

    /// The root of the tree.
    let root: Node

    /// Cuts a tree to the caps and cleans its strings.
    ///
    /// Nodes deeper than ``maximumDepth`` and those beyond ``maximumNodes`` in depth-first
    /// order are dropped. A text is cleaned (see ``cleaned(_:limit:)``) and cut to
    /// ``maximumTextLength``; one that is empty afterwards becomes `nil`, and so does an empty
    /// role, subrole or identifier. Normalizing a normalized snapshot changes nothing.
    static func normalized(_ root: Node) -> AXSnapshot {
        var kept = 0
        let node = normalize(root, depth: 0, kept: &kept) ?? Node()
        return AXSnapshot(root: node)
    }

    /// Returns the text with line breaks and tabs as spaces, every other control character
    /// and every character that reverses the direction of text removed, trimmed and cut to
    /// `limit` characters; `nil` when nothing is left.
    ///
    /// The direction overrides are removed because they can make text read as something it is
    /// not. A string is cut before it is cleaned, so a very long one costs no more than a long
    /// one.
    static func cleaned(_ text: String?, limit: Int) -> String? {
        guard let text else {
            return nil
        }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars.prefix(limit * 4) {
            switch scalar {
            case "\n", "\r", "\t", "\u{2028}", "\u{2029}":
                scalars.append(" ")
            case _ where scalar.properties.generalCategory == .control, _ where isDirectionOverride(scalar):
                continue
            default:
                scalars.append(scalar)
            }
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    private static func isDirectionOverride(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069:
            true
        default:
            false
        }
    }

    private static func normalize(_ node: Node, depth: Int, kept: inout Int) -> Node? {
        guard depth <= maximumDepth, kept < maximumNodes else {
            return nil
        }
        kept += 1
        var result = Node(
            role: cleaned(node.role, limit: maximumIdentifierLength),
            subrole: cleaned(node.subrole, limit: maximumIdentifierLength),
            identifier: cleaned(node.identifier, limit: maximumIdentifierLength),
            text: cleaned(node.text, limit: maximumTextLength)
        )
        for child in node.children {
            // A child is dropped when the depth or the node count is used up; so are the
            // siblings after it, which have the same depth and come later in the order.
            guard let normalizedChild = normalize(child, depth: depth + 1, kept: &kept) else {
                break
            }
            result.children.append(normalizedChild)
        }
        return result
    }
}
