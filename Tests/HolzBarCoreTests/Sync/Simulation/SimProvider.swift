import Foundation

/// The outcome of a write handed to the provider.
enum SimWriteOutcome: Equatable, Sendable {
    case written(version: Int)
    /// The Mac's folder is unmounted. The attempt is recorded as a violation candidate.
    case notMounted
}

/// A delivery that reached a Mac's replica: the world raises a folder signal for it.
struct SimDeliveryNotice: Equatable, Sendable {
    var mac: SimMacName
    var path: String
}

/// One content the provider has seen at a path.
struct SimVersion: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case write
        /// A conflict copy of another version, under another path.
        case conflictCopy(of: Int)
        case foreign(SimForeignKind)
    }

    var id: Int
    var path: String
    var data: Data
    /// The Mac that wrote it; `nil` for foreign bytes and provider-made files.
    var writer: SimMacName?
    /// Global virtual time of the write.
    var writtenAt: Int64
    var kind: Kind
    /// A copy that stays on one Mac (Nextcloud).
    var localTo: SimMacName?
}

/// A write attempt on an unmounted folder.
struct SimViolation: Equatable, Sendable {
    var time: Int64
    var mac: SimMacName
    var path: String
    var note: String
}

enum SimDeliveryMode: Equatable, Sendable {
    /// New main content at the path; a stale one is dropped.
    case main
    /// Main content forced back (restore), even if older than what the replica holds.
    case restore
    /// An unresolved conflict version next to the main content (iCloud).
    case conflictVersion
    /// The file disappears unless a newer version replaced it.
    case delete(upTo: Int)
    /// A dataless placeholder becomes present content.
    case materialize
}

struct SimDelivery: Equatable, Sendable {
    var time: Int64
    var sequence: Int
    var target: SimMacName
    var path: String
    var version: Int
    var mode: SimDeliveryMode
    var duplicate: Bool
}

/// The hostile file provider (A2 section 6): per-Mac replicas of one shared folder that the provider moves
/// content between after heavy-tailed delays, with offline windows, reordering across paths, coalescing,
/// duplicates, conflict copies, last-writer-wins, iCloud per-device winners, restores, deletions, eviction,
/// partial exposure, stalls, unmount and foreign bytes. Every random choice comes from its own seeded stream.
struct SimProvider: Sendable {
    /// Global virtual time; the world keeps it current.
    var now: Int64 = 0
    var policy: SimFaultPolicy
    private var random: SimRandom

    private(set) var replicas: [SimMacName: SimFolderReplica] = [:]
    private(set) var versions: [Int: SimVersion] = [:]
    /// Version IDs per path in write order.
    private(set) var history: [String: [Int]] = [:]
    /// The version the cloud currently considers current per path (absent: deleted or never written).
    private(set) var current: [String: Int] = [:]
    private(set) var queue: [SimDelivery] = []
    private(set) var violations: [SimViolation] = []
    private var resolved: Set<Int> = []
    private var computerNames: [SimMacName: String] = [:]
    private var nextVersion = 1
    private var nextSequence = 1
    private var log: [String] = []

    init(policy: SimFaultPolicy = .ideal, random: SimRandom = SimRandom(seed: 0)) {
        self.policy = policy
        self.random = random
    }

    /// Folder-change signals reach running Macs after a delivery (SMB emits none).
    var signalsFolderChanges: Bool { policy.signalsFolderChanges }

    var nextDeliveryTime: Int64? { queue.map(\.time).min() }

    func replica(of mac: SimMacName) -> SimFolderReplica { replicas[mac] ?? SimFolderReplica() }

    func version(_ id: Int) -> SimVersion? { versions[id] }

    /// Gives a Mac a replica. A Mac joining a folder with content receives it after the usual delays.
    mutating func ensureReplica(for mac: SimMacName, computerName: String? = nil) {
        if let computerName { computerNames[mac] = computerName }
        guard replicas[mac] == nil else { return }
        replicas[mac] = SimFolderReplica()
        catchUp(mac)
    }

