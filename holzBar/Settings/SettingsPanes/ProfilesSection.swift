//
//  ProfilesSection.swift
//  holzBar
//

import SwiftUI

/// The Profiles group: saves the current layout as a profile and applies saved ones
/// (jordanbaird/Ice#26).
struct ProfilesSection: View {
    @Environment(AppState.self) private var appState
    var profiles: LayoutProfiles
    @State private var isNamingProfile = false
    @State private var newProfileName = ""
    @State private var renamedProfile: LayoutProfile?
    @State private var renamedName = ""
    @State private var importedProfile: SharedProfile?
    @State private var isShowingImportError = false
    @State private var refusedSave: LayoutProfileList.LimitViolation?

    /// Whether the alert about a refused save is shown.
    private var isShowingRefusedSave: Binding<Bool> {
        Binding {
            refusedSave != nil
        } set: { isPresented in
            if !isPresented {
                refusedSave = nil
            }
        }
    }

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
        SettingsGroup(
            SettingsCatalog.ProfilesAndHistoryPane.profiles,
            footnote: Text("At most 100 profiles. When the limit is reached, delete one to save or import a new one.")
        ) {
            ForEach(profiles.profiles) { profile in
                ProfileRows(
                    profiles: profiles,
                    profile: profile,
                    isCurrent: profile.name == profiles.currentProfileName
                ) {
                    renamedName = profile.name
                    renamedProfile = profile
                }
            }
            SettingsButtonRow(.profilesSaveAsProfile) {
                Button("Save as Profile…") {
                    newProfileName = profiles.currentProfileName ?? ""
                    isNamingProfile = true
                }
            }
            SettingsButtonRow(.profilesImport) {
                Button("Import Profile…") {
                    chooseProfileFile()
                }
                .disabled(profiles.isAtProfileLimit)
            }
            let controlledCount = appState.automation.controlledItemKeys.count
            if controlledCount > 0 {
                SettingsStateLine(
                    .info,
                    Text("\(controlledCount) items are controlled by rules. A profile leaves them where their rule puts them.")
                )
            }
            if profiles.isOverProfileLimit {
                SettingsStateLine(
                    .info,
                    Text("New profiles can be saved or imported while there are fewer than 100. Delete profiles to make room.")
                )
            } else if profiles.isAtProfileLimit {
                SettingsStateLine(
                    .info,
                    Text("You have the most profiles there can be. Delete one to save or import a new one.")
                )
            }
            SettingsNoteLine(Text("To apply a profile with a Focus, add the holzBar filter to that Focus in System Settings."))
        }
        .alert("Save Layout as Profile", isPresented: $isNamingProfile) {
            TextField("Name", text: $newProfileName)
            Button("Save") {
                if case .refused(let violation) = profiles.saveCurrentLayout(as: newProfileName) {
                    // After the naming alert has gone, so the second alert is not lost.
                    Task {
                        refusedSave = violation
                    }
                }
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
        .alert("Save Layout as Profile", isPresented: isShowingRefusedSave) {
            Button("OK", role: .cancel) { }
        } message: {
            switch refusedSave {
            case .tooLarge?:
                Text("The profiles would be too large to store. Delete one, then save again.")
            default:
                if profiles.isOverProfileLimit {
                    Text("New profiles can be saved or imported while there are fewer than 100. Delete profiles to make room.")
                } else {
                    Text("You have the most profiles there can be. Delete one to save or import a new one.")
                }
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

// MARK: - ProfileRows

/// One saved profile and its sub rows: apply it, bind it to a display or a Space, rename, share
/// or delete it.
private struct ProfileRows: View {
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

    /// What the profile is bound to, the title of its Bind menu.
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
        SettingsButtonRow(Text(verbatim: profile.name), small: isCurrent ? Text("Applied") : nil) {
            Button("Apply") {
                profiles.apply(profile)
            }
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
        SettingsButtonRow(
            Text("Bind"),
            info: Text("Bind a profile to a display or a Space to apply it when you connect the display or switch to the Space.")
        ) {
            Menu {
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
            } label: {
                bindingDescription ?? Text("Not bound")
            }
            .fixedSize()
        }
        .settingsSubRow()
        SettingsButtonRow {
            Button("Rename…", action: rename)
        }
        .settingsSubRow()
        SettingsButtonRow(
            Text("Share as a file"),
            info: Text("The file names the apps and the section of each. It holds no display, Wi-Fi, hotkey or other setting.")
        ) {
            Button("Share…") {
                isSharing = true
            }
        }
        .settingsSubRow()
        SettingsButtonRow(
            Text("Delete profile"),
            info: Text("The menu bar stays as it is. You can undo this with \u{2318}Z.")
        ) {
            Button("Delete…", role: .destructive) {
                isConfirmingDelete = true
            }
        }
        .settingsSubRow()
    }
}
