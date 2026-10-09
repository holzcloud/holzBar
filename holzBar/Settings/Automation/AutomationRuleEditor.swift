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
    let onDelete: () -> Void

    @State private var isAskingForWiFiName = false
    @State private var wifiName = ""

    /// What a rule can do, as the choices of one menu.
    private enum ActionChoice: Hashable {
        case profile
        case hiddenSection
        case alwaysHiddenSection
        case zenOn
        case zenOff
        case keepAwake
        case allowSleep
        case showItem
        case runScript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            TextField("Name", text: $rule.name)
                .textFieldStyle(.roundedBorder)
            heading("When")
            Picker("Conditions", selection: $rule.match) {
                Text("All of these are true").tag(AutomationMatch.all)
                Text("Any of these is true").tag(AutomationMatch.any)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach($rule.clauses) { $clause in
                AutomationConditionRow(condition: $clause.condition) {
                    rule.clauses.removeAll { $0.id == clause.id }
                }
            }
            addConditionMenu
            heading("Then")
            actionPicker
            if case .applyProfile(let name) = rule.action {
                profilePicker(selection: name)
            }
            if case .showItemOnlyWhile(let key, let hiding) = rule.action {
                itemPicker(key: key, hiding: hiding)
            }
            if case .runScript(let name) = rule.action {
                scriptPicker(name: name)
            }
            if restoresApply {
                Toggle("When it stops being true, go back", isOn: $rule.restoresWhenEnded)
            }
            Button("Delete Rule", role: .destructive, action: onDelete)
                .padding(.top, HolzBarTheme.Spacing.xs)
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

    private func heading(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(HolzBarTheme.Typography.caption)
            .textCase(.uppercase)
            .foregroundStyle(HolzBarTheme.Palette.textTertiary)
            .padding(.top, HolzBarTheme.Spacing.xs)
    }

    // MARK: Conditions

    private var addConditionMenu: some View {
        Menu("Add Condition", systemImage: "plus") {
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
                    Button(script.name) {
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
        }
        .menuStyle(.borderlessButton)
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
                switch choice {
                case .profile:
                    rule.action = .applyProfile(profileNames.first ?? "")
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
        Picker("Action", selection: actionChoice) {
            Text("Apply a layout profile").tag(ActionChoice.profile)
            Text("Show the hidden section").tag(ActionChoice.hiddenSection)
            Text("Show the always-hidden section").tag(ActionChoice.alwaysHiddenSection)
            Text("Turn Zen mode on").tag(ActionChoice.zenOn)
            Text("Turn Zen mode off").tag(ActionChoice.zenOff)
            Text("Keep the Mac awake").tag(ActionChoice.keepAwake)
            Text("Let the Mac sleep").tag(ActionChoice.allowSleep)
            Text("Show an item only while this is true").tag(ActionChoice.showItem)
            Text("Run a script").tag(ActionChoice.runScript)
        }
    }

    @ViewBuilder
    private func profilePicker(selection name: String) -> some View {
        if profileNames.isEmpty {
            Text("Save a layout profile in Menu Bar Layout first.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        } else {
            Picker(
                "Profile",
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
            Text("Put a script in the Scripts folder and allow it below first.")
                .font(HolzBarTheme.Typography.caption)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
        } else {
            Picker(
                "Script",
                selection: Binding(
                    get: { name },
                    set: { rule.action = .runScript($0) }
                )
            ) {
                ForEach(scripts) { script in
                    Text(verbatim: script.name).tag(script.name)
                }
                if !name.isEmpty, !scripts.contains(where: { $0.name == name }) {
                    Text(verbatim: name).tag(name)
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
        Picker(
            "Item",
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
        Picker(
            "Otherwise hide it in",
            selection: Binding(
                get: { hiding },
                set: { rule.action = .showItemOnlyWhile(itemKey: key, hiding: $0) }
            )
        ) {
            Text("Hidden").tag(AutomationSection.hidden)
            Text("Always-Hidden").tag(AutomationSection.alwaysHidden)
        }
    }

    /// Whether the action is one that can be undone when the rule ends.
    private var restoresApply: Bool {
        switch rule.action {
        case .applyProfile, .zen, .keepAwake: true
        case .showSection, .showItemOnlyWhile, .runScript: false
        }
    }
}

/// One condition of a rule: what it says, the settings it has, and a button to remove it.
private struct AutomationConditionRow: View {
    @Environment(AppState.self) private var appState
    @Binding var condition: AutomationCondition
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text(verbatim: AutomationDescription.text(for: condition).capitalizedFirst)
                    .font(HolzBarTheme.Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove Condition"))
            }
            settings
            if case .wifiNetwork = condition {
                WiFiPermissionNote(monitor: appState.automation.wifiMonitor)
            }
        }
        .padding(.horizontal, HolzBarTheme.Spacing.sm)
        .padding(.vertical, HolzBarTheme.Spacing.xs + 2)
        .background(
            HolzBarTheme.Palette.text.opacity(0.05),
            in: HolzBarTheme.shape(HolzBarTheme.Radius.control)
        )
    }

    @ViewBuilder
    private var settings: some View {
        switch condition {
        case .batteryBelow(let percent):
            Stepper(
                value: Binding(
                    get: { percent },
                    set: { condition = .batteryBelow($0) }
                ),
                in: 5...95,
                step: 5
            ) {
                Text("Level")
            }
        case .time(let window):
            timeSettings(window)
        case .power, .lowPowerMode, .appRunning, .appFrontmost, .displayConnected, .network, .wifiNetwork, .scriptSucceeds:
            EmptyView()
        }
    }

    @ViewBuilder
    private func timeSettings(_ window: AutomationTimeWindow) -> some View {
        HStack {
            DatePicker(
                "From",
                selection: minutesBinding(window.startMinute) { $0.startMinute = $1 },
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "To",
                selection: minutesBinding(window.endMinute) { $0.endMinute = $1 },
                displayedComponents: .hourAndMinute
            )
        }
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            ForEach(1...7, id: \.self) { day in
                Toggle(
                    Calendar.current.veryShortWeekdaySymbols[day - 1],
                    isOn: Binding(
                        get: { window.weekdays.contains(day) },
                        set: { isOn in
                            var updated = window
                            if isOn {
                                updated.weekdays.insert(day)
                            } else {
                                updated.weekdays.remove(day)
                            }
                            condition = .time(updated)
                        }
                    )
                )
                .toggleStyle(.button)
                .accessibilityLabel(Text(verbatim: Calendar.current.weekdaySymbols[day - 1]))
            }
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
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Label("Needs Location Services. Until you allow holzBar, this condition is never true.", systemImage: "lock")
                    .font(HolzBarTheme.Typography.caption)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if monitor.authorization != .notDetermined {
                    Button("Open Location Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(HolzBarTheme.Typography.caption)
                }
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
