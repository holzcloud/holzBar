import Foundation

/// A failing run reduced to what is needed to print it: the Macs it started with, the (shrunk) events, the seed
/// and preset, and the violation.
struct SimFailure: Sendable {
    var name: String
    var seed: UInt64
    var preset: SimProviderPreset?
    var macs: [SimMacSpec]
    var events: [SimEvent]
    var violation: SimViolation
}

/// What each invariant says, in the words of the scenario "Must" field (A1 section 7.1).
enum SimInvariantText {
    static let statements: [SimInvariantID: String] = [
        "INV-S1": "A sync-caused change never replaces a live user value, except by an answer whose sheet showed it as losing or by a version that already holds a later user change of that setting.",
        "INV-S1g": "No live user change is lost everywhere: it stays in some Mac's settings, a readable file or a pending entry.",
        "INV-S2": "Sync never moves a setting back to an older user value, nor to unset without an explicit deletion.",
        "INV-S3": "A published file claims only changes its writer has seen and carries every live entry it claims.",
        "INV-S4": "A file that does not mention a setting leaves it unchanged: absence is not deletion.",
        "INV-S5": "A deletion by the user appears as an explicit deletion in the next publication.",
        "INV-S6": "A Mac writes only its own device file, and over it only when it is absent or was read in this session and is dominated.",
        "INV-S7": "A waiting change lasts across quit, file deletion and later arrivals.",
        "INV-S8": "No local key, salt, hash, user ID or name appears in a written byte.",
        "INV-S9": "An answer supersedes exactly the values its sheet showed; a value that arrived later survives.",
        "INV-F9": "Decisions and publications are identical across clock offsets and clock steps (modulo counter renaming).",
        "INV-A1": "Automatic events change no prompt, hint or user-state publication.",
        "INV-A5": "Launches without user events mint nothing, also across builds and after a beta2 run.",
        "INV-F2": "The order in which versions arrive does not change the final state.",
        "INV-F3": "Duplicate and coalesced deliveries change nothing.",
        "INV-C1": "Under quiescence all Macs agree on every synced unit.",
        "INV-C2": "Under quiescence relaunches alone write nothing.",
        "INV-C3": "The number of questions after the quiescence point is bounded.",
        "INV-C4": "Relaunches alone cause no hint and no prompt.",
        "INV-C5": "Every live change reaches every other Mac, or waits there as a hint or prompt.",
        "INV-C6": "A fresh Mac joining after the drain gets exactly the agreed state.",
        "INV-P6": "A real conflict is shown; it is never applied, hidden or published over.",
    ]

    static func statement(of id: SimInvariantID) -> String {
        statements[id] ?? "The invariant \(id) holds."
    }
}

enum SimScenarioPrinter {
    // MARK: A1 style

    /// The scenario as the A1 failure catalogue writes it: Setup, Steps, Wrong, Must (A1 section 7.1).
    static func a1Style(_ failure: SimFailure) -> String {
        var lines: [String] = []
        lines.append("Scenario \(failure.name) (seed \(failure.seed), provider \(failure.preset?.rawValue ?? "ideal"))")
        lines.append("")
        lines.append("Setup")
        for spec in failure.macs { lines.append("  - \(describe(spec))") }
        lines.append("")
        lines.append("Steps")
        for (index, event) in failure.events.enumerated() {
            lines.append("  \(index + 1). \(event.sentence)")
        }
        lines.append("")
        lines.append("Wrong")
        lines.append("  \(failure.violation.id): \(failure.violation.description)")
        lines.append("")
        lines.append("Must")
        lines.append("  \(failure.violation.id): \(SimInvariantText.statement(of: failure.violation.id))")
        return lines.joined(separator: "\n")
    }

    private static func describe(_ spec: SimMacSpec) -> String {
        var text = "Mac \(spec.name): \(spec.version.rawValue) build on macOS generation \(spec.generation)"
        if spec.enabled, let folder = spec.folder {
            text += ", sync on in folder \(folder)"
        } else {
            text += ", sync off"
        }
        text += spec.running ? ", running" : ", not running"
        if spec.clockOffsetMilliseconds != 0 {
            text += ", clock \(spec.clockOffsetMilliseconds > 0 ? "+" : "")\(spec.clockOffsetMilliseconds / 1000) s"
        }
        if !spec.defaults.isEmpty {
            let entries = spec.defaults.keys.sorted().map { "\($0) = \(spec.defaults[$0]!.canonical)" }
            text += ", settings \(entries.joined(separator: ", "))"
        }
        return text
    }

