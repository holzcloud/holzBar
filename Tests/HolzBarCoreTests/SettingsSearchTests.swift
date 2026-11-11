import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSearch")
struct SettingsSearchTests {
    private static func entry(
        _ id: String, _ pane: SettingsPaneID = .general, group: String = "Group",
        label: String, info: String? = nil, summary: String? = nil
    ) -> SettingsEntry {
        SettingsEntry(id: id, pane: pane, group: group, label: label, info: info, summary: summary)
    }

    @Test("A blank query finds nothing")
    func blankQuery() {
        let entries = [Self.entry("a", label: "Show icon")]
        #expect(SettingsSearch.results(for: "", in: entries).isEmpty)
        #expect(SettingsSearch.results(for: "  \t ", in: entries).isEmpty)
    }

    @Test("Every word must occur, in any order")
    func allWordsMustMatch() {
        let entries = [
            Self.entry("a", label: "Show Shelf", info: "Opens below the menu bar"),
            Self.entry("b", label: "Show icon")
        ]
        #expect(SettingsSearch.results(for: "SHELF below", in: entries).map(\.id) == ["a"])
        #expect(SettingsSearch.results(for: "show", in: entries).map(\.id) == ["a", "b"])
        #expect(SettingsSearch.results(for: "show nothing", in: entries).isEmpty)
    }

    @Test("Diacritics and case do not matter")
    func diacriticsAndCase() {
        let entries = [Self.entry("a", label: "Tastenkürzel zum Zeigen")]
        #expect(SettingsSearch.results(for: "tastenkurzel", in: entries).map(\.id) == ["a"])
        #expect(SettingsSearch.results(for: "ZEIGEN", in: entries).map(\.id) == ["a"])
    }

    @Test("Full-width and half-width kana match each other")
    func kanaWidth() {
        let half = [Self.entry("a", label: "ｱﾌﾟﾘ")]
        let full = [Self.entry("b", label: "アプリ")]
        #expect(SettingsSearch.results(for: "アプリ", in: half).map(\.id) == ["a"])
        #expect(SettingsSearch.results(for: "ｱﾌﾟﾘ", in: full).map(\.id) == ["b"])
    }

    @Test("Info, summary and group title are searched")
    func otherFields() {
        let entries = [
            Self.entry("a", group: "Zen mode and lock", label: "One"),
            Self.entry("b", label: "Two", summary: "Plays what you hear"),
            Self.entry("c", label: "Three", info: "Needs Accessibility")
        ]
        #expect(SettingsSearch.results(for: "zen", in: entries).map(\.id) == ["a"])
        #expect(SettingsSearch.results(for: "hear", in: entries).map(\.id) == ["b"])
        #expect(SettingsSearch.results(for: "accessibility", in: entries).map(\.id) == ["c"])
    }

    @Test("Label hits come before hits through info, summary or group, each in catalogue order")
    func ranking() {
        let entries = [
            Self.entry("a", label: "Other", info: "about the shelf"),
            Self.entry("b", label: "Shelf position"),
            Self.entry("c", label: "Third", summary: "shelf"),
            Self.entry("d", label: "Use Shelf")
        ]
        #expect(SettingsSearch.results(for: "shelf", in: entries).map(\.id) == ["b", "d", "a", "c"])
    }

    @Test("Results group by pane in sidebar order, only for panes with a hit")
    func grouping() {
        let results = [
            Self.entry("a", .hotkeys, label: "One"),
            Self.entry("b", .layout, label: "Two"),
            Self.entry("c", .hotkeys, label: "Three")
        ]
        let grouped = SettingsSearch.grouped(results)
        #expect(grouped.map(\.pane) == [.layout, .hotkeys])
        #expect(grouped[1].entries.map(\.id) == ["a", "c"])
        #expect(SettingsSearch.grouped([]).isEmpty)
    }
}
