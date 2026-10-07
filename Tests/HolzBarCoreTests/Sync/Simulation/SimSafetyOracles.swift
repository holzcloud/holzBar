import CryptoKit
import Foundation

/// The safety invariants of analysis section 2.2 that the world can observe, by invariant ID. Each oracle reads
/// the ground truth and the world's observations (writes, reads, prompts, answers, transitions), never the
/// engine's own metadata; where it needs the engine's word (claimedPast, its device ID) it asks the optional
/// introspection hooks and skips a brain that cannot answer. Violations are charged to redesigned Macs only.
enum SimSafetyOracles {
    // MARK: Registry

    /// Every safety oracle, in ID order.
    static var all: [any SimOracle] { catalogue.sorted { $0.id < $1.id } }

    /// An oracle by ID.
    static func oracle(_ id: SimInvariantID) -> SimClosureOracle? {
        catalogue.first { $0.id == id }
    }

    private static let catalogue: [SimClosureOracle] = [
        s1, s1g, s2, s3, s4, s5, s6, s7, s8, s9, pr2, n1, a6, p1, p2, p3, p4, p5, p7,
        id1, id2, id3, id4, id5, id6, j1, f1, f4, f5, f6, f7, r2, r3,
        z1, z2, z3, z4, z5, z6, b1, b2, b3, b4, b5, b6, b7, b8, b9,
    ]

    // MARK: Helpers

    /// The step record the oracle was called for.
    static func step(_ world: SimWorld) -> SimStepRecord? {
        if case .step(let record)? = world.focus { return record }
        return nil
    }

    /// Whether a user token was live just before a hook, judged by the ground truth over the changes that
    /// existed then (justified supersession, A2 section 2.5). A `pre` token is live until an answer loses it.
    static func liveBefore(_ world: SimWorld, token: String, unit: String, changeCount: Int) -> Bool {
        let truth = world.groundTruth
        guard let change = truth.change(forToken: token) else {
            if case .pre? = SimValue.origin(ofToken: token) {
                return !truth.changes.contains { $0.id < changeCount && $0.kind == .answer && $0.lostTokens.contains(token) }
            }
            return false
        }
        guard change.id < changeCount else { return false }
        for other in truth.changes where other.id < changeCount && other.id != change.id {
            switch other.kind {
            case .user:
                if other.unit == unit, other.id > change.id, (other.clock[change.mac] ?? 0) >= change.sequence { return false }
            case .answer:
                if other.lostTokens.contains(token) { return false }
            }
        }
        return true
    }

    /// Whether some ingested version's past holds a later user change of the unit (or an answer that lost the token).
    static func supersededByIngest(_ world: SimWorld, token: String, unit: String, ingests: [Int]) -> Bool {
        let truth = world.groundTruth
        let change = truth.change(forToken: token)
        for version in ingests {
            let past = truth.past(ofVersion: version)
            for other in truth.changes where past.contains(other.id) {
                switch other.kind {
                case .user:
                    guard let change else { continue }
                    if other.unit == unit, other.id > change.id, (other.clock[change.mac] ?? 0) >= change.sequence {
                        return true
                    }
                case .answer:
                    if other.lostTokens.contains(token) { return true }
                }
            }
        }
        return false
    }

    /// Whether a hook's changes are charged to a redesigned engine: the Mac runs one, or it applied a version
    /// that a redesigned Mac wrote (INV-B1).
    static func charged(_ world: SimWorld, _ hook: SimHookRecord) -> Bool {
        if world.isRedesign(hook.mac) { return true }
        return hook.ingests.contains { version in
            world.writer(ofVersion: version).map { world.isRedesign($0) } ?? false
        }
    }

    /// The user-change tokens a hook took away from a unit that were still live and not justifiably superseded.
    static func unjustifiedLosses(_ world: SimWorld, _ hook: SimHookRecord, _ transition: SimTransition) -> [String] {
        var lost: [String] = []
        for token in transition.oldTokens.subtracting(transition.newTokens).sorted() {
            switch world.groundTruth.origin(of: token) {
            case .user, .pre: break
            case .automatic, .unknown: continue
            }
            guard liveBefore(world, token: token, unit: transition.unit, changeCount: hook.changeCountBefore) else { continue }
            if let answered = hook.answered, answered.prompt.losingTokens(for: answered.answer).contains(token) { continue }
            if supersededByIngest(world, token: token, unit: transition.unit, ingests: hook.ingests) { continue }
            lost.append(token)
        }
        return lost
    }

    // MARK: INV-S1 and INV-S1g

    /// INV-S1: a sync-caused change never replaces a live user value (or a `pre` value) except by an answer whose
    /// prompt showed it as losing, or by a version whose past holds a later user change of that unit.
    static let s1 = SimClosureOracle("INV-S1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            for transition in hook.transitions {
                let lost = unjustifiedLosses(world, hook, transition)
                if !lost.isEmpty {
                    return "Mac \(hook.mac) lost \(lost.joined(separator: ", ")) at \(transition.unit) in its \(hook.name.rawValue) "
                        + "hook without an answer that showed it as losing and without a version holding a later user change"
                }
            }
        }
        return nil
    }

    /// INV-S1g: no live user change of a redesigned Mac is lost everywhere: not in any Mac's settings, any readable
    /// replica or any pending entry (losses where every holder was destroyed by non-sync events are excluded).
    static let s1g = SimClosureOracle("INV-S1g", .step) { world, _ in
        let lost = world.groundTruth.globallyLost().filter { token in
            world.groundTruth.change(forToken: token).map { world.isRedesign($0.mac) } ?? false
        }
        guard !lost.isEmpty else { return nil }
        return "live user change \(lost.joined(separator: ", ")) is held nowhere: no settings, no readable file, no pending entry"
    }
}

