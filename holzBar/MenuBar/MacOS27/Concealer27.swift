//
//  Concealer27.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog

/// Hides menu bar items on macOS 27, where holzBar's expanding dividers no longer work.
///
/// On macOS 27 the section of each application comes from a saved layout, first
/// taken from the user's holzBar layout: MenuBarAgent reorders items on its own, so their
/// order on the bar no longer says which section they belong to. The concealer hides
/// applications through `MenuBarAssessmentAssertion27`, following that layout and the
/// state of holzBar's sections.
@available(macOS 27.0, *)
@MainActor
@Observable
final class Concealer27 {
    @ObservationIgnored private let controller = ConcealmentController27(backend: MenuBarAssessmentAssertion27())
    @ObservationIgnored private let logger = Logger(category: "Concealer27")
    @ObservationIgnored private weak var appState: AppState?
    /// Tasks that observe display changes; cancelled with the concealer.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Observes the running applications, so a menu bar agent that launches or quits is
    /// noticed: NSWorkspace's launch and quit notifications reach regular apps only.
    @ObservationIgnored private var runningApplicationsObservation: NSKeyValueObservation?

    /// The bundle identifiers running at the last change of the running applications.
    @ObservationIgnored private var runningBundleIDs = Set<String>()
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var suspendedUntil: ContinuousClock.Instant?

    /// Counts the suspensions begun, so only the timer of the one that owns ``suspendedUntil``
    /// puts concealment back.
    @ObservationIgnored private var suspensionOwner = 0

    /// When the last concealment change landed on the bar, which is when the bar last started
    /// moving.
    @ObservationIgnored private var lastChangeAt = ContinuousClock.now

    /// The applies queued, and whoever waits for one to land.
    @ObservationIgnored private var applyLedger = ApplyLedger27<CheckedContinuation<Bool, Never>>()

    /// How long a show is waited for. MenuBarAgent answers an activation within 3 s or the
    /// activation times out (`MenuBarAssessmentAssertion27`), so a show that has not landed by
    /// then is not waited for.
    private static let applyWaitLimit = Duration.seconds(3)

    /// How long MenuBarAgent animates the bar after items are concealed or released
    /// (measured on macOS 27.0: about 250 ms, with a margin here).
    private static let settleAfterChange = Duration.milliseconds(400)

    /// Failed applies in a row, each answered by one more try a moment later.
    @ObservationIgnored private var failedApplies = 0

    /// Counts the changes of `isConcealing` and `concealedPIDs`, so an apply that fails for
    /// good corrects them only while they still describe its own target.
    @ObservationIgnored private var stateGeneration = 0

    /// How many times in a row a failed apply is tried again.
    private static let maximumApplyRetries = 3

    /// Applications shown for a moment, with the number of callers showing each.
    @ObservationIgnored private var temporarilyShown = [String: Int]()
    /// Observers of the active space and the Settings pane.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Whether any application is meant to be concealed right now.
    private(set) var isConcealing = false

    /// Whether a suspension under way lifted concealment; see ``concealsThroughSuspensions``.
    private(set) var suspendedConcealment = SuspendedConcealment()

    /// Whether any application is meant to be concealed, counting the ones a suspension
    /// releases for a moment (a bridged click, a relayout for the notch).
    ///
    /// `isConcealing` turns `false` for every suspension. What follows concealment as a state,
    /// such as the capture badge on holzBar's icon, reads this instead, so it does not flicker
    /// with every click on a system item.
    var concealsThroughSuspensions: Bool {
        suspendedConcealment.conceals(isConcealing: isConcealing)
    }

    /// Process identifiers of the applications meant to be concealed right now.
    private(set) var concealedPIDs = Set<pid_t>()

    /// Visible applications concealed for the moment so holzBar's icon clears the notch
    /// (`NotchCover27`). Never part of the saved layout; cleared when the active display
    /// changes, an application that may own items launches or quits, or what the sections
    /// conceal changes.
    @ObservationIgnored private var notchConcealed = Set<String>()

    /// The applications the sections concealed when `update()` last ran, to tell when
    /// `notchConcealed` is worth working out again.
    @ObservationIgnored private var notchCoverBasis: Set<String>?

    /// The display whose notch `notchConcealed` was worked out for.
    @ObservationIgnored private var notchCoverDisplayID: CGDirectDisplayID?

    /// The display whose bar was active at the last settled read, and its width.
    @ObservationIgnored private var lastActiveDisplay: (id: CGDirectDisplayID, width: CGFloat, hasNotch: Bool)?

    /// Whether the last settled read showed items folded behind the overflow button.
    @ObservationIgnored private var lastReadHadFoldedItems = false

    /// Applications that launched while their section is concealed, shown until their item
    /// exists (jordanbaird/Ice#1007).
    @ObservationIgnored private var launchGrace = LaunchGrace27()

