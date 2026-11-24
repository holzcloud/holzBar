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
/// wake or a display change, an app is in its launch grace). The observation that opens the gate
/// runs only while an app waits, and the one wait for the system to settle is a single
/// `Task.sleep`; nothing polls. An answer is remembered by the saved layout and the list of
/// known apps, so the app is never asked again.
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
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "NewAppQuestions27")

    init(appState: AppState?) {
        self.appState = appState
    }

    /// Whether the Always Hidden choice is offered: only while that section is enabled.
    var offersAlwaysHidden: Bool {
        appState?.settings.advanced.enableAlwaysHiddenSection ?? false
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
            declined: []
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
    /// leaves. Don't ask again only takes the row away here.
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

    // MARK: - The gate

    /// Asks the waiting apps when the gate is open. While it is closed, one observation of the
    /// events that close it and one wait for the system to settle bring the apps back here.
    private func releaseIfOpen() {
        guard let appState else {
            return
        }
        _ = question.release(gate: gate(appState), at: .now)
        publish()
        guard !question.waiting.isEmpty else {
            gateLoop?.cancel()
            gateLoop = nil
            settleTask?.cancel()
            settleTask = nil
            return
        }
        if gateLoop == nil {
            gateLoop = ObservationLoop.observe({ [weak self] in
                self?.appState.map { $0.isDraggingMenuBarItem || $0.systemActivityMonitor.isPaused || !$0.concealer27.launchGraceBundleIDs.isEmpty } ?? false
            }, onChange: { [weak self] _ in
                self?.releaseIfOpen()
            })
        }
        armSettleWait(appState)
    }

    /// Arms one wait for the system to settle, when only time keeps the gate closed: the monitor
    /// publishes no event when the bar has settled.
    private func armSettleWait(_ appState: AppState) {
        settleTask?.cancel()
        settleTask = nil
        let monitor = appState.systemActivityMonitor
        guard !monitor.isSettled, !monitor.isPaused else {
            return
        }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: SystemActivity.settleDelay, tolerance: .milliseconds(200), clock: .continuous)
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
            launchGrace: appState.concealer27.launchGraceBundleIDs
        )
    }

    private func publish() {
        if asked != question.asked {
            asked = question.asked
        }
    }
}