// MARK: - Focus and history helpers

extension SimSafetyOracles {
    static func write(_ world: SimWorld) -> SimWriteRecord? {
        if case .write(let record)? = world.focus { return record }
        return nil
    }

    static func prompt(_ world: SimWorld) -> SimPromptRecord? {
        if case .prompt(let record)? = world.focus { return record }
        return nil
    }

    static func answer(_ world: SimWorld) -> SimAnswerRecord? {
        if case .answer(let record)? = world.focus { return record }
        return nil
    }

    static func read(_ world: SimWorld) -> SimReadRecord? {
        if case .read(let record)? = world.focus { return record }
        return nil
    }

    /// A redesigned writer's write that actually reached the provider.
    static func chargedWrite(_ world: SimWorld) -> SimWriteRecord? {
        guard let write = write(world), world.isRedesign(write.mac) else { return nil }
        return write
    }

    /// Whether `data` carries `needle` raw or in its decoded property-list strings.
    static func carries(_ data: Data, _ needle: String) -> Bool {
        firstCarried(in: data, among: [needle]) != nil
    }

    /// The first needle that `data` carries raw or in its decoded property-list strings (rendered once).
    static func firstCarried(in data: Data, among needles: [String]) -> String? {
        let needles = needles.filter { !$0.isEmpty }
        guard !needles.isEmpty else { return nil }
        let rendering = SimDigest.canonicalRendering(of: data)
        for needle in needles where data.range(of: Data(needle.utf8)) != nil || rendering.contains(needle) {
            return needle
        }
        return nil
    }

    /// The encodings in which a digest could appear in a file.
    static func digestForms(of text: String) -> [String] {
        let digest = SHA256.hash(data: Data(text.utf8))
        let bytes = Data(digest)
        let lower = digest.map { String(format: "%02x", $0) }.joined()
        return [lower, lower.uppercased(), bytes.base64EncodedString()]
    }

    /// The identity markers of every Mac in the world, plain.
    static func plainMarkers(_ world: SimWorld, _ pick: (SimIdentityMarkers) -> [String]) -> [String] {
        world.macs.keys.sorted().flatMap { pick(world.macs[$0]!.markers) }
    }

    /// The digests of every Mac's markers: of each marker alone and salted either way, and of the salt.
    static func hashedMarkers(_ world: SimWorld, key: String, _ pick: (SimIdentityMarkers) -> [String]) -> [String] {
        world.oracleCache.list("hashed-\(key)-\(world.macs.count)") {
            var forms: [String] = []
            for mac in world.macs.keys.sorted() {
                let markers = world.macs[mac]!.markers
                for marker in pick(markers) {
                    for text in [marker, markers.salt + marker, marker + markers.salt, markers.salt] {
                        forms.append(contentsOf: digestForms(of: text))
                    }
                }
            }
            return forms
        }
    }

    /// What a Mac's units and files tell about which units it holds: units named by the tokens it holds.
    static func conflictedUnits(_ world: SimWorld, _ mac: SimMacName) -> [String] {
        let snapshot = world.holderSnapshot()
        var tokens = snapshot.defaults[mac] ?? []
        for file in snapshot.files { tokens.formUnion(file.tokens) }
        let units = Set(tokens.compactMap { SimWorld.unit(ofToken: $0) })
        return units.sorted().filter { world.groundTruth.conflict(mac: mac, unit: $0) }
    }

    /// The units of an ingested file that a brain says it mentions; falls back to the units of its tokens.
    static func mentionedUnits(_ world: SimWorld, by mac: SimMacName, version: Int) -> Set<String>? {
        guard let path = world.path(ofVersion: version), let data = world.data(ofVersion: version) else { return nil }
        if let known = world.introspection(of: mac)?.mentionedUnits(inFile: path, data: data) { return known }
        var tokens = Set<String>()
        for brainMac in world.brains.keys.sorted() { tokens.formUnion(world.brains[brainMac]!.heldTokens(inFile: path, data: data)) }
        guard !tokens.isEmpty else { return nil }
        return Set(tokens.compactMap { SimWorld.unit(ofToken: $0) })
    }

    /// The size of a unit's value in bytes, as the state size check counts it.
    static func size(of value: SimValue) -> Int {
        switch value {
        case .data(let bytes): bytes.count
        case .string(let text): text.utf8.count
        default: value.canonical.utf8.count
        }
    }

    static func isNonSyncDestruction(_ event: SimEvent, mac: SimMacName) -> Bool {
        switch event {
        case .reinstall(let target), .sigmaLost(let target), .restoreSigma(let target), .restorePrefs(let target),
             .restoreHome(let target, _), .clone(_, let target), .copyAccount(_, let target):
            return target == mac
        default:
            return false
        }
    }
}

// MARK: - Safety oracles, second part

extension SimSafetyOracles {
    // MARK: INV-S2 to INV-S5

