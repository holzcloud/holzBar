//
//  CodecFuzzTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

// Fuzzing of the three codecs that read bytes other Macs or other builds wrote: the device file, the state (Sigma) and the legacy
// file (analysis section 5.8). One seed gives one input, so a failure is reproduced by its chunk and index. An input is valid bytes that
// were then damaged (truncated, flipped, type-swapped, made oversize, nested, given counters at the edge or a wrong identity)
// or plain random bytes.
//
// For every input:
//   - the decoder returns, within a time limit, and never crashes;
//   - an accepted file is a whole valid replica: it encodes again and decodes to an equal replica, its counters are in range,
//     every entry is covered by its context, and no family or set is over its limit;
//   - a refused file is refused whole: merged into a state it leaves the replica as it was;
//   - an accepted file never makes the engine write a value outside the schema: whatever the file's units hold, what the
//     defaults would receive passes the app's own schema (`Defaults.validatedSettings`).

/// The bytes one seed gives, with the name they are decoded under.
private struct FuzzInput {
    var data: Data
    var fileName: String
    var kind: String
}

private struct FuzzGenerator {
    var random: SimRandom

    init(seed: UInt64) {
        random = SimRandom(seed: seed)
    }

    static let macs: [SyncMacID] = [
        "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB",
        "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC", "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD",
    ].compactMap { SyncMacID($0) }

    static let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Values

    private mutating func scalar() -> SyncValue {
        switch random.int(in: 0...7) {
        case 0: .bool(random.chance(0.5))
        case 1: .integer(Int64(random.int(in: -5...400)))
        case 2: .real(Double(random.int(in: -50...50)) / 4)
        case 3: .string(random.pick(["", "a", "hidden", "ns:Title", String(repeating: "x", count: random.int(in: 1...300))]))
        case 4: .data(Data((0..<random.int(in: 0...40)).map { _ in UInt8(truncatingIfNeeded: random.next()) }))
        case 5: .date(FuzzGenerator.date.addingTimeInterval(Double(random.int(in: 0...1000))))
        case 6: .integer(random.pick([0, 1, 2, 3, 1 << 33, Int64.max, Int64.min]))
        default: .real(random.pick([0, 1.5, -1, 1e300, .infinity]))
        }
    }

    private mutating func value(depth: Int = 0) -> SyncValue {
        if depth < 2, random.chance(0.18) {
            return .array((0..<random.int(in: 0...3)).map { _ in value(depth: depth + 1) })
        }
        if depth < 2, random.chance(0.18) {
            var fields: [String: SyncValue] = [:]
            for _ in 0..<random.int(in: 0...3) { fields[random.pick(["name", "combo", "section", "token", "sections27", "applicationSections"])] = value(depth: depth + 1) }
            return .dictionary(fields)
        }
        return scalar()
    }

    // MARK: Replicas

    private static let wholeUnits = ["ShowOnHover", "RehideInterval", "ItemSpacingOffset", "UseIceBar", "MenuBarAppearanceConfigurationV2", "HolzBarIcon", "SpacerCount"]
    private static let splitUnits: [(String, String)] = [
        ("Hotkeys", "ToggleHiddenSection"), ("Hotkeys", "SearchMenuBarItems"), ("ItemIcons", "ns:Title"), ("RevealRules", "LowBattery"),
        ("l27", "com.app.a"), ("l27", "com.app.b"), ("prof", "p1"), ("prof", "p2"),
    ]

