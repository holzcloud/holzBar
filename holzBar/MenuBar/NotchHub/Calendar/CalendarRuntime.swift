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

/// The running part of the Calendar module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off: no store, no
/// observer, no wait. When it starts and the system has not been asked yet, it asks once for
/// full access to events. The events are read through one actor, kept in memory for the shown
/// window only and dropped on shutdown.
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

    /// Whether events can be read.
    private(set) var authorization = CalendarAuthorization.current

    @ObservationIgnored private var fetcher: CalendarFetcher? = CalendarFetcher()
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var isHubOpen = false
    @ObservationIgnored private var permissionLoop: ObservationLoop?
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

    /// The store changed: read again while the hub is open. A closed hub reads when it opens.
    private func storeDidChange() {
        if isHubOpen {
            reload()
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
            return
        }
        let calendar = Calendar.current
        let windowStart = calendar.startOfDay(for: .now)
        let windowEnd = NextEvents.windowEnd(now: .now, calendar: calendar)
        fetchTask = Task { [weak self] in
            let events = await fetcher.events(from: windowStart, to: windowEnd)
            guard !Task.isCancelled, let self else {
                return
            }
            let now = Date.now
            let selection = NextEvents.select(events: events, now: now, calendar: calendar)
            rows = selection.rows.map { row in
                let link = MeetingLinks.find(url: row.event.url, location: row.event.location, notes: row.event.notes)
                let isJoinable = link != nil && row.phase != .allDay
                    && MeetingLinks.isJoinable(start: row.event.start, end: row.event.end, now: now)
                return CalendarRowModel(row: row, link: link, isJoinable: isJoinable)
            }
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
        fetchTask?.cancel()
        fetchTask = nil
        requestTask?.cancel()
        requestTask = nil
        changeTask?.cancel()
        changeTask = nil
        waitTask?.cancel()
        waitTask = nil
        permissionLoop = nil
        rows = []
        fetcher = nil
    }
}
