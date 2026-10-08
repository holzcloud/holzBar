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
    }

    struct Version: Equatable, Sendable {
        var id: Int
        var writer: SimMacName?
        var path: String
        var clock: [SimMacName: Int]
        var time: Int64
        /// For a provider-made copy: the version whose content it holds.
        var originVersion: Int?
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

    private(set) var changes: [Change] = []
    private(set) var versions: [Int: Version] = [:]
    private(set) var prompts: [ShownPrompt] = []
    private(set) var eventLog: [String] = []
    /// What the user knows: the clock of own changes and of the versions the Mac applied or was asked about.
    private var clocks: [SimMacName: [SimMacName: Int]] = [:]
    /// What the Mac has merged: the clock a version it writes carries, since its file relays what it merged.
    private var seenClocks: [SimMacName: [SimMacName: Int]] = [:]
    /// The changes the Mac's user knows of, by value.
    private var informedIDs: [SimMacName: Set<Int>] = [:]
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

    /// Whether `later`, a change of a user who knew what they knew, was informed of `change`.
    func knew(_ later: Change, of change: Change) -> Bool {
        (later.clock[change.mac] ?? 0) >= change.sequence || later.informed.contains(change.id)
    }

    /// The Mac's settings were replaced (a restore of the preferences, a clone, a reinstall): the user knows what
    /// the settings hold now and what the user changed on this Mac, and nothing else.
    func resetInformed(mac: SimMacName, tokens: some Sequence<String>) {
        informedIDs[mac] = Set(changes.filter { $0.mac == mac }.map(\.id))
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

    /// A user change on a unit. An empty token list is a user delete (a reset to default, a removal).
    @discardableResult
    func recordUserChange(mac: SimMacName, unit: String, tokens: [String], time: Int64) -> Int {
        let sequence = tick(mac)
        let change = Change(
            id: changes.count, kind: .user, mac: mac, sequence: sequence, unit: unit, tokens: tokens,
            time: time, clock: clocks[mac] ?? [:], informed: informedIDs[mac] ?? []
        )
        changes.append(change)
        for token in tokens { changeByToken[token] = change.id }
        informedIDs[mac, default: []].insert(change.id)
        return change.id
    }

    /// An automatic change: it advances the Mac's clock but is no part of any `Past`.
    func recordAutomaticChange(mac: SimMacName, unit: String, tokens: [String], time: Int64) {
        tick(mac)
        for token in tokens { automaticTokens[token] = mac }
    }

    /// A Mac wrote a version. The version's past is a copy of the writer's clock.
    func recordWrite(version: Int, writer: SimMacName, path: String, time: Int64) {
        tick(writer)
        versions[version] = Version(
            id: version, writer: writer, path: path, clock: seenClocks[writer] ?? [:], time: time, originVersion: nil
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

    /// Foreign bytes: a version no Mac wrote, with an empty past.
    func recordForeign(version: Int, path: String, time: Int64) {
        versions[version] = Version(id: version, writer: nil, path: path, clock: [:], time: time, originVersion: nil)
    }

    /// A provider-made copy holds the same content, so it has the same past.
    func recordCopy(version: Int, of origin: Int, path: String, time: Int64) {
        let base = versions[origin]
        versions[version] = Version(
            id: version, writer: base?.writer, path: path, clock: base?.clock ?? [:], time: time, originVersion: origin
        )
    }

    /// The brain decided on a version (applied, merged, adopted, found it dominated, or answered a prompt about it):
    /// its past joins the Mac's. Reading a version without deciding is not an ingest.
    func recordIngest(mac: SimMacName, version: Int, time: Int64) {
        guard let source = versions[version] else { return }
        var clock = clocks[mac] ?? [:]
        for (other, component) in source.clock { clock[other] = max(clock[other] ?? 0, component) }
        clocks[mac] = clock
        var seen = seenClocks[mac] ?? [:]
        for (other, component) in source.clock { seen[other] = max(seen[other] ?? 0, component) }
        seenClocks[mac] = seen
        tick(mac)
    }

    /// The Mac merged a version into its state without applying it or asking its user: it will relay it, so
    /// the file it writes covers it, but the Mac's user knows nothing of it.
    func recordMerge(mac: SimMacName, version: Int, time: Int64) {
        guard let source = versions[version] else { return }
        var seen = seenClocks[mac] ?? [:]
        for (other, component) in source.clock { seen[other] = max(seen[other] ?? 0, component) }
        seenClocks[mac] = seen
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
        changes.append(Change(
            id: changes.count, kind: .answer, mac: mac, sequence: sequence, unit: nil, tokens: [], time: time,
            clock: clocks[mac] ?? [:], lostTokens: lost,
            retainedTokens: Set(prompt.shown.flatMap { [$0.local, $0.folder].compactMap { $0 } }).subtracting(lost),
            informed: informedIDs[mac] ?? []
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
        return changes(coveredBy: known.clock)
    }

    /// `Past(m, t)`: the same for a Mac's own state now.
    func past(ofMac mac: SimMacName) -> Set<Int> {
        changes(coveredBy: clocks[mac] ?? [:])
    }

    /// What the Mac has merged and relays: the changes its next file covers.
    func seenPast(ofMac mac: SimMacName) -> Set<Int> {
        changes(coveredBy: seenClocks[mac] ?? [:])
    }

    /// What the Mac's user knows: its past, and the changes whose values its settings held or a sheet showed.
    func informedPast(ofMac mac: SimMacName) -> Set<Int> {
        past(ofMac: mac).union(informedIDs[mac] ?? [])
    }

    /// The user change that minted a token.
    func change(forToken token: String) -> Change? {
        changeByToken[token].map { changes[$0] }
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
        for other in changes where other.id != change.id && other.time <= time && (known?.contains(other.id) ?? true) {
            switch other.kind {
            case .user:
                if other.unit == unit, other.id > change.id, knew(other, of: change) { return false }
            case .answer:
                if other.lostTokens.contains(token) { return false }
            }
        }
        return true
    }

    /// The live user tokens that no Mac's defaults, no readable version in any replica and no pending
    /// holding carries, excluding losses where every holder was destroyed by non-sync events (INV-S1g).
    func globallyLost(at time: Int64 = Int64.max) -> [String] {
        let held = holderSource().allTokens
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
        let snapshot = holderSource()
        // A Mac can only know of what it received: what a later change elsewhere superseded does not count yet.
        let known: Set<Int>? = visibleOnly ? seenPast(ofMac: mac).union(informedPast(ofMac: mac)) : nil
        let mine = liveTokens(of: snapshot.defaults[mac] ?? [], on: unit, known: known)
        guard !mine.isEmpty else { return [] }
        let pastOfMac = informedPast(ofMac: mac)
        var result = Set<Int>()
        for file in snapshot.files where file.version > 0 && versions[file.version] != nil && (!visibleOnly || file.mac == mac) {
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
        let known = seenPast(ofMac: mac).union(informedPast(ofMac: mac))
        let held = holderSource().defaults[mac] ?? []
        let mine = Set(held.filter { isLive(token: $0, unit: unit, known: known) || isAsserted($0, unit: unit, known: known) })
        // A Mac that holds nothing for the unit because its user removed the setting still holds that deletion.
        let holdsDeletion = mine.isEmpty && changes.last { $0.kind == .user && $0.mac == mac && $0.unit == unit }.map { change in
            change.tokens.isEmpty && !changes.contains { other in
                other.kind == .user && other.unit == unit && other.id > change.id && known.contains(other.id) && knew(other, of: change)
            }
        } == true
        guard !mine.isEmpty || holdsDeletion else { return false }
        let informed = informedPast(ofMac: mac)
        // An answer that kept a value asserts it again: a value that a user superseded since, without knowing
        // of the answer, is a sibling of what this Mac holds.
        for answer in changes where answer.kind == .answer && answer.mac != mac && known.contains(answer.id) {
            for token in answer.retainedTokens where !mine.contains(token) && isAsserted(token, unit: unit, known: known) {
                return true
            }
        }
        for change in changes where change.kind == .user && change.unit == unit && known.contains(change.id) && !informed.contains(change.id) {
            if change.tokens.isEmpty {
                // A deletion is live until a later change that knew of it.
                let superseded = changes.contains { other in
                    other.kind == .user && other.unit == unit && other.id > change.id && known.contains(other.id) && knew(other, of: change)
                }
                if !superseded { return true }
            } else if change.tokens.contains(where: { !mine.contains($0) && isLive(token: $0, unit: unit, known: known) }) {
                return true
            }
        }
        return false
    }

    /// Whether an answer that kept the value of `token` on `unit` asserts it still: no later change that knew of
    /// the answer superseded it, and no later answer gave it up. The same value is asserted again by each answer
    /// that keeps it, which a token alone does not tell apart.
    func isAsserted(_ token: String, unit: String, known: Set<Int>) -> Bool {
        guard SimWorld.unit(ofToken: token) == unit else { return false }
        return changes.contains { answer in
            guard answer.kind == .answer, answer.retainedTokens.contains(token), known.contains(answer.id) else { return false }
            return !changes.contains { other in
                guard other.id > answer.id, known.contains(other.id) else { return false }
                switch other.kind {
                case .user: return other.unit == unit && knew(other, of: answer)
                case .answer: return other.lostTokens.contains(token)
                }
            }
        }
    }

    /// The units the Mac can know of a conflict on.
    func knownConflictUnits(mac: SimMacName) -> [String] {
        let known = seenPast(ofMac: mac).union(informedPast(ofMac: mac))
        let units = Set(changes.filter { known.contains($0.id) }.compactMap(\.unit))
        return units.sorted().filter { knownConflict(mac: mac, unit: $0) }
    }

    private func liveTokens(of tokens: Set<String>, on unit: String, known: Set<Int>? = nil) -> Set<String> {
        Set(tokens.filter { isLive(token: $0, unit: unit, known: known) })
    }
}
