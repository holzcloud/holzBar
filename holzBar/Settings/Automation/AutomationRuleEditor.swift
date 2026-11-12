//
//  AutomationRuleEditor.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The editor of one rule, shown under its row: the name, the conditions and what the rule
/// does.
struct AutomationRuleEditor: View {
    @Environment(AppState.self) private var appState
    @Binding var rule: AutomationRule
    let profileNames: [String]
    /// Puts the keyboard focus into the Name field, for a rule that was just added.
    let focusesName: Bool
    /// The name of the item when the rule is the rule of one item (made from the item's menu in
    /// Menu Bar Layout). The editor then has no action to choose: the rule shows that item only
    /// while its conditions hold.
    var itemName: String?
    let onDelete: () -> Void

    @FocusState private var isNameFocused: Bool
    @State private var isAskingForWiFiName = false
    @State private var wifiName = ""
    @State private var isAskingForBluetooth = false
    @State private var bluetoothNames: [String]?

    /// What a rule can do, as the choices of one menu.
    private enum ActionChoice: Hashable {
        case profile
        case mood
        case hiddenSection
        case alwaysHiddenSection
        case zenOn
        case zenOff
        case keepAwake
        case allowSleep
        case showItem
        case runScript
    }

    /// Deletes a condition at once; the undo toast puts it back at its place (D-04, D-16).
    private func deleteClause(_ clause: AutomationClause) {
        guard let index = rule.clauses.firstIndex(where: { $0.id == clause.id }) else {
            return
        }
        rule.clauses.remove(at: index)
        let ruleID = rule.id
        let binding = $rule
        let automation = appState.automation
        // The editor's rule while it is shown (a sheet edits a copy until Save), else the
        // stored rule with that identifier; a rule that is gone takes nothing back.
        let change: (@escaping (inout AutomationRule) -> Void) -> Void = { edit in
            if binding.wrappedValue.id == ruleID {
                edit(&binding.wrappedValue)
            } else if let ruleIndex = automation.rules.firstIndex(where: { $0.id == ruleID }) {
                edit(&automation.rules[ruleIndex])
            }
        }
        appState.layoutUndo.recordDeletion(
            String(localized: "\u{201C}\(AutomationDescription.text(for: clause.condition).capitalizedFirst)\u{201D} deleted"),
            place: .settings,
            restore: {
                change { rule in
                    guard rule.clauses.count < 10, !rule.clauses.contains(where: { $0.id == clause.id }) else {
                        return
                    }
                    DeletionUndo.reinsert(clause, at: index, into: &rule.clauses)
                }
            },
            deleteAgain: {
                change { rule in
                    rule.clauses.removeAll { $0.id == clause.id }
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(Text("Name")) {
                TextField("Name", text: $rule.name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: HolzBarTheme.SettingsKit.textFieldMinWidth)
                    .focused($isNameFocused)
            }
            SettingsSegmentedRow(Text("When"), selection: $rule.match) {
                Text("All apply").tag(AutomationMatch.all)
                Text("One applies").tag(AutomationMatch.any)
            }
            ForEach($rule.clauses) { $clause in
                AutomationConditionRow(condition: $clause.condition) {
                    deleteClause(clause)
                }
            }
            SettingsRow(
                Text("Add condition"),
                info: Text("At most ten conditions per rule. Entries with “…” ask for a name or a permission.")
            ) {
                addConditionMenu
            }
            if let itemName {
                SettingsValueRow(Text("Then"), value: Text("\(itemName) is shown only while this is true."))
                if case .showItemOnlyWhile(let key, let hiding) = rule.action {
                    hidingPicker(key: key, hiding: hiding)
                        .settingsSubRow()
                }
            } else {
                actionPicker
            }
            if itemName == nil, case .applyProfile(let name) = rule.action {
                profilePicker(selection: name)
                    .settingsSubRow()
            }
            if itemName == nil, case .applyMood(let name) = rule.action {
                moodPicker(selection: name)
                    .settingsSubRow()
            }
            if itemName == nil, case .showItemOnlyWhile(let key, let hiding) = rule.action {
                itemPicker(key: key, hiding: hiding)
                    .settingsSubRow()
            }
            if itemName == nil, case .runScript(let name) = rule.action {
                scriptPicker(name: name)
                    .settingsSubRow()
            }
            if itemName == nil, restoresApply {
                if case .runScript = rule.action {
                    SettingsToggleRow(
                        Text("Also run it when the rule stops being true"),
                        isOn: $rule.restoresWhenEnded,
                        info: Text("The script then runs when the rule starts and when it ends.")
                    )
                } else {
                    SettingsToggleRow(
                        Text("When it stops being true, go back"),
                        isOn: $rule.restoresWhenEnded,
                        info: Text("When the conditions stop being true, holzBar undoes what the rule did.")
                    )
                }
            }
            SettingsButtonRow {
                Button("Delete rule…", role: .destructive, action: onDelete)
            }
        }
        .task {
            if focusesName {
                isNameFocused = true
            }
        }
        .alert("Wi-Fi Network", isPresented: $isAskingForWiFiName) {
            TextField("Network name", text: $wifiName)
            Button("Add") {
                addWiFiCondition()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS shares the Wi-Fi network name only with apps that may use Location Services. holzBar uses it only to read that name and never reads your location. macOS asks for your permission next.")
        }
        .alert("Bluetooth Device", isPresented: $isAskingForBluetooth) {
            Button("Continue") {
                // The list of paired devices is read only now, after the reason was shown.
                appState.activate(for: .settings)
                bluetoothNames = AutomationBluetoothObserver.pairedNames()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS lets an app see which Bluetooth devices are connected only with your permission. holzBar reads the names of your paired devices and whether they are connected, nothing else. macOS asks for your permission next.")
        }
        .confirmationDialog(
            "Bluetooth Device",
            isPresented: Binding(get: { bluetoothNames != nil }, set: { if !$0 { bluetoothNames = nil } })
        ) {
            ForEach(bluetoothNames ?? [], id: \.self) { name in
                Button(name) {
                    add(.bluetoothConnected(name))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Adds the condition, and asks for Location Services now that the reason was shown.
    private func addWiFiCondition() {
        let name = wifiName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 32 else {
            return
        }
        appState.activate(for: .settings)
        appState.automation.wifiMonitor.requestAuthorization()
        add(.wifiNetwork(name))
    }

    // MARK: Conditions

    private var addConditionMenu: some View {
        Menu("Choose") {
            Button("On battery") {
                add(.power(.battery))
            }
            Button("Plugged in") {
                add(.power(.adapter))
            }
            Button("Battery level") {
                add(.batteryBelow(20))
            }
            Button("Low Power Mode") {
                add(.lowPowerMode)
            }
            Divider()
            Menu("An app is running") {
                ForEach(runningApplications, id: \.bundleIdentifier) { application in
                    Button(application.localizedName ?? application.bundleIdentifier ?? "") {
                        if let bundleID = application.bundleIdentifier {
                            add(.appRunning(bundleID))
                        }
                    }
                }
            }
            Menu("An app is in front") {
                ForEach(runningApplications, id: \.bundleIdentifier) { application in
                    Button(application.localizedName ?? application.bundleIdentifier ?? "") {
                        if let bundleID = application.bundleIdentifier {
                            add(.appFrontmost(bundleID))
                        }
                    }
                }
            }
            Button("Time of day") {
                add(.time(AutomationTimeWindow(startMinute: 22 * 60, endMinute: 6 * 60, weekdays: [])))
            }
            Menu("A display is connected") {
                ForEach(connectedDisplays) { display in
                    Button(display.name) {
                        add(.displayConnected(display.uuid))
                    }
                }
            }
            Menu("A script succeeds") {
                ForEach(approvedScripts) { script in
                    Button(URLPrompt.displayName(script.name)) {
                        add(.scriptSucceeds(script.name))
                    }
                }
            }
            Divider()
            Button("Wi-Fi network by name…") {
                wifiName = appState.automation.wifiMonitor.currentName ?? ""
                isAskingForWiFiName = true
            }
            Button("Connected through Wi-Fi") {
                add(.network(.wifi))
            }
            Button("Connected through Ethernet") {
                add(.network(.ethernet))
            }
            Button("Offline") {
                add(.network(.offline))
            }
            Button("Connected through a VPN") {
                add(.network(.vpn))
            }
            Button("Expensive connection (hotspot)") {
                add(.network(.expensive))
            }
            Divider()
            Button("Camera in use") {
                add(.cameraInUse)
            }
            Button("Microphone in use") {
                add(.microphoneInUse)
            }
            Divider()
            Menu("Sound plays through") {
                ForEach(AudioOutputDevices.outputNames(), id: \.self) { name in
                    Button(name) {
                        add(.audioOutput(name))
                    }
                }
            }
            Button("A Bluetooth device is connected…") {
                isAskingForBluetooth = true
            }
        }
        .fixedSize()
        .disabled(rule.clauses.count >= 10)
    }

    private func add(_ condition: AutomationCondition) {
        rule.clauses.append(AutomationClause(condition: condition))
    }

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    /// A connected display, by its UUID.
    private struct DisplayChoice: Identifiable {
        let uuid: String
        let name: String

        var id: String { uuid }
    }

    private var connectedDisplays: [DisplayChoice] {
        NSScreen.screens.compactMap { screen in
            Bridging.getDisplayUUIDString(for: screen.displayID).map { DisplayChoice(uuid: $0, name: screen.localizedName) }
        }
    }

    // MARK: Action

    private var actionChoice: Binding<ActionChoice> {
        Binding(
            get: {
                switch rule.action {
                case .applyProfile: .profile
                case .applyMood: .mood
                case .showSection(.hidden): .hiddenSection
                case .showSection(.alwaysHidden): .alwaysHiddenSection
                case .zen(true): .zenOn
                case .zen(false): .zenOff
                case .keepAwake(true): .keepAwake
                case .keepAwake(false): .allowSleep
                case .showItemOnlyWhile: .showItem
                case .runScript: .runScript
                }
            },
            set: { choice in
                let wasScript = if case .runScript = rule.action { true } else { false }
                defer {
                    // A script runs again at the end only when the user asks for it; the other
                    // actions go back by default.
                    if choice == .runScript, !wasScript {
                        rule.restoresWhenEnded = false
                    } else if choice != .runScript, wasScript {
                        rule.restoresWhenEnded = true
                    }
                }
                switch choice {
                case .profile:
                    rule.action = .applyProfile(profileNames.first ?? "")
                case .mood:
                    rule.action = .applyMood(appState.appearanceManager.moods.first?.name ?? "")
                case .hiddenSection:
                    rule.action = .showSection(.hidden)
                case .alwaysHiddenSection:
                    rule.action = .showSection(.alwaysHidden)
                case .zenOn:
                    rule.action = .zen(true)
                case .zenOff:
                    rule.action = .zen(false)
                case .keepAwake:
                    rule.action = .keepAwake(true)
                case .allowSleep:
                    rule.action = .keepAwake(false)
                case .showItem:
                    rule.action = .showItemOnlyWhile(itemKey: itemChoices.first?.key ?? "", hiding: .hidden)
                case .runScript:
                    rule.action = .runScript(approvedScripts.first?.name ?? "")
                }
            }
        )
    }

    private var actionPicker: some View {
        SettingsPickerRow(Text("Then"), selection: actionChoice) {
            Text("Apply a layout profile").tag(ActionChoice.profile)
            Text("Switch to a mood").tag(ActionChoice.mood)
            Text("Show the hidden section").tag(ActionChoice.hiddenSection)
            Text("Show the always-hidden section").tag(ActionChoice.alwaysHiddenSection)
            Text("Turn Zen mode on").tag(ActionChoice.zenOn)
            Text("Turn Zen mode off").tag(ActionChoice.zenOff)
            Text("Keep the Mac awake").tag(ActionChoice.keepAwake)
            Text("Let the Mac sleep").tag(ActionChoice.allowSleep)
            Text("Show a menu bar item only while this is true").tag(ActionChoice.showItem)
            Text("Run a script").tag(ActionChoice.runScript)
        }
    }

    @ViewBuilder
    private func profilePicker(selection name: String) -> some View {
        if profileNames.isEmpty {
            SettingsStateLine(.info, Text("Save a layout profile in Profiles & History first."))
        } else {
            SettingsPickerRow(
                Text("Profile"),
                selection: Binding(
                    get: { name },
                    set: { rule.action = .applyProfile($0) }
                )
            ) {
                ForEach(profileNames, id: \.self) { profileName in
                    Text(verbatim: profileName).tag(profileName)
                }
            }
        }
    }

    @ViewBuilder
    private func moodPicker(selection name: String) -> some View {
        let moods = appState.appearanceManager.moods
        if moods.isEmpty && name.isEmpty {
            SettingsStateLine(.info, Text("Save a mood in Appearance first."))
        } else {
            SettingsPickerRow(
                Text("Mood"),
                selection: Binding(
                    get: { name },
                    set: { rule.action = .applyMood($0) }
                )
            ) {
                // A mood the rule names that was deleted stays in the list, so the row says what
                // it was for.
                ForEach(moods.map(\.name).contains(name) || name.isEmpty ? moods.map(\.name) : moods.map(\.name) + [name], id: \.self) { moodName in
                    Text(verbatim: moodName).tag(moodName)
                }
            }
        }
    }

    /// The scripts the user approved and that may run now.
    private var approvedScripts: [ScriptStore.Entry] {
        appState.automation.scriptStore.scripts.filter { entry in
            if case .allowed = entry.decision {
                return true
            }
            return false
        }
    }

    @ViewBuilder
    private func scriptPicker(name: String) -> some View {
        let scripts = approvedScripts
        if scripts.isEmpty && name.isEmpty {
            SettingsStateLine(.info, Text("Put a script in your scripts folder and allow it in Scripts first."))
        } else {
            SettingsPickerRow(
                Text("Script"),
                selection: Binding(
                    get: { name },
                    set: { rule.action = .runScript($0) }
                )
            ) {
                ForEach(scripts) { script in
                    Text(verbatim: URLPrompt.displayName(script.name)).tag(script.name)
                }
                if !name.isEmpty, !scripts.contains(where: { $0.name == name }) {
                    Text(verbatim: URLPrompt.displayName(name)).tag(name)
                }
            }
        }
    }

    /// An item in the menu bar now, by its identity key.
    private struct ItemChoice: Identifiable {
        let key: String
        let name: String

        var id: String { key }
    }

    private var itemChoices: [ItemChoice] {
        let itemManager = appState.itemManager
        var choices = [ItemChoice]()
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.itemCache[section] where !item.isControlItem {
                choices.append(ItemChoice(key: itemManager.identityKey(for: item), name: item.displayName))
            }
        }
        return choices
    }

    @ViewBuilder
    private func itemPicker(key: String, hiding: AutomationSection) -> some View {
        let choices = itemChoices
        SettingsPickerRow(
            Text("Menu bar item"),
            selection: Binding(
                get: { key },
                set: { rule.action = .showItemOnlyWhile(itemKey: $0, hiding: hiding) }
            )
        ) {
            ForEach(choices) { choice in
                Text(verbatim: choice.name).tag(choice.key)
            }
            // An item the rule names that is not in the menu bar now stays chosen.
            if !key.isEmpty, !choices.contains(where: { $0.key == key }) {
                Text(verbatim: AutomationDescription.itemName(forKey: key)).tag(key)
            }
        }
        hidingPicker(key: key, hiding: hiding)
    }

    private func hidingPicker(key: String, hiding: AutomationSection) -> some View {
        SettingsPickerRow(
            Text("Otherwise hide it in"),
            selection: Binding(
                get: { hiding },
                set: { rule.action = .showItemOnlyWhile(itemKey: key, hiding: $0) }
            )
        ) {
            Text("Hidden").tag(AutomationSection.hidden)
            Text("Always Hidden").tag(AutomationSection.alwaysHidden)
        }
    }

    /// Whether the action has something to do when the rule ends: undo what it did, or, for a
    /// script, run it again with `HOLZBAR_EVENT=rule-ended`.
    private var restoresApply: Bool {
        switch rule.action {
        case .applyProfile, .applyMood, .zen, .keepAwake, .runScript: true
        case .showSection, .showItemOnlyWhile: false
        }
    }
}

/// One condition of a rule: what it says, the settings it has, and a button to remove it.
private struct AutomationConditionRow: View {
    @Environment(AppState.self) private var appState
    @Binding var condition: AutomationCondition
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsButtonRow(Text(verbatim: AutomationDescription.text(for: condition).capitalizedFirst)) {
                Button(action: onRemove) {
                    Label("Delete condition", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .help(Text("Delete condition"))
            }
            settings
                .settingsSubRow()
            if case .wifiNetwork = condition {
                WiFiPermissionNote(monitor: appState.automation.wifiMonitor)
                    .settingsSubRow()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: AutomationDescription.text(for: condition).capitalizedFirst))
    }

    @ViewBuilder
    private var settings: some View {
        switch condition {
        case .batteryBelow(let percent):
            SettingsStepperRow(
                Text("Level"),
                value: Binding(
                    get: { percent },
                    set: { condition = .batteryBelow($0) }
                ),
                in: 5...95,
                step: 5,
                info: Text("From 5 to 95 percent, in steps of 5.")
            ) { value in
                Text(verbatim: (Double(value) / 100).formatted(.percent))
            }
        case .time(let window):
            timeSettings(window)
        case .power, .lowPowerMode, .appRunning, .appFrontmost, .displayConnected, .network, .wifiNetwork,
            .cameraInUse, .microphoneInUse, .audioOutput, .bluetoothConnected, .scriptSucceeds:
            EmptyView()
        }
    }

    @ViewBuilder
    private func timeSettings(_ window: AutomationTimeWindow) -> some View {
        SettingsRow(Text("From")) {
            DatePicker(
                "From",
                selection: minutesBinding(window.startMinute) { $0.startMinute = $1 },
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        SettingsRow(Text("To")) {
            DatePicker(
                "To",
                selection: minutesBinding(window.endMinute) { $0.endMinute = $1 },
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        SettingsMultiSegmentedRow(
            Text("Weekdays"),
            selection: Binding(
                get: { window.weekdays },
                set: { weekdays in
                    var updated = window
                    updated.weekdays = weekdays
                    condition = .time(updated)
                }
            ),
            values: Array(1...7),
            info: Text("No day chosen means every day.")
        ) { day in
            Text(verbatim: Calendar.current.veryShortWeekdaySymbols[day - 1])
                .accessibilityLabel(Text(verbatim: Calendar.current.weekdaySymbols[day - 1]))
        }
    }

    /// A date binding for a minute of the day, which writes back through `update`.
    private func minutesBinding(
        _ minutes: Int,
        update: @escaping (inout AutomationTimeWindow, Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: { AutomationDescription.time(minutes: minutes) },
            set: { date in
                guard case .time(var window) = condition else {
                    return
                }
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                update(&window, (components.hour ?? 0) * 60 + (components.minute ?? 0))
                condition = .time(window)
            }
        )
    }
}

/// Says that the Wi-Fi name condition needs Location Services, until the user allowed it.
private struct WiFiPermissionNote: View {
    let monitor: WiFiNetworkMonitor

    var body: some View {
        if !monitor.isAuthorized {
            let text = Text("Needs Location Services. Until you allow holzBar, this condition is never true.")
            if monitor.authorization != .notDetermined {
                SettingsStateLine(.warning, text) {
                    Button("Open Location Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else {
                SettingsStateLine(.warning, text)
            }
        }
    }
}

private extension String {
    /// The string with its first letter in capitals, for a sentence fragment shown on its own.
    var capitalizedFirst: String {
        prefix(1).localizedUppercase + dropFirst()
    }
}
