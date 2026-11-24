//
//  NewAppQuestions27.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// Asks where an app that macOS 27 shows in the menu bar for the first time should go (Phase 97,
/// D-12, COMF-04): the thin macOS 27 side of ``NewAppQuestion``.
///
/// ``Concealer27/placeNewApplications(items:)`` hands over the new bundle identifiers while the
/// switch "Ask where a new app goes" is on; the "New items go to" placement still applies at
/// once, so an app is never left unplaced while the question waits. The model is created on the
/// first use, so with the switch off it does not exist (D-05).
///
/// A noticed app waits while the gate is closed (a drag runs, the system has not settled after a
/// wake or a display change, the app is in its launch grace, the quiet start after the model was
/// created is not over, ten seconds have not passed since the last new app). The observation that
/// opens the gate runs only while an app waits, and the time rules need one `Task.sleep` that the
/// next one replaces; nothing polls. Waiting questions are kept by bundle identifier on this Mac
/// until answered, so a quit loses none (D-19). An answer is remembered by the saved layout and the
/// list of known apps; Don't ask again is kept in its own local list.
///
/// App names reach the Layout group and nothing else: they stay in memory and never reach a log.
@available(macOS 27.0, *)
@MainActor
@Observable
final class NewAppQuestions27 {
    /// The apps that are asked about now, in the order they were noticed.
    private(set) var asked = [NewAppQuestion.App]()

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var question = NewAppQuestion()
    @ObservationIgnored private var gateLoop: ObservationLoop?
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    /// When the model was created: nothing is asked during the quiet start after it.
    @ObservationIgnored private let startedAt = ContinuousClock.now
    @ObservationIgnored private let logger = Logger(category: "NewAppQuestions27")

    init(appState: AppState?) {
        self.appState = appState
    }

    /// Whether the Always Hidden choice is offered: only while that section is enabled.
    var offersAlwaysHidden: Bool {
        appState?.settings.advanced.enableAlwaysHiddenSection ?? false
    }

    /// The icon of an app to show beside its question: the running application's, else the one of
    /// its bundle, else `nil`. It is read when a card draws and never kept.
    func icon(for bundleID: String) -> NSImage? {
        if let icon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Notes the apps that appeared in the menu bar for the first time. Those that are never asked
    /// about are skipped; the others are kept on this Mac until answered (a quit does not lose
    /// them) and asked as soon as the gate is open.
    func noteNewApplications(_ bundleIDs: Set<String>) {
        let now = ContinuousClock.now
        let noted = bundleIDs.sorted().filter { noteApplication($0, at: now) }
        if !noted.isEmpty {
            storePending { NewAppQuestion.remembered(adding: noted, to: $0) }
        }
        releaseIfOpen()
    }

    /// Notes the questions kept from before the last quit, once, when the model is created: they
    /// wait for the gate like new ones. An identifier that is refused now is taken out of the list.
    func restoreWaitingQuestions() {
        guard appState?.settings.advanced.asksWhereNewAppGoes == true else {
            return
        }
        let now = ContinuousClock.now
        let stored = Defaults.stringArray(forKey: .newAppQuestionPending) ?? []
        let kept = stored.filter { noteApplication($0, at: now) }
        if kept != stored {
            storePending { _ in NewAppQuestion.remembered(adding: kept, to: []) }
        }
        releaseIfOpen()
    }

    /// Notes one app when it may be asked about.
    ///
    /// - Returns: Whether the app may be asked about, so it is waiting or asked.
    private func noteApplication(_ bundleID: String, at now: ContinuousClock.Instant) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard NewAppQuestion.isEligible(
            bundleID: bundleID,
            bundlePath: url?.path,
            ownBundleID: Constants.bundleIdentifier,
            declined: Set(Defaults.stringArray(forKey: .newAppQuestionDeclined) ?? [])
        ) else {
            return false
        }
        let displayName = running?.localizedName ?? url.map { FileManager.default.displayName(atPath: $0.path) } ?? ""
        let name = ItemRuleNotices.cleanedName(displayName, fallback: bundleID)
        question.note(NewAppQuestion.App(bundleID: bundleID, name: name, noticedAt: now))
        return true
    }

    /// Writes the waiting list: bundle identifiers only, never names.
    private func storePending(_ change: ([String]) -> [String]) {
        let stored = Defaults.stringArray(forKey: .newAppQuestionPending) ?? []
        let changed = change(stored)
        if changed != stored {
            Defaults.set(changed, forKey: .newAppQuestionPending)
        }
    }