    private mutating func replica() -> SyncReplica {
        var counters: [SyncMacID: UInt64] = [:]
        var registers: [SyncUnitKey: [SyncEntry]] = [:]
        let writers = Array(FuzzGenerator.macs.prefix(random.int(in: 1...4)))
        for _ in 0..<random.int(in: 0...9) {
            let key: SyncUnitKey = random.chance(0.5)
                ? .whole(random.pick(FuzzGenerator.wholeUnits))
                : { let pair = random.pick(FuzzGenerator.splitUnits); return .split(family: pair.0, item: pair.1) }()
            var entries: [SyncEntry] = registers[key] ?? []
            for _ in 0..<random.int(in: 1...2) {
                let mac = random.pick(writers)
                let n = UInt64(random.int(in: 1...60))
                counters[mac] = max(counters[mac] ?? 0, n)
                let payload: SyncPayload = random.chance(0.15) ? .deleted : .value(value())
                entries.append(SyncEntry(dot: SyncDot(mac: mac, n: n), at: FuzzGenerator.date, payload: payload))
            }
            registers[key] = entries
        }
        for mac in writers where random.chance(0.4) { counters[mac] = (counters[mac] ?? 0) + UInt64(random.int(in: 1...5)) }
        var sets: [String: [String]] = [:]
        if random.chance(0.4) { sets["known27"] = (0..<random.int(in: 0...5)).map { "com.app.\($0)" } }
        return SyncReplica(context: SyncContext(counters: counters), registers: registers, sets: sets)
    }

