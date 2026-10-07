import Foundation

/// The outcome of a write handed to the provider.
enum SimWriteOutcome: Equatable, Sendable {
    case written(version: Int)
    case notMounted
    case timedOut
}

/// A delivery that reached a Mac's replica: the world raises a folder signal for it.
struct SimDeliveryNotice: Equatable, Sendable {
    var mac: SimMacName
    var path: String
}

/// The file provider. This first version delivers every write to every replica at once; the fault model
/// (delays, offline windows, conflicts and the rest) replaces it in the next task behind the same surface.
struct SimProvider: Sendable {
    var now: Int64 = 0
    private(set) var replicas: [SimMacName: SimFolderReplica] = [:]
    private var nextVersion = 1
    private var notices: [SimDeliveryNotice] = []
    private var log: [String] = []

    init() {}

    mutating func ensureReplica(for mac: SimMacName) {
        if replicas[mac] == nil { replicas[mac] = SimFolderReplica() }
    }

    func replica(of mac: SimMacName) -> SimFolderReplica { replicas[mac] ?? SimFolderReplica() }

    mutating func write(from mac: SimMacName, path: String, data: Data) -> SimWriteOutcome {
        ensureReplica(for: mac)
        let version = nextVersion
        nextVersion += 1
        for target in replicas.keys.sorted() {
            replicas[target]?.entries[path] = .present(data)
            replicas[target]?.versions[path] = version
            if target != mac { notices.append(SimDeliveryNotice(mac: target, path: path)) }
        }
        log.append("write \(mac) \(path) v\(version)")
        return .written(version: version)
    }

    /// Folder-change signals reach running Macs after a delivery (SMB emits none).
    var signalsFolderChanges: Bool { true }

    var nextDeliveryTime: Int64? { notices.isEmpty ? nil : now }

    mutating func requestDownload(path: String, mac: SimMacName) {}

    mutating func resolveConflictVersions(path: String, mac: SimMacName) {
        replicas[mac]?.conflictVersions[path] = nil
    }

    mutating func deliverDue(until time: Int64) -> [SimDeliveryNotice] {
        now = time
        defer { notices = [] }
        return notices
    }

    mutating func settle(at time: Int64) {
        for mac in replicas.keys.sorted() { replicas[mac]?.settle(at: time) }
    }

    mutating func drainLog() -> [String] {
        defer { log = [] }
        return log
    }
}
