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
                if #available(macOS 27.0, *) {
                    CommandDragNoticesSection()
                }
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
                        HStack(spacing: HolzBarTheme.Spacing.sm) {
                            Text("Items can be sorted by dragging them within a section.")
                        }
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

// MARK: - CommandDragNoticesSection

/// Tells the user what a Command-drag across the holzBar icon did, so a drop is never silent: an
/// app's new section with Undo, or why a drop changed nothing. The notices stay until they are
/// dismissed or the list is full, and are never stored.
@available(macOS 27.0, *)
private struct CommandDragNoticesSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let notices = appState.commandDragSection27.notices
        Group {
            if !notices.isEmpty {
                HolzBarSection {
                    Text("Set by Command-Drag")
                        .font(.headline)
                } content: {
                    ForEach(notices) { notice in
                        row(for: notice)
                    }
                    Text("The section is per app: every item of the app changed with it.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                }
            }
        }
        .onChange(of: appState.commandDragSection27.noticeCount) {
            // Every drop that arrives while Settings is open is announced, also one equal to an
            // earlier notice; notices that existed when the pane opened and dismissals are not.
            if let newest = appState.commandDragSection27.notices.first {
                LayoutBarItemView.announce(sentence(for: newest))
            }
        }
    }

    /// "“Name” is now hidden.", or the reason a drop changed nothing; the nameless notice of an
    /// item macOS keeps in place names no app.
    private func sentence(for notice: CommandDragNotice) -> String {
        let name = notice.itemName
        switch notice.kind {
        case .set(_, let section):
            return section == .visible
                ? String(localized: "\u{201C}\(name)\u{201D} is now visible.")
                : String(localized: "\u{201C}\(name)\u{201D} is now hidden.")
        case .kept(.rule):
            return String(localized: "\u{201C}\(name)\u{201D} stays where it is: a rule controls it.")
        case .kept(.pinned):
            return String(localized: "\u{201C}\(name)\u{201D} stays where it is: macOS keeps it in place.")
        case .kept(.system):
            return String(localized: "macOS keeps its own items in place: the drop changed nothing.")
        }
    }

    private func row(for notice: CommandDragNotice) -> some View {
        HStack {
            Text(sentence(for: notice))
            Spacer()
            if case .set = notice.kind {
                Button("Undo") {
                    appState.commandDragSection27.undo(notice)
                }
            }
            Button("OK") {
                appState.commandDragSection27.dismiss(notice)
            }
        }
        .padding(10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sentence(for: notice))
    }
}