    mutating func deviceFile() -> (bytes: Data, mac: SyncMacID) {
        let mac = random.pick(FuzzGenerator.macs)
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: mac, installation: "nonce-\(random.int(in: 0...9))", written: FuzzGenerator.date, replica: replica())
        return ((try? SyncDeviceFile.encode(contents)) ?? Data(), mac)
    }

    mutating func state() -> Data {
        var state = SyncState(mac: random.pick(FuzzGenerator.macs), nonce: "nonce", isEnabled: random.chance(0.8))
        state.replica = replica()
        state.counter = UInt64(random.int(in: 0...80))
        state.publishedCounter = UInt64(random.int(in: 0...80))
        state.generation = UInt64(random.int(in: 0...30))
        for key in state.replica.keys where random.chance(0.6) {
            state.applied[key] = state.replica.live(key).map(\.dot)
            state.baseline[key] = random.chance(0.5) ? .unset : SyncValue.bool(true).digest
        }
        if random.chance(0.3) {
            state.pendingJoin = SyncPendingJoin(replica: replica(), shown: [:], isFounding: random.chance(0.5), folderIdentity: "folder")
        }
        state.refusals = random.chance(0.3)
            ? [FuzzGenerator.macs[1].rawValue: SyncRefusalRecord(reason: SyncRefusal.tooLarge(5).code, size: 2_000_000, modified: FuzzGenerator.date, firstSeen: FuzzGenerator.date)]
            : [:]
        return (try? SyncStateCodec.encode(state)) ?? Data()
    }

    mutating func legacyObject() -> [String: Any] {
        var settings: [String: Any] = [:]
        for key in ["ShowOnHover", "RehideInterval", "ItemSpacingOffset", "Hotkeys", "UseIceBar", "Unknown"] where random.chance(0.6) {
            settings[key] = value().propertyList
        }
        var fields: [String: Any] = [SettingsSyncFile.settingsKey: settings]
        if random.chance(0.9) { fields[SettingsSyncFile.modifiedKey] = FuzzGenerator.date }
        if random.chance(0.9) { fields[SettingsSyncDevice.deviceIDKey] = "OLD-MAC-\(random.int(in: 0...9))" }
        return fields
    }

    // MARK: Damage

    private enum Step { case key(String), index(Int) }

    private func paths(in object: Any, prefix: [Step] = [], into result: inout [[Step]]) {
        guard result.count < 600 else { return }
        result.append(prefix)
        if let dictionary = object as? [String: Any] {
            for key in dictionary.keys.sorted() { paths(in: dictionary[key]!, prefix: prefix + [.key(key)], into: &result) }
        } else if let array = object as? [Any] {
            for (index, element) in array.enumerated() { paths(in: element, prefix: prefix + [.index(index)], into: &result) }
        }
    }

    private func node(at path: ArraySlice<Step>, in object: Any) -> Any? {
        guard let step = path.first else { return object }
        switch step {
        case .key(let key): return (object as? [String: Any])?[key].flatMap { node(at: path.dropFirst(), in: $0) }
        case .index(let index):
            guard let array = object as? [Any], array.indices.contains(index) else { return nil }
            return node(at: path.dropFirst(), in: array[index])
        }
    }

    private func replacing(_ object: Any, at path: ArraySlice<Step>, with new: Any?) -> Any? {
        guard let step = path.first else { return new }
        switch step {
        case .key(let key):
            guard var dictionary = object as? [String: Any], let child = dictionary[key] else { return object }
            dictionary[key] = replacing(child, at: path.dropFirst(), with: new)
            return dictionary
        case .index(let index):
            guard var array = object as? [Any], array.indices.contains(index) else { return object }
            if path.count == 1, new == nil {
                array.remove(at: index)
            } else if let replaced = replacing(array[index], at: path.dropFirst(), with: new) {
                array[index] = replaced
            }
            return array
        }
    }

    private mutating func swapped() -> Any {
        let pool: [Any] = [
            "text", 7, -1, 1 << 40, true, Data([0, 1, 2]), FuzzGenerator.date, 3.5, Double.nan, [Any](), [String: Any](), [1, 2, 3],
            ["a": 1] as [String: Any], "", String(repeating: "m", count: 5000), -1.5e300,
        ]
        return random.pick(pool)
    }

    private mutating func edgeCounter() -> Any {
        random.pick([0, -1, 1 << 34, (1 << 34) + 1, Int64.max, Int64.min, 1 << 33, 4_294_967_296 * 4, 1 << 62] as [Int64])
    }

    private mutating func edgeIdentity(of mac: String) -> Any {
        random.pick([
            mac.lowercased(), "", "not-a-uuid", String(repeating: "A", count: 5000), FuzzGenerator.macs[1].rawValue, mac + "\u{0}", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAA",
        ] as [String])
    }

    /// Damages a property-list object in one of several ways; `nil` when it could not be damaged that way.
    mutating func damaged(_ object: Any, kind: inout String) -> Any? {
        var all: [[Step]] = []
        paths(in: object, into: &all)
        let counterKeys: Set<String> = ["n", "counter", "publishedCounter", "generation", "launchCount", "format", "minor", "unitTable", "laterLaunch"]
        let choice = random.int(in: 0...7)
        switch choice {
        case 0:
            kind = "type swap"
            let path = random.pick(all)
            return replacing(object, at: path[...], with: swapped())
        case 1:
            kind = "counter at the edge"
            let candidates = all.filter { path in
                if case .key(let key)? = path.last { return counterKeys.contains(key) }
                return path.count >= 2 && { if case .key(let key) = path[path.count - 2] { return key == "context" } else { return false } }()
            }
            guard !candidates.isEmpty else { return nil }
            return replacing(object, at: random.pick(candidates)[...], with: edgeCounter())
        case 2:
            kind = "identity"
            let candidates = all.filter { path in
                if case .key(let key)? = path.last { return key == "mac" || key == "installation" }
                return false
            }
            guard !candidates.isEmpty else { return nil }
            let path = random.pick(candidates)
            let current = node(at: path[...], in: object) as? String ?? ""
            return replacing(object, at: path[...], with: edgeIdentity(of: current))
        case 3:
            kind = "oversize"
            let candidates = all.filter { path in
                let held = node(at: path[...], in: object)
                return held is [Any] || held is [String: Any]
            }
            guard !candidates.isEmpty else { return nil }
            let path = random.pick(candidates)
            let size = random.pick([1025, 1100, 2001, 2500, 4096])
            if let array = node(at: path[...], in: object) as? [Any] {
                let element = array.first ?? 1
                return replacing(object, at: path[...], with: Array(repeating: element, count: size))
            }
            var dictionary = (node(at: path[...], in: object) as? [String: Any]) ?? [:]
            let template = dictionary.keys.sorted().first.flatMap { dictionary[$0] } ?? ["mac": SyncMacID("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!.rawValue, "n": 1, "at": FuzzGenerator.date, "value": true] as [String: Any]
            for index in 0..<size { dictionary["k\(index)"] = template }
            return replacing(object, at: path[...], with: dictionary)
        case 4:
            kind = "deep nesting"
            let path = random.pick(all)
            var wrapped: Any = node(at: path[...], in: object) ?? 1
            for _ in 0..<random.pick([20, 40, 100, 180]) { wrapped = random.chance(0.8) ? [wrapped] : ["k": wrapped] }
            return replacing(object, at: path[...], with: wrapped)
        case 5:
            kind = "dropped field"
            let path = random.pick(all.filter { !$0.isEmpty })
            guard case .key(let key)? = path.last else { return replacing(object, at: path[...], with: nil) }
            let parent = Array(path.dropLast())
            guard var dictionary = node(at: parent[...], in: object) as? [String: Any] else { return nil }
            dictionary[key] = nil
            return replacing(object, at: parent[...], with: dictionary)
        case 6:
            kind = "unknown field"
            let candidates = all.filter { node(at: $0[...], in: object) is [String: Any] }
            guard !candidates.isEmpty else { return nil }
            let path = random.pick(candidates)
            var dictionary = (node(at: path[...], in: object) as? [String: Any]) ?? [:]
            dictionary["fuzz\(random.int(in: 0...9))"] = swapped()
            return replacing(object, at: path[...], with: dictionary)
        default:
            kind = "duplicate dot"
            let candidates = all.filter { path in
                if case .key("units")? = path.first, path.count == 2 { return node(at: path[...], in: object) is [Any] }
                return false
            }
            guard !candidates.isEmpty else { return nil }
            let path = random.pick(candidates)
            guard let list = node(at: path[...], in: object) as? [Any], let first = list.first else { return nil }
            return replacing(object, at: path[...], with: list + [first, first])
        }
    }

    private mutating func rawDamage(_ data: Data, kind: inout String) -> Data {
        guard !data.isEmpty else { return data }
        var bytes = [UInt8](data)
        switch random.int(in: 0...2) {
        case 0:
            kind = "truncation"
            let boundary = random.pick([0, 1, 7, 8, 9, bytes.count / 2, bytes.count - 1, bytes.count - 8, bytes.count - 32])
            let cut = random.chance(0.5) ? random.int(in: 0...bytes.count) : max(0, min(bytes.count, boundary))
            return Data(bytes.prefix(cut))
        case 1:
            kind = "byte flips"
            for _ in 0..<random.int(in: 1...8) { bytes[random.int(in: 0...(bytes.count - 1))] ^= UInt8(1 << random.int(in: 0...7)) }
            return Data(bytes)
        default:
            kind = "inserted bytes"
            let at = random.int(in: 0...bytes.count)
            bytes.insert(contentsOf: (0..<random.int(in: 1...16)).map { _ in UInt8(truncatingIfNeeded: random.next()) }, at: at)
            return Data(bytes)
        }
    }

    // MARK: Inputs

    /// The canonical bytes of an object, in a format drawn from the seed.
    private mutating func encoded(_ object: Any) -> Data? {
        random.chance(0.5) ? CanonicalPlist.binary(object) : CanonicalPlist.xml(object)
    }

    /// The same property list as `data`, written canonically (the codecs' own writers order a dictionary as its storage does).
    private mutating func canonical(_ data: Data) -> Data {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return data }
        return encoded(object) ?? data
    }

    /// The input of one index: a codec by `index % 3` for its own kind of bytes.
    mutating func input(index: Int) -> (codec: Int, input: FuzzInput) {
        let codec = index % 3
        var kind = "valid"
        var name = ""
        var data: Data
        switch codec {
        case 0:
            let file = deviceFile()
            data = canonical(file.bytes)
            name = "\(file.mac.rawValue).plist"
        case 1:
            data = canonical(state())
        default:
            data = encoded(legacyObject()) ?? Data()
        }
        let roll = random.int(in: 0...9)
        if roll == 0 {
            kind = "random bytes"
            let prefix: [UInt8] = random.pick([[], Array("bplist00".utf8), Array("<?xml version=\"1.0\"?><plist>".utf8), [0xFF]])
            data = Data(prefix + (0..<random.int(in: 0...3000)).map { _ in UInt8(truncatingIfNeeded: random.next()) })
        } else if roll <= 6 {
            if let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let changed = damaged(object, kind: &kind), let bytes = encoded(changed) {
                data = bytes
            } else {
                data = rawDamage(data, kind: &kind)
            }
            if random.chance(0.25) { data = rawDamage(data, kind: &kind) }
        } else if roll == 7 {
            data = rawDamage(data, kind: &kind)
        }
        if codec == 0, random.chance(0.1) {
            kind += " and another name"
            name = random.pick(["\(FuzzGenerator.macs[2].rawValue).plist", "x.plist", ".plist", "\(FuzzGenerator.macs[0].rawValue.lowercased()).plist"])
        }
        return (codec, FuzzInput(data: data, fileName: name, kind: kind))
    }
}