    /// INV-S2: no silent revert to an older user value, nor to unset without an explicit deletion.
    static let s2 = SimClosureOracle("INV-S2", .step) { world, _ in
        guard let step = step(world) else { return nil }
        let truth = world.groundTruth
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            for transition in hook.transitions {
                let lost = unjustifiedLosses(world, hook, transition)
                // (a) the new value is a user value that happened before the one it replaces.
                for new in transition.newTokens.subtracting(transition.oldTokens) {
                    guard let newer = truth.change(forToken: new) else { continue }
                    for old in transition.oldTokens.subtracting(transition.newTokens) {
                        guard let older = truth.change(forToken: old), older.id != newer.id else { continue }
                        if (older.clock[newer.mac] ?? 0) >= newer.sequence {
                            if let answered = hook.answered, answered.prompt.losingTokens(for: answered.answer).contains(old) { continue }
                            return "Mac \(hook.mac) moved \(transition.unit) back from \(old) to the older \(new)"
                        }
                    }
                }
                // (b) the unit became unset although no explicit deletion is in the past of what was applied.
                if transition.new == nil, !lost.isEmpty {
                    let deleted = hook.ingests.contains { version in
                        let past = truth.past(ofVersion: version)
                        return truth.changes.contains { change in
                            past.contains(change.id) && change.kind == .user && change.unit == transition.unit
                                && change.tokens.isEmpty
                        }
                    }
                    if !deleted { return "Mac \(hook.mac) unset \(transition.unit) without an explicit deletion" }
                }
            }
        }
        return nil
    }

    /// INV-S3: a written file claims only what its writer has seen and carries every live entry it claims.
    static let s3 = SimClosureOracle("INV-S3", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil,
              let claimed = world.brains[write.mac]?.claimedPast(ofFile: write.path, data: write.data)
        else { return nil }
        let truth = world.groundTruth
        let seen = world.userTokens(inPastOf: write.mac)
        let over = claimed.subtracting(seen).sorted()
        if !over.isEmpty {
            return "Mac \(write.mac) published \(write.path) claiming \(over.joined(separator: ", ")), which it has not seen"
        }
        var carried = Set<String>()
        for mac in world.brains.keys.sorted() {
            carried.formUnion(world.brains[mac]!.heldTokens(inFile: write.path, data: write.data))
        }
        for token in claimed.sorted() {
            guard let unit = SimWorld.unit(ofToken: token), truth.isLive(token: token, unit: unit),
                  !carried.contains(token)
            else { continue }
            let change = truth.change(forToken: token)
            let replaced = carried.contains { other in
                guard let later = truth.change(forToken: other), let change else { return false }
                return later.unit == unit && later.id != change.id && (later.clock[change.mac] ?? 0) >= change.sequence
                    && truth.isLive(token: other, unit: unit)
            }
            if !replaced { return "Mac \(write.mac) published \(write.path) claiming \(token) but does not carry it" }
        }
        return nil
    }

    /// INV-S4: a file that does not mention a unit leaves it unchanged.
    static let s4 = SimClosureOracle("INV-S4", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) && !hook.ingests.isEmpty {
            for transition in hook.transitions where transition.new == nil && transition.old != nil {
                if let answered = hook.answered, answered.answer == .use { continue }
                let mentions = hook.ingests.compactMap { mentionedUnits(world, by: hook.mac, version: $0) }
                guard !mentions.isEmpty else { continue }
                if mentions.contains(where: { !$0.contains(transition.unit) }) {
                    return "Mac \(hook.mac) removed \(transition.unit) after reading a file that does not mention it"
                }
            }
        }
        return nil
    }

    /// INV-S5: a deletion by the user appears as an explicit deletion in the writer's next publication.
    static let s5 = SimClosureOracle("INV-S5", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil,
              let deleted = world.introspection(of: write.mac)?.deletedUnits(inFile: write.path, data: write.data)
        else { return nil }
        let truth = world.groundTruth
        let previous = world.writeLog.dropLast().last { $0.mac == write.mac && $0.version != nil }?.changeCount ?? 0
        for change in truth.changes where change.id >= previous && change.id < write.changeCount {
            guard change.kind == .user, change.mac == write.mac, change.tokens.isEmpty, let unit = change.unit else { continue }
            if deleted.contains(unit) { continue }
            let reset = truth.changes.contains {
                $0.kind == .user && $0.unit == unit && $0.id > change.id && $0.id < write.changeCount && !$0.tokens.isEmpty
            }
            if !reset { return "Mac \(write.mac) published \(write.path) without the explicit deletion of \(unit)" }
        }
        return nil
    }

    // MARK: INV-S6, INV-S7

    /// INV-S6: single writer. A Mac writes only its own device file, and over it only when it is absent or was
    /// read in this session and is dominated.
    static let s6 = SimClosureOracle("INV-S6", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil else { return nil }
        if write.path == SimLimits.legacyPath {
            return "Mac \(write.mac) wrote the shared file \(write.path)"
        }
        let own = world.introspection(of: write.mac)?.report().ownFilePath
        if let own {
            if write.path != own { return "Mac \(write.mac) wrote \(write.path), not its own file \(own)" }
        } else if !SimLimits.isDeviceFile(write.path) {
            return "Mac \(write.mac) wrote \(write.path), which is no device file"
        }
        if case .absent = write.previousEntry { return nil }
        if !(write.previousSeenInSession && write.previousDominated) {
            return "Mac \(write.mac) wrote over \(write.path) without having read it in this session"
                + (write.previousDominated ? "" : " and it is not dominated by what the Mac has seen")
        }
        return nil
    }

    /// INV-S7: a waiting change survives quit, file deletion and later arrivals until an answer or an application.
    static let s7 = SimClosureOracle("INV-S7", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.before.keys.sorted() where world.isRedesign(mac) {
            guard let before = step.before[mac], let after = step.after[mac] else { continue }
            if isNonSyncDestruction(step.event, mac: mac) { continue }
            for token in before.heldTokens.subtracting(after.heldTokens).sorted() {
                if step.answers.contains(where: { $0.mac == mac }) { continue }
                if after.defaultsTokens.contains(token) { continue }
                guard let unit = SimWorld.unit(ofToken: token), world.groundTruth.isLive(token: token, unit: unit)
                else { continue }
                return "Mac \(mac) dropped the waiting change \(token) without an answer or an application"
            }
        }
        return nil
    }

    // MARK: INV-S8, INV-PR2, INV-ID5

    /// INV-S8: no marker and no local key appears in a written byte.
    static let s8 = SimClosureOracle("INV-S8", .write) { world, _ in
        guard let write = chargedWrite(world) else { return nil }
        if let needle = firstCarried(in: write.data, among: plainMarkers(world) { $0.all }) {
            return "\(write.path) written by \(write.mac) contains the planted marker \(needle)"
        }
        if let key = firstCarried(in: write.data, among: SimKeys.localKeys.sorted() + ["SettingsSync"]) {
            return "\(write.path) written by \(write.mac) contains the local key \(key)"
        }
        return nil
    }

    /// INV-PR2: no identifier and no SHA-256 of one, with or without the salt, appears in a written byte.
    static let pr2 = SimClosureOracle("INV-PR2", .write) { world, _ in
        guard let write = chargedWrite(world) else { return nil }
        if let needle = firstCarried(in: write.data, among: plainMarkers(world, { $0.all })) {
            return "\(write.path) written by \(write.mac) contains the planted identifier \(needle)"
        }
        if let needle = firstCarried(in: write.data, among: hashedMarkers(world, key: "all") { $0.all }) {
            return "\(write.path) written by \(write.mac) contains the digest \(needle.prefix(16)) of a planted identifier"
        }
        for mac in world.macs.keys.sorted() {
            let digest = Data(SHA256.hash(data: Data(world.macs[mac]!.markers.hardwareID.utf8)))
            if write.data.range(of: digest) != nil { return "\(write.path) written by \(write.mac) contains the raw digest of a hardware ID" }
        }
        return nil
    }

    /// INV-ID5: identity stays local.
    static let id5 = SimClosureOracle("INV-ID5", .write) { world, _ in
        guard let write = chargedWrite(world) else { return nil }
        let pick: (SimIdentityMarkers) -> [String] = { [$0.hardwareID, $0.salt, $0.computerName, $0.userName] }
        if let needle = firstCarried(in: write.data, among: plainMarkers(world, pick)) {
            return "\(write.path) written by \(write.mac) contains \(needle)"
        }
        if firstCarried(in: write.data, among: hashedMarkers(world, key: "identity", pick)) != nil {
            return "\(write.path) written by \(write.mac) contains a digest of a hardware ID, salt or name"
        }
        return nil
    }

    // MARK: INV-S9

    /// INV-S9: an answer supersedes exactly the values its sheet showed; Later and Cancel change nothing.
    static let s9 = SimClosureOracle("INV-S9", .answer) { world, _ in
        guard let record = answer(world), world.isRedesign(record.mac) else { return nil }
        if record.answer == .later || record.answer == .cancel, !record.transitions.isEmpty {
            return "Mac \(record.mac) changed settings on \(record.answer.canonical)"
        }
        var shown = Set<String>()
        for entry in record.prompt.shown {
            if let local = entry.local { shown.insert(local) }
            if let folder = entry.folder { shown.insert(folder) }
        }
        for transition in record.transitions {
            for token in transition.oldTokens.subtracting(transition.newTokens).sorted() where !shown.contains(token) {
                if world.groundTruth.origin(of: token) == .automatic { continue }
                return "Mac \(record.mac) superseded \(token) at \(transition.unit) by answering, but the sheet did not show it"
            }
        }
        return nil
    }

    // MARK: INV-N1, INV-A6

    /// INV-N1: no sync-caused change touches a local key (the macOS 27 families only on generation 27 Macs).
    static let n1 = SimClosureOracle("INV-N1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            let generation = world.macs[hook.mac]?.generation ?? 26
            for change in hook.keyChanges where SimLocalKeys.isLocal(change.key, generation: generation) {
                return "Mac \(hook.mac) changed the local key \(change.key) in its \(hook.name.rawValue) hook"
            }
        }
        return nil
    }

    /// INV-A6: a re-key never publishes a deletion that no user made.
    static let a6 = SimClosureOracle("INV-A6", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil,
              let introspection = world.introspection(of: write.mac),
              let deleted = introspection.deletedUnits(inFile: write.path, data: write.data)
        else { return nil }
        let truth = world.groundTruth
        let userDeleted = Set(truth.changes.filter { $0.kind == .user && $0.tokens.isEmpty }.compactMap(\.unit))
        for unit in deleted.sorted() where !userDeleted.contains(unit) {
            return "Mac \(write.mac) published a deletion of \(unit) that no user made (a re-key)"
        }
        let rekeyed = introspection.report().rekeyDeletions
        if !rekeyed.isEmpty { return "Mac \(write.mac) published the re-key deletions \(rekeyed.sorted().joined(separator: ", "))" }
        return nil
    }
}

