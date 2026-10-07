import Foundation

/// How a provider resolves two concurrent writes to one path (A2 section 6.2).
enum SimConflictStyle: String, Hashable, Sendable, CaseIterable {
    /// iCloud: each device keeps its own content as the winner and the other content stays an unresolved version.
    case perDeviceWinner
    /// Dropbox: `<name> (<computer>'s conflicted copy <date>).plist`.
    case dropbox
    /// OneDrive: `<name>-<computer>.plist`. The computer name is a marker the privacy oracle looks for.
    case oneDrive
    /// Nextcloud: `<name> (conflicted copy <date> <time>).plist`, kept only on the losing Mac.
    case nextcloud
    /// Syncthing: `<name>.sync-conflict-<date>-<time>-<id>.plist`.
    case syncthing
    /// SMB and others: the last writer wins, no copy.
    case lastWriterWins
}

/// Per-step probabilities of the provider's fault events, used by the generator of plan 28-06.
struct SimFaultRates: Equatable, Sendable {
    var restore = 0.0
    var delete = 0.0
    var deleteFolder = 0.0
    var evict = 0.0
    var exposePartial = 0.0
    var stall = 0.0
    var unmount = 0.0
    var foreign = 0.0
    var offline = 0.0
}

/// The fault policy (A2 section 6.3).
struct SimFaultPolicy: Equatable, Sendable {
    /// Median delivery delay. Zero delivers at once, without drawing a random number.
    var medianDelayMilliseconds: Int64 = 0
    /// Probability that a stale delivery is dropped and that due deliveries of one path coalesce to the newest.
    var coalesceProbability = 1.0
    /// Probability that a delivery arrives a second time.
    var duplicateProbability = 0.0
    /// Two writes to one path within this window by Macs that have not seen each other conflict.
    var conflictWindowMilliseconds: Int64 = 30_000
    /// Probability that a concurrent write makes a conflict copy; otherwise the last writer wins.
    var conflictCopyProbability = 1.0
    var conflictStyles: [SimConflictStyle] = []
    /// Probability that delivered content arrives as a dataless placeholder.
    var datalessOnArrivalProbability = 0.0
    /// Whether running Macs get a folder-change signal after a delivery (SMB emits none).
    var signalsFolderChanges = true
    var rates = SimFaultRates()
    /// Typical durations the generator uses for offline windows, partial exposure and stalls.
    var typicalOfflineMilliseconds: Int64 = 60_000
    var typicalPartialMilliseconds: Int64 = 3_000
    var typicalStallMilliseconds: Int64 = 2_000

    /// No delay and no faults: every write reaches every replica at the same instant.
    static let ideal = SimFaultPolicy()
}

/// The seven presets of A2 section 6.3 and analysis section 5.3.
enum SimProviderPreset: String, CaseIterable, Sendable {
    case iCloud
    case dropbox
    case oneDrive
    case nextcloud
    case syncthing
    case smb
    case hostile

    var policy: SimFaultPolicy {
        switch self {
        case .iCloud:
            SimFaultPolicy(
                medianDelayMilliseconds: 4_000, duplicateProbability: 0.05, conflictCopyProbability: 0.6,
                conflictStyles: [.perDeviceWinner], datalessOnArrivalProbability: 0.4,
                rates: SimFaultRates(restore: 0.01, delete: 0.005, deleteFolder: 0.002, evict: 0.03, foreign: 0.005, offline: 0.02)
            )
        case .dropbox:
            SimFaultPolicy(
                medianDelayMilliseconds: 3_000, duplicateProbability: 0.05, conflictCopyProbability: 0.7,
                conflictStyles: [.dropbox], datalessOnArrivalProbability: 0.3,
                rates: SimFaultRates(restore: 0.01, delete: 0.005, deleteFolder: 0.002, evict: 0.02, foreign: 0.005, offline: 0.02)
            )
        case .oneDrive:
            SimFaultPolicy(
                medianDelayMilliseconds: 5_000, duplicateProbability: 0.05, conflictCopyProbability: 0.7,
                conflictStyles: [.oneDrive], datalessOnArrivalProbability: 0.3,
                rates: SimFaultRates(restore: 0.01, delete: 0.005, deleteFolder: 0.002, evict: 0.02, foreign: 0.005, offline: 0.02)
            )
        case .nextcloud:
            SimFaultPolicy(
                medianDelayMilliseconds: 8_000, duplicateProbability: 0.03, conflictCopyProbability: 0.7,
                conflictStyles: [.nextcloud], datalessOnArrivalProbability: 0.1,
                rates: SimFaultRates(restore: 0.01, delete: 0.005, deleteFolder: 0.002, evict: 0.01, foreign: 0.005, offline: 0.03)
            )
        case .syncthing:
            // No dataless files, but days of lag are possible and a replica can roll back.
            SimFaultPolicy(
                medianDelayMilliseconds: 20_000, duplicateProbability: 0.05, conflictCopyProbability: 0.8,
                conflictStyles: [.syncthing], datalessOnArrivalProbability: 0,
                rates: SimFaultRates(restore: 0.03, delete: 0.005, deleteFolder: 0.002, foreign: 0.005, offline: 0.06),
                typicalOfflineMilliseconds: 3 * 24 * 3600 * 1000
            )
        case .smb:
            // Last writer wins, partial reads, unmount, stalls and polling only.
            SimFaultPolicy(
                medianDelayMilliseconds: 500, conflictCopyProbability: 0, conflictStyles: [],
                signalsFolderChanges: false,
                rates: SimFaultRates(delete: 0.005, exposePartial: 0.03, stall: 0.03, unmount: 0.02, offline: 0.01),
                typicalStallMilliseconds: 4_000
            )
        case .hostile:
            SimFaultPolicy(
                medianDelayMilliseconds: 10_000, coalesceProbability: 0.8, duplicateProbability: 0.15,
                conflictCopyProbability: 0.8, conflictStyles: SimConflictStyle.allCases,
                datalessOnArrivalProbability: 0.3,
                rates: SimFaultRates(
                    restore: 0.04, delete: 0.02, deleteFolder: 0.01, evict: 0.05, exposePartial: 0.04,
                    stall: 0.04, unmount: 0.03, foreign: 0.04, offline: 0.06
                ),
                typicalOfflineMilliseconds: 24 * 3600 * 1000
            )
        }
    }
}