@Suite("CodecFuzz")
struct CodecFuzzTests {
    private static let table = SyncUnitTable.version1(normalizers: .canonical)
    private static let chunks = 16

    /// The state a refused file is merged into: it holds entries of other Macs, so a merge that took a refused file in part would change it.
    private static func baseState() -> SyncState {
        let own = FuzzGenerator.macs[0]
        let other = FuzzGenerator.macs[1]
        let hover = SyncEntry(dot: SyncDot(mac: other, n: 3), at: FuzzGenerator.date, payload: .value(.bool(true)))
        let rehide = SyncEntry(dot: SyncDot(mac: own, n: 2), at: FuzzGenerator.date, payload: .value(.integer(30)))
        var state = SyncState(mac: own, nonce: "nonce-0", isEnabled: true)
        state.replica = SyncReplica(
            context: SyncContext(counters: [own: 2, other: 3]),
            registers: [.whole("ShowOnHover"): [hover], .whole("RehideInterval"): [rehide]]
        )
        state.counter = 2
        state.publishedCounter = 2
        return state
    }

    private static func environment() -> SyncEnvironment {
        SyncFixtures.environment(generation: .g27, table: table)
    }

    /// The keys the sync may write to the defaults: every key the table projects.
    private static let writableKeys: Set<String> = Set(SyncUnitTable.syncedKeys.map(\.rawValue))

