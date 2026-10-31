//
//  Permission.swift
//  holzBar
//

import Cocoa
import EventKit
import Observation

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
@Observable
class Permission: Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    private(set) var hasPermission = false {
        didSet {
            if hasPermission, !waiters.isEmpty {
                endWaits(with: true)
            }
        }
    }

    /// The title of the permission.
    let title: String

    /// Descriptive details for the permission.
    let details: [String]

    /// A Boolean value that indicates if the app can work without this permission.
    let isRequired: Bool

    /// What a permission that is asked for later is used for, in one sentence, for the
    /// Permissions window. `nil` for a permission asked for at launch, which lists its
    /// ``details`` instead.
    let summary: String?

    /// What happens without the permission, in one sentence, for the Permissions window.
    let withoutNote: String?

    /// A Boolean value that indicates whether holzBar asks for this permission at the
    /// first launch.
    ///
    /// A permission that is not asked for at launch is checked once when holzBar starts
    /// and asked for only by the feature that needs it (see ``ScreenRecordingFeature``).
    let requestsAtLaunch: Bool

    /// The URL of the settings pane to open.
    @ObservationIgnored private let settingsURL: URL?

    /// The name of the privacy service that `tccutil` uses for this permission.
    @ObservationIgnored private let tccService: String?

    /// The function that checks permissions.
    @ObservationIgnored private let check: () -> Bool

    /// The function that requests permissions.
    @ObservationIgnored private let request: () -> Void

    /// The task that checks permissions once a second while the app does not have
    /// this one.
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// How long a permission that is not asked for at launch keeps checking after a
    /// request. macOS posts no notification for a grant, so the check runs once a
    /// second, but not forever when the user decides against it.
    private static let requestCheckDuration = Duration.seconds(300)

    /// The pending waits for this permission, each with its own stream.
    @ObservationIgnored private var waiters: [UUID: AsyncStream<Bool>.Continuation] = [:]

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - requestsAtLaunch: A Boolean value that indicates whether holzBar asks for this
    ///     permission at the first launch.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - tccService: The name of the privacy service that `tccutil` uses for this permission.
    ///   - summary: What a permission that is asked for later is used for.
    ///   - withoutNote: What happens without a permission that is asked for later.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        requestsAtLaunch: Bool,
        settingsURL: URL?,
        tccService: String?,
        summary: String? = nil,
        withoutNote: String? = nil,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.summary = summary
        self.withoutNote = withoutNote
        self.isRequired = isRequired
        self.requestsAtLaunch = requestsAtLaunch
        self.settingsURL = settingsURL
        self.tccService = tccService
        self.check = check
        self.request = request
        if requestsAtLaunch {
            startCheck()
        } else {
            // Checked once; the repeated check starts only with a request.
            updateHasPermission()
        }
    }

    /// Checks the permission now and, while the app does not have it, once a second.
    ///
    /// The check stops as soon as the permission is granted, so nothing polls once the app
    /// has every permission. A permission that is not asked for at launch stops checking
    /// after ``requestCheckDuration`` without a grant and ends its waits.
    private func startCheck() {
        updateHasPermission()
        guard !hasPermission else {
            stopTimer()
            return
        }
        guard checkTask == nil else {
            return
        }
        let deadline: ContinuousClock.Instant? = requestsAtLaunch ? nil : ContinuousClock.now + Self.requestCheckDuration
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(100))
                guard let self, !Task.isCancelled else {
                    return
                }
                updateHasPermission()
                if hasPermission {
                    stopTimer()
                } else if let deadline, ContinuousClock.now >= deadline {
                    stopCheck()
                }
            }
        }
    }

    /// Checks the permission and stores the result if it changed, so that views
    /// observing it are not redrawn every second.
    private func updateHasPermission() {
        let granted = check()
        if hasPermission != granted {
            hasPermission = granted
        }
    }

    /// Stops the timer of the permission check.
    private func stopTimer() {
        checkTask?.cancel()
        checkTask = nil
    }

    /// Checks the permission again, as the user, a profile or `tccutil` can grant it or
    /// take it away while holzBar runs.
    ///
    /// Nothing polls while the app has the permission. A permission asked for at launch
    /// that is missing checks once a second until it is granted again (``startCheck()``),
    /// so what waits for the grant runs; any other permission is only checked once.
    func refresh() {
        if requestsAtLaunch {
            startCheck()
        } else {
            updateHasPermission()
        }
    }

    /// Performs the request and opens the System Settings app to the appropriate pane.
    ///
    /// The check runs again afterwards, as a reset can take away a permission the app had.
    func performRequest() {
        request()
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
        startCheck()
    }

    /// A Boolean value that indicates whether the app's entry for this permission
    /// can be reset.
    var canReset: Bool {
        tccService != nil && Bundle.main.bundleIdentifier != nil
    }

    /// Removes the app's entry for this permission from the privacy database, then
    /// performs the request again.
    ///
    /// After an update or a rebuild, macOS can keep an entry for the app's previous
    /// signature. System Settings then shows the permission as granted while the
    /// check keeps failing, and the permissions window cannot be left (reported on
    /// jordanbaird/Ice#1004). Removing the entry lets the user grant it afresh.
    func resetAndRequest() {
        guard let tccService, let bundleIdentifier = Bundle.main.bundleIdentifier else {
            performRequest()
            return
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tccutil")
        process.arguments = ["reset", tccService, bundleIdentifier]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performRequest()
            }
        }
        do {
            try process.run()
        } catch {
            performRequest()
        }
    }

    /// Removes the app's entry for this permission from the privacy database and checks again.
    ///
    /// holzBar stops using the permission at once and does not ask for it again; the user
    /// grants it afresh when they want to. This is what the user can also do by hand in
    /// System Settings, in Privacy & Security.
    func revoke() {
        guard let tccService, let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tccutil")
        process.arguments = ["reset", tccService, bundleIdentifier]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        try? process.run()
    }

    /// Opens the pane of System Settings where the user can remove the permission by hand.
    func openSettings() {
        if let settingsURL {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Waits for the app to be granted this permission.
    ///
    /// Every call waits on its own stream, so any number of waits can run at the
    /// same time and each one returns.
    ///
    /// - Returns: `true` once the app has the permission (at once when it already
    ///   has it), and `false` when ``stopCheck()`` ends the checks first or the
    ///   waiting task is cancelled.
    @discardableResult
    func waitForPermission() async -> Bool {
        startCheck()
        guard !hasPermission else {
            return true
        }
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let id = UUID()
        waiters[id] = continuation
        defer {
            waiters.removeValue(forKey: id)
        }
        for await granted in stream {
            return granted
        }
        // Only reached when the waiting task is cancelled, which ends the iteration.
        return hasPermission
    }

    /// Ends every pending wait with the given result.
    private func endWaits(with granted: Bool) {
        let continuations = waiters.values
        waiters.removeAll()
        for continuation in continuations {
            continuation.yield(granted)
            continuation.finish()
        }
    }

    /// Stops running the permission check.
    func stopCheck() {
        stopTimer()
        endWaits(with: false)
    }
}

// MARK: - AccessibilityPermission

final class AccessibilityPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Accessibility"),
            details: [
                String(localized: "Read where menu bar items are."),
                String(localized: "Move, show and click menu bar items for you."),
                String(localized: "Notice clicks, scrolls and hovers in the menu bar for show on click, scroll and hover."),
            ],
            isRequired: true,
            requestsAtLaunch: true,
            settingsURL: nil,
            tccService: "Accessibility",
            check: {
                AXHelpers.isProcessTrusted()
            },
            request: {
                AXHelpers.isProcessTrusted(prompt: true)
            }
        )
    }
}