    // MARK: Swift test

    /// A ready-to-paste Swift Testing function that builds the scenario with the `SimScenario` builders.
    static func swiftTest(_ failure: SimFailure) -> String {
        var lines: [String] = []
        let name = failure.name
        lines.append("@Test(\"\(name)\")")
        lines.append("func \(identifier(name))() {")
        let preset = failure.preset.map { ".\($0.rawValue)" } ?? "nil"
        lines.append("    // Add `.brains { version, mac in <the engine under test> }` to run it against that engine.")
        lines.append("    SimScenario(\"\(name)\", seed: \(failure.seed), preset: \(preset))")
        lines.append("        .macs([")
        for spec in failure.macs { lines.append("            \(swiftSpec(spec)),") }
        lines.append("        ])")
        for event in failure.events { lines.append("        \(event.builderCall)") }
        lines.append("        .expectNoViolation([\"\(failure.violation.id)\"])")
        lines.append("        .check()")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func identifier(_ name: String) -> String {
        var result = ""
        var upper = false
        for character in name {
            if character.isLetter || character.isNumber {
                result.append(upper ? Character(character.uppercased()) : character)
                upper = false
            } else {
                upper = !result.isEmpty
            }
        }
        if result.isEmpty { return "scenario" }
        if let first = result.first, first.isNumber { result = "scenario" + result }
        return result
    }

    static func swiftSpec(_ spec: SimMacSpec) -> String {
        var parts = [macLiteral(spec.name), ".\(spec.version.rawValue)"]
        if spec.generation != 26 { parts.append("generation: \(spec.generation)") }
        if !spec.enabled { parts.append("enabled: false") }
        if spec.folder != "F1" { parts.append("folder: \(spec.folder.map { "\"\($0)\"" } ?? "nil")") }
        if spec.running { parts.append("running: true") }
        if !spec.defaults.isEmpty {
            let entries = spec.defaults.keys.sorted().map { "\"\($0)\": \(spec.defaults[$0]!.swiftLiteral)" }
            parts.append("defaults: [\(entries.joined(separator: ", "))]")
        }
        if spec.clockOffsetMilliseconds != 0 { parts.append("clockOffsetMilliseconds: \(spec.clockOffsetMilliseconds)") }
        return "SimMacSpec(\(parts.joined(separator: ", ")))"
    }

    static func macLiteral(_ mac: SimMacName) -> String {
        ["A", "B", "C", "D"].contains(mac.name) ? ".\(mac.name)" : "\"\(mac.name)\""
    }
}

// MARK: - Event text

extension SimValue {
    /// Swift source for the value.
    var swiftLiteral: String {
        switch self {
        case .string(let text): ".string(\"\(text)\")"
        case .int(let number): ".int(\(number))"
        case .bool(let flag): ".bool(\(flag))"
        case .data(let bytes): ".data(Data(\(Array(bytes))))"
        case .array(let elements): ".array([\(elements.map(\.swiftLiteral).joined(separator: ", "))])"
        case .dictionary(let entries):
            ".dictionary([\(entries.keys.sorted().map { "\"\($0)\": \(entries[$0]!.swiftLiteral)" }.joined(separator: ", "))])"
        }
    }
}

extension SimAnswer {
    var swiftLiteral: String {
        switch self {
        case .use: ".use"
        case .keep: ".keep"
        case .later: ".later"
        case .cancel: ".cancel"
        case .pick(let picks):
            ".pick([\(picks.keys.sorted().map { "\"\($0)\": .\(picks[$0]!.rawValue)" }.joined(separator: ", "))])"
        }
    }
}

