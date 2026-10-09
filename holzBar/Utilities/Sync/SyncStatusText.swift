//
//  SyncStatusText.swift
//  holzBar
//

import AppKit
import Foundation

/// The texts of the sync status: the lines in Settings → Advanced, the hint at the top of holzBar's menu and its
/// button. The engine says what to show (`SyncView`); this only turns it into words, in the order of the UI contract.
/// Nothing here decides, reads a file or polls.
enum SyncStatusText {
    /// How a line is drawn: secondary text, or orange for the two lines the contract names.
    enum Tone: Hashable {
        case secondary
        case warning
    }

    /// One line of the label stack of the sync row.
    struct Line: Identifiable, Hashable {
        let id: String
        let text: String
        let tone: Tone
    }

    // MARK: Hint

    /// The sentence of a hint: the state line in Settings and the header of the hint in holzBar's menu.
    static func menuText(for hint: SyncHint) -> String {
        switch hint {
        case .restart, .choose:
            String(localized: "Settings changed on another Mac")
        case .chooseAfterJoin:
            String(localized: "Choose which settings this Mac uses")
        }
    }

    /// The title of the one button of a hint, in Settings and in the menu.
    static func buttonTitle(for hint: SyncHint) -> String {
        switch hint {
        case .restart:
            String(localized: "Restart")
        case .choose, .chooseAfterJoin:
            String(localized: "Choose Settings…")
        }
    }

    // MARK: Status lines

    /// The text of a status line.
    static func text(for line: SyncStatusLine) -> String {
        switch line {
        case .joining(let waitingFiles):
            if waitingFiles > 0 {
                String(localized: "Reading the sync folder… (\(waitingFiles) files not downloaded yet)")
            } else {
                String(localized: "Reading the sync folder…")
            }
        case .bystander(let rows):
            String(localized: "Your other Macs differ on \(rows) settings")
        case .waitingFiles(let count):
            String(localized: "Waiting for \(count) files in the sync folder to download.")
        case .newerFormat:
            String(localized: "A Mac uses a newer holzBar. Update holzBar to sync with it.")
        case .olderHolzBar:
            String(localized: "A Mac with an older holzBar still uses this folder. Update holzBar there to sync with it.")
        case .oversizeIcon:
            String(localized: "Your custom holzBar icon is too large to sync.")
        case .unreadableFile:
            String(localized: "A sync file in the folder can't be read.")
        case .unusableValue:
            String(localized: "A setting from a newer holzBar can't be used here.")
        case .skippedFiles(let count):
            String(localized: "holzBar skipped \(count) sync files in the folder because there are too many.")
        case .tooLargeToPublish:
            String(localized: "This Mac's settings are too large to sync. The folder keeps the previous ones.")
        }
    }

    /// The tone of a status line: orange only for a sync file that can't be read; every other line is secondary text.
    static func tone(of line: SyncStatusLine) -> Tone {
        switch line {
        case .unreadableFile:
            .warning
        case .joining, .bystander, .waitingFiles, .newerFormat, .olderHolzBar, .oversizeIcon, .unusableValue, .skippedFiles, .tooLargeToPublish:
            .secondary
        }
    }

    /// The place of a line in the label stack: the join, then the hint, then the bystander line, then the notes.
    private static func rank(of line: SyncStatusLine) -> Int {
        switch line {
        case .joining: 0
        case .bystander: 2
        case .waitingFiles: 3
        case .newerFormat: 4
        case .olderHolzBar: 5
        case .oversizeIcon: 6
        case .unreadableFile: 7
        case .unusableValue: 8
        case .tooLargeToPublish: 9
        case .skippedFiles: 10
        }
    }

    /// The place of the hint's sentence: after the join line and before the bystander line.
    private static let hintRank = 1

