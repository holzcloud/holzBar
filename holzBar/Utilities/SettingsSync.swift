//
//  SettingsSync.swift
//  holzBar
//

import AppKit
import CryptoKit
import IOKit
import Observation
import os
import OSLog

/// Shows the question of the sync sheet and returns the user's answer. The sheet is plan 28-17's.
@MainActor
protocol SyncQuestionPresenting: AnyObject {
    /// Shows `question` as a sheet on `window`.
    ///
    /// - Returns: What the user answered, or `nil` when the sheet closed without an answer.
    func present(_ question: SyncQuestion, on window: NSWindow) async -> SyncAnswerRequest?
}

/// The host of the settings sync engine: it keeps holzBar's settings in step across Macs through
/// files in a folder the Macs sync, such as iCloud Drive or a Nextcloud, Dropbox, OneDrive or
/// Syncthing folder or a network share (jordanbaird/Ice#95, SYNC-01).
///
/// The host decides nothing. `SyncEngine.handle` decides, the same function the simulator runs; the
/// host builds its events from the preferences, the folder, the state file, timers and the user's
/// clicks, and carries out the effects it returns strictly in order. Each Mac writes only its own
/// device file `holzBar/Macs/<MacID>.plist` and never touches `holzBar/Settings.plist` of the
/// earlier builds (decision D-02). The folder's own app moves the files; holzBar never connects to
/// the network.
///
/// Sync is paused in this build (``SettingsSyncPause``): every entry point checks
/// ``SettingsSyncPause/isActive(isPaused:)``, so nothing here reads, writes, watches, mounts or
/// changes the stored sync configuration until plan 28-18 removes the pause.
///
/// No file access runs on the main thread, apart from the launch, which waits for the folder for a
/// second at most. The folder is read and written on one serial file queue with time limits (a
/// provider that hangs stalls that queue, never the menu bar); the state file and the preferences
/// are flushed on a second queue that only touches local files. The state is persisted before any
/// device file is written, and the generation key and the counter mirror before the state.
@MainActor
@Observable
final class SettingsSync {
    private nonisolated static let logger = Logger(category: "SettingsSync")

    // MARK: Stored keys

    /// The key of the bookmark of the chosen folder. It starts with "SettingsSync", so it stays on this Mac
    /// (`SettingsBackup.excludedKeyPrefixes`). The keys of the earlier builds (`SettingsSyncLastSynced`, the digests
    /// and edit counts, `SettingsSyncPendingModified`) stay where they are for a downgrade and are never evidence.
    private nonisolated static let folderBookmarkKey = "SettingsSyncFolderBookmark"

    /// The bookmark of a folder the user chose and whose join is not decided yet, so a join survives a relaunch.
    private nonisolated static let pendingFolderBookmarkKey = "SettingsSyncPendingFolderBookmark"

    /// The key of this Mac's sync ID, the salt and the hash that binds the ID to this Mac and this account, and the
    /// ID this Mac had before it rotated (`SyncEffect.storeIdentity`). None of them is exported, imported, synced or logged.
    private nonisolated static let deviceIDKey = "SettingsSyncDeviceID"
    private nonisolated static let deviceSaltKey = "SettingsSyncDeviceSalt"
    private nonisolated static let deviceHashKey = "SettingsSyncDeviceHash"
    private nonisolated static let legacyDeviceIDKey = "SettingsSyncLegacyDeviceID"

    // MARK: Queues and limits

    /// The queue of every access to the sync folder, one at a time. A provider that hangs stalls it.
    private nonisolated static let fileQueue = DispatchQueue(label: "com.holzcloud.holzBar.SettingsSync.folder", qos: .utility)

    /// The queue of the state file and the flush of the preferences: local files only, so it never waits for a provider.
    private nonisolated static let stateQueue = DispatchQueue(label: "com.holzcloud.holzBar.SettingsSync.state", qos: .utility)

    /// How long a read or a write of the folder may take before it is given up, in seconds.
    private nonisolated static let folderTimeLimit: TimeInterval = 30

    /// The poll of a folder on a network volume, in seconds: file events do not see another computer's writes there.
    private nonisolated static let networkPollInterval: TimeInterval = 2 * 60

    // MARK: Launch

    /// The host the launch built, adopted by the app state. `nil` while sync is paused, off without a state, or when
    /// a newer holzBar wrote the state.
    private static var launched: SettingsSync?

    /// The host of the app state: the one the launch built, or a plain one.
    static func forAppState() -> SettingsSync {
        launched ?? SettingsSync()
    }

    /// Starts the engine before anything reads the settings. The app delegate calls this before it creates the app
    /// state, after the migrations that rewrite the preferences.
    ///
    /// It loads the state, feeds the launch to the engine and carries out what comes first: it applies the settings that
    /// are waiting, persists the state, and reads the folder for a second at most, never waiting for a file that is not on
    /// this Mac. Everything else the engine asked for waits for ``performSetup(with:)``. It writes no device file.
    static func launch() {
        guard SettingsSyncPause.isActive() else {
            return
        }
        let host = SettingsSync()
        guard host.runLaunch(creatingState: false) else {
            return
        }
        launched = host
    }

    // MARK: Observable state

    /// A Boolean value that indicates whether syncing is turned on.
    private(set) var isEnabled = false

    /// Whether the user turned sync on, as stored, shown while sync is paused (``SettingsSyncPause``); nothing syncs
    /// then, and the choice stays as it is.
    private(set) var isTurnedOnWhilePaused = false

    /// The name of the synced folder to show, or `nil` when there is none. Updated while sync is on, when the folder is
    /// chosen, when the settings show it (``refreshFolder()``) and after each read, never in a view body.
    private(set) var folderDisplayName: String?

    /// The hint and the status lines of the sync, as the engine computes them from its state.
    private(set) var view = SyncView(hint: nil, lines: [])

    /// What holzBar offers for settings that wait, shown in the sync settings and the holzBar menu.
    var hint: SyncHint? {
        view.hint
    }

    /// The applications whose arrangement automatic stores must leave alone (`SyncLayout27.protectedApplications(in:)`).
    var protectedApplications: Set<String> {
        state.map(SyncLayout27.protectedApplications(in:)) ?? []
    }

