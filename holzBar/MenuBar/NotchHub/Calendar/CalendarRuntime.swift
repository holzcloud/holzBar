//
//  CalendarRuntime.swift
//  holzBar
//

import AppKit
import EventKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// What the Calendar module may read, from the system's authorization status.
enum CalendarAuthorization: Equatable {
    /// The user has not been asked.
    case notDetermined
    /// Full access: events can be read.
    case granted
    /// The user refused.
    case denied
    /// A profile or parental control forbids it.
    case restricted
    /// Events can be added but not read; the module needs full access.
    case writeOnly

    /// The status the system reports now. It reads no store and shows no prompt.
    static var current: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }
}

/// A row of the Calendar tab: the chosen event and, when it has one, its meeting link.
struct CalendarRowModel: Identifiable, Equatable {
    let row: NextEvents.Row
    /// The validated meeting link, if the event has one.
    let link: MeetingLink?
    /// Whether the Join button shows: a link, a timed event, and now is inside the join window.
    let isJoinable: Bool

    var id: String { row.id }
}

/// What decides whether the closed hub's countdown exists, and for how long it leads.
private struct CountdownInputs: Equatable {
    let observers: Set<ClosedHubWork.Observer>
    let lead: CountdownLead
}

/// What the module's settings say, to notice a change of them.
private struct SettingsState: Equatable {
    let showsAllDay: Bool
    let hidden: Set<String>
}