// MARK: - ScreenRecordingPermission

final class ScreenRecordingPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Screen Recording"),
            details: ScreenRecordingFeature.allCases.map(\.reason.localizedFromCatalog),
            isRequired: false,
            requestsAtLaunch: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"),
            tccService: "ScreenCapture",
            summary: ScreenRecordingFeature.summary.localizedFromCatalog,
            withoutNote: String(localized: "Optional. Without it holzBar shows the apps' icons."),
            check: {
                // Refreshes the cached result too, which the capture paths read.
                ScreenCapture.cachedCheckPermissions(reset: true)
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}

// MARK: - CalendarPermission

/// Full access to the user's events, for the Calendar module of the Notch hub.
///
/// It is not asked for at launch: the status is read once, without a prompt, and the module
/// asks when it is switched on (``requestAccess()``). The Permissions window and the Advanced
/// pane offer Allow and Revoke like Screen Recording's.
final class CalendarPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Calendar"),
            details: [String(localized: "Shows your next events and their meeting links in the notch hub.")],
            isRequired: false,
            requestsAtLaunch: false,
            // The Calendars pane is opened by ``openSettings()`` once the system will not ask
            // again; while it still asks, the prompt is all that opens.
            settingsURL: nil,
            tccService: "Calendar",
            summary: String(localized: "Shows your next events and their meeting links in the notch hub."),
            withoutNote: String(localized: "Optional. Without it the Calendar module cannot show your events."),
            check: {
                EKEventStore.authorizationStatus(for: .event) == .fullAccess
            },
            request: {
                Task {
                    await CalendarPermission.requestAccess()
                }
            }
        )
    }

    /// Asks the system for full access to events; the prompt appears only while the status is
    /// not determined. The one place the request is made. The result is ignored: the
    /// permission reads the status itself (``Permission/refresh()``).
    static func requestAccess() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
    }

    /// Asks while the system still asks; once the user has decided, opens the Calendars pane
    /// of System Settings, where the decision can be changed.
    override func performRequest() {
        let isDecided = EKEventStore.authorizationStatus(for: .event) != .notDetermined
        super.performRequest()
        if isDecided {
            openSettings()
        }
    }

    override func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - BluetoothPermission

/// Bluetooth, for the connection alerts of the Accessory alerts module and the Bluetooth
/// trigger of automation rules.
///
/// It is not asked for at launch: reading it looks at the authorization class property only,
/// which asks nothing and starts no Bluetooth work. The question is asked once by the
/// module or by Allow in the Permissions window, through ``BluetoothDeviceMonitor``; Revoke
/// resets holzBar's own entry like the other optional permissions.
final class BluetoothPermission: Permission {
    init() {
        super.init(
            title: String(localized: "Bluetooth"),
            details: [
                String(localized: "Show which of your paired accessories are connected, for the connection alerts of Accessory alerts."),
                String(localized: "Tell automation rules which Bluetooth device is connected."),
            ],
            isRequired: false,
            requestsAtLaunch: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth"),
            tccService: "Bluetooth",
            summary: String(localized: "Show which of your paired accessories are connected, for the connection alerts of Accessory alerts."),
            withoutNote: String(localized: "Optional. Without it Accessory alerts cannot tell which accessories are connected."),
            check: {
                BluetoothDeviceMonitor.access == .allowed
            },
            request: {
                BluetoothDeviceMonitor.requestAccess()
            }
        )
    }
}