    /// The folder line: "Through <folder>", or the orange line that the folder can't be found.
    static func folderLine(name: String?) -> Line {
        if let name {
            Line(id: "folder", text: String(localized: "Through \(name)"), tone: .secondary)
        } else {
            Line(id: "folder", text: String(localized: "The sync folder cannot be found. Choose it again."), tone: .warning)
        }
    }

    /// Every line of the sync row under its title, after the folder line, in the order of the contract: the state line
    /// (the join, the hint, the bystander line), then the notes. Each is one sentence.
    static func lines(of view: SyncView) -> [Line] {
        var ranked: [(rank: Int, line: Line)] = view.lines.map { line in
            (rank(of: line), Line(id: "\(line)", text: text(for: line), tone: tone(of: line)))
        }
        if let hint = view.hint {
            ranked.append((hintRank, Line(id: "hint", text: menuText(for: hint), tone: .secondary)))
        }
        return ranked.sorted { $0.rank < $1.rank }.map(\.line)
    }

    /// Whether a join reads the folder or waits for the answer: Change… and Turn Off give way to Cancel.
    static func isJoining(_ view: SyncView) -> Bool {
        if view.hint == .chooseAfterJoin {
            return true
        }
        return view.lines.contains { line in
            if case .joining = line {
                return true
            }
            return false
        }
    }

    /// Whether a join reads the folder, and no question waits yet: Cancel is the only button.
    static func isReading(_ view: SyncView) -> Bool {
        isJoining(view) && view.hint != .chooseAfterJoin
    }
}

// MARK: - Rows of the question sheet

/// What the sheet needs from the app to name a hotkey's target, an item, an application and the picture of an icon.
struct SyncRowNames {
    /// The name of a hotkey's target as the Hotkeys settings show it.
    var hotkey: (HotkeyTarget) -> String
    /// The name of the item with this identity key, or the key when the item is not in the menu bar now.
    var item: (String) -> String
    /// The name of the application with this bundle identifier, or the identifier when the name is unknown.
    var application: (String) -> String
    /// The name and the picture of a stored holzBar icon, or `nil` when the data is not an image set.
    var icon: (Data) -> SyncIconPicture?
}

/// A holzBar icon as the sheet shows it.
struct SyncIconPicture {
    var name: String
    var image: NSImage?
    var isCustom: Bool
}

/// A value as a cell of the sheet shows it: text, or a small picture.
struct SyncValueDisplay {
    var text: String
    var image: NSImage?
    /// Whether the picture stands for the value alone; the text is for the help tag and VoiceOver.
    var hidesText: Bool

    init(_ text: String, image: NSImage? = nil, hidesText: Bool = false) {
        self.text = text
        self.image = image
        self.hidesText = hidesText
    }
}

extension SyncStatusText {
    // MARK: Dates

    /// "changed on 3 Oct, 14:02": the day, the month and the time of the Mac that made the change, and the year only when it
    /// is not this year. The date is the minting Mac's and is shown only; the other Mac is never named.
    static func dateText(for date: Date, now: Date = .now) -> String {
        let isThisYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        let formatted = if isThisYear {
            date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        } else {
            date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
        }
        return String(localized: "changed on \(formatted)")
    }

    // MARK: Labels

    /// The label of a row: the setting's own label, and for the units of a family what they belong to.
    static func rowLabel(for row: SyncRow, names: SyncRowNames) -> String {
        switch row.unit {
        case .whole(let name):
            return wholeLabel(name)
        case .split(let family, let item):
            switch family {
            case Defaults.Key.hotkeys.rawValue:
                return String(localized: "Hotkey: \(hotkeyTitle(of: item, names: names))")
            case Defaults.Key.itemIcons.rawValue:
                return String(localized: "\(names.item(item)): image")
            case Defaults.Key.revealRules.rawValue:
                return revealRuleLabel(item)
            case Defaults.Key.revealOnChangeItems.rawValue:
                return String(localized: "\(names.item(item)): Show When It Changes")
            case SyncUnitTable.layout27Family:
                return String(localized: "\(names.application(item)): menu bar section")
            case SyncUnitTable.profilesFamily:
                return profileLabel(row)
            default:
                return item
            }
        }
    }