    // MARK: Writing

    /// A Mac writes a file. The writer sees it at once; the other Macs get it after a delay.
    mutating func write(from mac: SimMacName, path: String, data: Data) -> SimWriteOutcome {
        ensureReplica(for: mac)
        guard replicas[mac]!.isMounted else {
            violations.append(SimViolation(time: now, mac: mac, path: path, note: "write on an unmounted folder"))
            log.append("violation \(mac) \(path) unmounted")
            return .notMounted
        }
        let id = newVersion(path: path, data: data, writer: mac, kind: .write)
        let predecessor = concurrentPredecessor(of: id, writer: mac)
        replicas[mac]!.entries[path] = .present(data)
        replicas[mac]!.versions[path] = id
        replicas[mac]!.seenVersions.insert(id)
        replicas[mac]!.partialWindows[path] = nil
        current[path] = id
        log.append("write \(mac) \(path) v\(id)")
        for target in replicas.keys.sorted() where target != mac {
            enqueue(version: id, to: target, mode: .main, from: mac)
        }
        if let loser = predecessor { resolveConcurrentWrite(winner: id, loser: loser) }
        return .written(version: id)
    }

    private mutating func newVersion(
        path: String, data: Data, writer: SimMacName?, kind: SimVersion.Kind, localTo: SimMacName? = nil
    ) -> Int {
        let id = nextVersion
        nextVersion += 1
        versions[id] = SimVersion(id: id, path: path, data: data, writer: writer, writtenAt: now, kind: kind, localTo: localTo)
        history[path, default: []].append(id)
        return id
    }

    /// The latest write by another Mac, inside the conflict window, that this Mac has not seen.
    private func concurrentPredecessor(of id: Int, writer: SimMacName) -> Int? {
        guard let path = versions[id]?.path else { return nil }
        let seen = replicas[writer]?.seenVersions ?? []
        for candidate in (history[path] ?? []).reversed() where candidate != id {
            guard let other = versions[candidate], other.kind == .write, let otherWriter = other.writer, otherWriter != writer
            else { continue }
            if other.writtenAt < now - policy.conflictWindowMilliseconds { break }
            if seen.contains(candidate) || resolved.contains(candidate) { continue }
            return candidate
        }
        return nil
    }

    private mutating func resolveConcurrentWrite(winner: Int, loser: Int) {
        guard let path = versions[winner]?.path else { return }
        resolved.insert(winner)
        resolved.insert(loser)
        var style = SimConflictStyle.lastWriterWins
        if !policy.conflictStyles.isEmpty, random.chance(policy.conflictCopyProbability) {
            style = random.pick(policy.conflictStyles)
        }
        switch style {
        case .lastWriterWins: lastWriterWins(path: path, winner: winner, loser: loser)
        case .perDeviceWinner: perDeviceWinner(path: path, winner: winner, loser: loser)
        case .dropbox, .oneDrive, .nextcloud, .syncthing: conflictCopy(path: path, winner: winner, loser: loser, style: style)
        }
    }

    // MARK: Concurrent write resolution

    /// No copy is kept: the earlier content disappears (SMB, some WebDAV).
    mutating func lastWriterWins(path: String, winner: Int, loser: Int) {
        queue.removeAll { $0.version == loser && $0.mode == .main }
        log.append("lastWriterWins \(path) winner v\(winner) loser v\(loser)")
    }

    /// iCloud: each device keeps its own content as the winner; the other content is an unresolved version on
    /// that device. Every other Mac gets the later write as the winner and the earlier one as a version.
    mutating func perDeviceWinner(path: String, winner: Int, loser: Int) {
        guard let winnerMac = versions[winner]?.writer, let loserMac = versions[loser]?.writer else { return }
        for index in queue.indices {
            if queue[index].version == loser, queue[index].mode == .main {
                queue[index].mode = .conflictVersion
            } else if queue[index].version == winner, queue[index].mode == .main, queue[index].target == loserMac {
                queue[index].mode = .conflictVersion
            }
        }
        log.append("perDeviceWinner \(path) winner v\(winner) on \(winnerMac), loser v\(loser) on \(loserMac)")
    }