extension SimEvent {
    /// A sentence for the Steps field of an A1-style scenario.
    var sentence: String {
        let who = mac.map { "\($0)" } ?? "-"
        switch self {
        case .userEdit(_, let unit, let value):
            return "\(who): the user changes \(unit)\(value.map { " to \($0.canonical)" } ?? " (a fresh value)")."
        case .userDelete(_, let unit): return "\(who): the user resets \(unit) to its default."
        case .userImport(_, let units): return "\(who): the user imports a settings file that sets \(units.sorted().joined(separator: ", ")) and lacks every other key."
        case .setHotkey(_, let action, let combo): return "\(who): the user assigns hotkey combination \(combo) to \(action)."
        case .chooseItemIcon(_, let item): return "\(who): the user chooses an icon for \(item)."
        case .oversizeIcon: return "\(who): the user picks an icon larger than 1 MiB."
        case .moveApp27(_, let bundle, let section): return "\(who): the user moves \(bundle) to section \(section) in the Layout pane."
        case .applyProfile(_, let profile, let byUser): return "\(who): \(byUser ? "the user applies" : "a Space binding applies") profile \(profile)."
        case .saveProfile(_, let profile): return "\(who): the user saves profile \(profile)."
        case .renameProfile(_, let profile): return "\(who): the user renames profile \(profile)."
        case .deleteProfile(_, let profile): return "\(who): the user deletes profile \(profile)."
        case .turnOn(_, let folder): return "\(who): the user turns sync on in folder \(folder)."
        case .turnOff: return "\(who): the user turns sync off."
        case .changeFolder(_, let folder): return "\(who): the user changes the sync folder to \(folder)."
        case .answer(_, let answer): return "\(who): the user answers the open sheet with \(answer.canonical)."
        case .autoPlace(_, let unit): return "\(who): holzBar places \(unit) by itself."
        case .learn(_, let key): return "\(who): holzBar learns a new entry of \(key)."
        case .setFlag(_, let key): return "\(who): holzBar sets the one-time flag \(key)."
        case .seed27: return "\(who): holzBar seeds the macOS 27 layout."
        case .placeNewApp27(_, let bundle): return "\(who): holzBar places the new app \(bundle) on macOS 27."
        case .upgradeOS: return "\(who): macOS is upgraded from 26 to 27."
        case .launch: return "\(who): holzBar launches."
        case .quit: return "\(who): holzBar quits."
        case .crash: return "\(who): holzBar crashes."
        case .restartApp: return "\(who): the user restarts holzBar."
        case .updateApp(_, let version): return "\(who): holzBar is updated to the \(version.rawValue) build."
        case .clone(let from, let to): return "\(to): a disk clone of \(from) is restored on other hardware."
        case .copyAccount(let from, let to): return "\(to): the account of \(from) is copied to another user on the same hardware."
        case .restorePrefs: return "\(who): older preferences are restored."
        case .restoreSigma: return "\(who): the older local sync state is restored."
        case .restoreHome(_, let keepCaches): return "\(who): the whole home folder is restored from a backup (caches \(keepCaches ? "kept" : "lost"))."
        case .sigmaLost: return "\(who): the local sync state is lost."
        case .reinstall: return "\(who): holzBar is reinstalled and all its data removed."
        case .advance(let milliseconds): return "\(milliseconds / 1000) s pass."
        case .clockStep(_, let milliseconds): return "\(who): the clock jumps by \(milliseconds / 1000) s."
        case .timerFired(_, let tag): return "\(who): the timer \(tag) fires."
        case .provider(let event): return "The provider: \(event.canonical)."
        }
    }

