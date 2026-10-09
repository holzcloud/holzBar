//
//  SyncAlias.swift
//  holzBar
//

import Foundation

/// The alias rule for the units keyed by a menu bar item (analysis section 4.6.2, INV-A6).
///
/// `ItemIdentity.storedKey` can map a stored key such as `ns:Title` to `ns:#1` on this Mac,
/// because the owners whose item titles change are learned per Mac. A unit whose item key
/// this Mac maps to another key is aliased here: it is relayed only, never captured as a
/// deletion, never applied and never asked about. `ItemIconStore.setChoice` and
/// `ItemChangeWatcher.setRevealedOnChange` write the new key and remove the old one, and the
/// old unit is then aliased, so a re-key is never published as a deletion.
nonisolated enum SyncAlias {
    /// Whether this Mac maps the unit's item key to another key.
    ///
    /// Only the units of the families `ItemIcons`, `RevealOnChangeItems` and the `OpenItem:`
    /// hotkeys can be aliased.
    static func isAliased(_ key: SyncUnitKey, titleChangingOwners: Set<String>) -> Bool {
        guard let item = itemKey(of: key) else {
            return false
        }
        return ItemIdentity.storedKey(item, titleChangingOwners: titleChangingOwners) != item
    }

    /// The units of `keys` that are aliased here.
    static func aliasedUnits(among keys: Set<SyncUnitKey>, titleChangingOwners: Set<String>) -> Set<SyncUnitKey> {
        keys.filter { isAliased($0, titleChangingOwners: titleChangingOwners) }
    }

    /// The item key a unit of an item-keyed family names; `nil` for every other unit.
    private static func itemKey(of key: SyncUnitKey) -> String? {
        guard case .split(let family, let item) = key else {
            return nil
        }
        switch family {
        case Defaults.Key.itemIcons.rawValue, Defaults.Key.revealOnChangeItems.rawValue:
            return item
        case Defaults.Key.hotkeys.rawValue:
            guard item.hasPrefix(HotkeyTarget.itemPrefix) else {
                return nil
            }
            return String(item.dropFirst(HotkeyTarget.itemPrefix.count))
        default:
            return nil
        }
    }
}
