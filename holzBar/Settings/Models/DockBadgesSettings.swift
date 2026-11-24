//
//  DockBadgesSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the Dock badges module's own settings: the apps whose Dock badge shows in the menu
/// bar, the groups of those apps, the switch that reads the badge and what an item shows while its
/// count is zero. The choice is stored as bundle identifiers, in the order chosen, and is exported
/// with the settings, and so are the groups and the zero mode; the switch uses a private macOS
/// interface, so it is off by default and stored on this Mac only. Each saves itself in its
/// `didSet`.
@MainActor
@Observable
final class DockBadgesSettings {
    /// The bundle identifiers of the chosen apps, at most ``DockBadgeApps/maximumCount``. Change
    /// it through ``setChosen(_:_:)``.
    private(set) var apps = [String]() {
        didSet {
            guard apps != oldValue else {
                return
            }
            Defaults.set(apps, forKey: .dockBadgeApps)
        }
    }

    /// The groups of chosen apps, at most ``DockBadgeGroupList/maximumCount``; an app is in at
    /// most one. Change them through the functions below.
    private(set) var groups = [DockBadgeGroup]() {
        didSet {
            guard groups != oldValue else {
                return
            }
            if let data = DockBadgeGroupList.encode(groups) {
                Defaults.set(data, forKey: .dockBadgeGroups)
            }
        }
    }

    /// Whether the badge on the Dock icons of the chosen apps is read: the Read badge counts
    /// switch. It uses a private macOS interface, so it is off by default and stored on this Mac
    /// only. A change makes the module start its read afresh.
    var readsCounts = false {
        didSet {
            guard readsCounts != oldValue else {
                return
            }
            Defaults.set(readsCounts, forKey: .dockBadgesReadsCounts)
            appState?.dockBadges.readsCountsDidChange()
        }
    }

    /// What an item shows while its count is zero: the one setting for every item. Dim by default.
    /// The module follows it through the badge inputs it observes.
    var zeroMode = DockBadgeZeroMode.dim {
        didSet {
            guard zeroMode != oldValue else {
                return
            }
            Defaults.set(zeroMode.rawValue, forKey: .dockBadgeZeroMode)
        }
    }

    @ObservationIgnored private weak var appState: AppState?

    /// Whether the app is chosen.
    func isChosen(_ bundleID: String) -> Bool {
        apps.contains(bundleID)
    }

    /// Chooses an app or takes it out of the choice. An app that is switched off leaves its group.
    func setChosen(_ bundleID: String, _ isChosen: Bool) {
        apps = DockBadgeApps.setting(bundleID, chosen: isChosen, in: apps)
        if !isChosen {
            groups = DockBadgeGroupList.removingApp(bundleID, from: groups)
        }
    }

    // MARK: Groups

    /// The group with the identifier, if there is one.
    func group(_ id: UUID) -> DockBadgeGroup? {
        groups.first { $0.id == id }
    }

    /// The group an app is in, if any.
    func group(containing bundleID: String) -> DockBadgeGroup? {
        groups.first { $0.apps.contains(bundleID) }
    }

    /// Makes a group without apps. The name is cleaned; an empty name and a list that already
    /// holds ``DockBadgeGroupList/maximumCount`` groups make none.
    ///
    /// - Returns: The new group's identifier, or `nil` when none was made.
    @discardableResult
    func addGroup(named name: String) -> UUID? {
        guard groups.count < DockBadgeGroupList.maximumCount, let name = DockBadgeGroupList.cleanedName(name) else {
            return nil
        }
        let id = UUID()
        groups.append(DockBadgeGroup(id: id, name: name, apps: []))
        return id
    }

    /// Renames a group. The name is cleaned; an empty name keeps the old one.
    func rename(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }), let name = DockBadgeGroupList.cleanedName(name) else {
            return
        }
        groups[index].name = name
    }

    /// Sets the apps of a group to the given chosen apps. An app that joins leaves the group it
    /// was in; an app that is not chosen is never added.
    func setApps(_ bundleIDs: [String], of id: UUID) {
        guard let current = group(id) else {
            return
        }
        var updated = groups
        for bundleID in current.apps where !bundleIDs.contains(bundleID) {
            updated = DockBadgeGroupList.removingApp(bundleID, from: updated)
        }
        for bundleID in bundleIDs where isChosen(bundleID) {
            updated = DockBadgeGroupList.assigning(bundleID, to: id, in: updated)
        }
        groups = updated
    }

    /// Takes an app into a group or out of it.
    func setMember(_ bundleID: String, of id: UUID, isMember: Bool) {
        guard let current = group(id) else {
            return
        }
        let others = current.apps.filter { $0 != bundleID }
        setApps(isMember ? others + [bundleID] : others, of: id)
    }

    /// Deletes a group; its apps stay chosen and show as items of their own again.
    ///
    /// - Returns: The group and its former index, for an undo; `nil` if it was not there.
    @discardableResult
    func deleteGroup(_ id: UUID) -> (group: DockBadgeGroup, index: Int)? {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return (groups.remove(at: index), index)
    }

    /// Puts a deleted group back at its former index, without the apps another group took since,
    /// unless a group with its identifier is there again.
    func reinsertGroup(_ group: DockBadgeGroup, at index: Int) {
        groups = DockBadgeGroupList.reinserting(group, at: index, into: groups)
    }

    /// Loads the stored switch, choice, groups and zero mode; a stored list that holds anything but
    /// valid, unique bundle identifiers is cut down to those, and the groups are validated again.
    func performSetup(with appState: AppState) {
        self.appState = appState
        Defaults.ifPresent(key: .dockBadgesReadsCounts, assign: &readsCounts)
        Defaults.ifPresent(key: .dockBadgeApps) { (stored: [String]) in
            apps = DockBadgeApps.sanitized(stored)
        }
        // The groups are validated as an imported list is; a member that is not chosen shows nowhere.
        Defaults.ifPresent(key: .dockBadgeGroups) { (stored: Data) in
            groups = DockBadgeGroupList.decode(stored)
        }
        // Anything stored that is not one of the two modes reads as the default.
        Defaults.ifPresent(key: .dockBadgeZeroMode) { (stored: Int) in
            zeroMode = DockBadgeZeroMode.stored(stored)
        }
    }
}