    /// The earlier content survives as a sibling file named by the provider (A2 section 6.2).
    mutating func conflictCopy(path: String, winner: Int, loser: Int, style: SimConflictStyle) {
        guard let loserVersion = versions[loser], let loserMac = loserVersion.writer else { return }
        queue.removeAll { $0.version == loser && $0.mode == .main }
        let copyPath = Self.conflictCopyPath(
            for: path, style: style, computerName: computerName(of: loserMac),
            loserMac: loserMac, globalNow: now
        )
        let localOnly: SimMacName? = style == .nextcloud ? loserMac : nil
        let copy = newVersion(
            path: copyPath, data: loserVersion.data, writer: loserMac, kind: .conflictCopy(of: loser), localTo: localOnly
        )
        current[copyPath] = copy
        resolved.insert(copy)
        // The copy appears on the losing Mac when the winner replaces its content.
        let atLoser = queue.first { $0.version == winner && $0.target == loserMac && $0.mode == .main }?.time
        for target in replicas.keys.sorted() {
            if let localOnly, target != localOnly { continue }
            if target == loserMac {
                enqueue(version: copy, to: target, mode: .main, from: nil, fixedTime: atLoser ?? now)
            } else {
                enqueue(version: copy, to: target, mode: .main, from: loserMac)
            }
        }
        log.append("conflictCopy \(style.rawValue) \(copyPath) winner v\(winner) loser v\(loser)")
    }

    /// The sibling path a provider gives to the losing content.
    static func conflictCopyPath(
        for path: String, style: SimConflictStyle, computerName: String, loserMac: SimMacName, globalNow: Int64
    ) -> String {
        let slash = path.lastIndex(of: "/")
        let directory = slash.map { String(path[...$0]) } ?? ""
        let file = slash.map { String(path[path.index(after: $0)...]) } ?? path
        let dot = file.lastIndex(of: ".")
        let stem = dot.map { String(file[..<$0]) } ?? file
        let ext = dot.map { String(file[$0...]) } ?? ""
        let parts = dateParts(globalNow: globalNow)
        switch style {
        case .dropbox:
            return "\(directory)\(stem) (\(computerName)'s conflicted copy \(parts.date))\(ext)"
        case .oneDrive:
            return "\(directory)\(stem)-\(computerName)\(ext)"
        case .nextcloud:
            return "\(directory)\(stem) (conflicted copy \(parts.date) \(parts.time))\(ext)"
        case .syncthing:
            let identifier = String(repeating: String(loserMac.name.prefix(1)).uppercased(), count: 7)
            return "\(directory)\(stem).sync-conflict-\(parts.compactDate)-\(parts.compactTime)-\(identifier)\(ext)"
        case .perDeviceWinner, .lastWriterWins:
            return path
        }
    }

    private static func dateParts(globalNow: Int64) -> (date: String, time: String, compactDate: String, compactTime: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let instant = Date(timeIntervalSince1970: Double(SimClock.epochMilliseconds + globalNow) / 1000)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        let year = c.year ?? 0, month = c.month ?? 0, day = c.day ?? 0
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = c.second ?? 0
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return (
            "\(year)-\(two(month))-\(two(day))",
            "\(two(hour)).\(two(minute)).\(two(second))",
            "\(year)\(two(month))\(two(day))",
            "\(two(hour))\(two(minute))\(two(second))"
        )
    }

