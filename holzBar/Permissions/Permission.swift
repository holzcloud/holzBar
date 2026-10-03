//
//  Permission.swift
//  holzBar
//

import Cocoa
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
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        requestsAtLaunch: Bool,
        settingsURL: URL?,
        tccService: String?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
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
            title: "Accessibility",
            details: [
                "Read where menu bar items are.",
                "Move, show and click menu bar items for you.",
                "Notice clicks, scrolls and hovers in the menu bar for show on click, scroll and hover.",
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
            title: "Screen Recording",
            details: ScreenRecordingFeature.allCases.map(\.reason),
            isRequired: false,
            requestsAtLaunch: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"),
            tccService: "ScreenCapture",
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