// MARK: - Prompts

extension SimSafetyOracles {
    /// INV-P1: every prompt has a witness: a per-unit conflict this Mac takes part in, a join difference, a `pre` row
    /// or a hotkey clash.
    static let p1 = SimClosureOracle("INV-P1", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac) else { return nil }
        let joining = world.introspection(of: record.mac)?.report().joining ?? false
        if record.prompt.shown.isEmpty, !joining {
            return "Mac \(record.mac) shows \"\(record.prompt.title)\" without any value in question"
        }
        for entry in record.prompt.shown {
            if joining, entry.local != entry.folder { continue }
            if world.groundTruth.conflict(mac: record.mac, unit: entry.unit) { continue }
            if let local = entry.local, world.groundTruth.origin(of: local) == .pre { continue }
            if entry.unit.hasPrefix("Hotkeys/"), entry.local != nil, entry.folder != nil { continue }
            return "Mac \(record.mac) asks about \(entry.unit) without a conflict, a join difference, a pre value or a clash"
        }
        return nil
    }

    /// INV-P2: equal means silent.
    static let p2 = SimClosureOracle("INV-P2", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac), !record.prompt.shown.isEmpty else { return nil }
        if record.prompt.shown.allSatisfy({ $0.local == $0.folder }) {
            return "Mac \(record.mac) asks although every shown value is equal"
        }
        return nil
    }

    /// INV-P3: no repeated question after an answer other than Later.
    static let p3 = SimClosureOracle("INV-P3", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac) else { return nil }
        for earlier in world.groundTruth.prompts where earlier.mac == record.mac && earlier.prompt.id != record.prompt.id {
            guard let answered = earlier.answer, answered != .later else { continue }
            if earlier.prompt.shown == record.prompt.shown, earlier.prompt.title == record.prompt.title {
                return "Mac \(record.mac) asks \"\(record.prompt.title)\" again after answering \(answered.canonical)"
            }
        }
        return nil
    }

    /// INV-P4: Later hides the question until the next launch, which may show it once.
    static let p4 = SimClosureOracle("INV-P4", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac) else { return nil }
        if record.hook == .launch || record.hook == .command { return nil }
        let history = world.allSteps
        guard let later = history.last(where: { step in
            step.index < record.stepIndex && step.answers.contains { $0.mac == record.mac && $0.answer == .later }
        }) else { return nil }
        let launched = history.contains { step in
            step.index > later.index && step.hooks.contains { $0.mac == record.mac && $0.name == .launch }
        }
        return launched ? nil : "Mac \(record.mac) asks again after Later without a launch in between"
    }

    /// INV-P5: at most one sync sheet is open.
    static let p5 = SimClosureOracle("INV-P5", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac) else { return nil }
        if let open = record.openBefore, open.id != record.prompt.id {
            return "Mac \(record.mac) opens a second sheet while \"\(open.title)\" is open"
        }
        return nil
    }

    /// INV-P7: a Mac with no live entry in a conflict gets no menu hint, only a line in Settings.
    static let p7 = SimClosureOracle("INV-P7", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) {
            guard step.after[mac]?.report?.menuHint == true else { continue }
            if conflictedUnits(world, mac).isEmpty {
                return "Mac \(mac) shows a menu hint although it has no live entry in any conflict"
            }
        }
        return nil
    }
}