    /// The Mac's computer name: the planted marker `MARKER-NAME-<mac>` unless the world gave another. OneDrive and
    /// Dropbox put it into a conflict copy's file name, which the privacy oracle must never find in a written byte.
    private func computerName(of mac: SimMacName) -> String {
        computerNames[mac] ?? "MARKER-NAME-\(mac.name)"
    }

    // MARK: Delivery

    private mutating func delay() -> Int64 {
        policy.medianDelayMilliseconds <= 0 ? 0 : random.heavyTailedDelay(medianMilliseconds: policy.medianDelayMilliseconds)
    }

    private mutating func enqueue(
        version id: Int,
        to target: SimMacName,
        mode: SimDeliveryMode,
        from writer: SimMacName?,
        fixedTime: Int64? = nil
    ) {
        guard let path = versions[id]?.path else { return }
        let sendTime = max(now, writer.flatMap { replicas[$0]?.offlineUntil } ?? 0)
        let time = max(fixedTime ?? (sendTime + delay()), replicas[target]?.offlineUntil ?? 0)
        queue.append(SimDelivery(
            time: time, sequence: nextSequence, target: target, path: path, version: id, mode: mode, duplicate: false
        ))
        nextSequence += 1
        if mode == .main, random.chance(policy.duplicateProbability) {
            queue.append(SimDelivery(
                time: time + delay() + 1, sequence: nextSequence, target: target, path: path, version: id,
                mode: mode, duplicate: true
            ))
            nextSequence += 1
        }
    }

    /// A Mac that joins, or mounts again, receives what the cloud considers current and loses what is gone.
    private mutating func catchUp(_ mac: SimMacName) {
        for path in current.keys.sorted() {
            guard let id = current[path], versions[id]?.localTo == nil else { continue }
            enqueue(version: id, to: mac, mode: .main, from: nil)
        }
        let held = replicas[mac]?.entries.keys.sorted() ?? []
        for path in held where current[path] == nil {
            let version = replicas[mac]?.versions[path] ?? 0
            queue.append(SimDelivery(
                time: now + delay(), sequence: nextSequence, target: mac, path: path, version: version,
                mode: .delete(upTo: max(version, 0)), duplicate: false
            ))
            nextSequence += 1
        }
    }

    /// Delivers everything due up to `time`, in order of (time, sequence), and returns what changed where.
    mutating func deliverDue(until time: Int64) -> [SimDeliveryNotice] {
        var notices: [SimDeliveryNotice] = []
        while true {
            var best: Int?
            for index in queue.indices where queue[index].time <= time {
                if let current = best, (queue[current].time, queue[current].sequence) <= (queue[index].time, queue[index].sequence) {
                    continue
                }
                best = index
            }
            guard let index = best else { break }
            let item = queue.remove(at: index)
            now = max(now, item.time)
            if item.mode == .main, !item.duplicate, random.chance(policy.coalesceProbability) {
                // Coalescing: when newer content for the same path is due as well, the older is skipped.
                let newer = queue.filter {
                    $0.target == item.target && $0.path == item.path && $0.mode == .main
                        && $0.time <= time && $0.version > item.version
                }
                if let newest = newer.map(\.version).max() {
                    queue.removeAll {
                        $0.target == item.target && $0.path == item.path && $0.mode == .main
                            && $0.time <= time && $0.version < newest
                    }
                    log.append("coalesce \(item.target) \(item.path) skips v\(item.version)")
                    continue
                }
            }
            if let notice = apply(item) { notices.append(notice) }
        }
        now = max(now, time)
        return notices
    }

