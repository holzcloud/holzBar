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
        content
            .sheet(isPresented: Bindable(appState.navigationState).isTidyUpPresented) {
                TidyUpSheet()
            }
            .sheet(item: Bindable(appState.navigationState).itemRuleTarget) { target in
                ItemRuleSheet(target: target)
            }
    }

    @ViewBuilder
    private var content: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            HolzBarForm(spacing: 20) {
                header
                if #available(macOS 27.0, *) {
                    StuckOverflowWarning(concealer: appState.concealer27)
                }
                ItemRuleNoticesSection()
                LayoutDraftSection()
                layoutBars
                HolzBarSection {
                    HStack {
                        Text("Let holzBar propose which items to hide, from what it knows of the apps. You decide, and you can undo it.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Tidy Up…") {
                            appState.navigationState.isTidyUpPresented = true
                        }
                    }
                    .padding(10)
                }
                SearchSettingsSection(general: appState.settings.general, opens: appState.searchOpens)
                if !ScreenRecordingAccess.isGranted(appState) {
                    // Without Screen Recording the items show their apps' icons; the hint
                    // offers their real pictures.
                    HolzBarSection {
                        ScreenRecordingHint(feature: .layoutPane, appState: appState)
                    }
                }
                UsageSuggestionsSection(usage: appState.usage)
                LayoutProfilesSection(profiles: appState.profiles)
                ItemGroupsSection(groups: appState.itemGroups, itemManager: itemManager)
                SpacersSection(spacers: appState.spacers)
                LayoutHistorySection(snapshots: appState.snapshots)
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
                .font(HolzBarTheme.Typography.callout.weight(.medium))
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
            HolzBarSection(name.localized) {
                LayoutBar(imageCache: appState.imageCache, section: name)
                if appState.layoutEditor.newItemsSection == name {
                    NewItemsTile()
                }
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
                        .font(HolzBarTheme.Typography.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - ItemRuleNoticesSection

/// Tells the user which items a rule put back after a move by hand, so a put-back is never
/// silent. The notices stay until they are dismissed or the rule goes.
private struct ItemRuleNoticesSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let notices = appState.automation.itemRuleNotices
        Group {
            if !notices.isEmpty {
                HolzBarSection {
                    Text("Put Back by a Rule")
                        .font(.headline)
                } content: {
                    ForEach(notices) { notice in
                        row(for: notice)
                    }
                    Text("Its rule decides where the item is. A move by hand lasts only while the rule shows the item.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                }
            }
        }
        .onChange(of: notices) { old, new in
            // A put-back while Settings is open is announced once; a dismissal is not.
            if let newest = new.first, !old.contains(newest) {
                LayoutBarItemView.announce(sentence(for: newest))
            }
        }
    }

    /// "“Name” was put back in Hidden."
    private func sentence(for notice: ItemRuleNotice) -> String {
        let section = MenuBarSection.Name(profileIndex: notice.putBackIn)?.displayString ?? ""
        return String(localized: "\u{201C}\(notice.itemName)\u{201D} was put back in \(section).")
    }

    private func row(for notice: ItemRuleNotice) -> some View {
        HStack {
            Text(sentence(for: notice))
            Spacer()
            Button("Edit Rule…") {
                edit(notice)
            }
            Button("OK") {
                appState.automation.dismissItemRuleNotice(forKey: notice.itemKey)
            }
        }
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sentence(for: notice))
    }

    /// Opens the rule of the item in the sheet of this pane. The item's own name is used when
    /// it is still on the bar, since the notice shows it cut short.
    private func edit(_ notice: ItemRuleNotice) {
        let itemManager = appState.itemManager
        let name = itemManager.itemCache.managedItems
            .first { itemManager.identityKey(for: $0) == notice.itemKey }?.displayName
        appState.navigationState.itemRuleTarget = ItemRuleTarget(key: notice.itemKey, name: name ?? notice.itemName)
    }
}

// MARK: - LayoutProfilesSection

/// Saves the current layout as a profile and applies saved ones
/// (jordanbaird/Ice#26).
private struct LayoutProfilesSection: View {
    @Environment(AppState.self) private var appState
    var profiles: LayoutProfiles
    @State private var isNamingProfile = false
    @State private var newProfileName = ""
    @State private var renamedProfile: LayoutProfile?
    @State private var renamedName = ""
    @State private var importedProfile: SharedProfile?
    @State private var isShowingImportError = false

    /// Whether the import sheet is shown.
    private var isImporting: Binding<Bool> {
        Binding {
            importedProfile != nil
        } set: { isPresented in
            if !isPresented {
                importedProfile = nil
            }
        }
    }

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

    /// Asks for a profile file and reads it. The file is untrusted: it is checked in full, and
    /// nothing in it runs.
    private func chooseProfileFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
        guard
            size <= SharedProfile.maximumSize,
            let data = try? Data(contentsOf: url),
            case .success(let shared) = SharedProfile.decode(data, ownBundleIdentifier: Constants.bundleIdentifier)
        else {
            isShowingImportError = true
            return
        }
        importedProfile = shared
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
            let controlledCount = appState.automation.controlledItemKeys.count
            if controlledCount > 0 {
                Text("\(controlledCount) items are controlled by rules. A profile leaves them where their rule puts them.")
                    .foregroundStyle(.secondary)
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
                Button("Import Profile…") {
                    chooseProfileFile()
                }
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
            .sheet(isPresented: isImporting) {
                if let importedProfile {
                    ImportProfileSheet(shared: importedProfile, profiles: profiles)
                }
            }
            .alert("This file is not a holzBar profile.", isPresented: $isShowingImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("It could not be read, or it holds something a profile may not hold.")
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
    @State private var isConfirmingDelete = false
    @State private var isSharing = false

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
                Button("Share…") {
                    isSharing = true
                }
                Button("Delete…", role: .destructive) {
                    isConfirmingDelete = true
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
        .sheet(isPresented: $isSharing) {
            ShareProfileSheet(profile: profile)
        }
        .holzBarConfirmation(
            isPresented: $isConfirmingDelete,
            title: Text("Delete the profile \u{201C}\(profile.name)\u{201D}?"),
            message: Text("The menu bar stays as it is. You can undo this with \u{2318}Z."),
            confirmTitle: "Delete",
            isDestructive: true
        ) {
            profiles.delete(named: profile.name)
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

    /// The group's color for the color well; the primary color while it has none.
    private func colorBinding(for group: MenuBarItemGroup) -> Binding<Color> {
        Binding {
            group.color.map { Color(nsColor: $0) } ?? .primary
        } set: { color in
            groups.setColor(NSColor(color), for: group)
        }
    }

    /// The name of one of the group symbols, for the symbol menu and VoiceOver.
    private func symbolTitle(_ symbolName: String) -> Text {
        switch symbolName {
        case "square.grid.2x2": Text("Apps")
        case "folder": Text("Folder")
        case "tray": Text("Tray")
        case "briefcase": Text("Work")
        case "house": Text("Home")
        case "gamecontroller": Text("Games")
        case "music.note": Text("Music")
        case "network": Text("Network")
        case "bolt": Text("Power")
        case "cloud": Text("Cloud")
        case "wrench.and.screwdriver": Text("Tools")
        case "star": Text("Favorites")
        default: Text(verbatim: symbolName)
        }
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
                                Label {
                                    symbolTitle(symbol)
                                } icon: {
                                    Image(systemName: symbol)
                                }
                            }
                        }
                        Divider()
                        Button("Choose Image…") {
                            groups.chooseImage(for: group)
                        }
                        Button("Use Symbol") {
                            groups.useSymbol(for: group)
                        }
                        .disabled(group.imageFile == nil)
                    } label: {
                        Image(systemName: group.symbolName)
                            .accessibilityLabel(Text("Symbol"))
                            .accessibilityValue(symbolTitle(group.symbolName))
                    }
                    .fixedSize()
                    .help("Symbol")
                    ColorPicker("Color", selection: colorBinding(for: group), supportsOpacity: false)
                        .labelsHidden()
                        .help("The color of the group's icon and name")
                    if group.colorHex != nil {
                        Button {
                            groups.setColor(nil, for: group)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove the color")
                        .accessibilityLabel("Remove the color")
                    }
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