// MARK: - Identity and join

extension SimSafetyOracles {
    /// INV-ID1: two installations on one folder have different IDs once each has launched since the duplicating event.
    static let id1 = SimClosureOracle("INV-ID1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        let history = world.allSteps
        for hook in step.hooks where hook.name == .launch && world.isRedesign(hook.mac) {
            guard let own = step.after[hook.mac]?.report?.deviceID else { continue }
            for other in step.after.keys.sorted() where other != hook.mac && world.isRedesign(other) {
                guard step.after[other]?.report?.deviceID == own,
                      step.after[other]?.folderID == step.after[hook.mac]?.folderID
                else { continue }
                var lastDuplicate = 0
                for past in history {
                    switch past.event {
                    case .clone(let from, let to), .copyAccount(let from, let to):
                        if Set([from, to]) == Set([hook.mac, other]) { lastDuplicate = past.index }
                    case .restorePrefs(let mac) where mac == hook.mac || mac == other:
                        lastDuplicate = past.index
                    default: break
                    }
                }
                func launched(_ mac: SimMacName) -> Bool {
                    history.contains { $0.index > lastDuplicate && $0.hooks.contains { $0.mac == mac && $0.name == .launch } }
                }
                if launched(hook.mac), launched(other) {
                    return "Macs \(hook.mac) and \(other) both use the device ID \(own) after launching"
                }
            }
        }
        return nil
    }

    /// INV-ID2: an ID changes only with a stated reason, and then the Mac is joining again.
    static let id2 = SimClosureOracle("INV-ID2", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.before.keys.sorted() where world.isRedesign(mac) {
            guard let before = step.before[mac]?.report?.deviceID, let after = step.after[mac]?.report,
                  let new = after.deviceID, new != before
            else { continue }
            if !after.joining { return "Mac \(mac) changed its device ID from \(before) to \(new) without joining again" }
            if after.reidentifyReason == nil { return "Mac \(mac) changed its device ID from \(before) to \(new) without a reason" }
        }
        return nil
    }

    /// INV-ID3: a file that carries this Mac's ID without this Mac having written it is never treated as its own.
    static let id3 = SimClosureOracle("INV-ID3", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where world.isRedesign(hook.mac) {
            guard let introspection = world.introspection(of: hook.mac),
                  let own = step.before[hook.mac]?.report?.deviceID ?? step.after[hook.mac]?.report?.deviceID
            else { continue }
            for read in hook.reads {
                guard case .data(let data, let version) = read.entry.result, version > 0,
                      let writer = world.writer(ofVersion: version), writer != hook.mac,
                      introspection.writerID(inFile: read.entry.path, data: data) == own
                else { continue }
                let after = step.after[hook.mac]?.report
                let handled = after?.foreignPaths.contains(read.entry.path) == true || (after?.deviceID).map { $0 != own } == true
                if !handled { return "Mac \(hook.mac) treats \(read.entry.path), written by \(writer) under its ID \(own), as its own" }
            }
        }
        return nil
    }