    private mutating func apply(_ item: SimDelivery) -> SimDeliveryNotice? {
        guard var replica = replicas[item.target] else { return nil }
        guard replica.isMounted else {
            log.append("drop \(item.target) \(item.path) v\(item.version) unmounted")
            return nil
        }
        let path = item.path
        switch item.mode {
        case .main, .restore:
            guard let version = versions[item.version] else { return nil }
            let held = replica.versions[path] ?? 0
            if item.mode == .main {
                if item.version == held { return nil }
                if held > item.version, item.duplicate || random.chance(policy.coalesceProbability) {
                    log.append("stale \(item.target) \(path) v\(item.version) held v\(held)")
                    return nil
                }
            }
            if case .foreign(.symbolicLink) = version.kind {
                replica.entries[path] = .symbolicLink
            } else if random.chance(policy.datalessOnArrivalProbability) {
                replica.entries[path] = .dataless(version.data)
            } else {
                replica.entries[path] = .present(version.data)
            }
            replica.versions[path] = item.version
            replica.seenVersions.insert(item.version)
            replica.partialWindows[path] = nil
        case .conflictVersion:
            guard let version = versions[item.version] else { return nil }
            var existing = replica.conflictVersions[path] ?? []
            guard !existing.contains(where: { $0.version == item.version }) else { return nil }
            existing.append(SimFolderReplica.ConflictVersion(version: item.version, data: version.data))
            replica.conflictVersions[path] = existing
            replica.seenVersions.insert(item.version)
        case .delete(let upTo):
            guard replica.entries[path] != nil, (replica.versions[path] ?? 0) <= upTo else { return nil }
            replica.entries[path] = nil
            replica.versions[path] = nil
            replica.partialWindows[path] = nil
            replica.conflictVersions[path] = nil
        case .materialize:
            guard case .dataless(let data) = replica.entry(path) else { return nil }
            replica.entries[path] = .present(data)
        }
        replicas[item.target] = replica
        log.append("deliver \(item.target) \(path) v\(item.version) \(item.mode)")
        return SimDeliveryNotice(mac: item.target, path: path)
    }

    // MARK: Faults

    /// Puts any earlier content of a path back, on every Mac (version history, Time Machine, a stale replica).
    mutating func restore(path: String, version: Int) {
        guard let old = versions[version], old.path == path else {
            log.append("restore ignored \(path) v\(version)")
            return
        }
        current[path] = version
        for target in replicas.keys.sorted() { enqueue(version: version, to: target, mode: .restore, from: nil) }
        log.append("restore \(path) v\(version)")
    }

    /// Removes one file everywhere (the user, the provider or another app).
    mutating func delete(path: String) {
        let upTo = history[path]?.last ?? 0
        current[path] = nil
        queue.removeAll { $0.path == path && $0.version <= upTo && ($0.mode == .main || $0.mode == .conflictVersion) }
        for target in replicas.keys.sorted() {
            queue.append(SimDelivery(
                time: now + delay(), sequence: nextSequence, target: target, path: path, version: upTo,
                mode: .delete(upTo: upTo), duplicate: false
            ))
            nextSequence += 1
        }
        log.append("delete \(path)")
    }

    /// Removes the whole `holzBar/` folder everywhere.
    mutating func deleteFolder() {
        var paths = Set(history.keys)
        for replica in replicas.values { paths.formUnion(replica.entries.keys) }
        for path in paths.sorted() where path.hasPrefix("holzBar/") { delete(path: path) }
        log.append("deleteFolder")
    }

    /// Turns a present file into a dataless placeholder on one Mac (Optimize Storage, Files On-Demand).
    mutating func evict(path: String, mac: SimMacName) {
        guard case .present(let data) = replicas[mac]?.entry(path) ?? .absent else { return }
        replicas[mac]?.entries[path] = .dataless(data)
        log.append("evict \(mac) \(path)")
    }

    /// Readers on one Mac see truncated bytes until `until`.
    mutating func exposePartial(path: String, mac: SimMacName, until: Int64) {
        guard case .present(let data) = replicas[mac]?.entry(path) ?? .absent else { return }
        let held = replicas[mac]?.versions[path] ?? 0
        replicas[mac]?.entries[path] = .partial(Data(data.prefix(max(1, data.count / 2))))
        replicas[mac]?.partialWindows[path] = SimFolderReplica.PartialWindow(until: until, full: data, version: held)
        log.append("exposePartial \(mac) \(path) until \(until)")
    }