/// The running part of the Calendar module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off: no store, no
/// observer, no wait. When it starts and the system has not been asked yet, it asks once for
/// full access to events. The events are read through one actor, kept in memory for the shown
/// window only and dropped on shutdown.
///
/// One narrow read happens while the hub is closed: the countdown before a meeting (D-18, D-24). It
/// exists only while ``ClosedHubWork`` lists it (the countdown is not Off and access is granted).
/// It reads only the start times of the next two meetings, holds them in memory (never a title, a
/// place, notes or attendees) and arms at most two one-shot wakes per meeting; the activity ends
/// through the board's own expiry at the start. Nothing polls.
@MainActor
@Observable
final class CalendarRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "calendar"

    let moduleID = CalendarRuntime.identifier
    let tint = HubTint.accent
    let offersTab = true

    /// The rows of the Calendar tab.
    private(set) var rows = [CalendarRowModel]()

    /// Whether ``rows``, which are read only while the hub is open, may still decide what the
    /// hub opens on at the next opening (``contextSignal``): they may until the event store or
    /// the settings change, or the read gets old.
    private(set) var freshness = CalendarReadFreshness()

    /// Whether events can be read.
    private(set) var authorization = CalendarAuthorization.current

    @ObservationIgnored private var fetcher: CalendarFetcher? = CalendarFetcher()
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var isHubOpen = false
    /// The countdown's plan for the next meeting, or `nil`. It holds the start time only.
    private var countdownPlan: CountdownSchedule.Plan?
    /// Bumped at every wake and every new plan, so what reads ``activities`` draws again at the
    /// moment the countdown starts or turns amber.
    private var countdownRevision = 0
    @ObservationIgnored private var heldStart: Date?
    @ObservationIgnored private var heldFollowingStart: Date?
    @ObservationIgnored private var countdownReadTask: Task<Void, Never>?
    @ObservationIgnored private var countdownWakeTask: Task<Void, Never>?
    @ObservationIgnored private var systemWakeTask: Task<Void, Never>?
    @ObservationIgnored private var countdownLoop: ObservationLoop?
    @ObservationIgnored private var isCountingDown = false
    @ObservationIgnored private var permissionLoop: ObservationLoop?
    @ObservationIgnored private var settingsLoop: ObservationLoop?
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private let logger = Logger(category: "Calendar")

    init(appState: AppState) {
        self.appState = appState
        let permission = appState.permissions.calendar
        permissionLoop = ObservationLoop.observe {
            permission.hasPermission
        } onChange: { [weak self] _ in
            self?.accessDidChange()
        }
        let settings = appState.settings.calendar
        settingsLoop = ObservationLoop.observe {
            SettingsState(showsAllDay: settings.showsAllDay, hidden: settings.hiddenCalendars)
        } onChange: { [weak self] _ in
            self?.storeDidChange()
        }
        // The store's change notification is the only thing that listens while the hub is
        // closed; it reads nothing then (``storeDidChange()``).
        changeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                self?.storeDidChange()
            }
        }
        if authorization == .notDetermined {
            ask()
        }
        countdownLoop = ObservationLoop.observe { [weak self] in
            self?.countdownInputs() ?? CountdownInputs(observers: [], lead: .off)
        } onChange: { [weak self] inputs in
            self?.apply(inputs)
        }
        apply(countdownInputs())
    }

    // MARK: Access

    /// Asks the system for full access, once. Called only when the status is not determined.
    private func ask() {
        requestTask = Task { [weak self] in
            await CalendarPermission.requestAccess()
            guard !Task.isCancelled else {
                return
            }
            self?.appState?.permissions.calendar.refresh()
            self?.accessDidChange()
        }
    }

    /// Asks the system for full access, for the button of the tab. Once the user has decided,
    /// the system shows no prompt, so the tab offers System Settings instead.
    func allowAccess() {
        guard authorization == .notDetermined else {
            openSystemSettings()
            return
        }
        ask()
    }

    /// Reads the status again after a grant or a change in System Settings.
    func accessDidChange() {
        let status = CalendarAuthorization.current
        guard status != authorization else {
            return
        }
        authorization = status
        if status == .granted {
            // A store made before the grant may not see the events.
            Task { [fetcher] in
                await fetcher?.reset()
            }
        }
        reload()
    }

    /// Opens the Calendars pane of System Settings, where access can be changed.
    func openSystemSettings() {
        appState?.permissions.calendar.openSettings()
    }

    // MARK: Reading

    /// The store changed: what was read before cannot be trusted for the context, and the open
    /// hub reads again. A closed hub reads nothing; it reads when it opens.
    private func storeDidChange() {
        freshness.didChange()
        if isHubOpen {
            reload()
        }
        if isCountingDown {
            refreshCountdown()
        }
    }

    /// Reads the window from the start of today to the end of tomorrow, chooses the rows and
    /// arms the one wait for the moment the list changes next.
    func reload() {
        fetchTask?.cancel()
        waitTask?.cancel()
        waitTask = nil
        guard authorization == .granted, let fetcher else {
            rows = []
            freshness.reset()
            return
        }
        let settings = appState?.settings.calendar
        let showsAllDay = settings?.showsAllDay ?? true
        let hidden = settings?.hiddenCalendars ?? []
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: .now)
        let windowEnd = NextEvents.windowEnd(now: .now, calendar: calendar)
        // A read counts from its start, and only if nothing changed while it ran.
        let readStart = Date.now
        let readToken = freshness.token
        fetchTask = Task { [weak self] in
            let events = await fetcher.events(from: windowStart, to: windowEnd)
            guard !Task.isCancelled, let self else {
                return
            }
            let now = Date.now
            let selection = NextEvents.select(
                events: events.filter { CalendarSelection.isVisible($0.calendarID, hidden: hidden) },
                now: now,
                calendar: calendar,
                includesAllDay: showsAllDay
            )
            rows = selection.rows.map { row in
                let link = MeetingLinks.find(url: row.event.url, location: row.event.location, notes: row.event.notes)
                let isJoinable = link != nil && row.phase != .allDay
                    && MeetingLinks.isJoinable(start: row.event.start, end: row.event.end, now: now)
                return CalendarRowModel(row: row, link: link, isJoinable: isJoinable)
            }
            freshness.didRead(startedAt: readStart, token: readToken)
            logger.debug("Calendar events changed: \(selection.rows.count, privacy: .public) rows")
            armWait(until: selection.nextBoundary)
        }
    }

    /// The module's only wait: one one-shot sleep until the list changes by itself (an event
    /// starts or ends, a join window opens, the day changes), and only while the hub is open.
    /// The continuous clock keeps counting while the Mac sleeps, so a wait that spans a sleep
    /// ends at once on wake.
    private func armWait(until boundary: Date) {
        waitTask?.cancel()
        waitTask = nil
        guard isHubOpen else {
            return
        }
        let seconds = max(0, boundary.timeIntervalSinceNow)
        waitTask = Task { [weak self] in
            try? await Task.sleep(until: .now + .seconds(seconds), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.reload()
        }
    }

    /// Opens a validated meeting link, only on a click on its button, and closes the hub.
    func join(_ link: MeetingLink, host: any HubHost) {
        NSWorkspace.shared.open(link.url)
        host.close()
    }

    // MARK: Hub

    /// The Overview card: the event that is on or next, with its start drawn by the system.
    var tile: HubTile? {
        guard authorization == .granted else {
            return nil
        }
        let model = rows.first { $0.row.phase != .allDay } ?? rows.first
        guard let model else {
            return HubTile(symbol: "calendar", title: Text("Next event"), value: String(localized: "No events"))
        }
        let event = model.row.event
        let title = event.title.isEmpty ? String(localized: "Untitled") : event.title
        let value = title.count > 14 ? String(title.prefix(13)) + "…" : title
        let detail: Text
        switch model.row.phase {
        case .happening: detail = Text("Now")
        case .upcoming: detail = Text(event.start, style: .relative)
        case .allDay: detail = Text("All day")
        }
        return HubTile(symbol: "calendar", title: Text("Next event"), value: value, detail: detail)
    }

    /// What the hub's context reads: the times of the timed events the runtime holds, never
    /// anything else of them. Nothing is read for it; all-day events are left out. Rows from an
    /// earlier opening still decide at this opening while nothing says they are out of date (the
    /// store reported no change since the read, the settings are the same and the read is not
    /// older than ``CalendarReadFreshness/maximumAge``); the context then checks each meeting
    /// against the clock, so one that has ended or is not near never decides. Otherwise they count
    /// as no meetings until this opening has read them: an event deleted or moved since then must
    /// not bring the module to the front.
    var contextSignal: HubContext.Signal? {
        guard freshness.mayDecide(now: .now) else {
            return .meetings([])
        }
        return .meetings(
            rows.compactMap { model in
                let event = model.row.event
                return event.isAllDay ? nil : HubContext.Meeting(start: event.start, end: event.end)
            }
        )
    }

    /// The meeting countdown of the closed notch: one activity from the lead before the next
    /// meeting's start until the start, amber for the last minute. It carries a fixed sentence for
    /// VoiceOver, never a title. The countdown is drawn by the system from ``LiveActivity/endsAt``,
    /// and the board drops the activity at the start (`holdSeconds` 0, finished at the start).
    var activities: [LiveActivity] {
        _ = countdownRevision
        guard let plan = countdownPlan else {
            return []
        }
        let now = Date.now
        guard now >= plan.startsAt, now < plan.meetingStart else {
            return []
        }
        return [
            LiveActivity(
                id: "countdown",
                moduleID: moduleID,
                kind: .timer,
                symbol: "calendar.badge.clock",
                title: String(localized: "Meeting starts soon"),
                priority: CountdownSchedule.priority,
                startedAt: plan.startsAt,
                endsAt: plan.meetingStart,
                finishedAt: plan.meetingStart,
                tint: CountdownSchedule.isAmber(plan, now: now) ? .amber : .accent,
                holdSeconds: 0
            ),
        ]
    }

    func hubVisibilityDidChange(isOpen: Bool) {
        isHubOpen = isOpen
        guard isOpen else {
            waitTask?.cancel()
            waitTask = nil
            return
        }
        // A change of access reloads by itself; otherwise the open hub reads again.
        let before = authorization
        accessDidChange()
        if authorization == before {
            reload()
        }
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(CalendarBodyView(runtime: self, host: host))
    }

    /// Cancels every task and lets go of the events and the store.
    func shutDown() {
        countdownLoop?.cancel()
        countdownLoop = nil
        stopCountdown()
        fetchTask?.cancel()
        fetchTask = nil
        requestTask?.cancel()
        requestTask = nil
        changeTask?.cancel()
        changeTask = nil
        waitTask?.cancel()
        waitTask = nil
        permissionLoop = nil
        settingsLoop = nil
        rows = []
        freshness.reset()
        fetcher = nil
    }
}

