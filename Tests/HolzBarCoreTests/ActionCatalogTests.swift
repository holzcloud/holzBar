//
//  ActionCatalogTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("The command palette's catalog")
struct ActionCatalogTests {
    private static let commands: [PaletteCommand] = [
        PaletteCommand(kind: .action(.toggleZenMode), title: "Zen mode", keywords: ["quiet", "focus"]),
        PaletteCommand(kind: .action(.toggleKeepAwake), title: "Keep the Mac awake", keywords: ["sleep", "caffeinate"]),
        PaletteCommand(kind: .applyProfile("Work"), title: "Apply profile Work"),
        PaletteCommand(kind: .openItem("com.apple.controlcenter:Wi-Fi"), title: "Wi-Fi"),
        PaletteCommand(kind: .openSettings, title: "Open Settings"),
    ]

    private func firstKind(_ query: String) -> PaletteCommand.Kind? {
        let results = ActionCatalog.results(for: query, in: Self.commands)
        return results.first?.kind
    }

    @Test("An empty query keeps the fixed order")
    func emptyQuery() {
        let results = ActionCatalog.results(for: "  ", in: Self.commands)
        #expect(results == Self.commands)
    }

    @Test("Abbreviations, keywords and typos find a command")
    func finding() {
        #expect(firstKind("zen") == .action(.toggleZenMode))
        #expect(firstKind("caffeinate") == .action(.toggleKeepAwake))
        #expect(firstKind("kma") == .action(.toggleKeepAwake))
        #expect(firstKind("setings") == .openSettings)
        #expect(firstKind("qqqq") == nil)
    }

    @Test("The prefix leaves out the menu bar items")
    func actionsOnly() {
        let withItems = ActionCatalog.results(for: "wi", in: Self.commands)
        #expect(withItems.contains { !$0.isAction })
        let actions = ActionCatalog.results(for: ">wi", in: Self.commands)
        #expect(actions.allSatisfy { $0.isAction })
        let all = ActionCatalog.results(for: ">", in: Self.commands)
        #expect(all.count == 4)
    }

    @Test("The result is the same every time, and every command has its own identifier")
    func deterministic() {
        let first = ActionCatalog.results(for: "o", in: Self.commands)
        let second = ActionCatalog.results(for: "o", in: Self.commands)
        #expect(first == second)
        #expect(Set(Self.commands.map(\.id)).count == Self.commands.count)
    }
}
