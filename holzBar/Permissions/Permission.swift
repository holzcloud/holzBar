//
//  Permission.swift
//  holzBar
//

import Combine
import Cocoa

// MARK: - Permission

/// An object that encapsulates the behavior of checking for and requesting
/// a specific permission for the app.
@MainActor
class Permission: ObservableObject, Identifiable {
    /// A Boolean value that indicates whether the app has this permission.
    @Published private(set) var hasPermission = false {
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

    /// The URL of the settings pane to open.
    private let settingsURL: URL?

    /// The name of the privacy service that `tccutil` uses for this permission.
    private let tccService: String?

    /// The function that checks permissions.
    private let check: () -> Bool

    /// The function that requests permissions.
    private let request: () -> Void

    /// Observer that runs on a timer to check permissions while the app does not
    /// have this one.
    private var timerCancellable: AnyCancellable?

    /// The pending waits for this permission, each with its own stream.
    private var waiters: [UUID: AsyncStream<Bool>.Continuation] = [:]

    /// Creates a permission.
    ///
    /// - Parameters:
    ///   - title: The title of the permission.
    ///   - details: Descriptive details for the permission.
    ///   - isRequired: A Boolean value that indicates if the app can work without this permission.
    ///   - settingsURL: The URL of the settings pane to open.
    ///   - tccService: The name of the privacy service that `tccutil` uses for this permission.
    ///   - check: A function that checks permissions.
    ///   - request: A function that requests permissions.
    init(
        title: String,
        details: [String],
        isRequired: Bool,
        settingsURL: URL?,
        tccService: String?,
        check: @escaping () -> Bool,
        request: @escaping () -> Void
    ) {
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.settingsURL = settingsURL
        self.tccService = tccService
        self.check = check
        self.request = request
        startCheck()
    }

    /// Checks the permission now and, while the app does not have it, once a second.
    ///
    /// The check stops as soon as the permission is granted, so nothing polls once the app
    /// has every permission.
    private func startCheck() {
        hasPermission = check()
        guard !hasPermission else {
            stopTimer()
            return
        }
        guard timerCancellable == nil else {
            return
        }
        timerCancellable = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                hasPermission = check()
                if hasPermission {
                    stopTimer()
                }
            }
    }

    /// Stops the timer of the permission check.
    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
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
        process.terminationHandler = { _ in
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
                "Get real-time information about the menu bar.",
                "Arrange menu bar items.",
            ],
            isRequired: true,
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
            details: [
                "Change the menu bar's appearance.",
                "Display images of individual menu bar items.",
            ],
            isRequired: false,
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"),
            tccService: "ScreenCapture",
            check: {
                ScreenCapture.checkPermissions()
            },
            request: {
                ScreenCapture.requestPermissions()
            }
        )
    }
}