    /// INV-ID4: own means written by me; an older version of mine that comes back is not applied as new.
    static let id4 = SimClosureOracle("INV-ID4", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) && !hook.transitions.isEmpty {
            for version in hook.ingests {
                guard world.writer(ofVersion: version) == hook.mac, let path = world.path(ofVersion: version) else { continue }
                let newest = world.writeLog.filter { $0.mac == hook.mac && $0.path == path }.compactMap(\.version).max() ?? version
                if version < newest {
                    return "Mac \(hook.mac) applied its own older version v\(version) of \(path) (its newest is v\(newest))"
                }
            }
        }
        return nil
    }

    /// INV-ID6: a file whose context covers dots this Mac never minted is not joined before the Mac re-identifies.
    static let id6 = SimClosureOracle("INV-ID6", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where world.isRedesign(hook.mac) && !hook.ingests.isEmpty {
            guard let introspection = world.introspection(of: hook.mac),
                  let before = step.before[hook.mac]?.report, let own = before.deviceID, let counter = before.ownCounter
            else { continue }
            for version in hook.ingests {
                guard let path = world.path(ofVersion: version), let data = world.data(ofVersion: version),
                      let claimed = introspection.claimedCounter(ofDevice: own, inFile: path, data: data), claimed > counter
                else { continue }
                if step.after[hook.mac]?.report?.deviceID == own {
                    return "Mac \(hook.mac) joined \(path), whose context covers its dot \(claimed) beyond its own \(counter), without re-identifying"
                }
            }
        }
        return nil
    }

    /// INV-J1: a join never commits while a listed device file is unread, and Cancel writes nothing.
    static let j1 = SimClosureOracle("INV-J1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) {
            guard let before = step.before[mac]?.report, let after = step.after[mac]?.report else { continue }
            if !before.joinCommitted, after.joinCommitted {
                let unread = after.unreadListedFiles.subtracting(after.refusedFiles)
                if !unread.isEmpty { return "Mac \(mac) committed its join while \(unread.sorted().joined(separator: ", ")) is unread" }
            }
        }
        for record in step.answers where record.answer == .cancel && world.isRedesign(record.mac) {
            if !record.writes.isEmpty { return "Mac \(record.mac) wrote \(record.writes[0].path) after Cancel" }
            if step.before[record.mac]?.enabled != step.after[record.mac]?.enabled
                || step.before[record.mac]?.folderID != step.after[record.mac]?.folderID {
                return "Mac \(record.mac) changed its sync setting after Cancel"
            }
        }
        return nil
    }
}

// MARK: - File-provider realities

extension SimSafetyOracles {
    /// INV-F1: a partial, corrupt or wrong-typed file is never ingested and never read as empty.
    static let f1 = SimClosureOracle("INV-F1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            let unreliable = hook.reads.first { read in
                if read.entry.wasPartial { return true }
                if case .foreign? = read.versionKind { return true }
                if case .data(_, let version) = read.entry.result, version == 0, read.replicaVersion == 0 { return true }
                return false
            }
            guard let bad = unreliable else { continue }
            let reliable = hook.reads.contains { $0.version > 0 && !$0.entry.wasPartial && $0.versionKind == .write }
            if !hook.transitions.isEmpty, !reliable {
                return "Mac \(hook.mac) changed settings after reading the unreliable file \(bad.entry.path)"
            }
            if hook.ingests.contains(where: { world.kind(ofVersion: $0).map { if case .foreign = $0 { true } else { false } } ?? false }) {
                return "Mac \(hook.mac) ingested foreign bytes from \(bad.entry.path)"
            }
        }
        return nil
    }

    private static func dominatedChange(_ world: SimWorld, _ step: SimStepRecord, copies: Bool) -> String? {
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            guard !hook.ingests.isEmpty, hook.ingests.allSatisfy({ hook.dominatedIngests.contains($0) }) else { continue }
            let isCopy = hook.ingests.contains { version in
                if case .conflictCopy? = world.kind(ofVersion: version) { return true }
                return false
            }
            guard isCopy == copies else { continue }
            let hinted = step.after[hook.mac]?.hint != nil && step.before[hook.mac]?.hint == nil
            if !hook.transitions.isEmpty || !hook.prompts.isEmpty || hinted {
                return "Mac \(hook.mac) reacted to a dominated \(copies ? "conflict copy" : "version") "
                    + "(v\(hook.ingests.map(String.init).joined(separator: ", v"))) with a change, a prompt or a hint"
            }
        }
        return nil
    }

    /// INV-F4: a dominated conflict copy never causes a prompt, a hint or an apply.
    static let f4 = SimClosureOracle("INV-F4", .step) { world, _ in
        step(world).flatMap { dominatedChange(world, $0, copies: true) }
    }

    /// INV-F5: a restored or late version that is dominated is never applied and never prompted about.
    static let f5 = SimClosureOracle("INV-F5", .step) { world, _ in
        step(world).flatMap { dominatedChange(world, $0, copies: false) }
    }

    /// INV-F6: deleting a file or the folder never causes a local deletion or reset.
    static let f6 = SimClosureOracle("INV-F6", .step) { world, _ in
        guard let step = step(world) else { return nil }
        switch step.event {
        case .provider(.delete), .provider(.deleteFolder): break
        default: return nil
        }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            if let removed = hook.transitions.first(where: { $0.old != nil && $0.new == nil }) {
                return "Mac \(hook.mac) removed \(removed.unit) because a file was deleted from the folder"
            }
        }
        for mac in step.before.keys.sorted() where world.isRedesign(mac) {
            if step.before[mac]?.enabled == true, step.after[mac]?.enabled == false {
                return "Mac \(mac) turned sync off because a file was deleted from the folder"
            }
        }
        return nil
    }

    /// INV-F7: nothing is written while the folder is unavailable.
    static let f7 = SimClosureOracle("INV-F7", .step) { world, _ in
        guard let step = step(world), step.writeViolationsAdded > 0 else { return nil }
        for violation in world.violations.suffix(step.writeViolationsAdded) where world.isRedesign(violation.mac) {
            return "Mac \(violation.mac) wrote \(violation.path) while its folder was unmounted"
        }
        return nil
    }

    /// INV-R2: launch adds at most one second.
    static let r2 = SimClosureOracle("INV-R2", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.name == .launch && world.isRedesign(hook.mac) && hook.blockedMilliseconds > 1_000 {
            return "Mac \(hook.mac) blocked its launch for \(hook.blockedMilliseconds) ms on the folder"
        }
        return nil
    }

    /// INV-R3: nothing is mounted by the sync code.
    static let r3 = SimClosureOracle("INV-R3", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) {
            let before = step.before[mac]?.report?.mountAttempts ?? 0
            let after = step.after[mac]?.report?.mountAttempts ?? 0
            if after > before { return "Mac \(mac) tried to mount a volume" }
        }
        return nil
    }
}

