//
//  QuestionOrderingTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("QuestionOrdering")
struct QuestionOrderingTests {
    /// The repository root, from this file's path (`Tests/HolzBarCoreTests/Sync/`).
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func row(_ unit: SyncUnitKey) -> SyncRow {
        SyncRow(
            unit: unit,
            local: nil,
            folder: [SyncRowValue(value: .value(.bool(true)), at: Date(timeIntervalSince1970: 0), source: .thisMac)],
            style: .twoWay
        )
    }

    /// Every ordering of `items`.
    private func permutations<T>(_ items: [T]) -> [[T]] {
        guard items.count > 1 else {
            return [items]
        }
        var result: [[T]] = []
        for index in items.indices {
            var rest = items
            let head = rest.remove(at: index)
            result += permutations(rest).map { [head] + $0 }
        }
        return result
    }

    // MARK: Categories

    @Test("Every synced key and every family has exactly one category")
    func everyUnitHasACategory() throws {
        let url = Self.repositoryRoot.appendingPathComponent(".github/sync-synced-keys.txt")
        let listed = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(!listed.isEmpty)
        for name in listed {
            let key = try #require(Defaults.Key(rawValue: name), "\(name) is a Defaults.Key")
            if case .knownApplications27 = SyncUnitTable.keyClass(key) {
                #expect(SyncRowCategory.category(ofKey: key) == nil, "The set of known applications is no row")
            } else {
                #expect(SyncRowCategory.category(ofKey: key) != nil, "\(name) has a category")
            }
        }
        for key in Defaults.Key.allCases {
            if case .local = SyncUnitTable.keyClass(key) {
                #expect(SyncRowCategory.category(ofKey: key) == nil, "\(key.rawValue) stays on this Mac and has no category")
            }
        }
    }

    @Test("Every whole unit and every family of the unit table is known to the ordering")
    func everyUnitOfTheTableIsKnown() {
        for key in Defaults.Key.allCases {
            switch SyncUnitTable.keyClass(key) {
            case .whole(let unit):
                #expect(SyncRowCategory.known(.whole(unit)) != nil, "\(unit)")
            case .split(let family):
                #expect(SyncRowCategory.known(.split(family: family, item: "x")) != nil, "\(family)")
            case .holzBarIconPart:
                #expect(SyncRowCategory.known(.whole(SyncUnitTable.holzBarIconUnit)) == .general)
            case .layout27:
                #expect(SyncRowCategory.known(.split(family: SyncUnitTable.layout27Family, item: "com.example")) == .arrangement)
            case .profiles:
                #expect(SyncRowCategory.known(.split(family: SyncUnitTable.profilesFamily, item: "id")) == .profiles)
            case .knownApplications27, .local:
                continue
            }
        }
        #expect(SyncRowCategory.known(.whole("FromANewerHolzBar")) == nil)
        #expect(SyncRowCategory.known(.split(family: "FromANewerHolzBar", item: "x")) == nil)
    }

    @Test("The categories follow the order of the contract")
    func categoryOrder() {
        let general = SyncRowCategory.category(of: .whole(Defaults.Key.showOnHover.rawValue))
        let advanced = SyncRowCategory.category(of: .whole(Defaults.Key.spacerCount.rawValue))
        let hotkeys = SyncRowCategory.category(of: .split(family: Defaults.Key.hotkeys.rawValue, item: "Toggle"))
        let appearance = SyncRowCategory.category(of: .whole(Defaults.Key.menuBarAppearanceConfigurationV2.rawValue))
        let groups = SyncRowCategory.category(of: .whole(Defaults.Key.itemGroups.rawValue))
        let items = SyncRowCategory.category(of: .split(family: Defaults.Key.revealRules.rawValue, item: "LowBattery"))
        let arrangement = SyncRowCategory.category(of: .split(family: SyncUnitTable.layout27Family, item: "com.example"))
        let profiles = SyncRowCategory.category(of: .split(family: SyncUnitTable.profilesFamily, item: "id"))
        #expect([general, advanced, hotkeys, appearance, groups, items, arrangement, profiles] == SyncRowCategory.allRawOrder)
        #expect(general < advanced && advanced < hotkeys && hotkeys < appearance && appearance < groups)
        #expect(groups < items && items < arrangement && arrangement < profiles)
        #expect(SyncRowCategory.category(of: .whole(SyncUnitTable.holzBarIconUnit)) == .general)
        #expect(SyncRowCategory.category(of: .split(family: Defaults.Key.itemIcons.rawValue, item: "a")) == .items)
        #expect(SyncRowCategory.category(of: .split(family: Defaults.Key.revealOnChangeItems.rawValue, item: "a")) == .items)
    }

