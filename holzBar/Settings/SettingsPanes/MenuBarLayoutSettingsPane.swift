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
            SettingsPaneHost(.layout) {
                topRow
                menuBarGroup
                LayoutDraftSection()
                noticesGroup
                UsageSuggestionsSection(usage: appState.usage)
                SearchSettingsSection(general: appState.settings.general, opens: appState.searchOpens)
                if !ScreenRecordingAccess.isGranted(appState) {
                    // Without Screen Recording the items show their apps' icons; the group
                    // offers their real pictures.
                    picturesGroup
                }
            }
            .onChange(of: appState.automation.itemRuleNotices) { old, new in
                // A put-back while Settings is open is announced once; a dismissal is not.
                if let newest = new.first, !old.contains(newest) {
                    LayoutBarItemView.announce(ItemRuleNoticeRows.sentence(for: newest))
                }
            }
            .onChange(of: commandDragNoticeCount) {
                // Every drop that arrives while Settings is open is announced, also one equal to
                // an earlier notice; notices that existed when the pane opened and dismissals
                // are not.
                if #available(macOS 27.0, *), let newest = appState.commandDragSection27.notices.first {
                    LayoutBarItemView.announce(CommandDragNoticeRows.sentence(for: newest))
                }
            }
        }
    }

    /// The row above the groups: Tidy Up… (Phase 90 puts Bars | List and the filter before it and
    /// Undo after it). The id lets a search hit scroll to it.
    private var topRow: some View {
        HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
            Picker(selection: Bindable(appState.navigationState).layoutView) {
                Text("Bars").tag(LayoutPaneView.bars)
                Text("List").tag(LayoutPaneView.list)
            } label: {
                Text(SettingsEntry.layoutView.label)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .id(SettingsEntry.layoutView.id)
            SettingsFilterField(
                text: Bindable(appState.navigationState).layoutFilter,
                prompt: Text("Filter"),
                label: Text(SettingsEntry.layoutFilter.label)
            )
            .fixedSize()
            .id(SettingsEntry.layoutFilter.id)
            Spacer(minLength: 0)
            Button("Tidy Up…", systemImage: "wand.and.stars") {
                appState.navigationState.isTidyUpPresented = true
            }
            .id(SettingsEntry.layoutTidyUp.id)
            if let info = SettingsEntry.layoutTidyUp.info {
                SettingsInfoButton(Text(info))
            }
            Button("Undo", systemImage: "arrow.uturn.backward") {
                appState.layoutUndo.undo()
            }
            .disabled(!appState.layoutUndo.canUndo)
            .help(Text("Undo the last change"))
            .id(SettingsEntry.layoutUndo.id)
        }
    }

    private var commandDragNoticeCount: Int {
        if #available(macOS 27.0, *) {
            return appState.commandDragSection27.noticeCount
        }
        return 0
    }

    private var hasNotices: Bool {
        if !appState.automation.itemRuleNotices.isEmpty {
            return true
        }
        if #available(macOS 27.0, *) {
            return !appState.commandDragSection27.notices.isEmpty || appState.concealer27.isOverflowStuck
        }
        return false
    }

    /// What was put back by a rule, what a Command-drag did and the folded-away warning; the
    /// group exists only while there is something to report.
    @ViewBuilder
    private var noticesGroup: some View {
        if hasNotices {
            SettingsGroup(SettingsCatalog.LayoutPane.notices) {
                ItemRuleNoticeRows()
                if #available(macOS 27.0, *) {
                    CommandDragNoticeRows()
                    StuckOverflowWarning(concealer: appState.concealer27)
                }
            }
        }
    }

    private var picturesGroup: some View {
        SettingsGroup(SettingsCatalog.LayoutPane.pictures) {
            SettingsStateLine(.warning, Text("Screen Recording is not allowed: the bars show app icons instead of pictures."))
            SettingsButtonRow(.layoutPictures) {
                Button("Allow Screen Recording…") {
                    Task {
                        await ScreenRecordingAccess.request(for: .layoutPane, appState: appState)
                    }
                }
            }
        }
    }

    private var menuBarGroup: some View {
        SettingsGroup(SettingsCatalog.LayoutPane.menuBar, footnote: barsFootnote) {
            if !hasItems {
                SettingsStateLine(.info, Text("Loading menu bar items…")) {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if appState.navigationState.layoutView == .list {
                // The list in place of the three bars; the rows below stay (D-08).
                LayoutListView()
            } else {
                layoutBar(for: .visible)
                layoutBar(for: .hidden)
            }
            SettingsToggleRow(
                .layoutAlwaysHidden,
                isOn: Bindable(appState.settings.advanced).enableAlwaysHiddenSection,
                small: Text("third section")
            )
            if appState.navigationState.layoutView == .bars {
                layoutBar(for: .alwaysHidden)
            }
            SettingsPickerRow(.layoutNewItems, selection: newItemsBinding) {
                Text(NewItemsPlacement.visible.localized).tag(NewItemsPlacement.visible)
                Text(NewItemsPlacement.hidden.localized).tag(NewItemsPlacement.hidden)
                if appState.settings.advanced.enableAlwaysHiddenSection {
                    Text(NewItemsPlacement.alwaysHidden.localized).tag(NewItemsPlacement.alwaysHidden)
                }
                Text(NewItemsPlacement.systemDefault.localized).tag(NewItemsPlacement.systemDefault)
            }
            .disabled(appState.layoutEditor.isApplying)
            if #available(macOS 27.0, *) {
                SettingsNoteLine(Text("Items can be sorted by dragging them within a section."))
                SettingsNoteLine(Text("macOS 27 hides whole apps: the items of one app always move together."))
            }
        }
    }

    /// What the pop-up New items go to shows and how it writes (D-40): a section waits for Apply
    /// in draft mode, where macOS puts them is written at once.
    private var newItemsBinding: Binding<NewItemsPlacement> {
        Binding(
            get: { appState.layoutEditor.newItemsPlacement },
            set: { appState.layoutEditor.setNewItemsPlacement($0) }
        )
    }

    private var barsFootnote: Text {
        let keys = Text("With the keyboard, ⌥ Option and an arrow key move the selected item, and ⌘1, ⌘2 and ⌘3 put it in a section.")
        if #available(macOS 27.0, *) {
            return Text("Drag an item into its section.")
                + Text(verbatim: " ")
                + keys
        } else {
            return Text("Drag an item into its section.")
                + Text(verbatim: " ")
                + Text("You can also ⌘ Command-drag an item in the menu bar: to the left of the holzBar icon, it is hidden.")
                + Text(verbatim: " ")
                + keys
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        SettingsPaneHost(.layout) {
            AutoHiddenMenuBarState(kind: .arrange)
        }
    }

    @ViewBuilder
    private func layoutBar(for name: MenuBarSection.Name) -> some View {
        if
            let section = appState.menuBarManager.section(withName: name),
            section.isEnabled
        {
            SettingsBlockRow {
                VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
                    Text(name.localized)
                        .font(HolzBarTheme.Typography.callout.weight(.semibold))
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    LayoutBar(imageCache: appState.imageCache, section: name)
                    if appState.layoutEditor.newItemsSection == name {
                        NewItemsTile()
                    }
                }
            }
            .settingsDependent(on: hasItems)
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
            SettingsStateLine(.warning, Text("Some items are folded away on the built-in display.")) {
                SettingsInfoButton(Text("macOS stopped laying them out when holzBar freed the space beside the notch, and left no control to reach them. Quitting and reopening the application whose item is missing brings it back."))
            }
        }
    }
}

