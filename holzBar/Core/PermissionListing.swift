//
//  PermissionListing.swift
//  holzBar
//

import Foundation

/// Which permissions the Permissions group of Advanced lists (D-28, D-57, D-65).
///
/// A permission is listed when a switched-on module needs it, when it is granted so that it can
/// be revoked, or when it is always listed. Only the permissions holzBar has an object for can be
/// listed; the order is always the order of ``candidates``.
nonisolated enum PermissionListing {
    /// The permissions holzBar has an object for, in the order the group shows them.
    static let candidates: [ModulePermission] = [.accessibility, .screenRecording, .calendar, .bluetooth]

    /// The permissions listed even when no module needs them and they are not granted (D-65):
    /// holzBar's own finding, moving and hiding of items needs Accessibility, not only modules.
    static let alwaysListed: Set<ModulePermission> = [.accessibility]

    /// The permissions the switched-on modules of the catalog need.
    static func needs(ofEnabled moduleIDs: Set<String>, in catalog: [ModuleDescriptor]) -> Set<ModulePermission> {
        Set(catalog.filter { moduleIDs.contains($0.id) }.compactMap(\.permission))
    }

    /// The permissions to list, in candidate order.
    static func listed(
        needed: Set<ModulePermission>,
        granted: Set<ModulePermission>,
        alwaysListed: Set<ModulePermission> = PermissionListing.alwaysListed
    ) -> [ModulePermission] {
        let shown = needed.union(granted).union(alwaysListed)
        return candidates.filter { shown.contains($0) }
    }
}