    /// The `SimScenario` builder call that adds this event.
    var builderCall: String {
        func mac(_ name: SimMacName) -> String { SimScenarioPrinter.macLiteral(name) }
        func quoted(_ text: String) -> String { "\"\(text)\"" }
        switch self {
        case .userEdit(let name, let unit, let value):
            if let value { return ".edit(\(mac(name)), \(quoted(unit)), value: \(value.swiftLiteral))" }
            return ".edit(\(mac(name)), \(quoted(unit)))"
        case .userDelete(let name, let unit): return ".delete(\(mac(name)), \(quoted(unit)))"
        case .userImport(let name, let units): return ".importFile(\(mac(name)), units: [\(units.sorted().map(quoted).joined(separator: ", "))])"
        case .setHotkey(let name, let action, let combo): return ".setHotkey(\(mac(name)), action: \(quoted(action)), combo: \(combo))"
        case .chooseItemIcon(let name, let item): return ".chooseItemIcon(\(mac(name)), item: \(quoted(item)))"
        case .oversizeIcon(let name): return ".oversizeIcon(\(mac(name)))"
        case .moveApp27(let name, let bundle, let section): return ".moveApp27(\(mac(name)), bundle: \(quoted(bundle)), section: \(section))"
        case .applyProfile(let name, let profile, let byUser): return ".applyProfile(\(mac(name)), \(quoted(profile)), byUser: \(byUser))"
        case .saveProfile(let name, let profile): return ".saveProfile(\(mac(name)), \(quoted(profile)))"
        case .renameProfile(let name, let profile): return ".renameProfile(\(mac(name)), \(quoted(profile)))"
        case .deleteProfile(let name, let profile): return ".deleteProfile(\(mac(name)), \(quoted(profile)))"
        case .turnOn(let name, let folder): return ".turnOn(\(mac(name)), folder: \(quoted(folder)))"
        case .turnOff(let name): return ".turnOff(\(mac(name)))"
        case .changeFolder(let name, let folder): return ".changeFolder(\(mac(name)), folder: \(quoted(folder)))"
        case .answer(let name, let answer): return ".answer(\(mac(name)), \(answer.swiftLiteral))"
        case .autoPlace(let name, let unit): return ".autoPlace(\(mac(name)), \(quoted(unit)))"
        case .learn(let name, let key): return ".learn(\(mac(name)), \(quoted(key)))"
        case .setFlag(let name, let key): return ".setFlag(\(mac(name)), \(quoted(key)))"
        case .seed27(let name): return ".seed27(\(mac(name)))"
        case .placeNewApp27(let name, let bundle): return ".placeNewApp27(\(mac(name)), bundle: \(quoted(bundle)))"
        case .upgradeOS(let name): return ".upgradeOS(\(mac(name)))"
        case .launch(let name): return ".launch(\(mac(name)))"
        case .quit(let name): return ".quit(\(mac(name)))"
        case .crash(let name): return ".crash(\(mac(name)))"
        case .restartApp(let name): return ".restartApp(\(mac(name)))"
        case .updateApp(let name, let version): return ".updateApp(\(mac(name)), .\(version.rawValue))"
        case .clone(let from, let to): return ".clone(from: \(mac(from)), to: \(mac(to)))"
        case .copyAccount(let from, let to): return ".copyAccount(from: \(mac(from)), to: \(mac(to)))"
        case .restorePrefs(let name): return ".restorePrefs(\(mac(name)))"
        case .restoreSigma(let name): return ".restoreSigma(\(mac(name)))"
        case .restoreHome(let name, let keepCaches): return ".restoreHome(\(mac(name)), keepCaches: \(keepCaches))"
        case .sigmaLost(let name): return ".sigmaLost(\(mac(name)))"
        case .reinstall(let name): return ".reinstall(\(mac(name)))"
        case .advance(let milliseconds):
            if milliseconds % 1000 == 0 { return ".advance(seconds: \(milliseconds / 1000))" }
            return ".advance(milliseconds: \(milliseconds))"
        case .clockStep(let name, let milliseconds): return ".clockStep(\(mac(name)), milliseconds: \(milliseconds))"
        case .timerFired(let name, let tag): return ".event(.timerFired(mac: \(mac(name)), tag: \(quoted(tag))))"
        case .provider(let event): return ".provider(\(event.swiftExpression))"
        }
    }
}

extension SimProviderEvent {
    /// Swift source for the provider event (the folder is left out when it is `F1`).
    var swiftExpression: String {
        func mac(_ name: SimMacName) -> String { SimScenarioPrinter.macLiteral(name) }
        func folderPart(_ folder: String) -> String { folder == "F1" ? "" : "folder: \"\(folder)\", " }
        switch self {
        case .restore(let folder, let path, let version): return ".restore(\(folderPart(folder))path: \"\(path)\", version: \(version))"
        case .delete(let folder, let path): return ".delete(\(folderPart(folder))path: \"\(path)\")"
        case .deleteFolder(let folder): return folder == "F1" ? ".deleteFolder()" : ".deleteFolder(folder: \"\(folder)\")"
        case .evict(let folder, let path, let name): return ".evict(\(folderPart(folder))path: \"\(path)\", mac: \(mac(name)))"
        case .exposePartial(let folder, let path, let name, let duration):
            return ".exposePartial(\(folderPart(folder))path: \"\(path)\", mac: \(mac(name)), forMilliseconds: \(duration))"
        case .stall(let folder, let name, let duration):
            return ".stall(\(folderPart(folder))mac: \(mac(name)), forMilliseconds: \(duration.map(String.init) ?? "nil"))"
        case .unmount(let folder, let name): return ".unmount(\(folderPart(folder))mac: \(mac(name)))"
        case .mount(let folder, let name): return ".mount(\(folderPart(folder))mac: \(mac(name)))"
        case .foreign(let folder, let path, let kind): return ".foreign(\(folderPart(folder))path: \"\(path)\", kind: .\(kind.rawValue))"
        case .offline(let folder, let name, let duration):
            return ".offline(\(folderPart(folder))mac: \(mac(name)), forMilliseconds: \(duration))"
        }
    }
}
