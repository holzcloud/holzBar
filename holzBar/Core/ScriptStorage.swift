//
//  ScriptStorage.swift
//  holzBar
//

import Foundation

/// When a profile hook runs.
nonisolated enum ProfileHookTiming: String, Codable, Sendable {
    /// Before the items move. holzBar waits for the script, at most its time limit.
    case beforeApplying
    /// Once the items moved. holzBar does not wait for the script.
    case afterApplying

    /// The `HOLZBAR_EVENT` the script sees.
    var event: ScriptEvent {
        switch self {
        case .beforeApplying: .profileWillApply
        case .afterApplying: .profileDidApply
        }
    }
}

/// A script that runs before or after a profile is applied (D-09, D-13).
///
/// It is for one profile, by name, or for every profile. It names a file of the scripts folder;
/// the script runs only when the user approved its exact content, like every other script. The
/// profile's name is never given to the script (D-06).
nonisolated struct ProfileHook: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// The profile the hook is for, or `nil` for every profile.
    var profileName: String?
    var timing: ProfileHookTiming
    /// The file name in the scripts folder.
    var scriptName: String

    /// The longest profile name, in UTF-8 bytes.
    static let maximumProfileNameBytes = 80

    var isValid: Bool {
        guard ScriptGate.isPlainName(scriptName) else {
            return false
        }
        guard let profileName else {
            return true
        }
        return !profileName.isEmpty && profileName.utf8.count <= Self.maximumProfileNameBytes
    }
}

/// The rules for the profile hooks of a ``ScriptStoreFile``.
nonisolated enum ProfileHooks {
    /// The most hooks that are kept.
    static let maximumCount = 50

    /// The scripts to run for a profile at one time: the hooks for that profile first, then
    /// those for every profile, each name once, in the order the hooks were made.
    static func scriptNames(for profileName: String, timing: ProfileHookTiming, in hooks: [ProfileHook]) -> [String] {
        let matching = hooks.filter { $0.timing == timing }
        let own = matching.filter { $0.profileName == profileName }
        let everyProfile = matching.filter { $0.profileName == nil }
        var seen = Set<String>()
        var names = [String]()
        for hook in own + everyProfile where seen.insert(hook.scriptName).inserted {
            names.append(hook.scriptName)
        }
        return names
    }

    /// The hooks with the ones of a renamed profile moved to its new name.
    static func renaming(_ hooks: [ProfileHook], from oldName: String, to newName: String) -> [ProfileHook] {
        hooks.map { hook in
            guard hook.profileName == oldName else {
                return hook
            }
            var renamed = hook
            renamed.profileName = newName
            return renamed
        }
    }

    /// The hooks without the ones of a deleted profile. Hooks for every profile stay.
    static func removing(_ hooks: [ProfileHook], profileName: String) -> [ProfileHook] {
        hooks.filter { $0.profileName != profileName }
    }
}

