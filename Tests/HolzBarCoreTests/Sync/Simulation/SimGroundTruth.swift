import Foundation

/// Who caused a step that may have removed tokens from a holder.
enum SimStepCause: Sendable {
    /// A sync peer's own code (apply, merge, write, adopt).
    case sync
    /// Anything else: the user, the provider, a wipe, a reinstall, a restore, a load-time writer.
    case nonSync
}

/// Where the origin of a value comes from (A2 section 2.3).
enum SimOrigin: Equatable, Sendable {
    case user
    case automatic
    /// Present before the Mac's first redesigned run; provenance unknown.
    case pre
    /// Not a token: a default or foreign value.
    case unknown
}

/// A readable file version in some replica, with the tokens its brain decoded from it.
struct SimHeldFile: Equatable, Sendable {
    var place: String
    var mac: SimMacName
    var path: String
    /// The provider version the bytes belong to.
    var version: Int
    var tokens: Set<String>
}

/// Everything that holds tokens at one moment: the Macs' defaults, every readable file in every replica and
/// every brain's pending holdings. The world builds it; hand-built traces in tests set it directly.
struct SimHolderSnapshot: Equatable, Sendable {
    var defaults: [SimMacName: Set<String>] = [:]
    var files: [SimHeldFile] = []
    var pending: [SimMacName: Set<String>] = [:]

    init(defaults: [SimMacName: Set<String>] = [:], files: [SimHeldFile] = [], pending: [SimMacName: Set<String>] = [:]) {
        self.defaults = defaults
        self.files = files
        self.pending = pending
    }

    /// Every token held anywhere.
    var allTokens: Set<String> {
        var all = Set<String>()
        for tokens in defaults.values { all.formUnion(tokens) }
        for file in files { all.formUnion(file.tokens) }
        for tokens in pending.values { all.formUnion(tokens) }
        return all
    }

    /// The places a token is held at, as stable strings.
    func places(of token: String) -> Set<String> {
        var places = Set<String>()
        for (mac, tokens) in defaults where tokens.contains(token) { places.insert("defaults:\(mac)") }
        for file in files where file.tokens.contains(token) { places.insert("file:\(file.place)") }
        for (mac, tokens) in pending where tokens.contains(token) { places.insert("pending:\(mac)") }
        return places
    }
}