// MARK: - ItemRuleNoticeRows

/// Tells the user which items a rule put back after a move by hand, so a put-back is never
/// silent. The notices stay until they are dismissed or the rule goes.
private struct ItemRuleNoticeRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ForEach(appState.automation.itemRuleNotices) { notice in
            SettingsButtonRow(
                Text(verbatim: Self.sentence(for: notice)),
                info: Text("Its rule decides where the item is. A move by hand lasts only while the rule shows the item.")
            ) {
                Button("Edit Rule…") {
                    edit(notice)
                }
                Button("OK") {
                    appState.automation.dismissItemRuleNotice(forKey: notice.itemKey)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.sentence(for: notice))
        }
    }

    /// "“Name” was put back in Hidden."
    static func sentence(for notice: ItemRuleNotice) -> String {
        let section = MenuBarSection.Name(profileIndex: notice.putBackIn)?.displayString ?? ""
        return String(localized: "\u{201C}\(notice.itemName)\u{201D} was put back in \(section).")
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

// MARK: - CommandDragNoticeRows

/// Tells the user what a Command-drag across the holzBar icon did, so a drop is never silent: an
/// app's new section with Undo, or why a drop changed nothing. The notices stay until they are
/// dismissed or the list is full, and are never stored.
@available(macOS 27.0, *)
private struct CommandDragNoticeRows: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ForEach(appState.commandDragSection27.notices) { notice in
            SettingsButtonRow(Text(verbatim: Self.sentence(for: notice)), info: info(for: notice)) {
                if case .set = notice.kind {
                    Button("Undo") {
                        appState.commandDragSection27.undo(notice)
                    }
                }
                Button("OK") {
                    appState.commandDragSection27.dismiss(notice)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.sentence(for: notice))
        }
    }

    /// The explanation fits a drop that set a section; for one that changed nothing it would be
    /// wrong.
    private func info(for notice: CommandDragNotice) -> Text? {
        if case .set = notice.kind {
            return Text("The section is per app: every item of the app changed with it.")
        }
        return nil
    }

    /// "“Name” is now hidden.", or the reason a drop changed nothing; the nameless notice of an
    /// item macOS keeps in place names no app.
    static func sentence(for notice: CommandDragNotice) -> String {
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
}
