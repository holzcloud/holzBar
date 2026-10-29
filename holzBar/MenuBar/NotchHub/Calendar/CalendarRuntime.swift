//
//  CalendarRuntime.swift
//  holzBar
//

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
    private(set) var rows = [NextEvents.Row]()

    /// Whether events can be read.
    private(set) var authorization = CalendarAuthorization.current

    @ObservationIgnored private var fetcher: CalendarFetcher? = CalendarFetcher()
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
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
        if authorization == .notDetermined {
            ask()
        }
        reload()
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

    /// Reads the window from the start of today to the end of tomorrow and chooses the rows.
    func reload() {
        fetchTask?.cancel()
        guard authorization == .granted, let fetcher else {
            rows = []
            return
        }
        let calendar = Calendar.current
        let now = Date.now
        let windowStart = calendar.startOfDay(for: now)
        let windowEnd = NextEvents.windowEnd(now: now, calendar: calendar)
        fetchTask = Task { [weak self] in
            let events = await fetcher.events(from: windowStart, to: windowEnd)
            guard !Task.isCancelled, let self else {
                return
            }
            let selection = NextEvents.select(events: events, now: .now, calendar: calendar)
            rows = selection.rows
            logger.debug("Calendar events changed: \(selection.rows.count, privacy: .public) rows")
        }
    }

    // MARK: Hub

    func hubVisibilityDidChange(isOpen: Bool) {
        if isOpen {
            // A change of access reloads by itself; otherwise the open hub reads again.
            let before = authorization
            accessDidChange()
            if authorization == before {
                reload()
            }
        }
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(CalendarBodyView(runtime: self))
    }

    /// Cancels every task and lets go of the events and the store.
    func shutDown() {
        fetchTask?.cancel()
        fetchTask = nil
        requestTask?.cancel()
        requestTask = nil
        permissionLoop = nil
        rows = []
        fetcher = nil
    }
}
