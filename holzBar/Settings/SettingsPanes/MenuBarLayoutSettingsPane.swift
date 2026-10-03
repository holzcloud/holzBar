//
//  MenuBarLayoutSettingsPane.swift
//  holzBar
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @Environment(AppState.self) var appState
    var itemManager: MenuBarItemManager

    private var hasItems: Bool {
        !itemManager.itemCache.managedItems.isEmpty
    }

    var body: some View {
        if !ScreenRecordingAccess.isGranted(appState) {
            missingScreenRecordingPermissions
        } else if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            HolzBarForm(spacing: 20) {
                header
                LayoutProfilesSection(profiles: appState.profiles)
                ItemGroupsSection(groups: appState.itemGroups, itemManager: itemManager)
                SpacersSection(spacers: appState.spacers)
                if #available(macOS 27.0, *) {
                    StuckOverflowWarning(concealer: appState.concealer27)
                }
                layoutBars
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HolzBarSection {
            VStack(spacing: 3) {
                Text("Drag to arrange your menu bar items into different sections.")
                    .font(.title3.bold())
                Group {
                    if #available(macOS 27.0, *) {
                        Text("macOS orders the items within each section.")
                    } else {
                        Text("Items can also be arranged by ⌘ Command + dragging them in the menu bar.")
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 20) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
        .opacity(hasItems ? 1 : 0.75)
        .blur(radius: hasItems ? 0 : 5)
        .allowsHitTesting(hasItems)
        .overlay {
            if !hasItems {
                loadingMenuBarItems
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("holzBar cannot arrange menu bar items in automatically hidden menu bars.")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var missingScreenRecordingPermissions: some View {
        ScreenRecordingHint(feature: .layoutPane, appState: appState)
            .font(.title3)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var loadingMenuBarItems: some View {
        VStack {
            Text("Loading menu bar items…")
            ProgressView()
        }
        .font(.title)
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            VStack(alignment: .leading) {
                Text(name.localized)
                    .font(.headline)
                    .padding(.leading, 8)

                LayoutBar(imageCache: appState.imageCache, section: name)
            }
        }
    }
}

/// Tells the user when macOS has left items folded away beside the notch.
///
/// macOS 27 folds the items that do not fit on the built-in display's bar. Concealing the
/// hidden applications frees the room again, but the fold is not reconsidered: the "«" that
/// reaches the folded items goes away with the items still behind it. Relaunching the
/// application whose item is missing lays it out again, which holzBar cannot do for the user —
/// Accessibility keeps reporting the frames of items it no longer draws, so which application
/// is missing cannot be told from them.
@available(macOS 27.0, *)
private struct StuckOverflowWarning: View {
    var concealer: Concealer27

    var body: some View {
        if concealer.isOverflowStuck {
            HolzBarSection {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Some items are folded away on the built-in display.")
                        .font(.headline)
                    Text("macOS stopped laying them out when holzBar freed the space beside the notch, and left no control to reach them. Quitting and reopening the application whose item is missing brings it back.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - LayoutProfilesSection

/// Saves the current layout as a profile and applies saved ones
/// (jordanbaird/Ice#26).
private struct LayoutProfilesSection: View {
    var profiles: LayoutProfiles
    @State private var isNamingProfile = false
    @State private var newProfileName = ""
    @State private var renamedProfile: LayoutProfile?
    @State private var renamedName = ""

    /// Whether the rename alert is shown.
    private var isRenaming: Binding<Bool> {
        Binding {
            renamedProfile != nil
        } set: { isPresented in
            if !isPresented {
                renamedProfile = nil
            }
        }
    }

    var body: some View {
        HolzBarSection("Profiles") {
            ForEach(profiles.profiles) { profile in
                LayoutProfileRow(
                    profiles: profiles,
                    profile: profile,
                    isCurrent: profile.name == profiles.currentProfileName
                ) {
                    renamedName = profile.name
                    renamedProfile = profile
                }
            }
            HStack {
                if profiles.profiles.isEmpty {
                    Text("Save the current layout as a profile, for example \u{201C}Work\u{201D} or \u{201C}Home\u{201D}.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Bind a profile to a display or a Space to apply it when you connect the display or switch to the Space.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save Current Layout…") {
                    newProfileName = profiles.currentProfileName ?? ""
                    isNamingProfile = true
                }
            }
            .alert("Save Layout as Profile", isPresented: $isNamingProfile) {
                TextField("Name", text: $newProfileName)
                Button("Save") {
                    profiles.saveCurrentLayout(as: newProfileName)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A profile with the same name is replaced. Apply it later from here, or with holzbar://profile/<name>.")
            }
            .alert("Rename Profile", isPresented: isRenaming) {
                TextField("Name", text: $renamedName)
                Button("Rename") {
                    if let renamedProfile {
                        profiles.rename(renamedProfile, to: renamedName)
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

// MARK: - LayoutProfileRow

/// One saved profile: apply it, bind it to a display or a Space, rename or delete it.
private struct LayoutProfileRow: View {
    var profiles: LayoutProfiles
    let profile: LayoutProfile
    let isCurrent: Bool
    let rename: () -> Void

    /// The screen of the Settings window, which "This Display" means.
    private var currentScreen: NSScreen? {
        NSScreen.main
    }

    /// The name of the bound display, or `nil` when it is not connected.
    private func displayName(for uuid: String) -> String? {
        NSScreen.screens.first { screen in
            Bridging.getDisplayUUIDString(for: screen.displayID) == uuid
        }?.localizedName
    }

    /// What the profile is bound to, for the line below its name.
    private var bindingDescription: Text? {
        let display = profile.displayUUID.map { uuid in
            displayName(for: uuid) ?? String(localized: "a display that is not connected")
        }
        switch (display, profile.spaceUUID) {
        case (let display?, _?):
            return Text("Bound to \(display) and a Space")
        case (let display?, nil):
            return Text("Bound to \(display)")
        case (nil, _?):
            return Text("Bound to a Space")
        case (nil, nil):
            return nil
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.name)
                    if isCurrent {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Applied")
                    }
                }
                if let bindingDescription {
                    bindingDescription
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Apply") {
                profiles.apply(profile)
            }
            Menu("Bind") {
                if let currentScreen, let uuid = Bridging.getDisplayUUIDString(for: currentScreen.displayID) {
                    Button("To This Display (\(currentScreen.localizedName))") {
                        profiles.bind(profile, toDisplay: uuid)
                    }
                }
                if let spaceUUID = Bridging.getActiveSpaceUUID() {
                    Button("To This Space") {
                        profiles.bind(profile, toSpace: spaceUUID)
                    }
                }
                Divider()
                Button("Remove Binding") {
                    profiles.unbind(profile)
                }
                .disabled(!profile.isBound)
            }
            .fixedSize()
            Menu {
                Button("Rename…", action: rename)
                Button("Delete", role: .destructive) {
                    profiles.delete(named: profile.name)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }
}

// MARK: - ItemGroupsSection

/// Creates groups of items behind icons of their own (jordanbaird/Ice#46).
private struct ItemGroupsSection: View {
    var groups: MenuBarItemGroups
    var itemManager: MenuBarItemManager
    @State private var isNamingGroup = false
    @State private var newGroupName = ""

    private var items: [MenuBarItem] {
        itemManager.itemCache.managedItems.filter { !$0.isControlItem }
    }

    var body: some View {
        HolzBarSection("Groups") {
            ForEach(groups.groups) { group in
                HStack {
                    Menu {
                        ForEach(MenuBarItemGroups.symbolNames, id: \.self) { symbol in
                            Button {
                                groups.setSymbol(symbol, for: group)
                            } label: {
                                Image(systemName: symbol)
                            }
                        }
                    } label: {
                        Image(systemName: group.symbolName)
                    }
                    .fixedSize()
                    Text(group.name)
                    Text("\(group.itemTags.count) items")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Items") {
                        ForEach(items, id: \.tag) { item in
                            Toggle(item.displayName, isOn: Binding(
                                get: { groups.contains(item, in: group) },
                                set: { _ in groups.toggle(item, in: group) }
                            ))
                        }
                    }
                    .fixedSize()
                    Button("Delete", role: .destructive) {
                        groups.deleteGroup(group)
                    }
                }
            }
            HStack {
                Text("A group puts several items behind an icon of its own.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("New Group…") {
                    newGroupName = ""
                    isNamingGroup = true
                }
            }
            .alert("New Group", isPresented: $isNamingGroup) {
                TextField("Name", text: $newGroupName)
                Button("Create") {
                    groups.addGroup(named: newGroupName)
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

// MARK: - SpacersSection

/// Adds empty items that make space between others (jordanbaird/Ice#91).
private struct SpacersSection: View {
    @Bindable var spacers: MenuBarSpacers

    var body: some View {
        HolzBarSection("Spacers") {
            Stepper(value: $spacers.count, in: 0...MenuBarSpacers.maximumCount) {
                Text("Spacers: \(spacers.count)")
            }
            .annotation("Empty items that add space between others. ⌘ Command-drag them where you want them, or arrange them below.")
            if spacers.count >= 1 {
                LabeledContent {
                    Slider(value: $spacers.width, in: 4...60, step: 2)
                        .frame(maxWidth: 200)
                } label: {
                    Text("Width: \(Int(spacers.width)) pt")
                }
            }
        }
    }
}