    /// The applications concealed at the last change, to tell a change of concealment.
    @ObservationIgnored private var lastConcealed = Set<String>()

    /// Settled reads in a row, while concealing, without holzBar's icon among the items.
    @ObservationIgnored private var readsWithoutIcon = 0

    /// Whether holzBar's icon was put back since concealment last changed.
    @ObservationIgnored private var didReinsertIcon = false

    /// The section of each application. Applications missing from it are visible.
    private var savedLayout: [String: MacOS27Section] {
        let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        return stored.compactMapValues(MacOS27Section.init(rawValue:))
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        guard MenuBarAssessmentAssertion27.isAvailable else {
            logger.error("MenuBarClientCore assertions are unavailable, so items will not be hidden")
            return
        }
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Reads only the bundle identifiers of the changed applications, keeps no reference to
        // them, takes no lock and never waits: the handler runs on the main thread.
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let changed = (change.newValue ?? []) + (change.oldValue ?? [])
            guard changed.contains(where: { $0.bundleIdentifier != nil }) else {
                return
            }
            Task { @MainActor in
                self?.runningApplicationsDidChange()
            }
        }
        observerTasks.append(Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                guard let self, !notchConcealed.isEmpty else {
                    continue
                }
                notchConcealed.removeAll()
                update()
            }
        })
        // The assertions are released at termination by `releaseAllForTermination()`,
        // which the app delegate calls synchronously.
        // Entering or leaving fullscreen swaps the menu bar the items are drawn in, and nothing
        // else here notices: the concealment was left exactly as the previous bar had it, so
        // holzBar's own item was missing from the bar that slides down over a fullscreen window and
        // there was nothing to click. `HIDEventManager` watches the same state, for the same
        // reason, on earlier versions of macOS.
        observers.append(
            ObservationLoop.observe { appState.activeSpace.isFullscreen } onChange: { [weak self] _ in
                self?.update()
            }
        )
        let navigation = appState.navigationState
        observers.append(
            ObservationLoop.observe { navigation.isSettingsPresented } onChange: { [weak self] _ in
                self?.update()
            }
        )
        observers.append(
            ObservationLoop.observe { navigation.settingsNavigationIdentifier } onChange: { [weak self] _ in
                self?.update()
            }
        )
        update()
    }

    deinit {
        for task in observerTasks {
            task.cancel()
        }
    }

    /// Answers a change of the running applications.
    ///
    /// Most changes leave the set of bundle identifiers as it was (a helper restarts, a second
    /// instance starts) and do nothing. Otherwise concealment is worked out again only when an
    /// application that may own items launched or quit (``AgentLaunches27``), at once: the
    /// allowlist has to land before a launching agent creates its status item.
    private func runningApplicationsDidChange() {
        let applications = NSWorkspace.shared.runningApplications
        let running = Set(applications.compactMap(\.bundleIdentifier))
        guard running != runningBundleIDs else {
            return
        }
        let instances = applications.compactMap { application -> AgentLaunches27.Instance? in
            guard let bundleID = application.bundleIdentifier else {
                return nil
            }
            let policy: AgentLaunches27.Policy = switch application.activationPolicy {
            case .regular: .regular
            case .accessory: .accessory
            case .prohibited: .prohibited
            @unknown default: .accessory
            }
            return (bundleID, application.bundleURL?.path(percentEncoded: false), policy)
        }
        let layout = savedLayout
        let stored = Defaults.array(forKey: .knownApplications27) as? [String] ?? []
        let known = Set(layout.keys).union(stored)
        let concealedInLayout = Set(layout.filter { $0.value != .visible }.keys)
        let reaction = AgentLaunches27.reaction(
            previous: runningBundleIDs,
            instances: instances,
            known: known,
            concealedInLayout: concealedInLayout
        )
        runningBundleIDs = reaction.running
        guard reaction.updatesConcealment else {
            return
        }
        logger.debug("Applications that may own items launched or quit (\(reaction.graces.count, privacy: .public) in concealed sections)")
        applicationsDidChange(graces: reaction.graces)
    }

    /// Answers applications that may own items launching or quitting, with exactly one update.
    ///
    /// An application whose saved section is hidden or always hidden is shown until its item
    /// exists, or for at most 10 s, then concealed: concealed before its status item exists,
    /// it gets an item of 3 points (jordanbaird/Ice#1007).
    ///
    /// - Parameter candidates: The launched applications whose saved section is concealed.
    private func applicationsDidChange(graces candidates: [String]) {
        // The bar is laid out anew, so the notch is worked out again.
        notchConcealed.removeAll()
        let now = ContinuousClock.now
        let begun = candidates.filter { launchGrace.begin($0, isConcealed: true, at: now) }
        guard !begun.isEmpty else {
            update()
            return
        }
        logger.debug("\(begun.count, privacy: .public) applications in concealed sections launched, showing them until their items exist")
        showTemporarily(bundleIDs: begun)
        // One bounded wait per change.
        Task { [weak self] in
            try? await Task.sleep(for: LaunchGrace27.timeout)
            guard let self else {
                return
            }
            endGraces(launchGrace.expired(at: .now))
        }
    }

    /// Ends the launch graces of the applications whose items appeared in a read of the bar.
    func itemsAppeared(bundleIDs: Set<String>) {
        guard !launchGrace.allowed.isEmpty else {
            return
        }
        endGraces(launchGrace.itemsAppeared(bundleIDs))
    }

    /// Conceals the applications whose launch grace ended, balancing their allowance.
    private func endGraces(_ bundleIDs: [String]) {
        guard !bundleIDs.isEmpty else {
            return
        }
        endTemporaryShow(bundleIDs: bundleIDs)
    }

    /// Releases every assertion as holzBar quits, so no application stays hidden.
    func releaseAllForTermination() {
        controller.releaseAll()
    }

    /// Derives what to conceal from holzBar's sections and applies it.
    func update() {
        applyChanges()
    }

    /// Derives what to conceal from holzBar's sections and queues the apply.
    ///
    /// - Returns: Whether the change is on its way: queued now, or at the end of the suspension
    ///   under way. `false` while concealment is paused or unavailable.
    @discardableResult
    private func applyChanges() -> Bool {
        guard let appState, MenuBarAssessmentAssertion27.isAvailable else {
            return false
        }
        // While the screen is locked, the Mac sleeps or the session is away, the assertions
        // stay as they are; the concealment is applied again once the bar has settled.
        guard !appState.systemActivityMonitor.isPaused else {
            return false
        }
        if let suspendedUntil, ContinuousClock.now < suspendedUntil {
            return true
        }
        let applications = NSWorkspace.shared.runningApplications
        let running = Set(applications.compactMap(\.bundleIdentifier))
        let layout = SectionLayout27.effectiveLayout(observed: [:], saved: savedLayout, running: running)
        let state = revealState(appState)
        // What the sections conceal sets how crowded the bar is: once they conceal more (a
        // reveal that ends, a layout edit), the notch is worked out again from the next settled
        // read. When they conceal less, the bar is no roomier and the apps stay concealed; the
        // next settled read adds more if the icon is under the notch again.
        let sectionConcealed = ConcealmentPlanner27.effectivelyConcealed(
            sets: ConcealmentPlanner27.concealedSets(layout: layout, state: state)
        )
        if let notchCoverBasis, NotchCover27.sectionsMayFreeRoom(before: notchCoverBasis, after: sectionConcealed) {
            notchConcealed.removeAll()
        }
        notchCoverBasis = sectionConcealed
        // Applications concealed for the notch join whatever the sections conceal.
        let target = NotchCover27.adding(
            notchConcealed.subtracting(temporarilyShown.keys),
            to: ConcealmentPlanner27.concealedSets(
                layout: layout,
                state: state,
                temporarilyShown: Set(temporarilyShown.keys)
            )
        )
        let concealed = ConcealmentPlanner27.effectivelyConcealed(sets: target)
        if concealed != lastConcealed {
            lastConcealed = concealed
            readsWithoutIcon = 0
            didReinsertIcon = false
        }
        isConcealing = !target.isEmpty
        defer { MenuBarItemProvider27.setConcealedPIDs(concealedPIDs) }
        concealedPIDs = Self.processIdentifiers(of: concealed, among: applications)
        stateGeneration += 1
        let generation = stateGeneration
        let previous = applyTask
        let sequence = applyLedger.queue()
        let task = Task { [weak self, controller, logger] in
            await previous?.value
            do {
                try await controller.apply(target: target, running: running)
                self?.failedApplies = 0
                self?.applyFinished(sequence, succeeded: true)
            } catch {
                logger.error("Could not apply concealment: \(error, privacy: .private)")
                self?.applyDidFail(generation: generation)
                self?.applyFinished(sequence, succeeded: false)
            }
        }
        applyTask = task
        // Concealing moves the remaining items, and hover hit-testing uses their cached
        // frames. The refresh stays out of `applyTask`, so a slow read never holds up the
        // next change. The bar animates for about 250 ms (measured).
        Task { [weak self] in
            await task.value
            try? await Task.sleep(for: .milliseconds(400))
            await self?.appState?.itemManager.cacheItemsIfNeeded()
            await self?.checkStuckOverflow()
            await self?.checkNotchCover()
            await self?.checkOwnIcon()
        }
        return true
    }

    /// Records that an apply landed and answers whoever waited for it.
    private func applyFinished(_ sequence: Int, succeeded: Bool) {
        // The bar starts moving when the change lands, not when it was queued.
        lastChangeAt = .now
        for waiter in applyLedger.finish(sequence, succeeded: succeeded) {
            waiter.resume(returning: succeeded)
        }
    }

    /// Waits for the given apply to land, for at most ``applyWaitLimit``.
    ///
    /// The apply and the time limit share the continuation, and the ledger hands it to only
    /// one of them. The shared timeout helpers do not fit: they wait for the operation to
    /// return, and nothing cancels an apply.
    ///
    /// - Returns: Whether the apply succeeded in time.
    private func waitForApply(_ apply: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let id = applyLedger.wait(for: apply, waiter: continuation) else {
                continuation.resume(returning: applyLedger.lastSucceeded)
                return
            }
            // Holds the concealer for at most the limit, so the continuation is always resumed.
            Task {
                try? await Task.sleep(for: Self.applyWaitLimit)
                self.applyLedger.abandon(id)?.resume(returning: false)
            }
        }
    }

    /// Waits until the concealment changes queued so far have landed, so a capture never
    /// photographs a bar whose change is still on its way.
    func waitForPendingApplies() async {
        guard applyLedger.hasPending else {
            return
        }
        _ = await waitForApply(applyLedger.lastQueued)
    }

    /// Tries a failed apply again a moment later, a few times in a row, then follows the
    /// assertions that are actually live.
    ///
    /// `isConcealing` and `concealedPIDs` already describe the concealment that failed, and
    /// hit-testing, captures and the click bridge rely on them; MenuBarAgent can reject an
    /// assertion or time out while it is busy, after login or wake.
    private func applyDidFail(generation: Int) {
        guard failedApplies < Self.maximumApplyRetries else {
            // The next failure, from whatever change comes next, gets its own tries.
            failedApplies = 0
            guard generation == stateGeneration else {
                return
            }
            logger.notice("Concealment could not be applied, keeping to the assertions still live")
            let concealed = controller.liveConcealed
            lastConcealed = concealed
            isConcealing = controller.isActive
            concealedPIDs = Self.processIdentifiers(of: concealed, among: NSWorkspace.shared.runningApplications)
            MenuBarItemProvider27.setConcealedPIDs(concealedPIDs)
            return
        }
        failedApplies += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.update()
        }
    }

    /// The process identifiers of the given applications that are running.
    private static func processIdentifiers(of bundleIDs: Set<String>, among applications: [NSRunningApplication]) -> Set<pid_t> {
        Set(applications.compactMap { application in
            guard let bundleID = application.bundleIdentifier, bundleIDs.contains(bundleID) else {
                return nil
            }
            return application.processIdentifier
        })
    }

    /// Puts holzBar's icon back when MenuBarAgent dropped it while concealing.
    ///
    /// A known issue of the macOS 27 backend (jordanbaird/Ice#1001): MenuBarAgent can remove
    /// holzBar's own item while assertions are active, which leaves nothing to click. After
    /// two settled reads in a row without it, the icon is added again — once per change of
    /// concealment, so it never loops.
    private func checkOwnIcon() async {
        guard
            let appState,
            isConcealing,
            CaptureIndicator.showsHolzBarIcon(isIconEnabled: appState.settings.general.showHolzBarIcon, badge: appState.captureBadge27),
            !didReinsertIcon
        else {
            readsWithoutIcon = 0
            return
        }
        let items = await MenuBarItemProvider27.items()
        guard !items.contains(where: { $0.tag == .visibleControlItem }) else {
            readsWithoutIcon = 0
            return
        }
        readsWithoutIcon += 1
        guard readsWithoutIcon >= 2 else {
            return
        }
        logger.notice("holzBar's icon went missing while concealing, putting it back")
        readsWithoutIcon = 0
        didReinsertIcon = true
        appState.menuBarManager.controlItem(withName: .visible)?.reinsert()
    }

    /// Puts holzBar's icon back when a capture starts and MenuBarAgent dropped the icon.
    ///
    /// holzBar's icon carries the capture dot while concealing. ``checkOwnIcon()`` looks for the
    /// icon only after a concealment change, and a capture can start long after one
    /// (jordanbaird/Ice#1001). Two reads of the settled bar without the icon, 400 ms apart, put
    /// it back. Like ``checkOwnIcon()``, it puts the icon back at most once per change of
    /// concealment, so captures that start and stop again never make it loop.
    func checkOwnIconForCapture() async {
        guard let appState, isConcealing, !didReinsertIcon else {
            return
        }
        await waitForPendingApplies()
        if let remaining = timeUntilSettled() {
            try? await Task.sleep(for: remaining)
        }
        guard !Task.isCancelled, !(await MenuBarItemProvider27.items()).contains(where: { $0.tag == .visibleControlItem }) else {
            return
        }
        try? await Task.sleep(for: Self.settleAfterChange)
        guard
            !Task.isCancelled,
            isConcealing,
            !didReinsertIcon,
            !(await MenuBarItemProvider27.items()).contains(where: { $0.tag == .visibleControlItem })
        else {
            return
        }
        logger.notice("holzBar's icon was missing when a capture started, putting it back")
        didReinsertIcon = true
        appState.menuBarManager.controlItem(withName: .visible)?.reinsert()
    }

    /// Keeps holzBar's icon out from under the notch, and lets MenuBarAgent lay the bar out
    /// again when it moves to a wider display with items folded.
    ///
    /// Runs after each settled read. While the icon lies under the notch of the active
    /// display, the nearest visible application right of it is concealed (one per read, until
    /// the icon is clear; Thaw #1195, #1153). When the active bar moves to a display without a
    /// notch or a wider one while the last read showed folded items, concealment is released
    /// and applied again once, so the folded items come back (Thaw #1106).
    private func checkNotchCover() async {
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            return
        }
        let displayID = screen.displayID
        let displayBounds = CGDisplayBounds(displayID)
        let items = await MenuBarItemProvider27.items()
        let chevronFrame = MenuBarItemProvider27.overflowButtonFrame()

        let previous = lastActiveDisplay
        lastActiveDisplay = (displayID, displayBounds.width, screen.hasNotch)
        let hadFoldedItems = lastReadHadFoldedItems
        lastReadHadFoldedItems = items.contains { item in
            displayBounds.intersects(item.bounds) && OverflowDetection27.isInOverflow(itemFrame: item.bounds, chevronFrame: chevronFrame)
        }
        if let previous, previous.id != displayID {
            if !notchConcealed.isEmpty {
                notchConcealed.removeAll()
                update()
                return
            }
            let isRoomier = !screen.hasNotch || displayBounds.width > previous.width
            if hadFoldedItems, isRoomier, isConcealing {
                logger.notice("The bar moved to a roomier display with items folded, laying it out again")
                suspend(for: Self.settleAfterChange)
                return
            }
        }

        guard
            screen.hasNotch,
            let notchSpan = StuckOverflow27.notchSpan(
                displayBounds: displayBounds,
                leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
                rightAreaWidth: screen.auxiliaryTopRightArea?.width
            ),
            let icon = items.first(where: { $0.tag == .visibleControlItem && $0.bounds.width > 4 })
        else {
            return
        }
        if notchCoverDisplayID != displayID {
            notchConcealed.removeAll()
            notchCoverDisplayID = displayID
        }
        let concealedBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { application -> String? in
            concealedPIDs.contains(application.processIdentifier) ? application.bundleIdentifier : nil
        })
        let visibleApps = items.compactMap { item -> NotchCover27.App? in
            guard item.isOnScreen, displayBounds.intersects(item.bounds), item.bounds.width > 4 else {
                return nil
            }
            return (bundleID: item.tag.namespace.description, frame: item.bounds)
        }
        let answer = NotchCover27.appsToConceal(
            iconFrame: icon.bounds,
            visibleApps: visibleApps,
            notchSpan: notchSpan,
            concealed: concealedBundleIDs.union(notchConcealed),
            ownBundleID: Constants.bundleIdentifier
        )
        guard let next = answer.first else {
            return
        }
        logger.notice("holzBar's icon is under the notch, concealing one more visible app for now")
        notchConcealed.insert(next)
        update()
    }

    /// Whether the notched bar looks stuck with items folded away and no way to reach them.
    ///
    /// Settings shows this; nothing acts on it. The cure measured so far is to relaunch the
    /// application whose item is missing, and which application that is cannot be told apart
    /// from the frames Accessibility keeps for items it no longer draws.
    private(set) var isOverflowStuck = false

    /// Notes whether concealment has left the notched bar's items folded with no overflow button.
    ///
    /// Seen twice on this machine (2026-09-29 and 2026-10-01), both times after holzBar restarted
    /// with the bar already crowded: macOS folds what does not fit beside the notch, concealing
    /// frees the room again, and the fold is not reconsidered — the "«" goes away with the items
    /// still behind it. Measured against that live state: neither `Scripts/macos27/reflow-probe.swift`
    /// nor restarting holzBar unfolds them, while relaunching the application whose item is missing
    /// does, at once.
    private func checkStuckOverflow() async {
        let items = await MenuBarItemProvider27.items()
        guard let screen = NSScreen.screenWithActiveMenuBar, screen.hasNotch else {
            isOverflowStuck = false
            return
        }
        let displayBounds = CGDisplayBounds(screen.displayID)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frames = items
            .filter { !concealedPIDs.contains($0.ownerPID) && $0.ownerPID != ownPID && displayBounds.intersects($0.bounds) }
            .map(\.bounds)
        let stuck = StuckOverflow27.isStuck(
            visibleItemFrames: frames,
            chevronFrame: MenuBarItemProvider27.overflowButtonFrame(),
            notchSpan: StuckOverflow27.notchSpan(
                displayBounds: displayBounds,
                leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
                rightAreaWidth: screen.auxiliaryTopRightArea?.width
            )
        )
        guard stuck != isOverflowStuck else {
            return
        }
        isOverflowStuck = stuck
        if stuck {
            logger.notice("The notched bar looks stuck: items folded away with no overflow button")
        } else {
            logger.notice("The notched bar lays its items out again")
        }
    }

    /// Releases every assertion for a moment, so a click can reach a system item.
    func suspend(for duration: Duration) {
        let deadline = suspensionDeadline(for: duration)
        let owner = beginSuspension(until: deadline)
        isConcealing = false
        concealedPIDs.removeAll()
        stateGeneration += 1
        let previous = applyTask
        applyTask = Task { [weak self, controller] in
            await previous?.value
            controller.releaseAll()
            self?.lastChangeAt = .now
        }
        scheduleEndOfSuspension(at: deadline, owner: owner)
    }

    /// Releases every assertion and returns once that has actually happened.
    ///
    /// Releasing goes through MenuBarAgent and queues behind whatever concealment change came
    /// before it. A click replayed on a timer could therefore arrive while the assertion was
    /// still live, and MenuBarAgent ignores those — which is why a click on the clock sometimes
    /// did nothing and worked on the second try.
    func suspendReleased(for duration: Duration) async {
        let owner = beginSuspension(until: suspensionDeadline(for: duration))
        isConcealing = false
        concealedPIDs.removeAll()
        stateGeneration += 1
        let previous = applyTask
        let release = Task { [controller] in
            await previous?.value
            controller.releaseAll()
        }
        applyTask = release
        await release.value
        lastChangeAt = .now
        // The duration counts from the release, which can queue behind a change before it. A
        // suspension begun meanwhile, or an early end, owns the deadline now.
        guard suspensionOwner == owner else {
            return
        }
        let deadline = suspensionDeadline(for: duration)
        suspendedUntil = deadline
        scheduleEndOfSuspension(at: deadline, owner: owner)
    }

    /// When a suspension for the given duration ends: never before the one under way, so a
    /// short suspension (a bridged click's) cannot cut a longer one (a relayout's) short.
    private func suspensionDeadline(for duration: Duration) -> ContinuousClock.Instant {
        let deadline = ContinuousClock.now + duration
        guard let suspendedUntil else {
            return deadline
        }
        return max(suspendedUntil, deadline)
    }

    /// Makes a new suspension the owner of the deadline, which it never brings forward.
    private func beginSuspension(until deadline: ContinuousClock.Instant) -> Int {
        suspensionOwner += 1
        suspendedUntil = deadline
        updateSuspendedConcealment { $0.begin(isConcealing: isConcealing) }
        return suspensionOwner
    }

    /// Changes ``suspendedConcealment``; an unchanged value is not assigned, so nothing
    /// observes it.
    private func updateSuspendedConcealment(_ change: (inout SuspendedConcealment) -> Void) {
        var updated = suspendedConcealment
        change(&updated)
        if updated != suspendedConcealment {
            suspendedConcealment = updated
        }
    }

    /// Puts concealment back at the deadline, unless a later suspension or an early end owns it.
    private func scheduleEndOfSuspension(at deadline: ContinuousClock.Instant, owner: Int) {
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard let self, suspensionOwner == owner else {
                return
            }
            suspendedUntil = nil
            // Within the same turn as the update, so observers see concealment go on again
            // without a gap.
            updateSuspendedConcealment { $0.end() }
            update()
        }
    }

    /// Puts concealment back before the suspension would have run out.
    func endSuspension() {
        guard suspendedUntil != nil else {
            return
        }
        suspensionOwner += 1
        suspendedUntil = nil
        updateSuspendedConcealment { $0.end() }
        update()
    }

    /// How much of the bar's movement is still to come after the last concealment change
    /// landed. A change still on its way is waited for with ``waitForPendingApplies()`` first.
    ///
    /// Work that runs while MenuBarAgent animates the bar lands on top of that animation:
    /// revealing the hidden items set off four overlapping display captures of 260–290 ms
    /// each and six Accessibility sweeps in little over a second (measured 2026-09-16), and
    /// the animation stuttered. Heavy work waits this out.
    func timeUntilSettled() -> Duration? {
        let settleAt = lastChangeAt + Self.settleAfterChange
        let now = ContinuousClock.now
        return now < settleAt ? settleAt - now : nil
    }

    /// Shows applications for a moment, to click or photograph their items.
    /// Every call must be balanced by ``endTemporaryShow(bundleIDs:)``.
    ///
    /// The whole set is shown in one change. Shown one at a time, each call re-applied
    /// concealment and MenuBarAgent animated the bar again, so photographing ten items meant
    /// ten reflows in a row and the capture caught the items in mid-fade: a faint glyph in a
    /// wide haze of bar that the background removal could not account for (measured
    /// 2026-09-17: those tiles held 1.6–2.3 % opaque pixels against 21–26 % faint ones, where
    /// an item photographed while it stood still holds 5–20 % against 3–9 %).
    func showTemporarily(bundleIDs: some Collection<String>) {
        guard !bundleIDs.isEmpty else {
            return
        }
        for bundleID in bundleIDs {
            temporarilyShown[bundleID, default: 0] += 1
        }
        update()
    }

    /// Ends one ``showTemporarily(bundleIDs:)``.
    func endTemporaryShow(bundleIDs: some Collection<String>) {
        guard !bundleIDs.isEmpty else {
            return
        }
        for bundleID in bundleIDs {
            guard let count = temporarilyShown[bundleID] else {
                continue
            }
            temporarilyShown[bundleID] = count > 1 ? count - 1 : nil
        }
        update()
    }

    /// Shows an application for a moment, to click or photograph its item.
    /// Every call must be balanced by ``endTemporaryShow(bundleID:)``.
    func showTemporarily(bundleID: String) {
        showTemporarily(bundleIDs: CollectionOfOne(bundleID))
    }

    /// Shows an application for a moment and returns once MenuBarAgent applied the change that
    /// shows it, to click or photograph its item where it is drawn.
    /// Every call must be balanced by ``endTemporaryShow(bundleID:)``, whatever it returns.
    ///
    /// The item's frame is where it was last drawn until the change lands, and another item or
    /// the clock may stand there by then.
    ///
    /// - Returns: Whether the change landed: `false` when concealment is paused or unavailable,
    ///   the apply failed, or it took longer than 3 s.
    func showTemporarily(bundleID: String) async -> Bool {
        temporarilyShown[bundleID, default: 0] += 1
        let carrying = applyLedger.nextApply
        guard applyChanges() else {
            return false
        }
        return await waitForApply(carrying)
    }

    /// Ends one ``showTemporarily(bundleID:)``.
    func endTemporaryShow(bundleID: String) {
        endTemporaryShow(bundleIDs: CollectionOfOne(bundleID))
    }

    /// Puts applications that holzBar has not seen before into the section chosen
    /// in the settings (jordanbaird/Ice#6, jordanbaird/Ice#767).
    ///
    /// An application missing from the saved layout is visible. holzBar remembers
    /// every application it has seen on the bar, so only new ones are placed, and
    /// the first run only records what is there. This placement is holzBar's own and does
    /// not count as a settings change for sync.
    func placeNewApplications(items: [MenuBarItem]) {
        guard let appState else {
            return
        }
        let bundleIDs = Set(items.compactMap { item -> String? in
            guard item.canBeHidden, !item.isSystemClone, !item.isControlItem else {
                return nil
            }
            return item.sourceApplication?.bundleIdentifier
        })
        let stored = Defaults.array(forKey: .knownApplications27) as? [String]
        let known = Set(stored ?? [])
        let newBundleIDs = bundleIDs.subtracting(known).subtracting(savedLayout.keys)

        guard stored == nil || !newBundleIDs.isEmpty else {
            return
        }
        Defaults.set(known.union(bundleIDs).sorted(), forKey: .knownApplications27)

        guard
            stored != nil,
            var name = appState.settings.advanced.newItemsPlacement.section,
            name != .visible
        else {
            return
        }
        if name == .alwaysHidden && !appState.settings.advanced.enableAlwaysHiddenSection {
            name = .hidden
        }
        var layout = savedLayout
        for bundleID in newBundleIDs {
            layout = SectionLayout27.settingSection(MacOS27Section(name), for: bundleID, in: layout)
            logger.notice("Placed new application \(bundleID, privacy: .private(mask: .hash)) in \(name.logString, privacy: .public)")
        }
        Defaults.set(layout.mapValues(\.rawValue), forKey: .macOS27Layout)
        update()
    }

    /// Moves an application to a section of the saved layout and applies it.
    ///
    /// Only the user moves an application this way (the Layout pane, with its undo), and this is the one
    /// place a user move enters sync: when the section changed it sends one intent for `l27/<bundleID>`
    /// with explicit values (visible is `0`, not an absence). A drop on the same section, or an undo to
    /// the same value, sends nothing.
    ///
    /// There is no other user arrangement path on macOS 27 (checked in plan 28-16): a Command-drag on the
    /// bar moves nothing holzBar saves (``AccessibilityBackend27/canMoveItems`` is false), and a profile
    /// the user applies and Import send their own intents. A new path has to send one too; the sync lint
    /// fails a new writer of the layout.
    func setSection(_ section: MacOS27Section, for bundleID: String) {
        let saved = savedLayout
        let before = saved[bundleID] ?? .visible
        let updated = SectionLayout27.settingSection(section, for: bundleID, in: saved)
        Defaults.set(updated.mapValues(\.rawValue), forKey: .macOS27Layout)
        if
            let intent = SyncLayout27.moveIntent(
                bundleID: bundleID,
                from: .integer(Int64(before.rawValue)),
                to: .integer(Int64(section.rawValue))
            )
        {
            appState?.settingsSync.recordIntent(.userSet([intent]))
        }
        update()
        Task { [weak self] in
            await self?.appState?.itemManager.cacheItemsRegardless()
        }
    }

    /// Writes the sections the bar still holds from before macOS 27 into the saved layout, once.
    ///
    /// Nothing recorded them before: an item's section was where it sat between holzBar's dividers.
    /// On 27 that order no longer means anything, and an application missing from the layout is
    /// visible, so without this an upgrade left holzBar hiding nothing until the whole layout was
    /// rebuilt by hand — reported on jordanbaird/Ice#1006, and the likeliest reading of several
    /// of the original Ice's "hides nothing on 27" issues.
    ///
    /// The bar is read once, the first time it can be: a user who has arranged a layout of their
    /// own keeps it, and a bar whose order macOS 27 has already rearranged is left alone (see
    /// ``SectionLayout27/seededLayout(items:hiddenControlItem:alwaysHiddenControlItem:)``).
    /// This placement is holzBar's own and does not count as a settings change for sync.
    func seedLayoutIfNeeded(items: [MenuBarItem]) {
        guard
            !Defaults.bool(forKey: .macOS27LayoutSeeded),
            savedLayout.isEmpty,
            !isConcealing,
            let hiddenControlItem = items.first(where: { $0.tag == .hiddenControlItem })
        else {
            return
        }
        // Once the bar can be read, this runs whatever it says: a bar that says nothing is still
        // an answer, and asking it again later would risk reading one holzBar itself had concealed.
        Defaults.set(true, forKey: .macOS27LayoutSeeded)
        let alwaysHiddenControlItem = items.first { $0.tag == .alwaysHiddenControlItem }
        let managed = items.compactMap { item -> (bundleID: String, bounds: CGRect)? in
            guard
                item.canBeHidden,
                !item.isSystemClone,
                !item.isControlItem,
                let bundleID = item.sourceApplication?.bundleIdentifier
            else {
                return nil
            }
            return (bundleID, item.bounds)
        }
        guard let seeded = SectionLayout27.seededLayout(
            items: managed,
            hiddenControlItem: hiddenControlItem.bounds,
            alwaysHiddenControlItem: alwaysHiddenControlItem?.bounds
        ) else {
            logger.notice("The bar's order says nothing about sections, so the macOS 27 layout stays empty")
            return
        }
        Defaults.set(seeded.mapValues(\.rawValue), forKey: .macOS27Layout)
        let described = seeded
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.rawValue)" }
            .joined(separator: " ")
        logger.notice("Took the macOS 27 layout from the order on the bar: \(described, privacy: .private(mask: .hash))")
        update()
    }

    /// Builds the item cache from the saved layout rather than the order on the bar.
    func cacheFromSavedLayout(items: [MenuBarItem], displayID: CGDirectDisplayID?) -> MenuBarItemManager.ItemCache {
        var cache = MenuBarItemManager.ItemCache(displayID: displayID)
        let layout = savedLayout
        for item in items.sorted(by: { $0.bounds.minX < $1.bounds.minX }) where item.canBeHidden && !item.isSystemClone {
            if item.isControlItem {
                if item.tag == .visibleControlItem {
                    cache[.visible].append(item)
                }
                continue
            }
            switch layout[item.sourceApplication?.bundleIdentifier ?? ""] ?? .visible {
            case .visible: cache[.visible].append(item)
            case .hidden: cache[.hidden].append(item)
            case .alwaysHidden: cache[.alwaysHidden].append(item)
            }
        }
        return cache
    }

    // MARK: Private

    private func revealState(_ appState: AppState) -> RevealState27 {
        let navigation = appState.navigationState
        if navigation.isSettingsPresented, navigation.settingsNavigationIdentifier == .menuBarLayout {
            // Everything is drawn while the layout window is open, so every item can be photographed.
            return .allRevealed
        }
        if appState.settings.general.usesShelf {
            // The holzBar Shelf shows hidden items in its own panel, so the bar stays concealed.
            return .allHidden
        }
        let manager = appState.menuBarManager
        if let alwaysHidden = manager.section(withName: .alwaysHidden), alwaysHidden.isEnabled, !alwaysHidden.isHidden {
            return .allRevealed
        }
        if let hidden = manager.section(withName: .hidden), !hidden.isHidden {
            return .hiddenRevealed
        }
        return .allHidden
    }
}

extension MacOS27Section {
    init(_ name: MenuBarSection.Name) {
        switch name {
        case .visible: self = .visible
        case .hidden: self = .hidden
        case .alwaysHidden: self = .alwaysHidden
        }
    }
}
