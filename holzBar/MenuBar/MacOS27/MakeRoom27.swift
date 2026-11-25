//
//  MakeRoom27.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// Tells that the apps in the Visible section do not fit the menu bar, and moves the ones that
/// can go to Hidden (Phase 97, D-07 to D-11).
///
/// This is the thin macOS 27 side of ``MenuBarFit``: it reads the item cache holzBar already keeps
/// into plain numbers, asks the model, keeps the banner state the surfaces draw, and performs a
/// pass as one layout write with one Undo step. It runs only while a surface that shows the banner
/// is open (Layout today): the observation starts when the first one opens and stops when the
/// last one closes, so nothing runs, polls or observes while they are closed. No timer, no
/// delay, no Accessibility call of its own.
///
/// App names reach the banner and nothing else: they stay in memory and never reach a log line.
@available(macOS 27.0, *)
@MainActor
@Observable
final class MakeRoom27 {
    /// A surface that shows the banner and keeps the model running while it is open.
    enum Surface: Hashable {
        case layout
        case shelf
    }

    /// What the banner says and what its button would do.
    struct Banner: Equatable {
        let verdict: MenuBarFit.Verdict
        /// The apps one pass would move, in the order they move.
        let candidates: [MenuBarFit.App]
        /// Whether the display has a notch: the sentence says "beside the notch" or "in the menu bar".
        let hasNotch: Bool
        /// Whether Usage suggestions is on: the info says "the apps you use least" or "some apps".
        let usesUsage: Bool
    }

    /// The banner, or `nil` while the apps fit, nothing is known or no surface is open.
    private(set) var banner: Banner?

    /// Whether the Shelf offers anything: only in Ask (D-10). Off offers nothing, and Automatic
    /// handles the overflow itself (D-11), so the Shelf shows no notice for it. The Layout banner
    /// ignores the mode and shows without a switch (D-11).
    var offersInShelf: Bool {
        appState?.settings.advanced.makeRoomMode == .ask
    }

    /// The banner the Shelf draws: the model's banner, or `nil` while the mode is Off.
    var shelfBanner: Banner? {
        offersInShelf ? banner : nil
    }

    /// Whether a pass is running: the layout was written and the items are read again.
    private(set) var isRunningPass = false

    /// Where a pass comes from.
    enum PassOrigin {
        /// The user pressed Move to Hidden: the banner's apps move.
        case user
        /// Automatic decided: the apps move that the planner names now, whether or not a banner shows.
        case automatic
    }

    /// The last pass Automatic made: the Notices row says it and can undo it (UI-SPEC).
    struct AutomaticPass {
        /// How many apps the pass moved.
        let count: Int
        /// The arrangement before the pass: Undo puts back the section each moved app had in it.
        let before: LayoutSnapshot
        /// The apps the pass moved; Undo touches no others.
        let movedKeys: [String]
        /// The pass's entry in the undo history, taken out when the row undoes it.
        let changeID: UUID
        /// The sentence of that entry's toast.
        let sentence: String
    }

    /// The last pass Automatic made, until it is dismissed, undone or replaced by the next one.
    private(set) var lastAutomaticPass: AutomaticPass?

    /// Whether Layout is open: Automatic never acts then. Observed, so Automatic hears it close.
    private(set) var isLayoutOpen = false