/// The ground truth of a run, computed from the event trace alone: vector clocks over program order and
/// file-ingest edges give `Past`, liveness, global loss and the per-unit conflict (A2 sections 2.4, 2.5 and 8;
/// analysis section 2.3 amendments). It never reads engine metadata; the engine's own claim about its past is
/// only compared against it through `claimedPast`.
final class SimGroundTruth {
    /// A user change or an answer: the events that make up `Past`.
    struct Change: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case user, answer }

        var id: Int
        var kind: Kind
        var mac: SimMacName
        /// The writer's own clock component after the event: the change is in a past whose clock is at least this.
        var sequence: Int
        var unit: String?
        var tokens: [String]
        var time: Int64
        /// The Mac's vector clock right after the event.
        var clock: [SimMacName: Int]
        /// For an answer: the tokens that lost.
        var lostTokens: Set<String> = []
        /// For an answer: the shown values it kept. The answer asserts them again, from then on.
        var retainedTokens: Set<String> = []
        /// The changes the Mac's user knew of when this one happened: the values the Mac's settings held or the
        /// sheet showed. A redesigned Mac merges versions without telling its user, so merging informs nobody.
        var informed: Set<Int> = []
        /// The Mac's own earlier changes that its settings no longer carried when this one happened (a restore, a clone, a
        /// reinstall replaced them): this change does not know of them, whatever its clock says.
        var forgotten: Set<Int> = []
        /// The build of the Mac when it happened: a Mac that was updated since is charged for what its new build does, not for
        /// what the old one did.
        var build: SimMacVersion?
    }

    struct Version: Equatable, Sendable {
        var id: Int
        var writer: SimMacName?
        var path: String
        var clock: [SimMacName: Int]
        var time: Int64
        /// For a provider-made copy: the version whose content it holds.
        var originVersion: Int?
        /// The writer's own changes that its sync state had lost when it wrote: the file does not carry them, whatever its
        /// counters say.
        var forgotten: Set<Int> = []
        /// Changes whose values the file carries under the writer's own dots (read from the legacy file, which has none): they are
        /// in no clock.
        var extra: Set<Int> = []
    }

    /// One open prompt as shown.
    struct ShownPrompt: Equatable, Sendable {
        var mac: SimMacName
        var prompt: SimPrompt
        var time: Int64
        var answer: SimAnswer?
        var answeredAt: Int64?
    }

    private enum HolderStatus {
        case holding
        case removedBySync
        case removedByNonSync
    }

    /// Supplies the current holders. The world sets it; tests set it by hand.
    var holderSource: () -> SimHolderSnapshot = { SimHolderSnapshot() }
    private var cachedHolders: SimHolderSnapshot?
    /// While the oracles of one moment run, nothing in the world changes, so the holders are computed once.
    var isCachingHolders = false {
        didSet {
            if !isCachingHolders {
                cachedHolders = nil
                memoPasts = [:]
            }
        }
    }
    private var memoPasts: [String: Set<Int>] = [:]

    private func remembered(_ key: String, _ compute: () -> Set<Int>) -> Set<Int> {
        guard isCachingHolders else { return compute() }
        if let known = memoPasts[key] { return known }
        let value = compute()
        memoPasts[key] = value
        return value
    }

    func holders() -> SimHolderSnapshot {
        guard isCachingHolders else { return holderSource() }
        if let cachedHolders { return cachedHolders }
        let snapshot = holderSource()
        cachedHolders = snapshot
        return snapshot
    }

    private(set) var changes: [Change] = [] {
        didSet {
            // The indexes follow the list, which only ever grows by appending.
            for index in oldValue.count..<changes.count {
                let change = changes[index]
                switch change.kind {
                case .user: if let unit = change.unit { userChangesByUnit[unit, default: []].append(index) }
                case .answer: answerIndexes.append(index)
                }
            }
        }
    }
    /// The positions in `changes` of the user changes of each unit, and of the answers.
    private var userChangesByUnit: [String: [Int]] = [:]
    private var answerIndexes: [Int] = []
    private(set) var versions: [Int: Version] = [:]
    private(set) var prompts: [ShownPrompt] = []
    private(set) var eventLog: [String] = []
    /// What the user knows: the clock of own changes and of the versions the Mac applied or was asked about.
    private var clocks: [SimMacName: [SimMacName: Int]] = [:]
    /// What the Mac has merged: the clock a version it writes carries, since its file relays what it merged.
    private var seenClocks: [SimMacName: [SimMacName: Int]] = [:]
    /// The changes the Mac's user knows of, by value.
    private var informedIDs: [SimMacName: Set<Int>] = [:]
    /// The Mac's own changes that its settings lost when they were replaced from outside.
    private var forgottenIDs: [SimMacName: Set<Int>] = [:]
    /// The part of ``forgottenIDs`` that stops a later change of the Mac from knowing of them.
    private var forgottenForKnowing: [SimMacName: Set<Int>] = [:]
    /// The Mac's own changes that its sync state lost when it was replaced (a restore, a clone, a lost Sigma): its next file does not
    /// cover them, and the file that does is a version it has not seen.
    private var engineForgottenIDs: [SimMacName: Set<Int>] = [:]
    private var generations: [SimMacName: Int] = [:]
    private var changeByToken: [String: Int] = [:]
    /// Values that a restore of the settings brought back: they were there before sync, like a first run's.
    private var restoredTokens: Set<String> = []
    private var automaticTokens: [String: SimMacName] = [:]
    private var holderStatus: [String: [String: HolderStatus]] = [:]

    init() {}

    // MARK: Recording

    /// Notes an event of the run, for scenario printing.
    func recordEvent(_ text: String, time: Int64) {
        eventLog.append("\(time) \(text)")
    }

    func setGeneration(_ generation: Int, of mac: SimMacName) {
        generations[mac] = generation
    }

    func generation(of mac: SimMacName) -> Int { generations[mac] ?? 26 }

    @discardableResult
    private func tick(_ mac: SimMacName) -> Int {
        var clock = clocks[mac] ?? [:]
        clock[mac, default: 0] += 1
        clocks[mac] = clock
        var seen = seenClocks[mac] ?? [:]
        seen[mac] = clock[mac] ?? 0
        seenClocks[mac] = seen
        return clock[mac] ?? 0
    }

    /// What a Mac's sync state knows: the causal past and what its next file covers.
    struct Knowledge: Equatable, Sendable {
        var clock: [SimMacName: Int]
        var seen: [SimMacName: Int]
        /// The changes the clock covers that the user of this knowledge does not know of (forgotten by a restore or a copy before):
        /// whoever inherits the clock inherits the gap.
        var userLack: Set<Int> = []
        /// The same for the sync state: changes that its clock covers and its replica no longer holds.
        var engineLack: Set<Int> = []
    }

    func knowledge(of mac: SimMacName) -> Knowledge {
        Knowledge(
            clock: clocks[mac] ?? [:], seen: seenClocks[mac] ?? [:],
            userLack: (forgottenIDs[mac] ?? []).union(lacksUser[mac] ?? []), engineLack: engineForgottenIDs[mac] ?? []
        )
    }

    /// The changes the Mac's clock covers that its user does not know of, inherited from the knowledge it was given.
    private var lacksUser: [SimMacName: Set<Int>] = [:]

    /// The Mac's sync state was replaced by one that knows `knowledge` (nothing for `nil`): a restore of the home folder or of
    /// Sigma, a lost state, a reinstall, a clone. Its own sequence numbers stay unique: only what it knows of others goes back.
    func replaceKnowledge(of mac: SimMacName, with knowledge: Knowledge?) {
        stateReplacedOrdinals[mac] = eventLog.count
        stateReplacedChangeCounts[mac] = changes.count
        let known = knowledge?.seen[mac] ?? 0
        engineForgottenIDs[mac] = Set(changes.filter { $0.mac == mac && $0.sequence > known }.map(\.id)).union(knowledge?.engineLack ?? [])
        amnesia.formUnion(engineForgottenIDs[mac] ?? [])
        lacksUser[mac] = knowledge?.userLack ?? []
        var clock = knowledge?.clock ?? [:]
        var seen = knowledge?.seen ?? [:]
        let own = clocks[mac]?[mac] ?? 0
        clock[mac] = max(clock[mac] ?? 0, own)
        seen[mac] = max(seen[mac] ?? 0, own)
        clocks[mac] = clock
        seenClocks[mac] = seen
    }

    /// Whether `later`, a change of a user who knew what they knew, was informed of `change`.
    func knew(_ later: Change, of change: Change) -> Bool {
        let covered = (later.clock[change.mac] ?? 0) >= change.sequence && !later.forgotten.contains(change.id)
        return covered || later.informed.contains(change.id)
    }

    /// How many changes existed when the Mac's settings were last replaced from outside: a user change before that is no
    /// part of the settings any more.
    func settingsReplaced(at mac: SimMacName) -> Int { replacedAt[mac] ?? 0 }
    private var replacedAt: [SimMacName: Int] = [:]

    /// The Mac's settings were replaced (a restore of the preferences, a clone, a reinstall): the user knows what
    /// the settings hold now and what the user changed on this Mac, and nothing else.
    func resetInformed(mac: SimMacName, tokens: some Sequence<String>, identityKept: Bool = false) {
        replacedAt[mac] = changes.count
        // What the user changed on this Mac is known only where the settings still carry it: the rest went with the old settings.
        let carried = Set(tokens.compactMap { changeByToken[$0] })
        forgottenIDs[mac] = Set(changes.filter { $0.mac == mac && !carried.contains($0.id) }.map(\.id))
        // A change the Mac's user made later does not know of what went with the settings, unless the Mac's own earlier entries are
        // still its own to the engine: preferences that went back leave the state and the ID it names, so a later change replaces them.
        if !identityKept { forgottenForKnowing[mac] = forgottenIDs[mac] }
        // Settings that went back make the state no evidence of them (a rolled-back preference file is untrusted, and the join that
        // follows starts from an empty replica): the changes the user lost are lost to the engine as well.
        amnesia.formUnion(forgottenIDs[mac] ?? [])
        informedIDs[mac] = []
        recordInformed(mac: mac, tokens: tokens)
        // What a replaced set of settings holds was there before sync knew of it, whoever made it.
        restoredTokens.formUnion(tokens)
    }

    /// The Mac's user has seen these values: they are in the Mac's settings, or a sheet showed them.
    func recordInformed(mac: SimMacName, tokens: some Sequence<String>) {
        for token in tokens {
            if let id = changeByToken[token] { informedIDs[mac, default: []].insert(id) }
        }
    }

    /// The build each Mac runs now; the world keeps it up to date.
    var buildOfMac: [SimMacName: SimMacVersion] = [:]

    /// A user change on a unit. An empty token list is a user delete (a reset to default, a removal).
    @discardableResult
    func recordUserChange(mac: SimMacName, unit: String, tokens: [String], time: Int64) -> Int {
        let sequence = tick(mac)
        // A value the Mac read from the legacy file is an entry of its own now, which the user's next change of the unit replaces
        // (the user need not have seen it).
        let legacyOfUnit = (legacyRead[mac] ?? []).filter { changes[$0].unit == unit }
        let change = Change(
            id: changes.count, kind: .user, mac: mac, sequence: sequence, unit: unit, tokens: tokens,
            time: time, clock: clocks[mac] ?? [:], informed: (informedIDs[mac] ?? []).union(legacyOfUnit),
            forgotten: (forgottenForKnowing[mac] ?? []).union(engineForgottenIDs[mac] ?? []).union(lacksUser[mac] ?? []),
            build: buildOfMac[mac]
        )
        changes.append(change)
        for token in tokens { changeByToken[token] = change.id }
        informedIDs[mac, default: []].insert(change.id)
        return change.id
    }

    /// An automatic change: it advances the Mac's clock but is no part of any `Past`.
    func recordAutomaticChange(mac: SimMacName, unit: String, tokens: [String], time: Int64, syncWasOff: Bool = false) {
        tick(mac)
        for token in tokens {
            automaticTokens[token] = mac
            automaticOrdinals[token] = eventLog.count
            if syncWasOff { placedWhileOff.insert(token) }
        }
    }

    /// Automatic values placed while the Mac was not in a group: no sync state existed then to note that holzBar placed them, and
    /// a store sends no intent, so at the join they are values the Mac holds and the group does not (D-10).
    private var placedWhileOff: Set<String> = []

    /// Whether `mac`'s engine state was lost or replaced after `token`, an automatic value, was placed: the engine that held the
    /// note that holzBar placed it (`automatic` in Sigma) is gone, and the value looks like the user's.
    func engineForgot(_ token: String, at mac: SimMacName) -> Bool {
        // The note lived in the Sigma of the Mac that placed it; every other Mac only relays what that Mac published.
        if placedWhileOff.contains(token) { return true }
        let owner = automaticTokens[token] ?? mac
        guard let placed = automaticOrdinals[token] else { return false }
        // A placement from before the Mac's join committed is a value that was there before sync (A1 S-08): the join publishes it where
        // the group has none.
        if let joined = joinCommitOrdinals[owner], placed <= joined { return true }
        guard let replaced = stateReplacedOrdinals[owner] else { return false }
        return placed <= replaced
    }

    private var automaticOrdinals: [String: Int] = [:]
    private var joinCommitOrdinals: [SimMacName: Int] = [:]

    /// The Mac's join committed: what it held before is what the join published.
    func recordJoinCommit(mac: SimMacName) {
        joinCommitOrdinals[mac] = eventLog.count
    }
    private var stateReplacedOrdinals: [SimMacName: Int] = [:]
    private var stateReplacedChangeCounts: [SimMacName: Int] = [:]

    /// The preferences of the Mac went back: the ID in them may be an older one, and the entries the Mac made under the one it held
    /// are those of another identity once it takes a new one.
    func recordPreferencesRestored(mac: SimMacName) {
        stateReplacedChangeCounts[mac] = changes.count
    }

    /// Whether `change` was made by this Mac before its sync state was replaced: the Mac's file of that time is one of another identity
    /// now, and what it holds is a change of "another Mac" to the engine.
    func isOfPreviousState(_ change: Change, at mac: SimMacName) -> Bool {
        guard change.mac == mac, let count = stateReplacedChangeCounts[mac] else { return false }
        return change.id < count
    }

    /// A Mac wrote a version. The version's past is a copy of the writer's clock.
    func recordWrite(version: Int, writer: SimMacName, path: String, time: Int64) {
        tick(writer)
        versions[version] = Version(
            id: version, writer: writer, path: path, clock: seenClocks[writer] ?? [:], time: time, originVersion: nil,
            forgotten: lostByEngine(writer), extra: (legacySeen[writer] ?? []).union(informedIDs[writer] ?? [])
        )
    }

    /// The answer did not close its prompt (the Mac refused it, or it was Cancel at a running sheet): it
    /// is no answer, so nothing it showed as losing is lost.
    func retractAnswer(mac: SimMacName, prompt: SimPrompt) {
        guard let index = changes.lastIndex(where: { $0.kind == .answer && $0.mac == mac }) else { return }
        changes[index].lostTokens = []
        changes[index].retainedTokens = []
        if let shown = prompts.lastIndex(where: { $0.mac == mac && $0.prompt.id == prompt.id && $0.answer != nil }) {
            prompts[shown].answer = nil
            prompts[shown].answeredAt = nil
        }
    }

    /// The settings hold `tokens` after the Mac answered: the answer keeps them (unless it gave them up).
    func assertHeld(mac: SimMacName, tokens: [String]) {
        guard let index = changes.lastIndex(where: { $0.kind == .answer && $0.mac == mac }) else { return }
        for token in tokens where !changes[index].lostTokens.contains(token) { changes[index].retainedTokens.insert(token) }
    }

    /// The engine did not decide some rows of the answer (the setting changed while the sheet was open): what those rows showed as
    /// losing is not lost, and the answer asserts none of it.
    func leaveOut(mac: SimMacName, prompt: SimPrompt, units: Set<String>) {
        guard !units.isEmpty, let index = changes.lastIndex(where: { $0.kind == .answer && $0.mac == mac }) else { return }
        for entry in prompt.shown where units.contains(entry.unit) {
            for token in [entry.local, entry.folder].compactMap({ $0 }) {
                changes[index].lostTokens.remove(token)
                changes[index].retainedTokens.remove(token)
            }
        }
    }

    /// Foreign bytes: a version no Mac wrote, with an empty past.
    func recordForeign(version: Int, path: String, time: Int64) {
        versions[version] = Version(id: version, writer: nil, path: path, clock: [:], time: time, originVersion: nil)
    }

    /// A provider-made copy holds the same content, so it has the same past.
    func recordCopy(version: Int, of origin: Int, path: String, time: Int64) {
        let base = versions[origin]
        versions[version] = Version(
            id: version, writer: base?.writer, path: path, clock: base?.clock ?? [:], time: time, originVersion: origin,
            forgotten: base?.forgotten ?? [], extra: base?.extra ?? []
        )
    }

    /// The brain decided on a version (applied, merged, adopted, found it dominated, or answered a prompt about it):
    /// its past joins the Mac's. Reading a version without deciding is not an ingest.
    func recordIngest(mac: SimMacName, version: Int, time: Int64) {
        guard let source = versions[version] else { return }
        var clock = clocks[mac] ?? [:]
        for (other, component) in source.clock { clock[other] = max(clock[other] ?? 0, component) }
        clocks[mac] = clock
        // The legacy file has no dots: what a redesigned Mac reads from it becomes entries of its own, so the file's past is no part of
        // what the Mac merged and relays (a later device file that carries the same changes under dots is news to it).
        if source.path != SimLimits.legacyPath {
            var seen = seenClocks[mac] ?? [:]
            for (other, component) in source.clock { seen[other] = max(seen[other] ?? 0, component) }
            seenClocks[mac] = seen
            remember(version: source, at: mac)
            legacySeen[mac, default: []].formUnion(source.extra)
        } else {
            let read = changes(coveredBy: source.clock)
            legacySeen[mac, default: []].formUnion(read)
            legacyRead[mac, default: []].formUnion(read)
        }
        tick(mac)
    }

    /// The changes whose values the Mac read from the legacy file: it may publish them under its own dots, but a device file that
    /// carries them under theirs is news to it.
    private var legacySeen: [SimMacName: Set<Int>] = [:]
    /// The changes whose values the Mac read from the legacy file itself.
    private var legacyRead: [SimMacName: Set<Int>] = [:]

    /// What the Mac's file may carry: what it merged, what it read from the legacy file, and what its own settings hold (a value
    /// that was there before sync, or that a copy brought along, is published as the Mac's).
    func claimablePast(ofMac mac: SimMacName) -> Set<Int> {
        seenPast(ofMac: mac).union(legacySeen[mac] ?? []).union(informedPast(ofMac: mac))
    }

    /// A version the Mac reads again tells it what it had forgotten: what its clock covers is seen again.
    private func remember(version source: Version, at mac: SimMacName) {
        guard var forgotten = engineForgottenIDs[mac], !forgotten.isEmpty else { return }
        forgotten.subtract(changes(coveredBy: source.clock))
        engineForgottenIDs[mac] = forgotten
    }

    /// The Mac merged a version into its state without applying it or asking its user: it will relay it, so
    /// the file it writes covers it, but the Mac's user knows nothing of it.
    func recordMerge(mac: SimMacName, version: Int, time: Int64) {
        guard let source = versions[version] else { return }
        if source.path != SimLimits.legacyPath {
            var seen = seenClocks[mac] ?? [:]
            for (other, component) in source.clock { seen[other] = max(seen[other] ?? 0, component) }
            seenClocks[mac] = seen
            remember(version: source, at: mac)
            legacySeen[mac, default: []].formUnion(source.extra)
        } else {
            let read = changes(coveredBy: source.clock)
            legacySeen[mac, default: []].formUnion(read)
            legacyRead[mac, default: []].formUnion(read)
        }
        tick(mac)
    }

    func recordPrompt(mac: SimMacName, prompt: SimPrompt, time: Int64) {
        tick(mac)
        prompts.append(ShownPrompt(mac: mac, prompt: prompt, time: time, answer: nil, answeredAt: nil))
    }

    /// The user answered a prompt. The answer is part of `Past` and supersedes the values it showed as losing.
    func recordAnswer(mac: SimMacName, prompt: SimPrompt, answer: SimAnswer, time: Int64) {
        let sequence = tick(mac)
        let lost = prompt.losingTokens(for: answer)
        // Later and Cancel decide nothing (A2 R-FUN-4): the version stays pending, so the answer neither gives a value up
        // nor asserts one.
        let decides = answer != .later && answer != .cancel
        changes.append(Change(
            id: changes.count, kind: .answer, mac: mac, sequence: sequence, unit: nil, tokens: [], time: time,
            clock: clocks[mac] ?? [:], lostTokens: lost,
            retainedTokens: decides ? Set(prompt.shown.flatMap { [$0.local, $0.folder].compactMap { $0 } }).subtracting(lost) : [],
            informed: informedIDs[mac] ?? [], forgotten: (forgottenForKnowing[mac] ?? []).union(engineForgottenIDs[mac] ?? []).union(lacksUser[mac] ?? [])
        ))
        if let index = prompts.lastIndex(where: { $0.mac == mac && $0.prompt.id == prompt.id && $0.answer == nil }) {
            prompts[index].answer = answer
            prompts[index].answeredAt = time
        }
    }

    /// Looks at the holders after a step and remembers how each token's holders went away.
    func observe(cause: SimStepCause, time: Int64) {
        let snapshot = holderSource()
        var current: [String: Set<String>] = [:]
        for token in snapshot.allTokens { current[token] = snapshot.places(of: token) }
        for token in Set(current.keys).union(holderStatus.keys).sorted() {
            var status = holderStatus[token] ?? [:]
            let now = current[token] ?? []
            for place in status.keys.sorted() where status[place] == .holding && !now.contains(place) {
                status[place] = cause == .sync ? .removedBySync : .removedByNonSync
            }
            for place in now { status[place] = .holding }
            holderStatus[token] = status
        }
    }

    // MARK: Causality

    /// The changes and answers a clock covers.
    private func changes(coveredBy clock: [SimMacName: Int]) -> Set<Int> {
        var covered = Set<Int>()
        for change in changes where (clock[change.mac] ?? 0) >= change.sequence { covered.insert(change.id) }
        return covered
    }

    /// `Past(V)`: the user changes and answers that happened before the write, through ingest edges only.
    func past(ofVersion version: Int) -> Set<Int> {
        guard let known = versions[version] else { return [] }
        return changes(coveredBy: known.clock).subtracting(known.forgotten).union(known.extra)
    }

    func scratchConflict(mac: SimMacName, unit: String) -> [String] {
        let known = knownPast(ofMac: mac)
        let held = holders().defaults[mac] ?? []
        let crossed = crossedTokens(on: unit, known: known)
        var lines = ["scratchConflict \(mac) \(unit) known=\(known.sorted()) seen=\(seenPast(ofMac: mac).sorted()) informed=\(informedPast(ofMac: mac).sorted()) held=\(held.sorted()) crossed=\(crossed.sorted())"]
        for token in held.sorted() { lines.append("  held \(token) live=\(isLive(token: token, unit: unit, known: known)) asserted=\(isAsserted(token, unit: unit, known: known))") }
        lines.append("  comparable=\(isComparable(unit: unit, on: mac)) knownConflict=\(knownConflict(mac: mac, unit: unit)) conflict=\(conflict(mac: mac, unit: unit, visibleOnly: true))")
        for index in userChangesByUnit[unit] ?? [] {
            let c = changes[index]
            lines.append("  change \(c.id) mac=\(c.mac) tokens=\(c.tokens) known=\(known.contains(c.id)) live=\(c.tokens.map { isLive(token: $0, unit: unit, known: known) }) forgotten=\(c.forgotten.sorted()) clock=\(c.clock)")
        }
        return lines
    }

    func scratchDebug() -> [String] {
        var lines: [String] = []
        for c in changes { lines.append("change \(c.id) \(c.kind) \(c.mac)#\(c.sequence) t=\(c.time) \(c.unit ?? "-") \(c.tokens) retained=\(c.retainedTokens.sorted()) lost=\(c.lostTokens.sorted()) clock=\(c.clock) informed=\(c.informed.sorted())") }
        for (m, v) in engineForgottenIDs { lines.append("engineForgotten \(m) \(v.sorted())") }
        for (m, v) in forgottenIDs { lines.append("forgotten \(m) \(v.sorted())") }
        for (m, v) in informedIDs { lines.append("informed \(m) \(v.sorted())") }
        for (m, v) in seenClocks { lines.append("seenClock \(m) \(v)") }
        for (m, v) in clocks { lines.append("clock \(m) \(v)") }
        return lines
    }

    /// How many pairs of answers crossed so far: two Macs that answered one conflict without knowing of each other's answer. Each pair
    /// may cost both Macs one more question, once.
    func crossingAnswerPairs() -> Int {
        let answers = answerIndexes.map { changes[$0] }
        var pairs = 0
        for (offset, first) in answers.enumerated() {
            for second in answers[(offset + 1)...] where first.mac != second.mac {
                guard !knew(second, of: first), !knew(first, of: second) else { continue }
                let units = Set((first.retainedTokens.union(first.lostTokens)).compactMap { SimWorld.unit(ofToken: $0) })
                    .intersection(Set((second.retainedTokens.union(second.lostTokens)).compactMap { SimWorld.unit(ofToken: $0) }))
                if !units.isEmpty,
                   !first.retainedTokens.isDisjoint(with: second.lostTokens) || !second.retainedTokens.isDisjoint(with: first.lostTokens) {
                    pairs += 1
                }
            }
        }
        // An answer and a change of the same unit by another Mac that knew nothing of each other stand in conflict as well (a user who
        // deletes or edits the setting while another answers a question about it).
        for answer in answers {
            let units = Set(answer.retainedTokens.union(answer.lostTokens).compactMap { SimWorld.unit(ofToken: $0) })
            for change in changes where change.kind == .user && change.mac != answer.mac {
                guard let unit = change.unit, units.contains(unit), !knew(answer, of: change), !knew(change, of: answer) else { continue }
                pairs += 1
            }
        }
        return pairs
    }

    /// The units whose answers crossed: the conflict stands although it was answered.
    func unitsWithCrossedAnswers() -> [String] {
        let everything = Set(changes.map(\.id))
        return Set(changes.compactMap(\.unit) + changes.flatMap { $0.retainedTokens.union($0.lostTokens).compactMap { SimWorld.unit(ofToken: $0) } })
            .sorted().filter { !crossedTokens(on: $0, known: everything).isEmpty }
    }

    /// The units that hold more than one live user value now: values of users who did not know of each other.
    func unitsWithConcurrentValues() -> [String] {
        var found: [String] = []
        for unit in userChangesByUnit.keys.sorted() {
            var live = Set<String>()
            let indexes = userChangesByUnit[unit] ?? []
            for index in indexes {
                let change = changes[index]
                for token in change.tokens where isLive(token: token, unit: unit) { live.insert(token) }
                // A deletion stands until a later change that knew of it, and it is a value that differs from the others.
                if change.tokens.isEmpty, !indexes.contains(where: { changes[$0].id > change.id && knew(changes[$0], of: change) }) {
                    live.insert("deleted:\(change.id)")
                }
            }
            if live.count > 1 { found.append(unit) }
        }
        return found
    }

    /// `Past(m, t)`: the same for a Mac's own state now.
    func past(ofMac mac: SimMacName) -> Set<Int> {
        remembered("past:\(mac.name)") { changes(coveredBy: clocks[mac] ?? [:]) }
    }

    /// The changes that the sync state of their own Mac lost at some time. The counter of that Mac stays above their dots (the
    /// floors keep dots unique), so a file it writes afterwards covers them without carrying them, and another Mac reads that as a
    /// deletion by the Mac that made them: the design of the counter floors (A2 section 4.6.6) accepts that, and an engine that
    /// took a new identity at every loss would not (it would orphan the entries instead).
    private(set) var amnesia: Set<Int> = []

    /// Whether `token` belongs to a change that its own Mac's sync state lost, so that a later file of that Mac may cover it.
    func lostToAmnesia(token: String) -> Bool {
        changeByToken[token].map { amnesia.contains($0) } ?? false
    }

    /// Whether the user of the change's Mac no longer has it (a restore or a copy replaced the settings that held it).
    func userForgot(_ change: Change) -> Bool {
        (forgottenIDs[change.mac] ?? []).contains(change.id)
    }

    /// The own changes the engine lost and the settings no longer hold.
    private func lostByEngine(_ mac: SimMacName) -> Set<Int> {
        engineForgottenIDs[mac] ?? []
    }

    /// The settings the Mac has after its sync state was replaced still hold some of the own changes the state lost: the next capture
    /// reads them from the settings again, so the engine has not lost them.
    func engineKeeps(mac: SimMacName, tokens: some Sequence<String>) {
        let tokens = Array(tokens)
        if var lost = engineForgottenIDs[mac], !lost.isEmpty {
            for token in tokens {
                if let id = changeByToken[token], lost.remove(id) != nil {
                    // A value that the settings hold and the state does not know is one that was there before sync knew of it.
                    restoredTokens.insert(token)
                }
            }
            engineForgottenIDs[mac] = lost
        }
    }

    /// A value that the settings hold and that the sync state that came back has not applied was there before sync knew of it.
    func markPre(tokens: some Sequence<String>) {
        for token in tokens where changeByToken[token] != nil { restoredTokens.insert(token) }
    }

    /// What the Mac has merged and relays: the changes its next file covers.
    func seenPast(ofMac mac: SimMacName) -> Set<Int> {
        remembered("seen:\(mac.name)") {
            changes(coveredBy: seenClocks[mac] ?? [:]).subtracting(lostByEngine(mac))
        }
    }

    /// What the Mac's user knows: its past, and the changes whose values its settings held or a sheet showed.
    func informedPast(ofMac mac: SimMacName) -> Set<Int> {
        remembered("informed:\(mac.name)") {
            past(ofMac: mac).subtracting(forgottenIDs[mac] ?? []).subtracting(lacksUser[mac] ?? []).union(informedIDs[mac] ?? [])
        }
    }

    /// What a Mac can know of: what it merged and what its user knows.
    func knownPast(ofMac mac: SimMacName) -> Set<Int> {
        remembered("known:\(mac.name)") { seenPast(ofMac: mac).union(informedPast(ofMac: mac)) }
    }

    /// The user change that minted a token.
    func change(forToken token: String) -> Change? {
        changeByToken[token].map { changes[$0] }
    }

    /// Whether holzBar placed the value itself, wherever the value sits now (a restore or a copy makes it the settings' own there,
    /// and an automatic store is still no change of the user's).
    func wasPlacedAutomatically(_ token: String) -> Bool { automaticTokens[token] != nil && changeByToken[token] == nil }

    /// Whether the value was there before sync knew of it: a restored or copied one, or an automatic placement that the Mac's engine
    /// could not tell from the user's (its note was lost, or it came before the join), which the join publishes as its own.
    func isPreLike(_ token: String, at mac: SimMacName) -> Bool {
        let origin = origin(of: token)
        return origin == .pre || (origin == .automatic && engineForgot(token, at: mac))
    }

    /// Where a token comes from.
    func origin(of token: String) -> SimOrigin {
        if restoredTokens.contains(token) { return .pre }
        if changeByToken[token] != nil { return .user }
        if automaticTokens[token] != nil { return .automatic }
        switch SimValue.origin(ofToken: token) {
        case .user?: return .user
        case .automatic?: return .automatic
        case .pre?: return .pre
        case nil: return .unknown
        }
    }

    // MARK: Liveness and loss

    /// A change stays live until a later informed user change on its unit, or an answer whose prompt showed its
    /// value as the losing alternative (A2 section 2.5, justified supersession).
    func isLive(token: String, unit: String, at time: Int64 = Int64.max, known: Set<Int>? = nil) -> Bool {
        guard let change = change(forToken: token), change.unit == unit, change.time <= time else { return false }
        for index in (userChangesByUnit[unit] ?? []) {
            let other = changes[index]
            guard other.id != change.id, other.time <= time, known?.contains(other.id) ?? true else { continue }
            if other.id > change.id, knew(other, of: change) { return false }
        }
        for index in answerIndexes {
            let other = changes[index]
            guard other.time <= time, known?.contains(other.id) ?? true else { continue }
            if other.lostTokens.contains(token) { return false }
        }
        return true
    }

    /// Whether a token is held nowhere now and every place that held it lost it to something that is not the sync peer's doing
    /// (a restore, a reinstall, a crash of the store): nothing the engine could have done keeps it.
    func wasDestroyedByNonSync(_ token: String) -> Bool {
        if holders().allTokens.contains(token) { return false }
        let status = holderStatus[token] ?? [:]
        return !status.isEmpty && status.values.allSatisfy { $0 == .removedByNonSync }
    }

    /// The live user tokens that no Mac's defaults, no readable version in any replica and no pending
    /// holding carries, excluding losses where every holder was destroyed by non-sync events (INV-S1g).
    func globallyLost(at time: Int64 = Int64.max) -> [String] {
        let held = holders().allTokens
        var lost: [String] = []
        for change in changes where change.kind == .user && change.time <= time {
            guard let unit = change.unit else { continue }
            for token in change.tokens where !held.contains(token) && isLive(token: token, unit: unit, at: time) {
                let status = holderStatus[token] ?? [:]
                let destroyedOnlyByNonSync = !status.isEmpty && status.values.allSatisfy { $0 == .removedByNonSync }
                if !destroyedOnlyByNonSync { lost.append(token) }
            }
        }
        return lost.sorted()
    }

    // MARK: Conflict

    /// Whether a Mac compares a unit: units of the macOS 27 families exist only on generation-27 Macs.
    func isComparable(unit: String, on mac: SimMacName) -> Bool {
        guard let scope = SimUnits.generationScope(unit) else { return true }
        return generation(of: mac) == scope
    }

    /// The versions in the folder that conflict with the Mac on a unit (D-07: per unit).
    ///
    /// `Conflict(m, a)` holds with a version V iff m has a live change on a that V lacks, V has a live change
    /// on a that m lacks, and the two hold different values there.
    func conflictingVersions(mac: SimMacName, unit: String, visibleOnly: Bool = false) -> [Int] {
        guard isComparable(unit: unit, on: mac) else { return [] }
        let snapshot = holders()
        // A Mac can only know of what it received: what a later change elsewhere superseded does not count yet.
        let known: Set<Int>? = visibleOnly ? knownPast(ofMac: mac) : nil
        let mine = liveTokens(of: snapshot.defaults[mac] ?? [], on: unit, known: known)
        guard !mine.isEmpty else { return [] }
        let pastOfMac = informedPast(ofMac: mac)
        var result = Set<Int>()
        for file in snapshot.files where file.version > 0 && versions[file.version] != nil && (!visibleOnly || file.mac == mac) {
            // The shared file of 0.0.6 and 0.0.7-beta1 is read by a redesigned Mac once, at a founding, which is a join
            // difference; it is no partner of a conflict (Appendix B: the two builds never share a file).
            if file.path == SimLimits.legacyPath { continue }
            let theirs = liveTokens(of: file.tokens, on: unit, known: known)
            guard !theirs.isEmpty, mine != theirs else { continue }
            let pastOfVersion = past(ofVersion: file.version)
            let iHaveWhatTheyLack = mine.contains { token in
                change(forToken: token).map { !pastOfVersion.contains($0.id) } ?? false
            }
            let theyHaveWhatILack = theirs.contains { token in
                change(forToken: token).map { !pastOfMac.contains($0.id) } ?? false
            }
            // A redesigned Mac relays what it merged: a file that holds this Mac's value live next to another
            // value has not seen it superseded, so the two are siblings in that file, a conflict too.
            let holdsMineAsSibling = !mine.isDisjoint(with: theirs)
            if iHaveWhatTheyLack || holdsMineAsSibling, theyHaveWhatILack { result.insert(file.version) }
        }
        return result.sorted()
    }

    func conflict(mac: SimMacName, unit: String, visibleOnly: Bool = false) -> Bool {
        // What the Mac can know of is a conflict as well as what the folder holds now.
        if visibleOnly, knownConflict(mac: mac, unit: unit) { return true }
        return !conflictingVersions(mac: mac, unit: unit).isEmpty
    }

    /// Whether the Mac can know of a conflict on the unit: its settings hold a live value, and it has merged a
    /// live change of the unit that its user does not know and that holds another value. The Mac keeps what it
    /// merged after the file it came in is gone or has been replaced, so a question about it has a witness
    /// whatever the provider delivered since. A hint or a sheet needs this and nothing more.
    func knownConflict(mac: SimMacName, unit: String) -> Bool {
        guard isComparable(unit: unit, on: mac) else { return false }
        let known = knownPast(ofMac: mac)
        let held = holders().defaults[mac] ?? []
        let crossed = crossedTokens(on: unit, known: known)
        var mine = Set(held.filter { isLive(token: $0, unit: unit, known: known) || isAsserted($0, unit: unit, known: known) || crossed.contains($0) })
        // The Mac's own changes that its engine holds stay its entries in a conflict although its settings were replaced and no longer
        // hold them (a restore): the group's sibling entries are still the Mac's to answer for.
        let settingsHoldNone = mine.isEmpty
        // What the Mac's own answer kept and another Mac's answer crossed is the Mac's entry whatever its settings hold now.
        if settingsHoldNone {
            for token in crossed where answerIndexes.contains(where: { changes[$0].mac == mac && changes[$0].retainedTokens.contains(token) }) {
                mine.insert(token)
            }
            // A value that the Mac took from the legacy file is an entry of its own, which waits for its Restart.
            for index in userChangesByUnit[unit] ?? [] where legacyRead[mac]?.contains(changes[index].id) == true {
                for token in changes[index].tokens where isLive(token: token, unit: unit, known: known) { mine.insert(token) }
            }
        }
        for index in userChangesByUnit[unit] ?? [] where settingsHoldNone {
            let own = changes[index]
            guard own.mac == mac, known.contains(own.id), isOfPreviousState(own, at: mac) || forgottenIDs[mac]?.contains(own.id) == true else { continue }
            for token in own.tokens where isLive(token: token, unit: unit, known: known) { mine.insert(token) }
        }
        // A Mac that holds nothing for the unit because its user removed the setting still holds that deletion.
        let unitIndexes = userChangesByUnit[unit] ?? []
        let holdsDeletion = mine.isEmpty && unitIndexes.last { changes[$0].mac == mac }.map { changes[$0] }.map { change in
            change.tokens.isEmpty && !unitIndexes.contains { index in
                let other = changes[index]
                return other.id > change.id && known.contains(other.id) && knew(other, of: change)
            }
        } == true
        // The same when the Mac's last answer about the unit took the value away (the group's deletion) and nothing newer of its own came.
        let answeredDeletion = mine.isEmpty && answerIndexes.last { index in
            let answer = changes[index]
            return answer.mac == mac && answer.retainedTokens.union(answer.lostTokens).contains { SimWorld.unit(ofToken: $0) == unit }
        }.map { changes[$0] }.map { answer in
            !answer.lostTokens.isEmpty && answer.retainedTokens.allSatisfy { SimWorld.unit(ofToken: $0) != unit }
                && !unitIndexes.contains { changes[$0].mac == mac && changes[$0].id > answer.id }
        } == true
        guard !mine.isEmpty || holdsDeletion || answeredDeletion else { return false }
        let informed = informedPast(ofMac: mac)
        // The user's own changes behind what the Mac holds. Such a change is concurrent with another's when its user had not been
        // told of it when making the change: a sheet answered afterwards decides about the two, it does not make the earlier
        // change know of the other. Without a change of the user's own (a value from another Mac, one that was there before
        // sync) what the user has been told by now decides.
        var ownBehind = mine.compactMap { change(forToken: $0) }.filter { $0.mac == mac }
        if holdsDeletion, let deletion = unitIndexes.last(where: { changes[$0].mac == mac }).map({ changes[$0] }) {
            ownBehind.append(deletion)
        }
        func isUnknownToUser(_ theirs: Change) -> Bool {
            ownBehind.isEmpty ? !informed.contains(theirs.id) : ownBehind.contains { !knew($0, of: theirs) }
        }
        // An answer that kept a value asserts it again: a value that a user superseded since, without knowing
        // of the answer, is a sibling of what this Mac holds.
        for index in answerIndexes {
            let answer = changes[index]
            guard answer.mac != mac, known.contains(answer.id) else { continue }
            for token in answer.retainedTokens where !mine.contains(token) && isAsserted(token, unit: unit, known: known) {
                return true
            }
        }
        // An answer that took a deletion (the group's, or its own Mac's) asserts that deletion again, as a fresh entry: a value that this
        // Mac's user set since, without knowing of the answer, is concurrent with it.
        if !mine.isEmpty {
            for index in answerIndexes {
                let answer = changes[index]
                guard answer.mac != mac, known.contains(answer.id), !answer.lostTokens.isEmpty,
                      answer.lostTokens.contains(where: { SimWorld.unit(ofToken: $0) == unit }),
                      !answer.retainedTokens.contains(where: { SimWorld.unit(ofToken: $0) == unit })
                else { continue }
                let supersededByUser = unitIndexes.contains { index in
                    let other = changes[index]
                    return other.id > answer.id && known.contains(other.id) && knew(other, of: answer)
                }
                let supersededByAnswer = answerIndexes.contains { index in
                    let other = changes[index]
                    return other.id > answer.id && known.contains(other.id) && knew(other, of: answer)
                        && other.retainedTokens.union(other.lostTokens).contains { SimWorld.unit(ofToken: $0) == unit }
                }
                if !supersededByUser, !supersededByAnswer, isUnknownToUser(answer) { return true }
            }
        }
        for index in unitIndexes {
            let change = changes[index]
            guard known.contains(change.id), isUnknownToUser(change) else { continue }
            if change.tokens.isEmpty {
                // A deletion is live until a later change that knew of it.
                let superseded = unitIndexes.contains { index in
                    let other = changes[index]
                    return other.id > change.id && known.contains(other.id) && knew(other, of: change)
                }
                if !superseded { return true }
            } else if change.tokens.contains(where: { !mine.contains($0) && isLive(token: $0, unit: unit, known: known) }) {
                return true
            }
        }
        return answersCross(on: unit, known: known)
    }

    /// Two answers given to one conflict without either knowing of the other (two Macs press a button at the same moment) each keep
    /// the value they chose and give up the other's: each answer is a fresh entry, and neither supersedes the other's, so both values
    /// stay live and the question comes back (D3-S04).
    func answersCross(on unit: String, known: Set<Int>) -> Bool {
        !crossedTokens(on: unit, known: known).isEmpty
    }

    /// The values the crossing answers of the unit gave up or kept: each is held by one of the answers' Macs as a live value of
    /// a user who did not know of the other's answer.
    func crossedTokens(on unit: String, known: Set<Int>) -> Set<String> {
        let relevant = answerIndexes.map { changes[$0] }.filter { answer in
            known.contains(answer.id) && answer.retainedTokens.union(answer.lostTokens).contains { SimWorld.unit(ofToken: $0) == unit }
        }
        var crossed = Set<String>()
        for first in relevant {
            for second in relevant where first.id < second.id && first.mac != second.mac {
                guard !knew(second, of: first), !knew(first, of: second) else { continue }
                let firstKeptSecondLost = first.retainedTokens.intersection(second.lostTokens)
                let secondKeptFirstLost = second.retainedTokens.intersection(first.lostTokens)
                crossed.formUnion(firstKeptSecondLost)
                crossed.formUnion(secondKeptFirstLost)
            }
        }
        return crossed
    }

    /// Whether an answer that kept the value of `token` on `unit` asserts it still: no later change that knew of
    /// the answer superseded it, and no later answer gave it up. The same value is asserted again by each answer
    /// that keeps it, which a token alone does not tell apart.
    func isAsserted(_ token: String, unit: String, known: Set<Int>) -> Bool {
        guard SimWorld.unit(ofToken: token) == unit else { return false }
        let unitIndexes = userChangesByUnit[unit] ?? []
        return answerIndexes.contains { answerIndex in
            let answer = changes[answerIndex]
            guard answer.retainedTokens.contains(token), known.contains(answer.id) else { return false }
            let supersededByUser = unitIndexes.contains { index in
                let other = changes[index]
                return other.id > answer.id && known.contains(other.id) && knew(other, of: answer)
            }
            if supersededByUser { return false }
            return !answerIndexes.contains { index in
                let other = changes[index]
                return other.id > answer.id && known.contains(other.id) && other.lostTokens.contains(token)
            }
        }
    }

    /// The units the Mac can know of a conflict on.
    func knownConflictUnits(mac: SimMacName) -> [String] {
        knownUnits(mac: mac).filter { knownConflict(mac: mac, unit: $0) }
    }

    /// The units of every change the Mac knows of: the candidates of a conflict it can know of.
    func knownUnits(mac: SimMacName) -> [String] {
        let known = knownPast(ofMac: mac)
        return Set(changes.filter { known.contains($0.id) }.compactMap(\.unit)).sorted()
    }

    private func liveTokens(of tokens: Set<String>, on unit: String, known: Set<Int>? = nil) -> Set<String> {
        Set(tokens.filter { isLive(token: $0, unit: unit, known: known) })
    }
}