// MARK: - Size and refusal

extension SimSafetyOracles {
    /// INV-Z1: every written file is at most the limit of its path.
    static let z1 = SimClosureOracle("INV-Z1", .write) { world, _ in
        guard let write = chargedWrite(world), write.data.count > SimLimits.deviceFileWriter else { return nil }
        return "Mac \(write.mac) wrote \(write.data.count) bytes to \(write.path), above the limit of \(SimLimits.deviceFileWriter)"
    }

    /// INV-Z2: no reader refuses a file a writer of the same build wrote within the writer limit.
    static let z2 = SimClosureOracle("INV-Z2", .read) { world, _ in
        guard let read = read(world), world.isRedesign(read.mac), case .tooLarge(let size) = read.entry.result,
              size <= SimLimits.deviceFileWriter, read.replicaVersion > 0,
              let writer = world.writer(ofVersion: read.replicaVersion), world.isRedesign(writer)
        else { return nil }
        return "Mac \(read.mac) refused \(read.entry.path) of \(size) bytes that \(writer) wrote within its limit"
    }

    /// INV-Z3: a state too large to publish is not written and shows a warning.
    static let z3 = SimClosureOracle("INV-Z3", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) {
            guard let report = step.after[mac]?.report, let state = world.macs[mac] else { continue }
            let units = SimUnits.units(of: state.defaults).filter { SimLocalKeys.isSyncedUnit($0.unit, generation: state.generation) }
            let total = units.reduce(0) { $0 + size(of: $1.value) }
            if total > SimLimits.stateSizeWarning, !report.sizeWarning {
                return "Mac \(mac) holds \(total) bytes of synced settings, too many to publish, and shows no warning"
            }
        }
        return nil
    }

    /// INV-Z4: the local sync state is bounded by the devices ever seen.
    static let z4 = SimClosureOracle("INV-Z4", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) {
            guard let report = step.after[mac]?.report else { continue }
            let bound = 4_096 + 512 * max(report.devicesSeen, 1)
            if report.sigmaBytes > bound {
                return "Mac \(mac) keeps \(report.sigmaBytes) bytes of sync state for \(report.devicesSeen) devices (bound \(bound))"
            }
        }
        return nil
    }

    /// INV-Z5: the number of device files holzBar created stays within a constant plus a few per Mac.
    static let z5 = SimClosureOracle("INV-Z5", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil else { return nil }
        let paths = Set(world.writeLog.filter { world.isRedesign($0.mac) && $0.version != nil }.map(\.path))
        let macs = world.macs.keys.filter { world.isRedesign($0) }.count
        let bound = 16 + 4 * macs
        return paths.count > bound ? "holzBar created \(paths.count) files for \(macs) Macs (bound \(bound))" : nil
    }

    /// INV-Z6: a file that is too large, partial, dataless, foreign or unreadable is never written over.
    static let z6 = SimClosureOracle("INV-Z6", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil else { return nil }
        switch write.previousEntry {
        case .dataless, .partial, .symbolicLink:
            return "Mac \(write.mac) wrote over \(write.path) although its content was not readable"
        case .present(let data) where data.count > SimLimits.deviceFileReader:
            return "Mac \(write.mac) wrote over \(write.path), which is too large to read"
        case .present, .absent:
            break
        }
        if case .foreign? = write.previousKind { return "Mac \(write.mac) wrote over foreign bytes at \(write.path)" }
        return nil
    }
}

// MARK: - Compatibility

extension SimSafetyOracles {
    /// INV-B1: a redesigned Mac never writes the file older peers read.
    static let b1 = SimClosureOracle("INV-B1", .write) { world, _ in
        guard let write = chargedWrite(world), write.path == SimLimits.legacyPath else { return nil }
        return "Mac \(write.mac) wrote \(write.path), which Macs on 0.0.6 and 0.0.7-beta1 apply"
    }