    /// How many apps of the last pass are still drawn in the Visible section after it.
    private(set) var failedCount = 0

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var surfaces = Set<Surface>()
    @ObservationIgnored private var loop: ObservationLoop?
    @ObservationIgnored private var passTask: Task<Void, Never>?
    /// What the user sees: a verdict that differs from it is taken over only after it stayed the
    /// same for the settle time (T-97-06).
    @ObservationIgnored private var settle = MenuBarFit.Settle(shown: .fits)
    /// The banner stays away until this instant after a pass (D-19).
    @ObservationIgnored private var quietUntil: ContinuousClock.Instant?
    /// The one one-shot wait for the next instant something is due; each evaluation replaces it.
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "MakeRoom27")

    /// What the observation watches: a change of any of it evaluates the model again.
    private struct Trigger: Equatable {
        var overflow: NativeOverflowReading27
        var items: [ItemSignature]
        var usageIsEnabled: Bool
        var menuFrame: CGRect?
        var revealsAll: Bool
        /// The gates of D-03: a drag, the Mac resting, a display change or wake that is still
        /// settling (the gate records when), an application in its launch grace.
        var isDragging = false
        var isPaused = false
        var wakeGate = DDCWakeGate()
        var graceIDs = Set<String>()
    }

    /// An item's window and where it is drawn; an item macOS folded away is not drawn.
    private struct ItemSignature: Equatable {
        let windowID: CGWindowID
        let bounds: CGRect
        let isOnScreen: Bool
    }

    /// The model's inputs with what the banner needs besides them.
    private struct Reading {
        let input: MenuBarFit.Input
        let hasNotch: Bool

        /// What the model says about these inputs, before the settle time.
        var verdict: MenuBarFit.Verdict {
            MenuBarFit.evaluate(input)
        }
    }

    init(appState: AppState?) {
        self.appState = appState
    }

    // MARK: - Surfaces

    /// A surface that shows the banner opened: evaluates now and keeps evaluating while any
    /// surface stays open.
    func surfaceDidOpen(_ surface: Surface) {
        surfaces.insert(surface)
        if surface == .layout, !isLayoutOpen {
            isLayoutOpen = true
        }
        if loop == nil {
            // A banner that is already true shows at once; later changes wait for the settle time.
            settle = MenuBarFit.Settle(shown: .fits)
            quietUntil = nil
            if let appState, let current = reading(appState) {
                settle = MenuBarFit.Settle(shown: current.verdict)
            }
            loop = ObservationLoop.observe({ [weak self] in
                self?.trigger() ?? Trigger(overflow: .unknown, items: [], usageIsEnabled: false, menuFrame: nil, revealsAll: false)
            }, onChange: { [weak self] _ in
                self?.evaluate()
            })
        }
        evaluate()
    }

    /// A surface closed. With none left, the observation stops and the banner goes.
    func surfaceDidClose(_ surface: Surface) {
        surfaces.remove(surface)
        if surface == .layout, isLayoutOpen {
            isLayoutOpen = false
        }
        guard surfaces.isEmpty else {
            return
        }
        loop?.cancel()
        loop = nil
        passTask?.cancel()
        passTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        quietUntil = nil
        isRunningPass = false
        failedCount = 0
        banner = nil
    }

    // MARK: - Evaluation

    /// Reads what the observation watches, which registers the observation too.
    private func trigger() -> Trigger {
        guard let appState else {
            return Trigger(overflow: .unknown, items: [], usageIsEnabled: false, menuFrame: nil, revealsAll: false)
        }
        let overflow = appState.concealer27.nativeOverflow
        let items = appState.itemManager.itemCache[.visible].map {
            ItemSignature(windowID: $0.windowID, bounds: $0.bounds, isOnScreen: $0.isOnScreen)
        }
        let menuFrame = overflow.displayID.flatMap { appState.applicationMenuFrames.frames[$0] }
        return Trigger(
            overflow: overflow,
            items: items,
            usageIsEnabled: appState.usage.isEnabled,
            menuFrame: menuFrame,
            revealsAll: revealsAll(appState),
            isDragging: appState.isDraggingMenuBarItem,
            isPaused: appState.systemActivityMonitor.isPaused,
            wakeGate: appState.systemActivityMonitor.ddcWakeGate,
            graceIDs: appState.concealer27.launchGraceBundleIDs
        )
    }

    /// Asks the model, lets the verdict settle and keeps the banner when it changed.
    ///
    /// The banner follows the settled verdict, never the raw one, and it is not drawn while a
    /// gate is closed (D-03, D-19): during a drag, before the system has settled after a wake or a
    /// display change, while an application is in its launch grace and for a few seconds after a
    /// pass. The gates that are events (drag, wake, display change, grace) re-run this through the
    /// observation; the ones that are only time (the settle time, the quiet time, the system
    /// settling) arm one one-shot wait for the earliest instant.
    private func evaluate() {
        wakeTask?.cancel()
        wakeTask = nil
        guard let appState, !surfaces.isEmpty, let reading = reading(appState) else {
            setBanner(nil)
            return
        }
        let now = ContinuousClock.now
        var due = [ContinuousClock.Instant]()
        if let instant = settle.note(reading.verdict, at: now) {
            due.append(instant)
        }
        var isQuiet = false
        if let quietUntil {
            if quietUntil > now {
                isQuiet = true
                due.append(quietUntil)
            } else {
                self.quietUntil = nil
            }
        }
        let monitor = appState.systemActivityMonitor
        let isSettled = monitor.isSettled
        if !isSettled, !monitor.isPaused {
            // Time only: the monitor publishes no event when the bar has settled.
            due.append(now + SystemActivity.settleDelay)
        }
        if let next = due.min() {
            wakeTask = Task { [weak self] in
                try? await Task.sleep(until: next, tolerance: .milliseconds(200), clock: .continuous)
                guard !Task.isCancelled else {
                    return
                }
                self?.evaluate()
            }
        }
        let isBlocked = appState.isDraggingMenuBarItem
            || !isSettled
            || !appState.concealer27.launchGraceBundleIDs.isEmpty
            || isQuiet
        guard !isBlocked, settle.shown.isOverflowing else {
            // A bar that fits again has no failed pass to report.
            if !settle.shown.isOverflowing, failedCount != 0 {
                failedCount = 0
            }
            setBanner(nil)
            return
        }
        let usesUsage = appState.usage.isEnabled
        // The button follows what is true now: while the shown verdict lingers after the bar
        // fits again, no move is offered.
        setBanner(Banner(
            verdict: settle.shown,
            candidates: reading.verdict.isOverflowing
                ? MenuBarFit.plan(reading.input, verdict: reading.verdict, usesUsage: usesUsage)
                : [],
            hasNotch: reading.hasNotch,
            usesUsage: usesUsage
        ))
    }

    private func setBanner(_ new: Banner?) {
        if new != banner {
            banner = new
        }
    }

    /// The model's inputs from the item cache and the display, or `nil` where there is no display.
    ///
    /// - Parameter forAutomatic: Whether Automatic asks: no surface shows every section and the
    ///   last verdict does not widen the room, so only what macOS already did counts.
    private func reading(_ appState: AppState, forAutomatic: Bool = false) -> Reading? {
        guard
            let displayID = appState.concealer27.nativeOverflow.displayID ?? Bridging.getActiveMenuBarDisplayID(),
            let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else {
            return nil
        }
        let displayBounds = CGDisplayBounds(displayID)
        let hasNotch = screen.hasNotch
        var room: Double?
        var referenceX = displayBounds.minX
        if hasNotch {
            if let rightArea = screen.auxiliaryTopRightArea {
                room = MenuBarFit.room(rightAreaWidth: Double(rightArea.width))
            }
            if let span = StuckOverflow27.notchSpan(
                displayBounds: displayBounds,
                leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
                rightAreaWidth: screen.auxiliaryTopRightArea?.width
            ) {
                referenceX = span.upperBound
            }
        } else if let menuFrame = appState.applicationMenuFrames.frames[displayID] {
            room = MenuBarFit.room(displayMaxX: Double(displayBounds.maxX), applicationMenuMaxX: Double(menuFrame.maxX))
            referenceX = menuFrame.maxX
        }
        let input = MenuBarFit.Input(
            room: room,
            apps: apps(appState, on: displayBounds, from: referenceX),
            native: native(appState.concealer27.nativeOverflow.state),
            revealsAll: forAutomatic ? false : revealsAll(appState),
            wasOverflowing: forAutomatic ? false : settle.shown.isOverflowing
        )
        return Reading(input: input, hasNotch: hasNotch)
    }

    /// Whether a surface shows every section now (Layout): macOS may fold items only because they
    /// are shown, so a fold counts only when the prediction agrees (C7).
    private func revealsAll(_ appState: AppState) -> Bool {
        appState.concealer27.revealState(appState) == .allRevealed
    }

    private func native(_ state: NativeOverflowState27) -> MenuBarFit.Native {
        switch state {
        case .none: .none
        case .collapsed: .collapsed
        case .expanded: .expanded
        case .unknown: .unknown
        }
    }

    // MARK: - Apps

    /// One application's items in the Visible section.
    private struct AppGroup {
        let key: String
        var items = [MenuBarItem]()
    }

    /// The apps of the Visible section on a display, the one nearest the reference position first.
    private func apps(_ appState: AppState, on displayBounds: CGRect, from referenceX: CGFloat) -> [MenuBarFit.App] {
        let items = appState.itemManager.itemCache[.visible]
            .filter { !$0.isControlItem && $0.bounds.width > 4 && displayBounds.intersects($0.bounds) }
            .sorted { $0.bounds.minX < $1.bounds.minX }
        var groups = [AppGroup]()
        var indexByKey = [String: Int]()
        for item in items {
            // An item without a known application cannot be moved; it still takes room.
            let key = item.layoutKey27 ?? "window-\(item.windowID)"
            if let index = indexByKey[key] {
                groups[index].items.append(item)
            } else {
                indexByKey[key] = groups.count
                groups.append(AppGroup(key: key, items: [item]))
            }
        }
        // Items macOS folded behind its overflow control are in the cache, not drawn, at the frame
        // they were last read at; their widths count like any other item's. Only Visible-section
        // apps are in `items`, so an app of a hidden section is never named (C7).
        let foldedIDs = Set(MenuBarItemProvider27.foldedItems().map(\.windowID))
        var facts = ItemFactsReader()
        let controlled = appState.automation.controlledItemKeys
        let usesUsage = appState.usage.isEnabled
        let today = UsageCounters.dayNumber(for: .now)
        return groups.map { group in
            let isMovable = group.items.allSatisfy {
                canMove($0, key: group.key, controlled: controlled, facts: &facts, appState: appState)
            }
            let clicks = usesUsage
                ? group.items.reduce(0) { total, item in
                    total + appState.usage.counters.clicks(
                        of: appState.itemManager.identityKey(for: item),
                        inLast: UsageCounters.retentionDays,
                        today: today
                    )
                }
                : nil
            let first = group.items[0]
            return MenuBarFit.App(
                key: group.key,
                name: ItemRuleNotices.cleanedName(first.sourceApplication?.localizedName ?? first.displayName, fallback: group.key),
                itemWidths: group.items.map { Double($0.bounds.width) },
                isMovable: isMovable,
                clicks: clicks,
                launchedAt: NSRunningApplication.runningApplications(withBundleIdentifier: group.key).first?.launchDate,
                distanceFromNotch: Double(first.bounds.minX - referenceX),
                isFolded: group.items.contains { foldedIDs.contains($0.windowID) }
            )
        }
    }

    /// Whether a pass may move the item's application (D-03): not holzBar's own, not Apple's, not
    /// an item that cannot be hidden or moved, not a widget, not one a rule controls and not one
    /// the classifier calls essential. A Live Activity is never in the item cache.
    private func canMove(
        _ item: MenuBarItem,
        key: String,
        controlled: Set<String>,
        facts: inout ItemFactsReader,
        appState: AppState
    ) -> Bool {
        guard
            item.layoutKey27 != nil,
            !item.isOwnArrangedItem,
            item.tag.namespace != .holzBar,
            item.canBeHidden,
            item.isMovable,
            !OwnBundle.matches(key, bundleIdentifier: Constants.bundleIdentifier),
            !key.lowercased().hasPrefix("com.apple."),
            !controlled.contains(appState.itemManager.identityKey(for: item))
        else {
            return false
        }
        let classifiable = facts.classifiable(item, in: .visible, using: appState.itemManager)
        return ItemClassifier.classify(classifiable) != .essential
    }

    // MARK: - Words

    /// The sentence of the banner on every surface: the Layout pane and the Shelf say the same.
    func sentence(for banner: Banner) -> String {
        if case let .folded(names, _) = banner.verdict {
            // The first two names, then the rest as a count, verbatim.
            let parts = MenuBarFit.sentenceNames(names)
            var namesText = parts.shown.joined(separator: ", ")
            if parts.more > 0 {
                namesText += " +\(parts.more)"
            }
            return String(localized: "Folded away: \(namesText)")
        }
        let items = itemCount(of: banner)
        return banner.hasNotch
            ? String(localized: "\(items) items do not fit beside the notch")
            : String(localized: "\(items) items do not fit in the menu bar")
    }

    /// What the info button or tooltip says: why the bar is full, what a move can do, that it can
    /// be undone and which apps the button would move. No sentence promises that a move gives
    /// more space: that is measured on a Mac first. Without a candidate the info says why nothing
    /// can move.
    func info(for banner: Banner) -> String {
        guard !banner.candidates.isEmpty else {
            return String(localized: "Nothing can move: the rest are Apple's items, holzBar's own or protected. Quit an app or remove an item to make room.")
        }
        let why: String
        let can: String
        if case .folded = banner.verdict {
            why = String(localized: "macOS ran out of room and folded these items away.")
            can = banner.usesUsage
                ? String(localized: "holzBar can move the apps you use least to Hidden, a few at a time.")
                : String(localized: "holzBar can move some apps to Hidden, a few at a time.")
        } else {
            why = banner.hasNotch
                ? String(localized: "These items are wider than the room beside the notch, so macOS folds some away.")
                : String(localized: "These items are wider than the room in the menu bar, so macOS folds some away.")
            can = banner.usesUsage
                ? String(localized: "Moving the apps you use least to Hidden can make room.")
                : String(localized: "Moving some apps to Hidden can make room.")
        }
        // The names are the apps' own, shown as they are; they never reach a log line.
        let names = ListFormatter.localizedString(byJoining: banner.candidates.map(\.name))
        return [why, can, String(localized: "You can undo it."), names].joined(separator: " ")
    }

    /// How many items do not fit.
    private func itemCount(of banner: Banner) -> Int {
        switch banner.verdict {
        case let .doesNotFit(items), let .folded(_, items): items
        case .fits, .unknown: 0
        }
    }

    // MARK: - Automatic

    /// What Automatic sees now and whether a pass would move anything.
    ///
    /// Only a verdict that says macOS folded Visible apps away is `.folded`: a bar that merely
    /// does not fit by the prediction, and a bar whose state cannot be told, are `.unknown`, so
    /// Automatic never acts on a guess. A bar that fits is `.clear`.
    func automaticReading() -> (OverflowAutoMove.Reading, hasCandidates: Bool) {
        let evaluation = automaticEvaluation()
        return (evaluation.reading, !evaluation.candidates.isEmpty)
    }

    private func automaticEvaluation() -> (reading: OverflowAutoMove.Reading, candidates: [MenuBarFit.App]) {
        guard let appState, let reading = reading(appState, forAutomatic: true) else {
            return (.unknown, [])
        }
        switch reading.verdict {
        case .folded:
            let usesUsage = appState.usage.isEnabled
            return (.folded, MenuBarFit.plan(reading.input, verdict: reading.verdict, usesUsage: usesUsage))
        case .fits:
            // A bar whose overflow control cannot be read is not known to be clear.
            return (reading.input.native == .unknown ? .unknown : .clear, [])
        case .doesNotFit, .unknown:
            return (.unknown, [])
        }
    }

    /// Takes the Notices row of the last automatic pass away; the pass stays done.
    func dismissAutomaticPass() {
        lastAutomaticPass = nil
    }

    /// Puts the apps of the last automatic pass back, only those, and takes the pass's entry out
    /// of the undo history so a later Undo does not undo it twice. A change the user made to the
    /// layout after the pass stays: only an app that is still in Hidden goes back to the section
    /// it had before. A failure is reported like any other undo that could not put everything
    /// back, and the bar is quiet for a moment afterwards so Ask does not offer the same move at once.
    func undoAutomaticPass() async {
        guard let pass = lastAutomaticPass, let appState else {
            return
        }
        lastAutomaticPass = nil
        let undo = appState.layoutUndo
        undo.forget(id: pass.changeID)
        // The toast of that pass would otherwise offer an Undo that acts on another change.
        if let toast = undo.toast, !toast.isFailure, toast.changeID == pass.changeID {
            undo.dismissToast(id: toast.id)
        }
        let concealer = appState.concealer27
        let back = pass.movedKeys.filter { concealer.section(forKey: $0) == .hidden }
        concealer.setSections(Dictionary(uniqueKeysWithValues: back.map {
            ($0, pass.before.applicationSections[$0].flatMap(MacOS27Section.init(rawValue:)) ?? .visible)
        }))
        appState.automation.itemsWereArrangedByHand()
        quietUntil = .now + MenuBarFit.Policy.quietAfterPass
        // macOS arranges per application and needs a moment, as after any undo.
        try? await Task.sleep(for: LayoutUndo.settleDelay27)
        await appState.itemManager.cacheItemsRegardless()
        let stillAway = Set((appState.itemManager.itemCache[.hidden] + appState.itemManager.itemCache[.alwaysHidden]).compactMap(\.layoutKey27))
        undo.report(isRestored: !back.contains(where: stillAway.contains), place: .settings)
        evaluate()
    }

    // MARK: - A pass

    /// Moves the apps to Hidden: one layout write and one Undo step, nothing else moves.
    ///
    /// - Parameters:
    ///   - place: Where the undo toast shows.
    ///   - origin: The user's pass moves the banner's apps; Automatic's moves the ones the planner
    ///     names now, and only while macOS has folded Visible apps away.
    /// - Returns: Whether a pass ran.
    @discardableResult
    func moveCandidates(place: LayoutUndo.Place, origin: PassOrigin = .user) -> Bool {
        guard !isRunningPass, let appState else {
            return false
        }
        let candidates: [MenuBarFit.App]
        switch origin {
        case .user:
            candidates = banner?.candidates ?? []
        case .automatic:
            let evaluation = automaticEvaluation()
            candidates = evaluation.reading == .folded ? evaluation.candidates : []
        }
        guard !candidates.isEmpty else {
            return false
        }
        let keys = candidates.map(\.key)
        let before = appState.layoutUndo.beforeSnapshot()
        appState.concealer27.setSections(Dictionary(uniqueKeysWithValues: keys.map { ($0, MacOS27Section.hidden) }))
        appState.automation.itemsWereArrangedByHand()
        // The toast says who moved the apps: holzBar did, when Automatic made the pass.
        let sentence = origin == .automatic
            ? String(localized: "holzBar moved \(keys.count) items to Hidden to make room.")
            : String(localized: "\(keys.count) items moved to Hidden")
        let changeID = appState.layoutUndo.recordArrangementChange(sentence, before: before, place: place)
        if origin == .automatic {
            lastAutomaticPass = AutomaticPass(count: keys.count, before: before, movedKeys: keys, changeID: changeID, sentence: sentence)
        }
        logger.info("A pass moved \(keys.count, privacy: .public) apps to Hidden")
        isRunningPass = true
        failedCount = 0
        passTask?.cancel()
        passTask = Task { [weak self] in
            await appState.itemManager.cacheItemsRegardless()
            guard !Task.isCancelled else {
                return
            }
            self?.passDidEnd(movedKeys: keys)
        }
        return true
    }

    /// The items were read again: counts what stayed and evaluates the model once more.
    private func passDidEnd(movedKeys: [String]) {
        isRunningPass = false
        // Quiet for a few seconds, so the banner never offers a move that fights what just happened.
        quietUntil = .now + MenuBarFit.Policy.quietAfterPass
        guard let appState else {
            return
        }
        let stillVisible = Set(appState.itemManager.itemCache[.visible].compactMap(\.layoutKey27))
        failedCount = movedKeys.filter { stillVisible.contains($0) }.count
        evaluate()
    }
}