/// What holzBar keeps about scripts, in `Scripts.json` on this Mac (D-05).
///
/// The file is local: it is not in `Defaults`, so no export, import or sync carries it, and no
/// URL command or Shortcut reaches it. It holds the scripts folder, what the user approved
/// (the full SHA-256 of the exact content), the time limits, the rules that use a script and
/// their place among the rules, and the profile hooks. Decoding is defensive: a file of a
/// newer version is not read, a file that is not a store is unreadable, and anything the file
/// holds is validated and capped (T-11-L3).
nonisolated struct ScriptStoreFile: Codable, Equatable, Sendable {
    /// The format of this build. A file with a higher version is read-only and never overwritten.
    /// Raise it whenever an enum of the file gains a case that an older build cannot decode: an
    /// older build skips such an element (and drops it at its next save), so only the version
    /// protects it.
    static let currentVersion = 1
    /// The largest file that is read, in bytes.
    static let maximumSize = 1_000_000
    /// The most approvals and the most time limits that are kept.
    static let maximumEntries = 200
    /// The longest folder path that is kept, in UTF-8 bytes.
    static let maximumFolderPathBytes = 1024

    var version = ScriptStoreFile.currentVersion
    /// The scripts folder the user chose, or `nil` for the default folder.
    var folderPath: String?
    /// The SHA-256 (64 lowercase hexadecimal characters) the user approved, by file name.
    var approvals = [String: String]()
    /// The time limit in seconds, by file name; a script without one gets the default.
    var timeLimits = [String: Int]()
    /// The rules that use a script. The settings hold none of them.
    var rules = [AutomationRule]()
    /// The identifier of every rule, in the order the user sees them.
    var ruleOrder = [UUID]()
    var profileHooks = [ProfileHook]()
    /// Whether the script rules and approvals of 0.0.8-beta1 and beta2 were moved here.
    var hasMigratedLegacyData = false

    nonisolated private enum CodingKeys: String, CodingKey {
        case version
        case folderPath
        case approvals
        case timeLimits
        case rules
        case ruleOrder
        case profileHooks
        case hasMigratedLegacyData
    }

    /// Whether a string is a SHA-256 in lowercase hexadecimal.
    static func isValidHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// The file with everything invalid dropped and everything over a limit cut off.
    func validated() -> ScriptStoreFile {
        var result = self
        result.version = Self.currentVersion
        if let folderPath, !Self.isValidFolderPath(folderPath) {
            result.folderPath = nil
        }
        result.approvals = Self.capped(approvals.filter { ScriptGate.isPlainName($0.key) && Self.isValidHash($0.value) })
        result.timeLimits = Self.capped(
            timeLimits
                .filter { ScriptGate.isPlainName($0.key) }
                .mapValues { ScriptLimits.timeLimit($0) }
        )
        result.rules = AutomationRule.validated(rules.filter(\.usesScript))
        var seenOrder = Set<UUID>()
        result.ruleOrder = Array(ruleOrder.filter { seenOrder.insert($0).inserted }.prefix(Self.maximumEntries))
        var seenHooks = Set<UUID>()
        result.profileHooks = Array(
            profileHooks.filter { $0.isValid && seenHooks.insert($0.id).inserted }.prefix(ProfileHooks.maximumCount)
        )
        return result
    }

    private static func isValidFolderPath(_ path: String) -> Bool {
        path.hasPrefix("/")
            && path.utf8.count <= maximumFolderPathBytes
            && !path.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    /// At most ``maximumEntries`` entries, the first by name.
    private static func capped<Value>(_ dictionary: [String: Value]) -> [String: Value] {
        guard dictionary.count > maximumEntries else {
            return dictionary
        }
        return Dictionary(uniqueKeysWithValues: dictionary.sorted { $0.key < $1.key }.prefix(maximumEntries).map { $0 })
    }

    /// The file with the script rules and approvals of 0.0.8-beta1 and beta2 added, once.
    ///
    /// A file that already migrated comes back unchanged. What the file holds already wins over
    /// the beta's data. A beta had no end script, so a rule that runs a script does not start
    /// to run one when it ends (11-02 note): its end option is off.
    ///
    /// - Parameters:
    ///   - rules: The rules of the settings that use a script.
    ///   - approvals: The beta's approvals by file name.
    ///   - order: The order of every rule of the settings, so the rules keep their place.
    func adoptingLegacy(
        rules legacyRules: [AutomationRule],
        approvals legacyApprovals: [String: String],
        order: [UUID] = []
    ) -> ScriptStoreFile {
        guard !hasMigratedLegacyData else {
            return self
        }
        var result = self
        let known = Set(rules.map(\.id))
        for var rule in legacyRules where rule.usesScript && !known.contains(rule.id) {
            if case .runScript = rule.action {
                rule.restoresWhenEnded = false
            }
            result.rules.append(rule)
        }
        for (name, hash) in legacyApprovals where result.approvals[name] == nil {
            result.approvals[name] = hash
        }
        if result.ruleOrder.isEmpty {
            result.ruleOrder = order
        }
        result.hasMigratedLegacyData = true
        return result.validated()
    }

    // MARK: Coding

    /// What ``decode(_:)`` found.
    nonisolated enum DecodeResult: Equatable, Sendable {
        case file(ScriptStoreFile)
        /// The file is of a newer version: it is not read and not overwritten.
        case unsupportedVersion
        /// The file is not a store: too large, not JSON, or not of this format.
        case unreadable
    }

    nonisolated private struct VersionOnly: Decodable {
        let version: Int
    }

    /// Reads a store file. Nothing is trusted: the size is limited, the version is read first,
    /// and the result is validated and capped.
    static func decode(_ data: Data) -> DecodeResult {
        guard data.count <= maximumSize else {
            return .unreadable
        }
        let decoder = JSONDecoder()
        guard let peek = try? decoder.decode(VersionOnly.self, from: data) else {
            return .unreadable
        }
        guard peek.version <= currentVersion else {
            return .unsupportedVersion
        }
        guard peek.version >= 1, let file = try? decoder.decode(ScriptStoreFile.self, from: data) else {
            return .unreadable
        }
        return .file(file.validated())
    }

    /// The JSON to write, with sorted keys, or `nil` when it would be over ``maximumSize``.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), data.count <= Self.maximumSize else {
            return nil
        }
        return data
    }
}

/// One element of a list or a dictionary that is skipped when it cannot be decoded, instead of
/// making the whole file unreadable.
nonisolated private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) {
        value = try? Value(from: decoder)
    }
}

