//
//  WhatsNewRelease.swift
//  holzBar
//

import Foundation

/// One New or Improved line of a release: a symbol, a short title and one sentence.
///
/// `title` and `detail` are English String Catalog keys; the window localizes them.
nonisolated struct WhatsNewItem: Identifiable, Equatable, Sendable {
    /// The name of an SF Symbol.
    let symbol: String
    /// A few words, as an English catalog key.
    let title: String
    /// One sentence, as an English catalog key.
    let detail: String

    var id: String { title }
}

/// One Fixed line of a release: a single sentence, as an English catalog key.
nonisolated struct WhatsNewFix: Identifiable, Equatable, Sendable {
    let text: String

    var id: String { text }
}

/// What one release brought, in the three groups the What's New window shows.
nonisolated struct WhatsNewRelease: Identifiable, Equatable, Sendable {
    /// The stable-numbered version, such as `1.0.1`; a beta shares its stable version's entry.
    let version: String
    let new: [WhatsNewItem]
    let improved: [WhatsNewItem]
    let fixed: [WhatsNewFix]

    var id: String { version }

    init(
        version: String,
        new: [WhatsNewItem] = [],
        improved: [WhatsNewItem] = [],
        fixed: [WhatsNewFix] = []
    ) {
        self.version = version
        self.new = new
        self.improved = improved
        self.fixed = fixed
    }
}