    private func record(_ message: String, _ input: FuzzInput, chunk: Int, index: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        Issue.record(Comment(rawValue: "chunk \(chunk) input \(index) (\(input.kind)): \(message)"), sourceLocation: sourceLocation)
    }

    /// Runs `body` and records when it takes longer than a generous limit: a decoder that hangs on hostile bytes.
    private func timed<T>(_ input: FuzzInput, chunk: Int, index: Int, _ what: String, _ body: () -> T) -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = body()
        let took = start.duration(to: clock.now)
        if took > .seconds(2) { record("\(what) took \(took)", input, chunk: chunk, index: index) }
        return result
    }

    private func checkDeviceFile(_ input: FuzzInput, chunk: Int, index: Int) {
        let result = timed(input, chunk: chunk, index: index, "the device file decoder") { SyncDeviceFile.decode(input.data, fileName: input.fileName) }
        let base = Self.baseState()
        let environment = Self.environment()
        let macID = SyncDeviceFile.macID(fromFileName: input.fileName)
        switch result {
        case .failure(let refusal):
            let outcome = SyncFileOutcome(macID: macID, size: input.data.count, modified: FuzzGenerator.date, state: .refused(refusal))
            let merged = SyncMerge.merge(SyncFolderRead(availability: .available, files: [outcome]), into: base, environment: environment)
            if merged.state.replica != base.replica {
                record("a refused file (\(refusal)) changed the replica", input, chunk: chunk, index: index)
            }
        case .success(let contents):
            checkAccepted(contents, input, chunk: chunk, index: index)
            let outcome = SyncFileOutcome(macID: contents.mac, size: input.data.count, modified: FuzzGenerator.date, state: .contents(contents))
            let merged = SyncMerge.merge(SyncFolderRead(availability: .available, files: [outcome]), into: base, environment: environment)
            checkApplied(merged.state, input, chunk: chunk, index: index)
        }
    }

    /// An accepted file is a whole valid replica.
    private func checkAccepted(_ contents: SyncDeviceFile.Contents, _ input: FuzzInput, chunk: Int, index: Int) {
        let replica = contents.replica
        for mac in replica.context.macs where replica.context[mac] > SyncDeviceFile.maximumCounter {
            record("an accepted file holds the counter \(replica.context[mac])", input, chunk: chunk, index: index)
        }
        for key in replica.keys {
            let entries = replica.live(key)
            for entry in entries {
                if !replica.context.covers(entry.dot) { record("an accepted file holds the uncovered dot \(entry.dot)", input, chunk: chunk, index: index) }
                if entry.dot.n > SyncDeviceFile.maximumCounter { record("an accepted file holds the dot \(entry.dot)", input, chunk: chunk, index: index) }
            }
        }
        var perFamily: [String: Int] = [:]
        for key in replica.keys {
            if case .split(let family, _) = key { perFamily[family, default: 0] += 1 }
        }
        for family in perFamily.keys.sorted() where perFamily[family]! > SyncDeviceFile.maximumEntriesPerFamily {
            record("an accepted file holds \(perFamily[family]!) items of \(family)", input, chunk: chunk, index: index)
        }
        for name in replica.sets.keys.sorted() where replica.sets[name]!.count > SyncDeviceFile.maximumSetElements {
            record("an accepted file holds \(replica.sets[name]!.count) elements of \(name)", input, chunk: chunk, index: index)
        }
        switch try? SyncDeviceFile.encode(contents) {
        case let data?:
            switch SyncDeviceFile.decode(data, fileName: "\(contents.mac.rawValue).plist") {
            case .success(let again):
                if again.replica != contents.replica || again.mac != contents.mac { record("an accepted file did not round-trip", input, chunk: chunk, index: index) }
            case .failure(let refusal):
                record("an accepted file was refused after encoding again: \(refusal)", input, chunk: chunk, index: index)
            }
        case nil:
            // An accepted file may be too large to write again once every field is canonical; that is a refusal of the writer, not a crash.
            break
        }
    }

    /// Whatever the merged state holds, what the sync would write to the defaults passes the app's schema.
    private func checkApplied(_ state: SyncState, _ input: FuzzInput, chunk: Int, index: Int) {
        var changes: [SyncUnitKey: SyncPayload] = [:]
        for key in state.replica.keys {
            if let entry = state.replica.live(key).first { changes[key] = entry.payload }
        }
        let writes = SyncProjection.defaultsWrites(applying: changes, to: [:], table: Self.table)
        for key in writes.keys.sorted() {
            guard Self.writableKeys.contains(key) else {
                record("the sync would write the key \(key), which it does not own", input, chunk: chunk, index: index)
                continue
            }
            guard let value = writes[key] ?? nil else { continue }
            if Defaults.Key.validatedSettings([key: value]).accepted[key] == nil {
                record("the sync would write a value of \(key) that the schema refuses: \(value)", input, chunk: chunk, index: index)
            }
        }
    }

    private func checkState(_ input: FuzzInput, chunk: Int, index: Int) {
        let result = timed(input, chunk: chunk, index: index, "the state decoder") { SyncStateCodec.decode(input.data) }
        guard case .state(let state) = result else { return }
        if state.format > SyncState.currentFormat { record("a state of a newer format was accepted", input, chunk: chunk, index: index) }
        guard let data = try? SyncStateCodec.encode(state) else { return }
        if case .state(let again) = SyncStateCodec.decode(data) {
            if again != state { record("an accepted state did not round-trip (\(Self.differingFields(state, again).joined(separator: ", ")))", input, chunk: chunk, index: index) }
        } else {
            record("an accepted state was refused after encoding again", input, chunk: chunk, index: index)
        }
    }

    private static func differingFields(_ one: SyncState, _ two: SyncState) -> [String] {
        var fields: [String] = []
        if one.format != two.format { fields.append("format") }
        if one.mac != two.mac { fields.append("mac") }
        if one.nonce != two.nonce { fields.append("nonce") }
        if one.counter != two.counter { fields.append("counter \(one.counter) vs \(two.counter)") }
        if one.publishedCounter != two.publishedCounter { fields.append("publishedCounter \(one.publishedCounter) vs \(two.publishedCounter)") }
        if one.generation != two.generation { fields.append("generation \(one.generation) vs \(two.generation)") }
        if one.replica != two.replica { fields.append("replica") }
        if one.applied != two.applied { fields.append("applied") }
        if one.baseline != two.baseline { fields.append("baseline") }
        if one.localOnly != two.localOnly { fields.append("localOnly") }
        if one.localOrigin != two.localOrigin { fields.append("localOrigin") }
        if one.pendingJoin != two.pendingJoin { fields.append("pendingJoin") }
        if one.legacy != two.legacy { fields.append("legacy") }
        if one.published != two.published { fields.append("published") }
        if one.laterLaunch != two.laterLaunch { fields.append("laterLaunch") }
        if one.launchCount != two.launchCount { fields.append("launchCount") }
        if one.refusals != two.refusals { fields.append("refusals") }
        if one.previousMacIDs != two.previousMacIDs { fields.append("previousMacIDs") }
        if one.previousCeilings != two.previousCeilings { fields.append("previousCeilings") }
        if one.isEnabled != two.isEnabled { fields.append("isEnabled") }
        if one.captureDeferred != two.captureDeferred { fields.append("captureDeferred") }
        if one.systemGeneration != two.systemGeneration { fields.append("systemGeneration") }
        return fields
    }

    private func checkLegacy(_ input: FuzzInput, chunk: Int, index: Int) {
        let result = timed(input, chunk: chunk, index: index, "the legacy reader") { SyncLegacyInput.read(input.data) }
        guard case .success(let file) = result else { return }
        guard case .success(let again) = SyncLegacyInput.read(input.data), again == file else {
            record("the legacy reader gave another answer for the same bytes", input, chunk: chunk, index: index)
            return
        }
        let table = Self.table
        let environment = Self.environment()
        // What a founding takes from the file is usable: every unit validates and is within its cap.
        for (key, value) in SyncJoin.usableLegacyUnits(file.settings, environment: environment).sorted(by: { $0.key < $1.key }) {
            guard let descriptor = table.descriptor(for: key), descriptor.validate(key.itemName, value), !descriptor.isOverCap(value) else {
                record("a founding would take the unusable value of \(key)", input, chunk: chunk, index: index)
                continue
            }
        }
    }

    @Test("Arbitrary, damaged and hostile bytes never crash the codecs, are refused whole or accepted whole, and never apply a value outside the schema", arguments: Array(0..<CodecFuzzTests.chunks))
    func fuzz(chunk: Int) {
        let total = SimBudget.read().fuzzInputs
        let perChunk = total / Self.chunks + (chunk < total % Self.chunks ? 1 : 0)
        var generator = FuzzGenerator(seed: 0x5EED_0000 + UInt64(chunk))
        var counts = [0, 0, 0]
        for index in 0..<perChunk {
            let (codec, input) = generator.input(index: index)
            counts[codec] += 1
            switch codec {
            case 0: checkDeviceFile(input, chunk: chunk, index: index)
            case 1: checkState(input, chunk: chunk, index: index)
            default: checkLegacy(input, chunk: chunk, index: index)
            }
        }
        #expect(counts.reduce(0, +) == perChunk)
    }

    @Test("The canonical writers produce what Foundation reads back, in both formats")
    func canonicalWritersReadBack() throws {
        let object: [String: Any] = [
            "bool": true, "false": false, "int": 42, "negative": -7, "big": Int64(1) << 40, "real": 3.5, "text": "text & <markup>",
            "wide": "ünïcode \u{1F600}", "long": String(repeating: "x", count: 40), "data": Data([0, 1, 2, 255]), "date": FuzzGenerator.date,
            "array": [1, "two", [3, 4], ["five": 5]] as [Any], "nested": ["a": ["b": ["c": [Any]()]]] as [String: Any],
            "many": Array(0..<300) as [Any], "empty": [String: Any](),
        ]
        for data in [try #require(CanonicalPlist.xml(object)), try #require(CanonicalPlist.binary(object))] {
            let read = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            #expect((read as? NSDictionary)?.isEqual(to: object) == true)
        }
        #expect(CanonicalPlist.xml(object) == CanonicalPlist.xml(object) && CanonicalPlist.binary(object) == CanonicalPlist.binary(object))
    }

    @Test("The same seed gives the same inputs")
    func inputsAreDeterministic() {
        var first = FuzzGenerator(seed: 99)
        var second = FuzzGenerator(seed: 99)
        for index in 0..<60 {
            let one = first.input(index: index)
            let two = second.input(index: index)
            #expect(one.codec == two.codec && one.input.data == two.input.data && one.input.fileName == two.input.fileName)
        }
    }

    @Test("The generator damages every way it names, and valid files are among its inputs")
    func generatorCoversTheDamage() {
        var generator = FuzzGenerator(seed: 7)
        var kinds = Set<String>()
        var accepted = 0
        for index in 0..<900 {
            let (codec, input) = generator.input(index: index)
            kinds.insert(input.kind)
            if codec == 0, case .success = SyncDeviceFile.decode(input.data, fileName: input.fileName) { accepted += 1 }
        }
        for expected in ["valid", "random bytes", "type swap", "counter at the edge", "identity", "oversize", "deep nesting", "dropped field", "unknown field", "duplicate dot", "truncation", "byte flips"] {
            #expect(kinds.contains(expected), "the generator never made \(expected)")
        }
        #expect(accepted > 20, "only \(accepted) device files were accepted, so the fuzz mostly tests refusals")
    }

    @Test("A device file with a counter at 2^34 is accepted and one above it is refused whole")
    func counterEdge() throws {
        var generator = FuzzGenerator(seed: 5)
        let file = generator.deviceFile()
        let object = try #require(try PropertyListSerialization.propertyList(from: file.bytes, options: [], format: nil) as? [String: Any])
        func with(_ counter: Int64) throws -> Data {
            var changed = object
            changed["context"] = [file.mac.rawValue: counter]
            changed["units"] = [String: Any]()
            changed["entries"] = [String: Any]()
            changed["sets"] = [String: Any]()
            return try PropertyListSerialization.data(fromPropertyList: changed, format: .binary, options: 0)
        }
        let name = "\(file.mac.rawValue).plist"
        guard case .success = SyncDeviceFile.decode(try with(1 << 34), fileName: name) else {
            Issue.record("a counter at 2^34 was refused")
            return
        }
        #expect(SyncDeviceFile.decode(try with((1 << 34) + 1), fileName: name) == .failure(.counterOutOfRange))
        #expect(SyncDeviceFile.decode(try with(-1), fileName: name) != nil)
    }
}