    /// Answers the question of an app: a section moves it at once as one Undo step, and the row
    /// leaves. Don't ask again moves nothing: the app is kept in the declined list on this Mac, so
    /// it is never asked about again.
    ///
    /// - Parameters:
    ///   - answer: The user's choice.
    ///   - bundleID: The app's bundle identifier.
    ///   - place: Where the undo toast shows.
    func answer(_ answer: NewAppQuestion.Answer, for bundleID: String, place: LayoutUndo.Place) {
        guard let appState, let app = asked.first(where: { $0.bundleID == bundleID }) else {
            return
        }
        if let section = section(for: answer) {
            let concealer = appState.concealer27
            if concealer.section(forKey: bundleID) != section {
                let before = appState.layoutUndo.beforeSnapshot()
                concealer.setSections([bundleID: section])
                appState.automation.itemsWereArrangedByHand()
                appState.layoutUndo.recordArrangementChange(
                    String(localized: "\(app.name) moved to \(Self.name(of: section).displayString)"),
                    before: before,
                    place: place
                )
                logger.info("A new application was moved to \(Self.name(of: section).logString, privacy: .public) by its answer")
            }
        }
        if answer == .dontAskAgain {
            let declined = Defaults.stringArray(forKey: .newAppQuestionDeclined) ?? []
            Defaults.set(NewAppQuestion.declined(adding: bundleID, to: declined), forKey: .newAppQuestionDeclined)
        }
        question.remove(bundleID)
        storePending { NewAppQuestion.remembered(removing: bundleID, from: $0) }
        publish()
    }

    /// The section an answer stands for; Always Hidden becomes Hidden while that section is off.
    private func section(for answer: NewAppQuestion.Answer) -> MacOS27Section? {
        switch answer {
        case .visible:
            .visible
        case .hidden:
            .hidden
        case .alwaysHidden:
            offersAlwaysHidden ? .alwaysHidden : .hidden
        case .dontAskAgain:
            nil
        }
    }

    private static func name(of section: MacOS27Section) -> MenuBarSection.Name {
        switch section {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    // MARK: - Switching off

    /// Drops every waiting and asked question, empties the kept list and stops every wait: with the
    /// switch off nothing waits and nothing costs (D-05). The declined list stays.
    func switchDidTurnOff() {
        question.clear()
        storePending { _ in [] }
        gateLoop?.cancel()
        gateLoop = nil
        waitTask?.cancel()
        waitTask = nil
        publish()
    }

    // MARK: - The gate

    /// Asks the waiting apps when the gate is open. While it is closed, one observation of the
    /// events that close it and one wait for the next instant time can open it bring the apps back
    /// here.
    private func releaseIfOpen() {
        guard let appState else {
            return
        }
        let due = question.release(gate: gate(appState), at: .now)
        publish()
        guard !question.waiting.isEmpty else {
            gateLoop?.cancel()
            gateLoop = nil
            waitTask?.cancel()
            waitTask = nil
            return
        }
        if gateLoop == nil {
            gateLoop = ObservationLoop.observe({ [weak self] in
                self?.appState.map(Self.closingEvents) ?? ClosingEvents(isDragging: false, isPaused: false, launchGrace: [])
            }, onChange: { [weak self] _ in
                self?.releaseIfOpen()
            })
        }
        arm(appState, due: due)
    }

    /// What closes the gate by an event; the observation follows it while an app waits.
    private struct ClosingEvents: Equatable {
        let isDragging: Bool
        let isPaused: Bool
        let launchGrace: Set<String>
    }

    private static func closingEvents(_ appState: AppState) -> ClosingEvents {
        ClosingEvents(
            isDragging: appState.isDraggingMenuBarItem,
            isPaused: appState.systemActivityMonitor.isPaused,
            launchGrace: appState.concealer27.launchGraceBundleIDs
        )
    }

    /// Arms the one wait for the next instant time can open the gate: the end of the quiet start or
    /// of the coalescing (`due`), or the system settling, which the monitor publishes no event for.
    private func arm(_ appState: AppState, due: ContinuousClock.Instant?) {
        waitTask?.cancel()
        waitTask = nil
        var next = due
        let monitor = appState.systemActivityMonitor
        if !monitor.isSettled, !monitor.isPaused {
            let settled = ContinuousClock.now.advanced(by: SystemActivity.settleDelay)
            next = next.map { min($0, settled) } ?? settled
        }
        guard let next else {
            return
        }
        waitTask = Task { [weak self] in
            try? await Task.sleep(until: next, tolerance: .milliseconds(200), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.releaseIfOpen()
        }
    }

    private func gate(_ appState: AppState) -> NewAppQuestion.Gate {
        NewAppQuestion.Gate(
            isDragging: appState.isDraggingMenuBarItem,
            isSettled: appState.systemActivityMonitor.isSettled,
            launchGrace: appState.concealer27.launchGraceBundleIDs,
            startedAt: startedAt
        )
    }

    private func publish() {
        if asked != question.asked {
            asked = question.asked
        }
    }
}