    /// The name of the hotkey stored under `item`.
    private static func hotkeyTitle(of item: String, names: SyncRowNames) -> String {
        HotkeyTarget(storageKey: item).map(names.hotkey) ?? item
    }

    private static func revealRuleLabel(_ item: String) -> String {
        switch item {
        case "LowBattery":
            String(localized: "When the battery is low")
        case "LowBatteryThreshold":
            String(localized: "Low battery threshold")
        case "Offline":
            String(localized: "When the network connection is lost")
        default:
            item
        }
    }

    /// The label of a whole unit: the label its pane shows.
    private static func wholeLabel(_ unit: String) -> String {
        if unit == SyncUnitTable.holzBarIconUnit {
            return String(localized: "holzBar icon")
        }
        guard let key = Defaults.Key(rawValue: unit) else {
            return unit
        }
        return switch key {
        case .showHolzBarIcon: String(localized: "Show holzBar icon")
        case .useShelf: String(localized: "Use holzBar Shelf")
        case .shelfLocation: String(localized: "Location")
        case .shelfDisplays: String(localized: "Use on")
        case .showsNotchOverflowInShelf: String(localized: "Show items covered by the notch")
        case .showOnClick: String(localized: "Show on click")
        case .showOnHover: String(localized: "Show on hover")
        case .showOnScroll: String(localized: "Show on scroll")
        case .showOnHoverDelay: String(localized: "Show on hover delay")
        case .autoRehide: String(localized: "Automatically rehide")
        case .rehideStrategy: String(localized: "Strategy")
        case .rehideInterval: String(localized: "Rehide interval")
        case .tempShowInterval: String(localized: "Hide opened items again after")
        case .itemSpacingOffset: String(localized: "Menu bar item spacing")
        case .holzBarIconShowsCaptureDot: String(localized: "Show a dot on the holzBar icon while the microphone or camera is in use")
        case .enableAlwaysHiddenSection: String(localized: "Enable the always-hidden section")
        case .showAllSectionsOnUserDrag: String(localized: "Show all sections when ⌘ Command + dragging menu bar items")
        case .sectionDividerStyle: String(localized: "Section divider style")
        case .hideApplicationMenus: String(localized: "Hide app menus when showing menu bar items")
        case .keepsDockIconHidden: String(localized: "Keep the Dock icon hidden")
        case .enableSecondaryContextMenu: String(localized: "Enable secondary context menu")
        case .newItemsPlacement: String(localized: "Place new menu bar items in")
        case .keepLiveActivitiesVisible: String(localized: "Keep Live Activities visible")
        case .autoZenWhileSharingScreen: String(localized: "Turn on Zen mode while the screen is mirrored or shared")
        case .openHiddenItemsInMenuBar: String(localized: "Open hidden items in the menu bar")
        case .spacerCount: String(localized: "Spacers")
        case .spacerWidth: String(localized: "Spacer width")
        case .menuBarAppearanceConfigurationV2: String(localized: "Menu Bar Appearance")
        case .itemGroups: String(localized: "Groups")
        default: unit
        }
    }

    /// The values of a profile row that are values, not removals: this Mac's, then the others'.
    private static func profileValues(_ row: SyncRow) -> [SyncValue] {
        var values: [SyncValue] = []
        for shown in [row.local].compactMap({ $0 }) + row.folder {
            if case .value(let value) = shown.value {
                values.append(value)
            }
        }
        return values
    }