    /// The sheet that shows the question; plan 28-17 sets it.
    @ObservationIgnored var questionPresenter: (any SyncQuestionPresenting)?

    // MARK: Private state

    @ObservationIgnored private weak var appState: AppState?

    /// The engine's state; `nil` until the engine started.
    @ObservationIgnored private var state: SyncState?

    /// What the effects of the engine's steps still have to do, in order, each with the state of its step.
    @ObservationIgnored private var queue: [Queued] = []

    /// The task that carries out the queue while an effect waits for a queue or a file.
    @ObservationIgnored private var pumpTask: Task<Void, Never>?

    /// Whether the launch or the quit carries out the queue itself: they block, for a bounded time, for the folder and the
    /// state file, which nothing else may do.
    @ObservationIgnored private var isBlocking = false

    /// Whether the app is quitting: nothing is scheduled, read or restarted then.
    @ObservationIgnored private var isTerminating = false

    /// The generation of the last state this host persisted, and the counter floor it knows.
    @ObservationIgnored private var persistedGeneration: UInt64 = 0
    @ObservationIgnored private var highWater: UInt64 = 0

    /// Whether the launch could not read the folder in time, so a check follows once the app is set up.
    @ObservationIgnored private var needsCheckAfterSetup = false

    @ObservationIgnored private let defaultsStore = SyncDefaultsStore(
        defaults: .standard,
        domainName: Bundle.main.bundleIdentifier ?? "com.holzcloud.holzBar"
    )
    @ObservationIgnored private let stateStore = SyncFileCoordination.makeStateStore()

    /// The unit table, built once: its normalizers decode the models and so belong to the main actor.
    private static let table = SyncUnitTable.version1(normalizers: SyncModelNormalizers.make())

    /// A fresh identity the engine takes when it has to re-identify this Mac, kept until the engine used it.
    @ObservationIgnored private var pendingFresh: SyncFreshIdentity?

    @ObservationIgnored private var timers: [SyncTimer: Task<Void, Never>] = [:]
    @ObservationIgnored private var defaultsObserver: Task<Void, Never>?
    @ObservationIgnored private var wakeObservers: [Task<Void, Never>] = []
    @ObservationIgnored private let snapshotDebouncer = Debouncer(delay: .milliseconds(300))

    /// Where the Macs sync, as last resolved off the main thread. The main actor uses only this and never resolves the
    /// bookmark itself, as the folder may be on a network share that hangs.
    @ObservationIgnored private var location = FolderLocation()

    /// The folder the user chose and whose join is not decided yet.
    @ObservationIgnored private var pendingFolderURL: URL?

    @ObservationIgnored private var folderWatcher: SyncFolderWatcher?
    @ObservationIgnored private var presenter: SyncFolderPresenter?
    @ObservationIgnored private var watchGeneration = 0

    /// Whether a folder is being chosen (the panel, the bookmark).
    @ObservationIgnored private var isChoosingFolder = false

    /// Whether a join the user just started with Turn On… or Change… goes on into the sheet once it has rows. A join
    /// holzBar started itself never does (D-09).
    @ObservationIgnored private var continuesIntoSheet = false

    /// Whether the question sheet is open.
    @ObservationIgnored private var isPresenting = false

    /// A question that waits for the Settings window to be on screen, to show as a sheet on it.
    @ObservationIgnored private var settingsWindowWait: ObservationLoop?

    // MARK: Setup

    func performSetup(with appState: AppState) {
        self.appState = appState
        let isTurnedOn = Defaults.bool(forKey: .syncsSettingsWithICloud)
        guard SettingsSyncPause.isActive() else {
            isTurnedOnWhilePaused = isTurnedOn
            Self.logger.info("Settings sync is paused in this build")
            return
        }
        guard state != nil else {
            return
        }
        refreshView()
        updateObservers()
        pump()
        if needsCheckAfterSetup {
            needsCheckAfterSetup = false
            schedule(.check, after: SyncTimer.check.delay)
        }
    }

    // MARK: Events

    /// The defaults changed in a way the engine should see: another model saved its setting. The engine captures it
    /// after its own debounce.
    func settingsDidChange() {
        guard SettingsSyncPause.isActive(), state != nil else {
            return
        }
        snapshotDebouncer.schedule { [weak self] in
            self?.feedSnapshot()
        }
    }

    /// The user changed units of the macOS 27 families (a move in the Layout pane, a profile, an import). It works whenever
    /// a state exists, also while sync is off: it then persists the state and drops the folder effects, so the moves the
    /// user made while sync was off are there for the later join.
    func recordIntent(_ intent: SyncIntent) {
        guard SettingsSyncPause.isActive(), let state else {
            return
        }
        feedSnapshot()
        let isOff = !state.isEnabled && state.pendingJoin == nil
        let before = queue.count
        run(.intent(intent))
        if isOff {
            // Only what must be persisted: nothing of the folder runs while sync is off.
            var kept = Array(queue[..<before])
            for item in queue[before...] {
                if case .persist = item.effect {
                    kept.append(item)
                }
            }
            queue = kept
        }
        pump()
    }

    /// An import of a settings file changed the preferences: they are the user's changes, captured by diff. The state is
    /// persisted when this returns, since the relaunch that follows an import must not lose them.
    func finishImport() {
        guard SettingsSyncPause.isActive(), state != nil else {
            return
        }
        snapshotDebouncer.cancel()
        guard run(.command(.importFinished(currentSnapshot()))) != nil else {
            return
        }
        drainSynchronousPrefix()
        persistQueuedStates()
        pump()
    }

    /// The app quits: capture the last changes and write the own file, waiting briefly for it.
    func prepareForTermination() {
        guard SettingsSyncPause.isActive(), let state, state.isEnabled else {
            return
        }
        snapshotDebouncer.cancel()
        guard run(.quit(currentSnapshot())) != nil else {
            return
        }
        // The queue holds what earlier steps left, then this step's: each persist before any write, each wait bounded.
        isBlocking = true
        isTerminating = true
        defer {
            isBlocking = false
            isTerminating = false
        }
        while let item = queue.first {
            queue.removeFirst()
            executeBlocking(item, timeLimit: 2)
        }
    }

