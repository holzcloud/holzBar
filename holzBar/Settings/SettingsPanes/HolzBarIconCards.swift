//
//  HolzBarIconCards.swift
//  holzBar
//

import SwiftUI

/// The choice of holzBar's own menu bar icon as rows of the icon group: the picture cards (the
/// styles, a card for no icon), an image of the user's own, and whether that image adapts to the
/// menu bar.
///
/// "No icon" replaces the old switch for showing the icon; the stored settings are the same
/// (`showHolzBarIcon` and `holzBarIcon`). Without the icon the way back to Settings is a reopen
/// of the app, a link, or a hotkey, and ``HolzBarIconNote`` says which.
struct HolzBarIconCards: View {
    @Bindable var settings: GeneralSettings
    @State private var isImportingCustomIcon = false
    @State private var isPresentingError = false
    @State private var presentedError: LocalizedErrorWrapper?

    private var choice: MenuBarIconChoice {
        .current(showsIcon: settings.showHolzBarIcon, styleName: settings.holzBarIcon.name.rawValue)
    }

    /// The image sets on the cards: the styles, then the custom image the user chose last.
    private var imageSets: [ControlItemImageSet] {
        var sets = ControlItemImageSet.userSelectableHolzBarIcons
        if let custom = settings.lastCustomHolzBarIcon {
            sets.append(custom)
        }
        return sets
    }

    private var choices: [MenuBarIconChoice] {
        imageSets.map { MenuBarIconChoice.style($0.name.rawValue) } + [.none]
    }

    /// Writes what a card writes: a style shows the icon with that image set; "No icon" hides
    /// the icon and keeps the stored style.
    private var choiceBinding: Binding<MenuBarIconChoice> {
        Binding(
            get: { choice },
            set: { newChoice in
                switch newChoice {
                case .style(let name):
                    if let imageSet = imageSet(named: name) {
                        settings.holzBarIcon = imageSet
                        settings.showHolzBarIcon = true
                    }
                case .none:
                    settings.showHolzBarIcon = false
                }
            }
        )
    }

    /// Whether the user's own image is the icon in the menu bar.
    private var showsCustomImage: Bool {
        guard settings.showHolzBarIcon, case .custom = settings.holzBarIcon.name else {
            return false
        }
        return true
    }

    var body: some View {
        SettingsPictureCardRow(
            .generalIcon,
            selection: choiceBinding,
            values: choices,
            name: { value in
                if case .style(let name) = value, let imageSet = imageSet(named: name) {
                    Text(imageSet.name.localized)
                } else {
                    Text("No icon")
                }
            },
            picture: { value in
                if case .style(let name) = value, let imageSet = imageSet(named: name) {
                    MenuBarIconPicture(imageSet: imageSet)
                } else {
                    MenuBarNoIconPicture()
                }
            }
        )
        SettingsButtonRow(.generalCustomImage) {
            Button("Choose image…") {
                isImportingCustomIcon = true
            }
        }
        .fileImporter(isPresented: $isImportingCustomIcon, allowedContentTypes: [.image]) { result in
            importCustomIcon(result)
        }
        .alert(isPresented: $isPresentingError, error: presentedError) {
            Button("OK") {
                presentedError = nil
                isPresentingError = false
            }
        }
        SettingsToggleRow(
            .generalCustomIconTemplate,
            isOn: $settings.customHolzBarIconIsTemplate,
            small: Text("custom image only")
        )
        .settingsSubRow()
        .settingsDependent(on: showsCustomImage)
    }

    private func imageSet(named name: String) -> ControlItemImageSet? {
        imageSets.first { $0.name.rawValue == name }
    }

    private func importCustomIcon(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            // Data(contentsOf:) would fetch an http(s) URL; holzBar reads only files.
            guard url.isFileURL else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            if url.startAccessingSecurityScopedResource() {
                defer { url.stopAccessingSecurityScopedResource() }
                let data = try Data(contentsOf: url)
                // Stored as a scaled PNG, the only form decoded at launch (bitmaps, never
                // PDF or other documents, as the settings can come from another Mac).
                Task {
                    guard let png = await ControlItemImage.customIconPNG(from: data) else {
                        presentedError = LocalizedErrorWrapper(CocoaError(.fileReadCorruptFile))
                        isPresentingError = true
                        return
                    }
                    settings.holzBarIcon = ControlItemImageSet(name: .custom, image: .data(png))
                    settings.showHolzBarIcon = true
                }
            }
        } catch {
            presentedError = LocalizedErrorWrapper(error)
            isPresentingError = true
        }
    }
}

/// The note line of the icon group: what the icon does, or how to reach Settings without it.
struct HolzBarIconNote: View {
    @Environment(AppState.self) private var appState
    @Bindable var settings: GeneralSettings

    var body: some View {
        SettingsNoteLine(Text(verbatim: sentences.joined(separator: " ")))
    }

    private var sentences: [String] {
        guard settings.showHolzBarIcon else {
            return [
                String(localized: "Without the icon, open holzBar again from Finder, Launchpad or Spotlight to reach Settings, or use the holzbar://settings link."),
                hotkeySentence,
            ]
        }
        var sentences = [
            String(localized: "Click shows or hides the hidden items, ⌥-click the always-hidden ones, and right-click opens holzBar's menu."),
        ]
        if #available(macOS 27.0, *) {
            sentences.append(String(localized: "On macOS 27, hide items in Layout."))
        } else {
            sentences.append(String(localized: "⌘ Command-drag an item to the left of the holzBar icon to hide it."))
        }
        return sentences
    }

    /// Which hotkeys reach Settings too, from the ways that are available now.
    private var hotkeySentence: String {
        let hotkeys = appState.settings.hotkeys
        let ways = SettingsAccess.ways(
            hasSearchHotkey: hotkeys.hotkey(withAction: .searchMenuBarItems)?.keyCombination != nil,
            hasCommandPaletteHotkey: hotkeys.hotkey(withAction: .openCommandPalette)?.keyCombination != nil
        )
        switch (ways.contains(.searchPanel), ways.contains(.commandPalette)) {
        case (true, true):
            return String(localized: "The search and the command palette reach Settings too.")
        case (true, false):
            return String(localized: "The search reaches Settings too.")
        case (false, true):
            return String(localized: "The command palette reaches Settings too.")
        case (false, false):
            return String(localized: "A hotkey for the search or the command palette reaches Settings too.")
        }
    }
}