    /// Whether the name and the layout of a profile differ among the values a row shows.
    private static func profileDifferences(_ row: SyncRow) -> (name: Bool, layout: Bool) {
        let values = profileValues(row)
        let names = Set(values.compactMap { $0.dictionaryValue?["name"]?.stringValue })
        let layouts = Set(values.map { value -> SyncDigest in
            var layout: [String: SyncValue] = [:]
            for field in ["applicationSections", "knownApplications"] {
                layout[field] = value.dictionaryValue?[field]
            }
            return SyncValue.dictionary(layout).digest
        })
        return (names.count > 1, layouts.count > 1)
    }

    /// The name of the profile, from this Mac's value, else from the first value that has one.
    private static func profileName(_ row: SyncRow) -> String {
        for value in profileValues(row) {
            if let name = value.dictionaryValue?["name"]?.stringValue {
                return name
            }
        }
        return String(localized: "Layout Profile")
    }

    private static func profileLabel(_ row: SyncRow) -> String {
        let name = profileName(row)
        let differences = profileDifferences(row)
        if differences.name, differences.layout {
            return String(localized: "Profile “\(name)”: name and macOS 27 layout")
        }
        if differences.layout {
            return String(localized: "Profile “\(name)”: macOS 27 layout")
        }
        return String(localized: "Profile “\(name)”: name")
    }

    // MARK: Values

    /// A value of `row` as a cell shows it. `nil` is no value at all (this Mac holds none).
    static func display(of payload: SyncPayload?, in row: SyncRow, names: SyncRowNames) -> SyncValueDisplay {
        guard let payload else {
            return SyncValueDisplay(String(localized: "Not set"))
        }
        switch payload {
        case .deleted:
            return SyncValueDisplay(deletedText(for: row.unit))
        case .value(let value):
            return display(of: value, in: row, names: names)
        }
    }

    /// What a removed value reads as: the state the removal leaves.
    private static func deletedText(for unit: SyncUnitKey) -> String {
        guard case .split(let family, _) = unit else {
            return String(localized: "Not set")
        }
        switch family {
        case Defaults.Key.hotkeys.rawValue:
            return String(localized: "None")
        case SyncUnitTable.layout27Family:
            return String(localized: "Visible")
        case SyncUnitTable.profilesFamily:
            return String(localized: "Deleted")
        case Defaults.Key.revealOnChangeItems.rawValue:
            return String(localized: "Off")
        default:
            return String(localized: "Not set")
        }
    }

    private static func display(of value: SyncValue, in row: SyncRow, names: SyncRowNames) -> SyncValueDisplay {
        switch row.unit {
        case .whole(let unit):
            if unit == SyncUnitTable.holzBarIconUnit {
                return iconDisplay(value, names: names)
            }
            guard let key = Defaults.Key(rawValue: unit) else {
                return SyncValueDisplay(String(localized: "Changed"))
            }
            switch key {
            case .menuBarAppearanceConfigurationV2, .itemGroups:
                return SyncValueDisplay(String(localized: "Changed"))
            default:
                return SyncValueDisplay(scalarText(value, key: key))
            }
        case .split(let family, let item):
            switch family {
            case Defaults.Key.hotkeys.rawValue:
                return SyncValueDisplay(hotkeyText(value))
            case Defaults.Key.itemIcons.rawValue:
                return SyncValueDisplay(itemIconText(value))
            case Defaults.Key.revealRules.rawValue:
                return SyncValueDisplay(revealRuleText(value, item: item))
            case Defaults.Key.revealOnChangeItems.rawValue:
                return SyncValueDisplay(booleanText(value))
            case SyncUnitTable.layout27Family:
                return SyncValueDisplay(sectionText(value))
            case SyncUnitTable.profilesFamily:
                return SyncValueDisplay(profileText(value, row: row))
            default:
                return SyncValueDisplay(String(localized: "Changed"))
            }
        }
    }

    private static func booleanText(_ value: SyncValue) -> String {
        guard let flag = value.boolValue else {
            return String(localized: "Changed")
        }
        return flag ? String(localized: "On") : String(localized: "Off")
    }

