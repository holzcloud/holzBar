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
    private var clocks: [SimMacName: [SimMacName: Int]] = [:]
    private var generations: [SimMacName: Int] = [:]
    private var changeByToken: [String: Int] = [:]
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
        return clock[mac] ?? 0
    }

    /// A user change on a unit. An empty token list is a user delete (a reset to default, a removal).
    @discardableResult
    func recordUserChange(mac: SimMacName, unit: String, tokens: [String], time: Int64) -> Int {
        let sequence = tick(mac)
        let change = Change(
            id: changes.count, kind: .user, mac: mac, sequence: sequence, unit: unit, tokens: tokens,
            time: time, clock: clocks[mac] ?? [:]
        )
        changes.append(change)
        for token in tokens { changeByToken[token] = change.id }
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
            id: version, writer: writer, path: path, clock: clocks[writer] ?? [:], time: time, originVersion: nil
        )
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
            clock: clocks[mac] ?? [:], lostTokens: lost
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

    /// The user change that minted a token.
    func change(forToken token: String) -> Change? {
        changeByToken[token].map { changes[$0] }
    }

    /// Where a token comes from.
    func origin(of token: String) -> SimOrigin {
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
    func isLive(token: String, unit: String, at time: Int64 = Int64.max) -> Bool {
        guard let change = change(forToken: token), change.unit == unit, change.time <= time else { return false }
        for other in changes where other.id != change.id && other.time <= time {
            switch other.kind {
            case .user:
                if other.unit == unit, other.id > change.id, (other.clock[change.mac] ?? 0) >= change.sequence { return false }
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
    func conflictingVersions(mac: SimMacName, unit: String) -> [Int] {
        guard isComparable(unit: unit, on: mac) else { return [] }
        let snapshot = holderSource()
        let mine = liveTokens(of: snapshot.defaults[mac] ?? [], on: unit)
        guard !mine.isEmpty else { return [] }
        let pastOfMac = past(ofMac: mac)
        var result = Set<Int>()
        for file in snapshot.files where file.version > 0 && versions[file.version] != nil {
            let theirs = liveTokens(of: file.tokens, on: unit)
            guard !theirs.isEmpty, mine != theirs else { continue }
            let pastOfVersion = past(ofVersion: file.version)
            let iHaveWhatTheyLack = mine.contains { token in
                change(forToken: token).map { !pastOfVersion.contains($0.id) } ?? false
            }
            let theyHaveWhatILack = theirs.contains { token in
                change(forToken: token).map { !pastOfMac.contains($0.id) } ?? false
            }
            if iHaveWhatTheyLack, theyHaveWhatILack { result.insert(file.version) }
        }
        return result.sorted()
    }

    func conflict(mac: SimMacName, unit: String) -> Bool {
        !conflictingVersions(mac: mac, unit: unit).isEmpty
    }

    private func liveTokens(of tokens: Set<String>, on unit: String) -> Set<String> {
        Set(tokens.filter { isLive(token: $0, unit: unit) })
    }
}
