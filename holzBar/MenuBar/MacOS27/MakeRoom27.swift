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

    /// Whether a pass is running: the layout was written and the items are read again.
    private(set) var isRunningPass = false

    /// How many apps of the last pass are still drawn in the Visible section after it.
    private(set) var failedCount = 0

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var surfaces = Set<Surface>()
    @ObservationIgnored private var loop: ObservationLoop?
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "MakeRoom27")

    /// What the observation watches: a change of any of it evaluates the model again.
    private struct Trigger: Equatable {
        var overflow: NativeOverflowReading27
        var items: [ItemSignature]
        var usageIsEnabled: Bool
        var menuFrame: CGRect?
    }

    /// An item's window and where it is drawn.
    private struct ItemSignature: Equatable {
        let windowID: CGWindowID
        let bounds: CGRect
    }

    /// The model's inputs with what the banner needs besides them.
    private struct Reading {
        let input: MenuBarFit.Input
        let hasNotch: Bool
    }

    init(appState: AppState?) {
        self.appState = appState
    }

    // MARK: - Surfaces

    /// A surface that shows the banner opened: evaluates now and keeps evaluating while any
    /// surface stays open.
    func surfaceDidOpen(_ surface: Surface) {
        surfaces.insert(surface)
        if loop == nil {
            loop = ObservationLoop.observe({ [weak self] in
                self?.trigger() ?? Trigger(overflow: .unknown, items: [], usageIsEnabled: false, menuFrame: nil)
            }, onChange: { [weak self] _ in
                self?.evaluate()
            })
        }
        evaluate()
    }

    /// A surface closed. With none left, the observation stops and the banner goes.
    func surfaceDidClose(_ surface: Surface) {
        surfaces.remove(surface)
        guard surfaces.isEmpty else {
            return
        }
        loop?.cancel()
        loop = nil
        passTask?.cancel()
        passTask = nil
        isRunningPass = false
        banner = nil
    }

    // MARK: - Evaluation

    /// Reads what the observation watches, which registers the observation too.
    private func trigger() -> Trigger {
        guard let appState else {
            return Trigger(overflow: .unknown, items: [], usageIsEnabled: false, menuFrame: nil)
        }
        let overflow = appState.concealer27.nativeOverflow
        let items = appState.itemManager.itemCache[.visible].map { ItemSignature(windowID: $0.windowID, bounds: $0.bounds) }
        let menuFrame = overflow.displayID.flatMap { appState.applicationMenuFrames.frames[$0] }
        return Trigger(overflow: overflow, items: items, usageIsEnabled: appState.usage.isEnabled, menuFrame: menuFrame)
    }

    /// Asks the model and keeps the banner when it changed.
    private func evaluate() {
        guard let appState, !surfaces.isEmpty, let reading = reading(appState) else {
            setBanner(nil)
            return
        }
        let verdict = MenuBarFit.evaluate(reading.input)
        guard verdict.isOverflowing else {
            setBanner(nil)
            return
        }
        let usesUsage = appState.usage.isEnabled
        setBanner(Banner(
            verdict: verdict,
            candidates: MenuBarFit.plan(reading.input, verdict: verdict, usesUsage: usesUsage),
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
    private func reading(_ appState: AppState) -> Reading? {
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
            revealsAll: false,
            wasOverflowing: banner?.verdict.isOverflowing == true
        )
        return Reading(input: input, hasNotch: hasNotch)
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
                distanceFromNotch: Double(first.bounds.minX - referenceX)
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
            !item.isWidget,
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

    // MARK: - A pass

    /// Moves the banner's apps to Hidden: one layout write and one Undo step, nothing else moves.
    ///
    /// - Parameter place: Where the undo toast shows.
    func moveCandidates(place: LayoutUndo.Place) {
        guard
            !isRunningPass,
            let appState,
            let candidates = banner?.candidates,
            !candidates.isEmpty
        else {
            return
        }
        let keys = candidates.map(\.key)
        let before = appState.layoutUndo.beforeSnapshot()
        appState.concealer27.setSections(Dictionary(uniqueKeysWithValues: keys.map { ($0, MacOS27Section.hidden) }))
        appState.automation.itemsWereArrangedByHand()
        appState.layoutUndo.recordArrangementChange(
            String(localized: "\(keys.count) items moved to Hidden"),
            before: before,
            place: place
        )
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
    }

    /// The items were read again: counts what stayed and evaluates the model once more.
    private func passDidEnd(movedKeys: [String]) {
        isRunningPass = false
        guard let appState else {
            return
        }
        let stillVisible = Set(appState.itemManager.itemCache[.visible].compactMap(\.layoutKey27))
        failedCount = movedKeys.filter { stillVisible.contains($0) }.count
        evaluate()
    }
}