    /// A single setting: On or Off, the label of a choice, or the number.
    private static func scalarText(_ value: SyncValue, key: Defaults.Key) -> String {
        switch value {
        case .bool:
            return booleanText(value)
        case .integer(let number):
            if let choice = choiceText(Int(number), key: key) {
                return choice
            }
            return number.formatted()
        case .real(let number):
            return number.formatted()
        default:
            return String(localized: "Changed")
        }
    }

    /// The label a pane shows for the choice `raw` of `key`, for the keys that hold a choice.
    private static func choiceText(_ raw: Int, key: Defaults.Key) -> String? {
        switch key {
        case .shelfLocation:
            HolzBarShelfLocation(rawValue: raw)?.title
        case .shelfDisplays:
            HolzBarShelfDisplays(rawValue: raw)?.title
        case .rehideStrategy:
            RehideStrategy(rawValue: raw)?.title
        case .sectionDividerStyle:
            SectionDividerStyle(rawValue: raw)?.title
        case .newItemsPlacement:
            NewItemsPlacement(rawValue: raw)?.title
        default:
            nil
        }
    }

    /// Key glyphs, such as "⌘⇧ H", or None for a hotkey that is cleared.
    private static func hotkeyText(_ value: SyncValue) -> String {
        guard case .data(let data) = value, let stored = HotkeyStorage.decode(data) else {
            return String(localized: "None")
        }
        return KeyCombination(key: KeyCode(rawValue: stored.key), modifiers: Modifiers(rawValue: stored.modifiers)).displayValue
    }

    private static func itemIconText(_ value: SyncValue) -> String {
        switch ItemIconChoice.parse(value.stringValue) {
        case .appIcon?:
            String(localized: "App icon")
        case .file?:
            String(localized: "Custom image")
        case nil:
            String(localized: "Not set")
        }
    }

    private static func revealRuleText(_ value: SyncValue, item: String) -> String {
        if item == "LowBatteryThreshold", let percent = value.integerValue {
            return (Double(percent) / 100).formatted(.percent)
        }
        return booleanText(value)
    }

    private static func sectionText(_ value: SyncValue) -> String {
        switch value.integerValue {
        case 0:
            String(localized: "Visible")
        case 1:
            String(localized: "Hidden")
        case 2:
            String(localized: "Always Hidden")
        default:
            String(localized: "Changed")
        }
    }

    /// A profile: its name when the names differ, else that its layout changed.
    private static func profileText(_ value: SyncValue, row: SyncRow) -> String {
        if profileDifferences(row).name, let name = value.dictionaryValue?["name"]?.stringValue {
            return name
        }
        return String(localized: "Changed")
    }

    /// A holzBar icon: a 20 pt thumbnail, for a custom image with the label "Custom icon" for VoiceOver.
    private static func iconDisplay(_ value: SyncValue, names: SyncRowNames) -> SyncValueDisplay {
        guard case .data(let data)? = value.dictionaryValue?[SyncNormalizers.iconField], let picture = names.icon(data) else {
            return SyncValueDisplay(String(localized: "Changed"))
        }
        if picture.isCustom {
            return SyncValueDisplay(String(localized: "Custom icon"), image: picture.image, hidesText: picture.image != nil)
        }
        return SyncValueDisplay(picture.name, image: picture.image)
    }

    // MARK: Clash

    /// The sentence of a hotkey clash: the combination, this Mac's action and the other Mac's.
    static func clashText(for row: SyncRow, partner: SyncUnitKey, names: SyncRowNames) -> String {
        func title(_ unit: SyncUnitKey) -> String {
            if case .split(_, let item) = unit {
                return hotkeyTitle(of: item, names: names)
            }
            return String(describing: unit)
        }
        let combination = display(of: row.folder.first?.value, in: row, names: names).text
        return String(localized: "\(combination): \(title(partner)) (this Mac) · \(title(row.unit)) (another Mac)")
    }
}