    /// Coordinated reads and writes on the Mac block until `until` (`Int64.max`: a hung provider).
    mutating func stall(mac: SimMacName, until: Int64) {
        guard replicas[mac] != nil else { return }
        replicas[mac]?.stalledUntil = until
        log.append("stall \(mac) until \(until == Int64.max ? "forever" : String(until))")
    }

    /// The share disappears on one Mac. A write attempt there is a violation candidate.
    mutating func unmount(_ mac: SimMacName) {
        guard replicas[mac] != nil else { return }
        replicas[mac]?.isMounted = false
        log.append("unmount \(mac)")
    }

    mutating func mount(_ mac: SimMacName) {
        guard replicas[mac]?.isMounted == false else { return }
        replicas[mac]?.isMounted = true
        catchUp(mac)
        log.append("mount \(mac)")
    }

    /// The Mac neither sends nor receives until `until`.
    mutating func setOffline(_ mac: SimMacName, until: Int64) {
        guard replicas[mac] != nil else { return }
        replicas[mac]?.offlineUntil = until
        for index in queue.indices where queue[index].target == mac || versions[queue[index].version]?.writer == mac {
            queue[index].time = max(queue[index].time, until)
        }
        log.append("offline \(mac) until \(until)")
    }

    /// Another app or person puts arbitrary bytes at a path: the folder is untrusted.
    mutating func foreign(path: String, kind: SimForeignKind) {
        let data: Data
        switch kind {
        case .symbolicLink:
            data = Data()
        case .oversize:
            data = Data(repeating: 0x78, count: (1 << 20) + 16)
        case .truncatedPlist:
            let base = current[path].flatMap { versions[$0]?.data } ?? Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist><dict>".utf8)
            data = Data(base.prefix(max(1, base.count / 2)))
        case .typeSwappedPlist:
            let swapped: [String: Any] = ["modified": "not a date", "deviceID": 7, "settings": "not a dictionary"]
            data = (try? PropertyListSerialization.data(fromPropertyList: swapped, format: .xml, options: 0)) ?? Data()
        case .garbage:
            data = Data("garbage".utf8)
        }
        let id = newVersion(path: path, data: data, writer: nil, kind: .foreign(kind))
        current[path] = id
        for target in replicas.keys.sorted() { enqueue(version: id, to: target, mode: .main, from: nil) }
        log.append("foreign \(kind.rawValue) \(path) v\(id)")
    }

    /// Reorders one delivery: a fault operation of its own ("reordering across paths").
    mutating func retime(version: Int, target: SimMacName, to time: Int64) {
        for index in queue.indices where queue[index].version == version && queue[index].target == target {
            queue[index].time = time
        }
    }

    /// Asks for a dataless file's content; it becomes present after a delay.
    mutating func requestDownload(path: String, mac: SimMacName) {
        guard case .dataless = replicas[mac]?.entry(path) ?? .absent else { return }
        let id = current[path] ?? replicas[mac]?.versions[path] ?? 0
        queue.append(SimDelivery(
            time: max(now + delay(), replicas[mac]?.offlineUntil ?? 0), sequence: nextSequence, target: mac,
            path: path, version: id, mode: .materialize, duplicate: false
        ))
        nextSequence += 1
        log.append("download requested \(mac) \(path)")
    }

    /// The Mac resolved the unresolved conflict versions at a path.
    mutating func resolveConflictVersions(path: String, mac: SimMacName) {
        replicas[mac]?.conflictVersions[path] = nil
    }

    // MARK: Housekeeping

    mutating func settle(at time: Int64) {
        for mac in replicas.keys.sorted() { replicas[mac]?.settle(at: time) }
    }

    mutating func drainLog() -> [String] {
        defer { log = [] }
        return log
    }
}
