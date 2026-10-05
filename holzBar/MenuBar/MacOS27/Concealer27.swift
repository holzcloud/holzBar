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
    /// Tasks that observe application launches and quits; cancelled with the concealer.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var suspendedUntil: ContinuousClock.Instant?

    /// When concealment last changed, which is when the bar last started moving.
    @ObservationIgnored private var lastChangeAt = ContinuousClock.now

    /// How long MenuBarAgent animates the bar after items are concealed or released
    /// (measured on macOS 27.0: about 250 ms, with a margin here).
    private static let settleAfterChange = Duration.milliseconds(400)

    /// Failed applies in a row, each answered by one more try a moment later.
    @ObservationIgnored private var failedApplies = 0

    /// How many times in a row a failed apply is tried again.
    private static let maximumApplyRetries = 3

    /// Applications shown for a moment, with the number of callers showing each.
    @ObservationIgnored private var temporarilyShown = [String: Int]()
    /// Observers of the active space and the Settings pane.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Whether any application is meant to be concealed right now.
    private(set) var isConcealing = false

    /// Process identifiers of the applications meant to be concealed right now.
    private(set) var concealedPIDs = Set<pid_t>()

    /// Visible applications concealed for the moment so holzBar's icon clears the notch
    /// (`NotchCover27`). Never part of the saved layout; cleared when the active display
    /// changes, an application launches or quits, or what the sections conceal changes.
    @ObservationIgnored private var notchConcealed = Set<String>()

    /// The reveal state and the sections' concealed sets `notchConcealed` was worked out for.
    @ObservationIgnored private var notchCoverBasis: (state: RevealState27, sets: [Set<String>])?

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
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observerTasks.append(Task { [weak self] in
            for await notification in workspaceCenter.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.applicationDidLaunch(bundleID: application?.bundleIdentifier)
            }
        })
        observerTasks.append(Task { [weak self] in
            for await _ in workspaceCenter.notifications(named: NSWorkspace.didTerminateApplicationNotification) {
                // The bar is laid out anew, so the notch is worked out again.
                self?.notchConcealed.removeAll()
                self?.update()
            }
        })
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

    /// Answers an application's launch.
    ///
    /// An application whose saved section is hidden or always hidden is shown until its item
    /// exists, or for at most 10 s, then concealed: concealed before its status item exists,
    /// it gets an item of 3 points (jordanbaird/Ice#1007).
    private func applicationDidLaunch(bundleID: String?) {
        // The bar is laid out anew, so the notch is worked out again.
        notchConcealed.removeAll()
        guard
            let bundleID,
            let section = savedLayout[bundleID],
            launchGrace.begin(bundleID, isConcealed: section != .visible, at: .now)
        else {
            update()
            return
        }
        logger.debug("An application in a concealed section launched, showing it until its item exists")
        showTemporarily(bundleID: bundleID)
        // One bounded wait per grace.
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
        guard let appState, MenuBarAssessmentAssertion27.isAvailable else {
            return
        }
        // While the screen is locked, the Mac sleeps or the session is away, the assertions
        // stay as they are; the concealment is applied again once the bar has settled.
        guard !appState.systemActivityMonitor.isPaused else {
            return
        }
        if let suspendedUntil, ContinuousClock.now < suspendedUntil {
            return
        }
        let applications = NSWorkspace.shared.runningApplications
        let running = Set(applications.compactMap(\.bundleIdentifier))
        let layout = SectionLayout27.effectiveLayout(observed: [:], saved: savedLayout, running: running)
        let state = revealState(appState)
        // What the sections conceal sets how crowded the bar is: once that changes (a reveal
        // that ends, a layout edit), the notch is worked out again from the next settled read.
        let sectionSets = ConcealmentPlanner27.concealedSets(layout: layout, state: state)
        if let notchCoverBasis, notchCoverBasis.state != state || notchCoverBasis.sets != sectionSets {
            notchConcealed.removeAll()
        }
        notchCoverBasis = (state, sectionSets)
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
        concealedPIDs = Set(applications.compactMap { application in
            guard let bundleID = application.bundleIdentifier, concealed.contains(bundleID) else {
                return nil
            }
            return application.processIdentifier
        })
        lastChangeAt = .now
        let previous = applyTask
        let task = Task { [weak self, controller, logger] in
            await previous?.value
            do {
                try await controller.apply(target: target, running: running)
                self?.failedApplies = 0
            } catch {
                logger.error("Could not apply concealment: \(error, privacy: .private)")
                self?.retryAfterFailedApply()
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
    }

    /// Tries a failed apply again a moment later, a few times in a row.
    ///
    /// `isConcealing` and `concealedPIDs` already describe the concealment that failed, and
    /// hit-testing, captures and the click bridge rely on them; MenuBarAgent can reject an
    /// assertion or time out while it is busy, after login or wake.
    private func retryAfterFailedApply() {
        guard failedApplies < Self.maximumApplyRetries else {
            return
        }
        failedApplies += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.update()
        }
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
            appState.settings.general.showHolzBarIcon,
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
        lastChangeAt = .now
        suspendedUntil = .now + duration
        isConcealing = false
        concealedPIDs.removeAll()
        let previous = applyTask
        applyTask = Task { [controller] in
            await previous?.value
            controller.releaseAll()
        }
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.suspendedUntil = nil
            self?.update()
        }
    }

    /// Releases every assertion and returns once that has actually happened.
    ///
    /// Releasing goes through MenuBarAgent and queues behind whatever concealment change came
    /// before it. A click replayed on a timer could therefore arrive while the assertion was
    /// still live, and MenuBarAgent ignores those — which is why a click on the clock sometimes
    /// did nothing and worked on the second try.
    func suspendReleased(for duration: Duration) async {
        lastChangeAt = .now
        suspendedUntil = .now + duration
        isConcealing = false
        concealedPIDs.removeAll()
        let previous = applyTask
        let release = Task { [controller] in
            await previous?.value
            controller.releaseAll()
        }
        applyTask = release
        await release.value
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            self?.suspendedUntil = nil
            self?.update()
        }
    }

    /// Puts concealment back before the suspension would have run out.
    func endSuspension() {
        guard suspendedUntil != nil else {
            return
        }
        suspendedUntil = nil
        update()
    }

    /// How much of the bar's movement is still to come after the last concealment change.
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

    /// Ends one ``showTemporarily(bundleID:)``.
    func endTemporaryShow(bundleID: String) {
        endTemporaryShow(bundleIDs: CollectionOfOne(bundleID))
    }

    /// Puts applications that holzBar has not seen before into the section chosen
    /// in the settings (jordanbaird/Ice#6, jordanbaird/Ice#767).
    ///
    /// An application missing from the saved layout is visible. holzBar remembers
    /// every application it has seen on the bar, so only new ones are placed, and
    /// the first run only records what is there.
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
    func setSection(_ section: MacOS27Section, for bundleID: String) {
        let updated = SectionLayout27.settingSection(section, for: bundleID, in: savedLayout)
        Defaults.set(updated.mapValues(\.rawValue), forKey: .macOS27Layout)
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