    private func feedSnapshot() {
        guard SettingsSyncPause.isActive(), let state else {
            return
        }
        let snapshot = currentSnapshot()
        guard snapshot != state.session.snapshot else {
            return
        }
        run(.defaultsChanged(snapshot))
        pump()
    }

    private func currentSnapshot() -> SyncSnapshot {
        defaultsStore.snapshot(table: Self.table, generation: Self.generation, baselineKeys: Set(state?.baseline.keys ?? [:].keys))
    }

    private static var generation: SyncGeneration {
        MenuBarBackendKind.current == .accessibility27 ? .g27 : .g26
    }

    private func timerFired(_ timer: SyncTimer) {
        timers[timer] = nil
        guard SettingsSyncPause.isActive() else {
            return
        }
        run(.timer(timer))
        pump()
    }

    /// Runs `command` with the current settings, so the engine decides with what the user sees now.
    private func command(_ command: SyncCommand) {
        guard SettingsSyncPause.isActive(), state != nil else {
            return
        }
        snapshotDebouncer.cancel()
        let snapshot = currentSnapshot()
        if snapshot != state?.session.snapshot {
            run(.defaultsChanged(snapshot))
        }
        run(.command(command))
        pump()
    }

    // MARK: The engine

    /// Feeds `event` to the engine and queues the effects of its step.
    @discardableResult
    private func run(_ event: SyncEvent, atFront: Bool = false) -> SyncStep? {
        guard SettingsSyncPause.isActive(), let current = state else {
            return nil
        }
        let step = SyncEngine.handle(event, state: current, environment: environment())
        accept(step, atFront: atFront)
        return step
    }

    private func accept(_ step: SyncStep, atFront: Bool) {
        let hadJoin = state?.pendingJoin != nil
        state = step.state
        if let fresh = pendingFresh, step.state.mac == fresh.mac {
            pendingFresh = nil
        }
        let commits = step.effects.contains { effect in
            if case .commitFolder = effect {
                true
            } else {
                false
            }
        }
        if hadJoin, step.state.pendingJoin == nil, !commits {
            // The join ended without committing (Cancel, Turn Off): the folder the user chose is forgotten.
            clearPendingFolder()
        }
        let items = step.effects.map { Queued(effect: $0, state: step.state) }
        if atFront {
            queue = items + queue
        } else {
            queue += items
        }
        refreshView()
    }

    private func environment() -> SyncEnvironment {
        let now = Date.now
        return SyncEnvironment(
            table: Self.table,
            generation: Self.generation,
            now: now,
            unixSeconds: UInt64(max(0, now.timeIntervalSince1970)),
            counterFloors: SyncCounterFloors(mirror: defaultsStore.counterMirror, highWater: highWater),
            guards: .all,
            freshIdentity: freshIdentity()
        )
    }

    private func freshIdentity() -> SyncFreshIdentity {
        if let pendingFresh {
            return pendingFresh
        }
        let fresh = SyncFreshIdentity(mac: SyncMacID(UUID()), nonce: UUID().uuidString)
        pendingFresh = fresh
        return fresh
    }

    /// Shows the engine's view, and goes on into the sheet for a join the user started.
    private func refreshView() {
        guard let state else {
            return
        }
        let refreshed = SyncEngine.view(of: state, environment: environment())
        if view != refreshed {
            view = refreshed
        }
        if isEnabled != state.isEnabled {
            isEnabled = state.isEnabled
        }
        updateFolderDisplayName()
        updateObservers()
        if state.pendingJoin == nil {
            continuesIntoSheet = false
        } else if continuesIntoSheet, state.pendingJoin?.phase == .asking {
            continuesIntoSheet = false
            if appState?.navigationState.isSettingsPresented == true {
                chooseSettings()
            }
        }
    }

    // MARK: The queue

    /// One effect of a step, with the state of that step: a persist writes the state of its own step, not a later one.
    private struct Queued {
        var effect: SyncEffect
        var state: SyncState
    }

    /// Carries out the queue: what needs no waiting at once, in order, and the rest on a task, one effect after another.
    private func pump() {
        guard SettingsSyncPause.isActive(), pumpTask == nil else {
            return
        }
        drainSynchronousPrefix()
        guard !queue.isEmpty else {
            return
        }
        guard !isBlocking else {
            // The launch carries out the queue itself.
            return
        }
        pumpTask = Task { [weak self] in
            await self?.pumpQueue()
        }
    }

    private func pumpQueue() async {
        while let item = queue.first {
            queue.removeFirst()
            await execute(item)
        }
        pumpTask = nil
    }

    /// Carries out the effects at the front of the queue that do not wait for anything.
    private func drainSynchronousPrefix() {
        while let item = queue.first, !Self.waits(item.effect) {
            queue.removeFirst()
            executeImmediately(item.effect)
        }
    }

    /// Whether an effect waits for a queue or a file.
    private static func waits(_ effect: SyncEffect) -> Bool {
        switch effect {
        case .persist, .readFolder, .writeOwnFile:
            true
        case .applyUnits, .applyKnownApplications, .schedule, .cancelTimer, .relaunch, .requestDownload, .storeIdentity, .commitFolder, .forgetFolder:
            false
        }
    }

    private func execute(_ item: Queued) async {
        switch item.effect {
        case .persist(let request):
            await persist(request, state: item.state)
        case .readFolder(let request):
            await readFolder(request)
        case .writeOwnFile(let request):
            await writeOwnFile(request, state: item.state)
        default:
            executeImmediately(item.effect)
        }
    }

    /// Carries out one effect and waits for it with the calling thread: the launch, the quit and an import, which
    /// cannot wait for a task. The wait is bounded.
    private func executeBlocking(_ item: Queued, timeLimit: TimeInterval) {
        switch item.effect {
        case .persist(let persist):
            persistBlocking(persist, state: item.state)
        case .readFolder(let request):
            readFolderBlocking(request, timeLimit: timeLimit)
        case .writeOwnFile(let request):
            writeOwnFileBlocking(request, state: item.state, timeLimit: timeLimit)
        case .relaunch, .schedule, .requestDownload:
            if !isTerminating {
                executeImmediately(item.effect)
            }
        default:
            executeImmediately(item.effect)
        }
    }

