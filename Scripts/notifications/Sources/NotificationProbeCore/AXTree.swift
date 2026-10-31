//
//  AXTree.swift
//  notifications
//
//  What the probe keeps of an Accessibility subtree: roles, subroles, identifiers and the
//  length of each text, never the text. Foundation only, so it is tested without a Mac's
//  Accessibility.
//

import Foundation

/// One node of a summarised subtree. It holds no text, only the length of the node's text.
public struct NodeInfo: Equatable, Sendable {
    public let depth: Int
    public let role: String?
    public let subrole: String?
    public let identifier: String?
    public let textLength: Int?

    public init(depth: Int, role: String?, subrole: String?, identifier: String?, textLength: Int?) {
        self.depth = depth
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.textLength = textLength
    }
}

/// The values the executable copies out of one `AXUIElement`: role, subrole, identifier, the
/// non-empty strings among its value, title and description, and its children.
public struct RawNode: Sendable {
    public var role: String?
    public var subrole: String?
    public var identifier: String?
    public var texts: [String]
    public var children: [RawNode]

    /// The first non-empty text, the one whose length is reported.
    public var text: String? { texts.first { !$0.isEmpty } }

    public init(
        role: String? = nil,
        subrole: String? = nil,
        identifier: String? = nil,
        texts: [String] = [],
        children: [RawNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.texts = texts
        self.children = children
    }
}

public enum AXTree {
    public static let defaultMaximumDepth = 8
    public static let defaultMaximumNodes = 200

    /// The subtree depth first, the root at depth 0, as `NodeInfo` values; nodes below
    /// `maximumDepth` and beyond `maximumNodes` are left out. Nothing but the length of
    /// each text is kept.
    public static func summarise(
        _ root: RawNode,
        maximumDepth: Int = defaultMaximumDepth,
        maximumNodes: Int = defaultMaximumNodes
    ) -> [NodeInfo] {
        var result = [NodeInfo]()
        visit(root, depth: 0, maximumDepth: maximumDepth, maximumNodes: maximumNodes) { node, depth in
            result.append(NodeInfo(
                depth: depth,
                role: node.role,
                subrole: node.subrole,
                identifier: node.identifier,
                textLength: node.text?.count
            ))
        }
        return result
    }

    /// Every non-empty text of the subtree in the same order and under the same caps, for the
    /// comparison with the known texts inside the process. It is never printed.
    public static func allTexts(
        _ root: RawNode,
        maximumDepth: Int = defaultMaximumDepth,
        maximumNodes: Int = defaultMaximumNodes
    ) -> [String] {
        var result = [String]()
        visit(root, depth: 0, maximumDepth: maximumDepth, maximumNodes: maximumNodes) { node, _ in
            result.append(contentsOf: node.texts.filter { !$0.isEmpty })
        }
        return result
    }

    /// The number of nodes that carry a text.
    public static func textNodeCount(_ nodes: [NodeInfo]) -> Int {
        nodes.filter { $0.textLength != nil }.count
    }

    /// An identifier as it may be printed without `--show-values`: a short word of letters,
    /// digits, dashes, underscores and colons, which is how the system names its elements.
    /// Anything else (a bundle identifier, a path, a sentence) could name an app or carry
    /// text, so only its length is printed.
    public static func printableIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else {
            return nil
        }
        let allowed = identifier.count <= 48 && identifier.unicodeScalars.allSatisfy {
            ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || "-_:".unicodeScalars.contains($0)
        }
        return allowed ? identifier : "other(\(identifier.count))"
    }

    private static func visit(
        _ node: RawNode,
        depth: Int,
        maximumDepth: Int,
        maximumNodes: Int,
        _ body: (RawNode, Int) -> Void
    ) {
        var visited = 0
        func walk(_ node: RawNode, _ depth: Int) {
            guard depth <= maximumDepth, visited < maximumNodes else {
                return
            }
            visited += 1
            body(node, depth)
            for child in node.children {
                walk(child, depth + 1)
            }
        }
        walk(node, depth)
    }
}

public enum TextMatcher {
    /// Whether the candidate contains the expected text, trimmed, without regard to case or
    /// accents. An empty expected text never matches.
    public static func matches(_ candidate: String, expected: String) -> Bool {
        let needle = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, !candidate.isEmpty else {
            return false
        }
        return candidate.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