    /// INV-B2: if a redesigned Mac does write the older file, it carries every importable key it holds.
    static let b2 = SimClosureOracle("INV-B2", .write) { world, _ in
        guard let write = chargedWrite(world), write.path == SimLimits.legacyPath,
              let file = SimMacBeta1.parse(write.data), let defaults = world.macs[write.mac]?.defaults
        else { return nil }
        for key in SimKeys.importableKeys where defaults[key] != nil && file.settings[key] == nil {
            return "Mac \(write.mac) wrote \(write.path) without the key \(key) that it holds"
        }
        return nil
    }

    /// INV-B3: a file of an older peer never changes a user or `pre` value on a redesigned Mac without an answer.
    static let b3 = SimClosureOracle("INV-B3", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && world.isRedesign(hook.mac) {
            let legacy = hook.ingests.contains { world.path(ofVersion: $0) == SimLimits.legacyPath }
            guard legacy else { continue }
            for transition in hook.transitions where !unjustifiedLosses(world, hook, transition).isEmpty {
                return "Mac \(hook.mac) replaced a value at \(transition.unit) from the older peer's file without an answer"
            }
        }
        return nil
    }

    /// INV-B4: at most one prompt per distinct content of an older peer's file.
    static let b4 = SimClosureOracle("INV-B4", .prompt) { world, _ in
        guard let record = prompt(world), world.isRedesign(record.mac),
              case .present(let data) = world.replica(of: record.mac).entry(SimLimits.legacyPath)
        else { return nil }
        let legacyTokens = SimMacBeta1().heldTokens(inFile: SimLimits.legacyPath, data: data)
        let folder = record.prompt.shown.compactMap(\.folder)
        guard !folder.isEmpty, folder.allSatisfy(legacyTokens.contains) else { return nil }
        for earlier in world.groundTruth.prompts where earlier.mac == record.mac && earlier.prompt.id != record.prompt.id {
            if earlier.prompt.shown == record.prompt.shown {
                return "Mac \(record.mac) asks a second time about the same content of the older peer's file"
            }
        }
        return nil
    }

    /// INV-B5: the pause gap. A `pre` value is never replaced without an answer.
    static let b5 = SimClosureOracle("INV-B5", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            for transition in hook.transitions {
                for token in unjustifiedLosses(world, hook, transition) where world.groundTruth.origin(of: token) == .pre {
                    return "Mac \(hook.mac) replaced the pre-existing value \(token) at \(transition.unit) without an answer"
                }
            }
        }
        return nil
    }

    /// INV-B6: the state of an older build is never evidence of dominance.
    static let b6 = SimClosureOracle("INV-B6", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for mac in step.after.keys.sorted() where world.isRedesign(mac) && step.after[mac]?.report?.usedLegacyStateAsEvidence == true {
            return "Mac \(mac) used the state of an older build as evidence in a decision"
        }
        return nil
    }

    /// INV-B7: after redesign, older build, redesign, nothing of the new format was overwritten and the return is a join.
    static let b7 = SimClosureOracle("INV-B7", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for write in step.writes where write.brainKind == .beta1 && write.path.hasPrefix(SimLimits.devicePrefix) {
            return "Mac \(write.mac) on the older build wrote the new format's file \(write.path)"
        }
        let history = world.allSteps
        for hook in step.hooks where hook.name == .launch && world.isRedesign(hook.mac) {
            guard let back = history.last(where: { past in
                if case .updateApp(let mac, let version) = past.event { return mac == hook.mac && (version == .redesign || version == .redesignSkew) }
                return false
            }), let away = history.last(where: { past in
                if case .updateApp(let mac, .beta1) = past.event { return mac == hook.mac && past.index < back.index }
                return false
            }), history.contains(where: { past in
                past.index > away.index && past.index < back.index
                    && past.hooks.contains { $0.mac == hook.mac && $0.name == .launch && $0.brainKind == .beta1 }
            }) else { continue }
            let launchedSince = history.contains { past in
                past.index > back.index && past.index < step.index
                    && past.hooks.contains { $0.mac == hook.mac && $0.name == .launch && world.isRedesign($0.mac) }
            }
            if !launchedSince, step.after[hook.mac]?.report?.joining != true {
                return "Mac \(hook.mac) returned from an older build without joining again"
            }
        }
        return nil
    }

    /// INV-B8: a redesigned Mac never rewrites data of a newer build.
    static let b8 = SimClosureOracle("INV-B8", .write) { world, _ in
        guard let write = chargedWrite(world), write.version != nil, let previous = write.previousWriter,
              previous != write.mac, world.macs[previous]?.version == .redesignSkew, world.macs[write.mac]?.version == .redesign
        else { return nil }
        return "Mac \(write.mac) rewrote \(write.path), which a newer build (\(previous)) wrote"
    }

    /// INV-B9: a redesigned Mac never writes the oldest peer's `device` field or touches `holzIce/`.
    static let b9 = SimClosureOracle("INV-B9", .write) { world, _ in
        guard let write = chargedWrite(world) else { return nil }
        if write.path.hasPrefix("holzIce/") { return "Mac \(write.mac) wrote \(write.path) under holzIce/" }
        if let object = try? PropertyListSerialization.propertyList(from: write.data, options: [], format: nil),
           let file = object as? [String: Any], file["device"] != nil {
            return "Mac \(write.mac) wrote a device field into \(write.path)"
        }
        return nil
    }
}