    /// Persists every state the queue still has to persist, now, in order: after an import, whose settings the relaunch
    /// that follows must not lose.
    private func persistQueuedStates() {
        var rest: [Queued] = []
        for item in queue {
            if case .persist(let persist) = item.effect {
                persistBlocking(persist, state: item.state)
            } else {
                rest.append(item)
            }
        }
        queue = rest
    }

    // MARK: Effects that do not wait

    private func executeImmediately(_ effect: SyncEffect) {
        switch effect {
        case .applyUnits(let units):
            let report = defaultsStore.apply(units, table: Self.table)
            if !report.skipped.isEmpty {
                Self.logger.info("Skipped \(report.skipped.count, privacy: .public) settings that are not valid on this Mac")
            }
        case .applyKnownApplications(let applications):
            defaultsStore.applyKnownApplications(applications)
        case .schedule(let timer, let delay):
            schedule(timer, after: delay)
        case .cancelTimer(let timer):
            timers[timer]?.cancel()
            timers[timer] = nil
        case .relaunch:
            SettingsBackup.relaunch()
        case .requestDownload(let macs):
            requestDownload(of: macs)
        case .storeIdentity(let mac, let legacyID):
            storeIdentity(mac, legacyID: legacyID)
        case .commitFolder(let identity):
            commitFolder(identity)
        case .forgetFolder:
            forgetFolder()
        case .persist, .readFolder, .writeOwnFile:
            // These wait; the queue carries them out.
            break
        }
    }

