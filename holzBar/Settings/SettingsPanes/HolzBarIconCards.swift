//
//  HolzBarIconCards.swift
//  holzBar
//

import SwiftUI

/// The choice of holzBar's own menu bar icon as a row of picture cards: the styles, a card for no
/// icon, and an image of the user's own.
///
/// "No icon" replaces the old switch for showing the icon; the stored settings are the same
/// (`showHolzBarIcon` and `holzBarIcon`). Without the icon the way back to Settings is a reopen
/// of the app, a link, or a hotkey, and the note under the cards says which.
struct HolzBarIconCards: View {
    @Environment(AppState.self) private var appState
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

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            LazyVGrid(columns: PictureCardGrid.columns, spacing: PictureCardGrid.gap) {
                ForEach(imageSets) { imageSet in
                    PictureCard(
                        imageSet.name.localized,
                        isSelected: choice == .style(imageSet.name.rawValue)
                    ) {
                        settings.holzBarIcon = imageSet
                        settings.showHolzBarIcon = true
                    } picture: {
                        MenuBarIconPicture(imageSet: imageSet)
                    }
                }
                PictureCard("No icon", isSelected: choice == .none) {
                    settings.showHolzBarIcon = false
                } picture: {
                    MenuBarNoIconPicture()
                }
            }
            HStack {
                Button("Choose image…") {
                    isImportingCustomIcon = true
                }
                Spacer()
            }
            if case .custom = settings.holzBarIcon.name {
                customIconToggle
            }
            note
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
    }

    private var customIconToggle: some View {
        Toggle("Custom icon uses dynamic appearance", isOn: $settings.customHolzBarIconIsTemplate)
            .annotation(
                """
                Display the icon as a monochrome image that dynamically adjusts to match \
                the menu bar's appearance. This setting removes all color from the icon, \
                but ensures consistent rendering with both light and dark backgrounds.
                """
            )
    }

    /// One calm sentence under the cards: what the icon does, or how to reach Settings without it.
    @ViewBuilder
    private var note: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            if choice == .none {
                Text("Without the icon, open holzBar again from Finder, Launchpad or Spotlight to reach Settings, or use the holzbar://settings link.")
                hotkeyNote
            } else {
                Text("Click to show hidden menu bar items. Right-click to access holzBar's settings.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Which hotkeys reach Settings too, from the ways that are available now.
    @ViewBuilder
    private var hotkeyNote: some View {
        let hotkeys = appState.settings.hotkeys
        let ways = SettingsAccess.ways(
            hasSearchHotkey: hotkeys.hotkey(withAction: .searchMenuBarItems)?.keyCombination != nil,
            hasCommandPaletteHotkey: hotkeys.hotkey(withAction: .openCommandPalette)?.keyCombination != nil
        )
        switch (ways.contains(.searchPanel), ways.contains(.commandPalette)) {
        case (true, true):
            Text("The search and the command palette reach Settings too.")
        case (true, false):
            Text("The search reaches Settings too.")
        case (false, true):
            Text("The command palette reaches Settings too.")
        case (false, false):
            Text("A hotkey for the search or the command palette reaches Settings too.")
        }
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