    // MARK: Order

    @Test("The order is by category, then label, then unit key, and the same for every input order")
    func orderIsStable() {
        let units: [SyncUnitKey] = [
            .split(family: SyncUnitTable.profilesFamily, item: "p1"),
            .split(family: SyncUnitTable.layout27Family, item: "com.example.b"),
            .whole(Defaults.Key.itemGroups.rawValue),
            .split(family: Defaults.Key.hotkeys.rawValue, item: "Toggle"),
            .whole(Defaults.Key.spacerCount.rawValue),
            .whole(Defaults.Key.showOnHover.rawValue),
        ]
        let labels: [SyncUnitKey: String] = [
            units[0]: "Profile “Work”: name",
            units[1]: "Example: menu bar section",
            units[2]: "Groups",
            units[3]: "Hotkey: Toggle",
            units[4]: "Spacers",
            units[5]: "Show on hover",
        ]
        func label(_ row: SyncRow) -> String {
            labels[row.unit] ?? ""
        }
        let expected: [SyncUnitKey] = [units[5], units[4], units[3], units[2], units[1], units[0]]
        for order in permutations(units.map(row)) {
            #expect(SyncRowOrdering.sorted(order, label: label).map(\.unit) == expected)
        }
    }

    @Test("Labels inside a category are compared the way the Finder compares names")
    func labelsAreStandardCompared() {
        let units: [SyncUnitKey] = (0..<4).map { .split(family: Defaults.Key.itemIcons.rawValue, item: "item\($0)") }
        let labels = ["Item 10: icon", "Item 2: icon", "item 1: icon", "Álbum: icon"]
        let byUnit = Dictionary(uniqueKeysWithValues: zip(units, labels))
        let sorted = SyncRowOrdering.sorted(units.map(row)) { byUnit[$0.unit] ?? "" }
        #expect(sorted.map { byUnit[$0.unit] ?? "" } == ["Álbum: icon", "item 1: icon", "Item 2: icon", "Item 10: icon"])
    }

    @Test("Equal labels fall back to the unit key, in any input order")
    func equalLabelsUseTheUnitKey() {
        let units: [SyncUnitKey] = [
            .split(family: Defaults.Key.itemIcons.rawValue, item: "a"),
            .split(family: Defaults.Key.itemIcons.rawValue, item: "b"),
            .split(family: Defaults.Key.itemIcons.rawValue, item: "c"),
        ]
        for order in permutations(units.map(row)) {
            #expect(SyncRowOrdering.sorted(order) { _ in "Same" }.map(\.unit) == units)
        }
    }

    @Test("Category beats label: a late category never sorts before an early one")
    func categoryBeatsLabel() {
        let late = row(.split(family: SyncUnitTable.profilesFamily, item: "p"))
        let early = row(.whole(Defaults.Key.showOnHover.rawValue))
        let sorted = SyncRowOrdering.sorted([late, early]) { $0.unit == late.unit ? "A" : "Z" }
        #expect(sorted.map(\.unit) == [early.unit, late.unit])
    }

    @Test("No rows give no rows")
    func empty() {
        #expect(SyncRowOrdering.sorted([]) { _ in "" }.isEmpty)
    }
}

private extension SyncRowCategory {
    /// Every category, in the order of its raw value.
    static var allRawOrder: [SyncRowCategory] {
        [.general, .advanced, .hotkeys, .appearance, .groups, .items, .arrangement, .profiles]
    }
}