nonisolated extension ScriptStoreFile {
    /// Every key is optional, so a later version can add keys and this one still reads the
    /// file. An element that cannot be decoded (a rule with a condition kind a later build
    /// added, a hook with an unknown timing, a value of the wrong type) is skipped and the rest
    /// of the file is kept: one such element must not take the approvals, the folder and every
    /// other rule with it (WR-05). A key that is not a list or a dictionary of the right kind
    /// still makes the file unreadable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        approvals = try container.decodeIfPresent([String: Lossy<String>].self, forKey: .approvals)?
            .compactMapValues(\.value) ?? [:]
        timeLimits = try container.decodeIfPresent([String: Lossy<Int>].self, forKey: .timeLimits)?
            .compactMapValues(\.value) ?? [:]
        rules = try container.decodeIfPresent([Lossy<AutomationRule>].self, forKey: .rules)?
            .compactMap(\.value) ?? []
        ruleOrder = try container.decodeIfPresent([Lossy<UUID>].self, forKey: .ruleOrder)?
            .compactMap(\.value) ?? []
        profileHooks = try container.decodeIfPresent([Lossy<ProfileHook>].self, forKey: .profileHooks)?
            .compactMap(\.value) ?? []
        hasMigratedLegacyData = try container.decodeIfPresent(Bool.self, forKey: .hasMigratedLegacyData) ?? false
    }
}

/// What a failed `open` of a store file means (WR-03). Only a file that was read and is not a
/// store may be set aside; a file that could not be opened for a passing reason is left alone.
nonisolated enum ScriptFileOpenFailure: Equatable, Sendable {
    /// Nothing is there: the first start.
    case missing
    /// A link is in the file's place (the file is opened without following links), so it is not
    /// a store.
    case notAStore
    /// Too many open files, an interrupted call, no permission, an I/O error: the file may be
    /// fine. It is neither read nor moved nor overwritten for this session.
    case unavailable

    init(errno code: Int32) {
        switch code {
        case ENOENT: self = .missing
        case ELOOP: self = .notAStore
        default: self = .unavailable
        }
    }
}

/// Splits the rules between the settings and `Scripts.json`, and puts them back together.
///
/// A rule that uses a script lives only in the store of this Mac (D-05, T-11-H1): the copy in
/// `Defaults`, which an export carries, holds none, and an import neither brings nor removes one.
nonisolated enum AutomationRuleStorage {
    /// The rules for the settings, the rules that use a script, and the identifier of every
    /// rule in order.
    static func split(_ rules: [AutomationRule]) -> (settings: [AutomationRule], local: [AutomationRule], order: [UUID]) {
        (
            settings: rules.filter { !$0.usesScript },
            local: rules.filter(\.usesScript),
            order: rules.map(\.id)
        )
    }

    /// The rules of the settings and of the store together, by `order`.
    ///
    /// The rules of this Mac's store always win: a rule of the settings that uses a script is
    /// left out (it came from a file, not from this Mac's store), and so is a rule of the
    /// settings whose identifier a rule of the store has (an old export of a rule that was a plain
    /// rule then, or a crafted file), so a file never replaces a script rule and the next save
    /// never deletes one (T-11-H1). The store's rules are never cut by the limit; the settings'
    /// rules take what room is left. The rules the order does not name follow the ordered ones, in
    /// their own order. A repeated identifier is kept once.
    static func merge(settings: [AutomationRule], local: [AutomationRule], order: [UUID]) -> [AutomationRule] {
        let own = AutomationRule.validated(local)
        let ownIDs = Set(own.map(\.id))
        let room = max(0, AutomationRule.maximumCount - own.count)
        let others = AutomationRule.validated(settings.filter { !$0.usesScript && !ownIDs.contains($0.id) })
            .prefix(room)
        let all = others + own
        var byID = [UUID: AutomationRule]()
        for rule in all {
            byID[rule.id] = rule
        }
        var used = Set<UUID>()
        var result = [AutomationRule]()
        for id in order {
            if let rule = byID[id], used.insert(id).inserted {
                result.append(rule)
            }
        }
        for rule in all where used.insert(rule.id).inserted {
            result.append(rule)
        }
        return result
    }

    /// How many rules of the settings that use no script have the identifier of a rule of the
    /// store, and so lose against it in ``merge``.
    static func collidingRuleCount(settings: [AutomationRule], local: [AutomationRule]) -> Int {
        let ownIDs = Set(local.map(\.id))
        return settings.filter { !$0.usesScript && ownIDs.contains($0.id) }.count
    }

    /// How many rules of the settings use a script and so are left out by ``merge``.
    static func droppedScriptRuleCount(settings: [AutomationRule]) -> Int {
        settings.filter(\.usesScript).count
    }
}