    private func schedule(_ timer: SyncTimer, after delay: TimeInterval) {
        timers[timer]?.cancel()
        var delay = delay
        if timer == .periodic, !location.isLocalVolume {
            delay = min(delay, Self.networkPollInterval)
        }
        timers[timer] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.timerFired(timer)
        }
    }

    /// Keeps this Mac's identity in the preferences: the ID, the salted hash that binds it to this Mac and this
    /// account, and the earlier ID.
    private func storeIdentity(_ mac: SyncMacID, legacyID: String?) {
        let defaults = UserDefaults.standard
        let salt = defaults.data(forKey: Self.deviceSaltKey) ?? SettingsSyncDevice.makeSalt()
        defaults.set(salt, forKey: Self.deviceSaltKey)
        defaults.set(mac.rawValue, forKey: Self.deviceIDKey)
        if let hardwareID = Self.hardwareID {
            defaults.set(SettingsSyncDevice.hardwareHash(of: hardwareID, uid: getuid(), salt: salt), forKey: Self.deviceHashKey)
        }
        if let legacyID {
            defaults.set(legacyID, forKey: Self.legacyDeviceIDKey)
        }
    }

    /// The join committed: the folder the user chose is the sync folder now.
    private func commitFolder(_ identity: SyncFolderIdentity) {
        let defaults = UserDefaults.standard
        if let bookmark = defaults.data(forKey: Self.pendingFolderBookmarkKey), Self.folderIdentity(of: bookmark) == identity {
            defaults.set(bookmark, forKey: Self.folderBookmarkKey)
            defaults.removeObject(forKey: Self.pendingFolderBookmarkKey)
            if let url = pendingFolderURL {
                location = FolderLocation(syncFolderURL: url, iCloudDriveURL: location.iCloudDriveURL)
            }
            stopWatching()
        }
        pendingFolderURL = nil
        Defaults.set(true, forKey: .syncsSettingsWithICloud)
        updateFolderDisplayName()
        updateObservers()
        Self.logger.notice("Joined the sync folder")
    }

    /// Sync is off: the folder is forgotten and nothing is read or written any more.
    private func forgetFolder() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.folderBookmarkKey)
        clearPendingFolder()
        Defaults.set(false, forKey: .syncsSettingsWithICloud)
        location = FolderLocation(iCloudDriveURL: location.iCloudDriveURL)
        folderDisplayName = nil
        stopWatching()
        Self.logger.notice("Turned sync off")
    }

    private func clearPendingFolder() {
        pendingFolderURL = nil
        if UserDefaults.standard.object(forKey: Self.pendingFolderBookmarkKey) != nil {
            UserDefaults.standard.removeObject(forKey: Self.pendingFolderBookmarkKey)
        }
    }

    private func requestDownload(of macs: [SyncMacID]) {
        // A join asks for the files of the folder the user chose, which is not the sync folder before it commits.
        let target = readTarget(for: state?.pendingJoin == nil ? .check : .join)
        Task {
            await BlockingWork.run(on: Self.fileQueue) {
                guard let folder = Self.resolveFolder(target) else {
                    return
                }
                let directory = folder
                    .appending(path: SyncFolderLayout.folderName, directoryHint: .isDirectory)
                    .appending(path: SyncFolderLayout.devicesName, directoryHint: .isDirectory)
                SyncFileCoordination.startDownloads(of: macs.map { directory.appending(path: "\($0.rawValue).plist") })
            }
        }
    }

    // MARK: Effects that wait

    /// Persists the generation key and the counter mirror, then the counter floor, the preferences and the state, in
    /// this order (analysis section 4.4). A state that did not persist writes no device file.
    private func persist(_ persist: SyncPersist, state: SyncState) async {
        guard beginPersist(persist) else {
            return
        }
        let stateStore = stateStore
        let defaultsStore = defaultsStore
        let failure = await BlockingWork.run(on: Self.stateQueue) {
            Self.write(state, counter: persist.counter, stateStore: stateStore, defaultsStore: defaultsStore)
        }
        endPersist(persist, failure: failure)
    }

    private func persistBlocking(_ persist: SyncPersist, state: SyncState) {
        guard beginPersist(persist) else {
            return
        }
        let stateStore = stateStore
        let defaultsStore = defaultsStore
        let failure = Self.stateQueue.sync {
            Self.write(state, counter: persist.counter, stateStore: stateStore, defaultsStore: defaultsStore)
        }
        endPersist(persist, failure: failure)
    }

    /// Whether the persist goes ahead: a state older than the one persisted never replaces it.
    private func beginPersist(_ persist: SyncPersist) -> Bool {
        guard persist.generation >= persistedGeneration else {
            return false
        }
        defaultsStore.setGeneration(persist.generation)
        defaultsStore.setCounterMirror(persist.counter)
        return true
    }

    private func endPersist(_ persist: SyncPersist, failure: SyncStateStoreError?) {
        if let failure {
            Self.logger.error("The sync state was not persisted: \(String(describing: failure), privacy: .public)")
            return
        }
        persistedGeneration = max(persistedGeneration, persist.generation)
        highWater = max(highWater, persist.counter)
    }

    private nonisolated static func write(
        _ state: SyncState,
        counter: UInt64,
        stateStore: SyncStateStore,
        defaultsStore: SyncDefaultsStore
    ) -> SyncStateStoreError? {
        stateStore.raiseHighWater(to: counter)
        defaultsStore.flush()
        do {
            try stateStore.persist(state)
            return nil
        } catch let error as SyncStateStoreError {
            return error
        } catch {
            return .cannotWrite
        }
    }

    /// Reads the folder and feeds what was found back, ahead of the rest of the queue.
    private func readFolder(_ request: SyncReadRequest) async {
        let target = readTarget(for: request.purpose)
        let outcome = await BlockingWork.run(
            on: Self.fileQueue,
            timeout: .seconds(Self.folderTimeLimit + 5),
            fallback: ReadOutcome(location: nil, read: nil, watchTarget: nil)
        ) {
            Self.readJob(request, target: target, budget: Self.folderTimeLimit)
        }.value
        adopt(outcome, for: request)
    }

    /// The same, for the launch: waits at most `timeLimit` seconds on the calling thread.
    private func readFolderBlocking(_ request: SyncReadRequest, timeLimit: TimeInterval) {
        guard case .launch(let budget) = request.purpose else {
            // Only the launch read may block the launching thread; any other read waits for the queue.
            return
        }
        let target = readTarget(for: request.purpose)
        let box = OSAllocatedUnfairLock<ReadOutcome?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        // A semaphore lends the waiting thread's priority to no one, so the block asks for it itself; at the queue's
        // utility QoS, a busy login could delay it past the bound and turn a file that is on this Mac into a hint.
        Self.fileQueue.async(qos: .userInitiated, flags: .enforceQoS) {
            let outcome = Self.readJob(request, target: target, budget: min(budget, timeLimit))
            box.withLock { $0 = outcome }
            done.signal()
        }
        guard done.wait(timeout: .now() + min(budget, timeLimit)) == .success, let outcome = box.withLock({ $0 }) else {
            Self.logger.info("The sync folder was not read in time; checking it after launch")
            needsCheckAfterSetup = true
            return
        }
        adopt(outcome, for: request)
    }

    private func adopt(_ outcome: ReadOutcome, for request: SyncReadRequest) {
        if let resolved = outcome.location {
            let wasLocal = location.isLocalVolume
            location = resolved
            updateFolderDisplayName()
            if wasLocal, !resolved.isLocalVolume, timers[.periodic] != nil {
                // File events do not see another computer's writes on a network volume: poll sooner.
                schedule(.periodic, after: Self.networkPollInterval)
            }
        }
        if case .join = request.purpose {
            // A join reads the folder the user chose: nothing of it is the sync folder yet.
        } else {
            ensureWatching(syncFolder: location.syncFolderURL, knownTarget: outcome.watchTarget)
        }
        let read = outcome.read ?? SyncFolderRead(availability: .unavailable)
        if case .launch = request.purpose, outcome.read == nil {
            return
        }
        if case .launch = request.purpose, read.files.contains(where: { $0.state == .pending || $0.state == .dataless }) {
            // A file that is not on this Mac waits for a check after launch.
            needsCheckAfterSetup = true
        }
        run(.folderRead(read, purpose: request.purpose), atFront: true)
    }

    /// Writes the own file, and feeds the result back, ahead of the rest of the queue.
    private func writeOwnFile(_ request: SyncWriteRequest, state: SyncState) async {
        guard state.generation <= persistedGeneration else {
            // The state this write belongs to did not persist: no device file is written before its state is.
            Self.logger.error("Not writing the own file: its state was not persisted")
            return
        }
        let presenter = presenter
        let result = await BlockingWork.run(
            on: Self.fileQueue,
            timeout: .seconds(Self.folderTimeLimit + 5),
            fallback: SyncWriteResult.failed(.unavailable)
        ) {
            Self.writeJob(request, presenter: presenter, budget: Self.folderTimeLimit)
        }.value
        run(.writeFinished(result), atFront: true)
    }

    /// The same, for the quit: the own file is written with the calling thread waiting, for a short time.
    private func writeOwnFileBlocking(_ request: SyncWriteRequest, state: SyncState, timeLimit: TimeInterval) {
        guard state.generation <= persistedGeneration else {
            return
        }
        let presenter = presenter
        let box = OSAllocatedUnfairLock<SyncWriteResult?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        Self.fileQueue.async(qos: .userInitiated, flags: .enforceQoS) {
            let result = Self.writeJob(request, presenter: presenter, budget: timeLimit)
            box.withLock { $0 = result }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeLimit) == .success, let result = box.withLock({ $0 }) else {
            return
        }
        run(.writeFinished(result), atFront: true)
    }

    // MARK: Folder jobs (file queue)

    /// What a read of the folder found.
    private nonisolated struct ReadOutcome: Sendable {
        /// Where the Macs sync as resolved for this read; `nil` for the read of a chosen folder.
        var location: FolderLocation?
        /// What the folder holds; `nil` when it was not read in time.
        var read: SyncFolderRead?
        /// The folder to watch.
        var watchTarget: URL?
    }

    /// Which folder a read is about.
    private nonisolated enum ReadTarget: Sendable {
        /// The sync folder.
        case active
        /// The folder the user chose, from its bookmark.
        case bookmark(Data)
    }

    private func readTarget(for purpose: SyncReadPurpose) -> ReadTarget {
        guard case .join = purpose, let identity = state?.pendingJoin?.folderIdentity else {
            return .active
        }
        if let bookmark = UserDefaults.standard.data(forKey: Self.pendingFolderBookmarkKey), Self.folderIdentity(of: bookmark) == identity {
            return .bookmark(bookmark)
        }
        // A join the launch started for the stored folder.
        return .active
    }

    private nonisolated static func readJob(_ request: SyncReadRequest, target: ReadTarget, budget: TimeInterval) -> ReadOutcome {
        let deadline = ContinuousClock.now.advanced(by: .seconds(budget))
        var resolved: FolderLocation?
        let folder: URL?
        switch target {
        case .active:
            resolved = resolveLocation()
            folder = resolved?.syncFolderURL
        case .bookmark(let data):
            folder = resolveBookmark(data)
        }
        guard let folder else {
            return ReadOutcome(location: resolved, read: SyncFolderRead(availability: .unavailable), watchTarget: nil)
        }
        let watch: URL? = if case .active = target { SyncFileCoordination.watchTarget(for: folder) } else { nil }
        let macs = folder
            .appending(path: SyncFolderLayout.folderName, directoryHint: .notDirectory)
            .appending(path: SyncFolderLayout.devicesName, directoryHint: .notDirectory)
        let read: SyncFolderRead?
        if SyncFileCoordination.isICloudDrive(folder) {
            read = SyncFileCoordination.coordinatedRead(at: macs, timeout: budget) {
                SyncFolderReader.read(request, syncFolder: folder, isDownloaded: { SyncFolderReader.isDownloaded($0) }, deadline: deadline)
            }
        } else {
            read = SyncFolderReader.read(request, syncFolder: folder, isDownloaded: { SyncFolderReader.isDownloaded($0) }, deadline: deadline)
        }
        return ReadOutcome(location: resolved, read: read, watchTarget: watch)
    }

    private nonisolated static func writeJob(_ request: SyncWriteRequest, presenter: SyncFolderPresenter?, budget: TimeInterval) -> SyncWriteResult {
        guard let folder = resolveLocation().syncFolderURL else {
            return .failed(.unavailable)
        }
        guard SyncFileCoordination.isICloudDrive(folder) else {
            return SyncFolderWriter.write(request, syncFolder: folder)
        }
        let file = folder
            .appending(path: SyncFolderLayout.folderName, directoryHint: .notDirectory)
            .appending(path: SyncFolderLayout.devicesName, directoryHint: .notDirectory)
            .appending(path: "\(request.contents.mac.rawValue).plist")
        return SyncFileCoordination.coordinatedWrite(at: file, presenter: presenter, timeout: budget) {
            SyncFolderWriter.write(request, syncFolder: folder)
        } ?? .failed(.unavailable)
    }

    // MARK: Folder location

    /// Where the Macs sync, as resolved on the file queue (``resolveLocation()``).
    private nonisolated struct FolderLocation: Sendable {
        /// The folder the Macs sync, or `nil` when there is none now.
        var syncFolderURL: URL?
        /// iCloud Drive's folder, if iCloud Drive is turned on.
        var iCloudDriveURL: URL?
        /// Whether the folder's volume is on this Mac.
        var isLocalVolume = true
    }

    /// iCloud Drive's folder, if iCloud Drive is turned on. Looked up on the file queue.
    private nonisolated static var iCloudDriveURL: URL? {
        SyncFileCoordination.iCloudDriveURL()
    }

    /// Resolves the folder the Macs sync, chosen by the user or iCloud Drive (see `SettingsSyncLocation`). A stale
    /// bookmark, or iCloud Drive used without a choice, is stored as the choice.
    ///
    /// Resolving the bookmark reaches the folder's volume, which may be a network share that hangs, so it runs on the
    /// file queue only (F-15). The bookmark is resolved without mounting: holzBar never mounts a network share itself,
    /// and a folder on a volume that is not mounted is not found until the user mounts it (INV-R3).
    private nonisolated static func resolveLocation() -> FolderLocation {
        let resolution: SettingsSyncLocation.Resolution
        var resolvedURL: URL?
        if let bookmark = UserDefaults.standard.data(forKey: folderBookmarkKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                resolvedURL = url
                resolution = .resolved(path: url.path(percentEncoded: false), isStale: isStale)
            } else {
                resolution = .failed
            }
        } else {
            resolution = .none
        }
        let iCloudDriveURL = iCloudDriveURL
        let decision = SettingsSyncLocation.decide(resolution: resolution, iCloudDrivePath: iCloudDriveURL?.path(percentEncoded: false))
        guard let folderPath = decision.folderPath else {
            return FolderLocation(iCloudDriveURL: iCloudDriveURL)
        }
        let url = resolvedURL ?? iCloudDriveURL ?? URL(filePath: folderPath, directoryHint: .isDirectory)
        if decision.storesBookmark, let bookmark = makeBookmark(of: url) {
            UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
        }
        return FolderLocation(syncFolderURL: url, iCloudDriveURL: iCloudDriveURL, isLocalVolume: SyncFileCoordination.isLocalVolume(url))
    }

    /// The folder a read or a download is about, resolved on the file queue.
    private nonisolated static func resolveFolder(_ target: ReadTarget) -> URL? {
        switch target {
        case .active:
            resolveLocation().syncFolderURL
        case .bookmark(let data):
            resolveBookmark(data)
        }
    }

    private nonisolated static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// The bookmark of the given folder, or `nil` when it cannot be made. Runs on the file queue.
    private nonisolated static func makeBookmark(of folderURL: URL) -> Data? {
        do {
            return try folderURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            logger.error("Could not store the sync folder: \(error, privacy: .private)")
            return nil
        }
    }

    /// An opaque name of the folder of a bookmark, which the engine carries and gives back (`SyncFolderIdentity`). It
    /// holds neither the path nor the name of the folder.
    private nonisolated static func folderIdentity(of bookmark: Data?) -> SyncFolderIdentity {
        guard let bookmark else {
            return "iCloud Drive"
        }
        return SHA256.hash(data: bookmark).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Updates the name of the synced folder to show, from the resolved folder.
    private func updateFolderDisplayName() {
        let name = location.syncFolderURL.map { url in
            SettingsSyncLocation.displayName(
                forFolder: url.path(percentEncoded: false),
                homePath: SyncFileCoordination.homeDirectory.path(percentEncoded: false),
                iCloudDrivePath: location.iCloudDriveURL?.path(percentEncoded: false)
            )
        }
        if folderDisplayName != name {
            folderDisplayName = name
        }
    }

    /// Updates the name of the synced folder to show while sync is on, as the folder may have been moved, renamed or
    /// deleted since. While sync is off, looks up iCloud Drive, where the folder panel starts.
    func refreshFolder() {
        guard SettingsSyncPause.isActive() else {
            return
        }
        let isOn = state?.isEnabled == true
        Task { [weak self] in
            if isOn {
                let resolved = await BlockingWork.run(on: Self.fileQueue) { Self.resolveLocation() }
                self?.location = resolved
                self?.updateFolderDisplayName()
            } else if self?.location.iCloudDriveURL == nil {
                let url = await BlockingWork.run(on: Self.fileQueue) { Self.iCloudDriveURL }
                self?.location.iCloudDriveURL = url
            }
        }
    }

    // MARK: Observers and watching

    /// Starts or stops observing the settings, the folder and the Mac's wake, as sync is on or off. The observers exist only
    /// while sync is on or a join is pending.
    private func updateObservers() {
        let isWanted = SettingsSyncPause.isActive() && appState != nil && (state?.isEnabled == true || state?.pendingJoin != nil)
        guard isWanted else {
            defaultsObserver?.cancel()
            defaultsObserver = nil
            wakeObservers.forEach { $0.cancel() }
            wakeObservers = []
            snapshotDebouncer.cancel()
            stopWatching()
            return
        }
        if defaultsObserver == nil {
            defaultsObserver = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                    self?.settingsDidChange()
                }
            }
        }
        if wakeObservers.isEmpty {
            // The folder may have changed while holzBar was in the background or the Mac slept, a volume may have been mounted
            // or unmounted: a check, after the engine's own delay.
            let workspace = NSWorkspace.shared.notificationCenter
            let names: [(NotificationCenter, Notification.Name)] = [
                (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
                (workspace, NSWorkspace.didWakeNotification),
                (workspace, NSWorkspace.didMountNotification),
                (workspace, NSWorkspace.didUnmountNotification),
            ]
            wakeObservers = names.map { center, name in
                Task { [weak self] in
                    for await _ in center.notifications(named: name) {
                        self?.scheduleCheck()
                    }
                }
            }
        }
        if folderWatcher == nil {
            ensureWatching(syncFolder: location.syncFolderURL)
        }
    }

    private func scheduleCheck() {
        guard SettingsSyncPause.isActive(), state?.isEnabled == true || state?.pendingJoin != nil else {
            return
        }
        schedule(.check, after: SyncTimer.check.delay)
    }

    /// Watches the folder that tells when another Mac's file arrives: `holzBar/Macs`, or the nearest folder above it that
    /// exists, so the watcher hears the folders appear that the first write creates.
    ///
    /// - Parameters:
    ///   - syncFolder: The folder the Macs sync.
    ///   - knownTarget: The folder to watch, when a read just looked at the file system; otherwise it is looked up on the
    ///     file queue.
    private func ensureWatching(syncFolder: URL?, knownTarget: URL? = nil) {
        guard SettingsSyncPause.isActive(), let syncFolder, appState != nil, state?.isEnabled == true || state?.pendingJoin != nil else {
            return
        }
        if let knownTarget, let folderWatcher, folderWatcher.folderURL.standardizedFileURL == knownTarget.standardizedFileURL {
            return
        }
        watchGeneration += 1
        let generation = watchGeneration
        let current = folderWatcher?.folderURL
        let onChange: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.scheduleCheck()
            }
        }
        Task { [weak self] in
            let made = await BlockingWork.run(on: Self.fileQueue) { () -> SyncFolderWatcher? in
                let target = knownTarget ?? SyncFileCoordination.watchTarget(for: syncFolder)
                if let current, current.standardizedFileURL == target.standardizedFileURL {
                    // Already watching it.
                    return nil
                }
                return SyncFolderWatcher(folderURL: target, onChange: onChange)
            }
            guard let self, generation == watchGeneration else {
                made?.cancel()
                return
            }
            guard let made else {
                return
            }
            stopWatching()
            watchGeneration = generation
            folderWatcher = made
            if SyncFileCoordination.isICloudDrive(made.folderURL) {
                // iCloud Drive's versions arrive through file coordination, which a watcher does not hear.
                let presenter = SyncFolderPresenter(folderURL: made.folderURL, onChange: onChange)
                SyncFileCoordination.add(presenter)
                self.presenter = presenter
            }
        }
    }

    private func stopWatching() {
        watchGeneration += 1
        folderWatcher?.cancel()
        folderWatcher = nil
        if let presenter {
            SyncFileCoordination.remove(presenter)
            self.presenter = nil
        }
    }

    // MARK: Commands

    /// Lets the user choose the folder the Macs sync, and starts the join of it: Turn On… when sync is off, Change… when it
    /// is on. Nothing changes until the join commits; Cancel keeps the previous folder.
    ///
    /// - Returns: Whether a folder was chosen; joining it goes on afterwards.
    @discardableResult
    func chooseFolder() -> Bool {
        guard SettingsSyncPause.isActive(), SettingsSyncPause.allowsChanges(), !isChoosingFolder else {
            return false
        }
        if state == nil {
            // A Mac that never synced has no engine yet: start it, so the join has a state to begin from.
            guard runLaunch(creatingState: true) else {
                return false
            }
            pump()
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Sync Here")
        panel.message = String(localized: "Choose a folder your Macs keep in sync, such as iCloud Drive or a Nextcloud, Dropbox, OneDrive or Syncthing folder. holzBar keeps its settings in a holzBar folder inside it.")
        panel.directoryURL = location.syncFolderURL ?? location.iCloudDriveURL
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        isChoosingFolder = true
        Task { [weak self] in
            // The bookmark is made on the file queue, off the main thread.
            let bookmark = await BlockingWork.run(on: Self.fileQueue) { Self.makeBookmark(of: url) }
            self?.startJoin(of: url, bookmark: bookmark)
        }
        return true
    }

    private func startJoin(of url: URL, bookmark: Data?) {
        isChoosingFolder = false
        guard SettingsSyncPause.isActive(), let bookmark, let state else {
            return
        }
        UserDefaults.standard.set(bookmark, forKey: Self.pendingFolderBookmarkKey)
        pendingFolderURL = url
        let identity = Self.folderIdentity(of: bookmark)
        continuesIntoSheet = true
        command(state.isEnabled ? .changeFolder(identity) : .turnOn(identity))
        updateObservers()
    }

    /// Turn Off: all folder access stops, the state is kept.
    func turnOff() {
        command(.turnOff)
    }

    /// Cancel while a join reads the folder or asks.
    func cancelJoin() {
        continuesIntoSheet = false
        command(.cancelJoin)
    }

    /// Applies what waits and restarts, as the hint's Restart offers.
    func restartWithWaitingSettings() {
        command(.restart)
    }

    /// Asks which settings to use, in a sheet on the Settings window, which opens for it.
    func chooseSettings() {
        guard SettingsSyncPause.isActive(), state != nil else {
            return
        }
        showSettings { [weak self] window in
            self?.present(on: window)
        }
    }

    /// The question the sheet shows: this Mac's own, or the one of the settings it is only a bystander of.
    func currentQuestion() -> SyncQuestion? {
        guard let state else {
            return nil
        }
        let environment = environment()
        return SyncEngine.question(for: state, scope: .mine, environment: environment)
            ?? SyncEngine.question(for: state, scope: .bystander, environment: environment)
    }

    /// Gives the engine the user's answer to the question.
    func submit(_ answer: SyncAnswerRequest) {
        command(.answer(answer))
    }

    private func present(on window: NSWindow) {
        guard !isPresenting, let questionPresenter, let question = currentQuestion() else {
            return
        }
        isPresenting = true
        Task { [weak self] in
            let answer = await questionPresenter.present(question, on: window)
            self?.isPresenting = false
            if let answer {
                self?.submit(answer)
            }
        }
    }

    /// Shows the Settings window on the Advanced pane, and then calls `present` with it once it is on screen, without
    /// polling. A newer request replaces one that still waits.
    private func showSettings(then present: @escaping @MainActor (NSWindow) -> Void) {
        guard let appState else {
            return
        }
        settingsWindowWait?.cancel()
        settingsWindowWait = nil
        let navigationState = appState.navigationState
        navigationState.settingsNavigationIdentifier = .advanced
        if navigationState.isSettingsPresented, let window = navigationState.settingsWindow {
            appState.activate(for: .settings)
            window.makeKeyAndOrderFront(nil)
            present(window)
            return
        }
        settingsWindowWait = ObservationLoop.observe { navigationState.isSettingsPresented } onChange: { [weak self] isPresented in
            guard isPresented, let self, let window = navigationState.settingsWindow else {
                return
            }
            settingsWindowWait?.cancel()
            settingsWindowWait = nil
            present(window)
        }
        // While permissions are missing, their window opens instead; the question waits.
        guard !appState.openPermissionsWindowIfNeeded() else {
            return
        }
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    // MARK: Starting the engine

    /// Starts the engine: loads the state, feeds the launch and carries out the first effects.
    ///
    /// - Parameter creatingState: Whether to start it without a state on disk and with sync off, so a join can begin
    ///   (Turn On… on a Mac that never synced). The launch at the start of the app does not: a Mac that never synced
    ///   has no state, and nothing runs for it.
    /// - Returns: Whether the engine runs.
    private func runLaunch(creatingState: Bool) -> Bool {
        let defaults = UserDefaults.standard
        let isOn = Defaults.bool(forKey: .syncsSettingsWithICloud)
        let hasPendingFolder = defaults.object(forKey: Self.pendingFolderBookmarkKey) != nil
        guard creatingState || isOn || hasPendingFolder || stateStore.hasFile else {
            return false
        }
        let loaded = stateStore.load()
        if case .read(.newerFormat) = loaded {
            // A newer holzBar wrote the state: this build neither reads nor replaces it, and does not sync (D-02).
            Self.logger.notice("A newer holzBar wrote the sync state; sync does nothing in this build")
            return false
        }
        highWater = stateStore.highWater
        let bookmark = defaults.data(forKey: Self.folderBookmarkKey)
        let input = SyncLaunchInput(
            snapshot: currentSnapshot(),
            stored: loaded.forEngine,
            identity: SyncIdentityInput(
                storedID: defaults.string(forKey: Self.deviceIDKey),
                storedHash: defaults.string(forKey: Self.deviceHashKey),
                salt: defaults.data(forKey: Self.deviceSaltKey),
                hardwareID: Self.hardwareID,
                uid: getuid()
            ),
            defaultsGeneration: defaultsStore.generation,
            lastSyncedSeen: defaultsStore.lastSyncedSeen,
            syncIsOn: isOn,
            folder: Self.folderIdentity(of: bookmark)
        )
        let step = SyncEngine.launch(input, environment: environment())
        if case .read(.state(let stored)) = loaded {
            persistedGeneration = stored.generation
        }
        persistedGeneration = max(persistedGeneration, defaultsStore.generation ?? 0)
        accept(step, atFront: false)
        if step.state.pendingJoin == nil {
            // A folder that was chosen for a join that is gone (the state was lost) is forgotten.
            clearPendingFolder()
        }
        isBlocking = true
        defer { isBlocking = false }
        carryOutLaunchEffects()
        return true
    }

    /// Carries out the queue the launch built, as far as it can without waiting: the settings, the state, the folder read
    /// of the launch. What waits for the app to be set up stays in the queue.
    private func carryOutLaunchEffects() {
        while let item = queue.first {
            switch item.effect {
            case .persist:
                queue.removeFirst()
                executeBlocking(item, timeLimit: SyncEngine.launchReadBudget)
            case .readFolder(let request):
                guard case .launch = request.purpose else {
                    return
                }
                queue.removeFirst()
                executeBlocking(item, timeLimit: SyncEngine.launchReadBudget)
            case .writeOwnFile:
                return
            default:
                queue.removeFirst()
                executeImmediately(item.effect)
            }
        }
    }

    // MARK: Hardware

    /// This Mac's hardware UUID, read from the I/O Registry. It never leaves this Mac and is never stored; only its salted
    /// hash is.
    private static let hardwareID: String? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }()
}
