//
//  AliasTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncAlias")
struct AliasTests {
    private let owners: Set<String> = ["ns"]

    @Test("An item icon whose key this Mac maps to another key is aliased")
    func iconIsAliased() {
        #expect(SyncAlias.isAliased(.split(family: "ItemIcons", item: "ns:Title"), titleChangingOwners: owners))
        #expect(SyncAlias.isAliased(.split(family: "ItemIcons", item: "ns"), titleChangingOwners: owners))
    }

    @Test("A key this Mac already uses is not aliased")
    func currentKeyIsNotAliased() {
        #expect(!SyncAlias.isAliased(.split(family: "ItemIcons", item: "ns:#1"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.split(family: "ItemIcons", item: "ns:Title"), titleChangingOwners: []))
        #expect(!SyncAlias.isAliased(.split(family: "ItemIcons", item: "other:Title"), titleChangingOwners: owners))
    }

    @Test("Reveal marks and the OpenItem hotkeys are aliased by their item key")
    func revealAndHotkeys() {
        #expect(SyncAlias.isAliased(.split(family: "RevealOnChangeItems", item: "ns:Title"), titleChangingOwners: owners))
        #expect(SyncAlias.isAliased(.split(family: "Hotkeys", item: "OpenItem:ns:Title"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.split(family: "Hotkeys", item: "OpenItem:ns:#2"), titleChangingOwners: owners))
    }

    @Test("Only the three item-keyed families are ever aliased")
    func otherUnitsAreNeverAliased() {
        #expect(!SyncAlias.isAliased(.split(family: "Hotkeys", item: "ToggleHiddenSection"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.split(family: "Hotkeys", item: "ApplyProfile:ns:Title"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.split(family: "RevealRules", item: "ns:Title"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.split(family: "l27", item: "ns:Title"), titleChangingOwners: owners))
        #expect(!SyncAlias.isAliased(.whole("ns:Title"), titleChangingOwners: owners))
    }

    @Test("aliasedUnits keeps the aliased units of a set")
    func aliasedUnitsOfASet() {
        let aliased = SyncUnitKey.split(family: "ItemIcons", item: "ns:Title")
        let kept: Set<SyncUnitKey> = [
            .whole("ShowOnHover"),
            .split(family: "ItemIcons", item: "other:Title"),
            .split(family: "ItemIcons", item: "ns:#1"),
        ]
        #expect(SyncAlias.aliasedUnits(among: kept.union([aliased]), titleChangingOwners: owners) == [aliased])
        #expect(SyncAlias.aliasedUnits(among: [], titleChangingOwners: owners).isEmpty)
    }
}