// MARK: Countdown

extension CalendarRuntime {
    /// What exists now, decided by ``ClosedHubWork`` and nowhere else, and the lead.
    fileprivate func countdownInputs() -> CountdownInputs {
        guard let appState else {
            return CountdownInputs(observers: [], lead: .off)
        }
        let lead = appState.settings.calendar.countdownLead
        let observers = ClosedHubWork.observers(
            ClosedHubWork.Switches(
                hubOn: appState.modules.isEnabled(NotchHubController.moduleID),
                calendarOn: appState.modules.isEnabled(Self.identifier),
                countdownOn: lead != .off,
                calendarAccess: authorization == .granted
            )
        )
        return CountdownInputs(observers: observers, lead: lead)
    }

    /// Starts or stops the countdown as the rule says; a new lead plans again.
    fileprivate func apply(_ inputs: CountdownInputs) {
        guard inputs.observers.contains(.countdown) else {
            stopCountdown()
            return
        }
        startCountdown()
        refreshCountdown()
    }

    /// Starts watching for the Mac waking from sleep, the only observer of the countdown besides
    /// the store's change notification the module has anyway.
    private func startCountdown() {
        guard !isCountingDown else {
            return
        }
        isCountingDown = true
        systemWakeTask = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                self?.refreshCountdown()
            }
        }
    }

    /// Drops the wakes, the start times and the activity.
    func stopCountdown() {
        isCountingDown = false
        countdownReadTask?.cancel()
        countdownReadTask = nil
        countdownWakeTask?.cancel()
        countdownWakeTask = nil
        systemWakeTask?.cancel()
        systemWakeTask = nil
        heldStart = nil
        heldFollowingStart = nil
        if countdownPlan != nil {
            countdownPlan = nil
            countdownRevision &+= 1
        }
    }

    /// Reads the start of the next meeting and of the one after it (dates only), from now to the end
    /// of tomorrow, and plans again. Both wakes of the earlier plan are dropped first.
    func refreshCountdown() {
        countdownReadTask?.cancel()
        countdownWakeTask?.cancel()
        countdownWakeTask = nil
        guard isCountingDown, authorization == .granted, let fetcher else {
            return
        }
        let hidden = appState?.settings.calendar.hiddenCalendars ?? []
        let lead = appState?.settings.calendar.countdownLead ?? .off
        let now = Date.now
        let windowEnd = NextEvents.windowEnd(now: now, calendar: .current)
        countdownReadTask = Task { [weak self] in
            let next = await fetcher.nextStart(from: now, to: windowEnd, hidden: hidden)
            var following: Date?
            if let next {
                following = await fetcher.nextStart(from: next, to: windowEnd, hidden: hidden)
            }
            guard !Task.isCancelled, let self, isCountingDown else {
                return
            }
            planCountdown(next: next, following: following, lead: lead)
        }
    }

    /// Makes the plan for a start and arms the one wake that is due next.
    private func planCountdown(next: Date?, following: Date?, lead: CountdownLead) {
        countdownWakeTask?.cancel()
        countdownWakeTask = nil
        heldStart = next
        heldFollowingStart = following
        let now = Date.now
        let plan = CountdownSchedule.plan(nextStart: next, lead: lead, now: now)
        countdownPlan = plan
        countdownRevision &+= 1
        logger.debug("Countdown planned: \(plan == nil ? 0 : 1, privacy: .public) plans")
        guard let plan else {
            if next != nil {
                // The start passed while the read ran: read again from now.
                refreshCountdown()
            }
            return
        }
        let wake = CountdownSchedule.nextWake(plan, now: now)
            ?? CountdownSchedule.followingWake(after: plan, followingStart: following, lead: lead, now: now)
        guard let wake else {
            return
        }
        let seconds = max(0, wake.timeIntervalSinceNow)
        countdownWakeTask = Task { [weak self] in
            try? await Task.sleep(until: .now + .seconds(seconds), tolerance: .seconds(1), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.countdownWakeDidFire()
        }
    }

    /// A wake came: while the meeting still lies ahead, the held times plan again without a read;
    /// once it has started, the next one is read.
    private func countdownWakeDidFire() {
        let lead = appState?.settings.calendar.countdownLead ?? .off
        if let held = heldStart, held > .now {
            planCountdown(next: held, following: heldFollowingStart, lead: lead)
        } else {
            refreshCountdown()
        }
    }
}
