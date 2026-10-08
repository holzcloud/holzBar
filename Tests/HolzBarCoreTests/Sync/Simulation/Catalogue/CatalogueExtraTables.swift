//
//  CatalogueExtraTables.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The unit tables and builds that the D3, judge and A2 scenarios of plan 28-12 need beyond `Catalogue.table`: the app's
/// real hotkey family (whose clash check reads real key combinations), the item icons (an item that changes its key), the
/// appearance (a setting two builds store differently), and a unit that only a newer build knows.
nonisolated enum CatalogueExtraTables {
    /// The app's real hotkey family and two of its actions: a hotkey is a stored `[key, modifiers]`.
    static let hotkeys = Defaults.Key.hotkeys.rawValue
    static let hotkeyToggle = "Hotkeys/ToggleHiddenSection"
    static let hotkeySearch = "Hotkeys/SearchMenuBarItems"

    /// The family of the item icons and the two keys one item has before and after its title changes.
    static let itemIcons = "ItemIcons"
    static let iconByTitle = "ItemIcons/ns:Title"
    static let iconByIndex = "ItemIcons/ns:#1"

    /// The appearance, as JSON data.
    static let appearance = SimMacRedesign.appearanceUnit

    /// A unit that only a newer build knows, and a unit both know whose newer build accepts a value this build refuses.
    static let future = "FutureSetting"
    static let mode = "ShelfMode"

    static func descriptor(
        _ name: String,
        cap: Int,
        family: Bool = false,
        scope: SyncGeneration? = nil,
        isSet: Bool = false,
        validate: @escaping @Sendable (String?, SyncValue) -> Bool = { _, _ in true }
    ) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [],
            cap: cap,
            maximumItems: family ? SyncDeviceFile.maximumEntriesPerFamily : nil,
            scope: scope,
            isSet: isSet,
            isFamily: family,
            measure: { $0.encodedSize },
            validate: validate
        )
    }

    /// A hotkey is stored data that decodes as a key combination.
    static let hotkeyDescriptor = descriptor(hotkeys, cap: 4 << 10, family: true) { _, value in
        guard case .data(let data) = value else { return false }
        return HotkeyStorage.decode(data) != nil
    }

    /// Every descriptor of the catalogue's table, again (it keeps its own private), plus the extras.
    static func descriptors(
        hotkeyFamily: Bool = false,
        itemIcons: Bool = false,
        appearance: Bool = false,
        newer: Bool = false
    ) -> [SyncUnitDescriptor] {
        var result = Catalogue.wholeUnits.map { descriptor($0, cap: 1 << 10) }
        result.append(descriptor(Catalogue.icon, cap: 256 << 10))
        result += Catalogue.pads.map { descriptor($0, cap: 600 << 10) }
        result.append(descriptor(SimEngineUnits.family, cap: 4 << 10, family: true))
        result.append(descriptor(SyncUnitTable.layout27Family, cap: 1 << 10, family: true, scope: .g27))
        result.append(descriptor(SyncUnitTable.profilesFamily, cap: 64 << 10, family: true, scope: .g27))
        result.append(descriptor(SyncUnitTable.knownApplicationsSet, cap: 0, scope: .g27, isSet: true))
        if hotkeyFamily { result.append(hotkeyDescriptor) }
        if itemIcons { result.append(descriptor(Self.itemIcons, cap: 4 << 10, family: true)) }
        if appearance { result.append(descriptor(Self.appearance, cap: 64 << 10)) }
        if newer {
            // The newer build knows a unit this one does not, and accepts every value of a unit that this one limits.
            result.append(descriptor(future, cap: 1 << 10))
            result.append(descriptor(mode, cap: 1 << 10))
        }
        return result
    }

    /// The table of the build that knows the extras of `descriptors(...)`.
    static func table(
        hotkeyFamily: Bool = false,
        itemIcons: Bool = false,
        appearance: Bool = false,
        newer: Bool = false,
        normalizers: SyncNormalizers = .canonical
    ) -> SyncUnitTable {
        SyncUnitTable(
            version: 1,
            descriptors: descriptors(hotkeyFamily: hotkeyFamily, itemIcons: itemIcons, appearance: appearance, newer: newer),
            normalizers: normalizers
        )
    }

    /// The normalizers of a build that decodes and re-encodes the appearance as the app's models do, which is what
    /// 0.0.7-beta2's load-time writer does to the stored value: a rewrite at launch then compares equal.
    static let modelNormalizers = SyncNormalizers(
        appearance: { value in
            guard case .data(let data) = value, let encoded = SimMacBeta2.reencoded(data, key: SimMacRedesign.appearanceUnit) else { return nil }
            return .data(encoded)
        },
        itemGroups: SyncNormalizers.canonicalJSON,
        holzBarIcon: SyncNormalizers.structuralIcon
    )

    /// The build of the older table of a world where a newer build runs next to it: it does not know `future` and refuses
    /// every value of `mode` but `"hidden"` and `"shown"`.
    static func olderTable() -> SyncUnitTable {
        var result = descriptors()
        result.append(descriptor(mode, cap: 1 << 10) { _, value in value == .string("hidden") || value == .string("shown") })
        return SyncUnitTable(version: 1, descriptors: result)
    }

    // MARK: Hotkeys

    /// The key combination every clash scenario uses (command, shift and one letter, in the app's own storage).
    static func combination(_ key: Int) -> SimValue {
        .data(HotkeyStorage.encode(key: key, modifiers: HotkeyStorage.knownModifierBits))
    }

    /// The engine's key of a hotkey unit.
    static func hotkeyKey(_ unit: String) -> SyncUnitKey? {
        SimEngineUnits.key(ofUnit: unit, hotkeyFamily: hotkeys)
    }

    /// The oracles that read bytes and files rather than the tokens of values: a hotkey is a bare combination that
    /// carries no token, so the oracles that follow tokens cannot judge a world of hotkeys.
    static let fileOracles = SimOracleSet.safety.only(["INV-S6", "INV-S8", "INV-PR2", "INV-B1", "INV-B9", "INV-N1", "INV-Z1", "INV-Z6"])

    /// The engine of a Mac that stores its hotkeys in the app's real family.
    static func hotkeyBrain(table: SyncUnitTable) -> SimMacRedesign {
        var brain = SimMacRedesign(table: table)
        brain.hotkeyFamily = hotkeys
        return brain
    }

    /// The scenarios of a file, or only those whose id is listed in the environment variable `CATALOGUE_ONLY` (comma
    /// separated, matched against the id and against the id up to its form suffix), which keeps a run of one scenario short
    /// while it is written or debugged. Without the variable every scenario runs.
    static func selected(_ scenarios: [CatalogueScenario]) -> [CatalogueScenario] {
        guard let only = ProcessInfo.processInfo.environment["CATALOGUE_ONLY"], !only.isEmpty else { return scenarios }
        let wanted = Set(only.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        return scenarios.filter { wanted.contains($0.id) || wanted.contains(String($0.id.split(separator: "/")[0])) }
    }
}
