//
//  HolzBarShelfColorManager.swift
//  holzBar
//

import Observation
import SwiftUI

@MainActor
@Observable
final class HolzBarShelfColorManager {
    private(set) var colorInfo: MenuBarAverageColorInfo?

    @ObservationIgnored private weak var shelfPanel: HolzBarShelfPanel?

    @ObservationIgnored private var windowImage: CGImage?

    /// Observers of the Shelf panel's screen, visibility and frame.
    @ObservationIgnored private var observations = [NSKeyValueObservation]()

    /// Tasks that refresh the colour when the space, the screens or the appearance change.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Follows the Shelf's frame at most every 0.1 s, with its latest frame.
    @ObservationIgnored private let frameThrottle = Debouncer(delay: .milliseconds(100))

    /// Captures the menu bar and wallpaper every 5 seconds, only while the Shelf is visible.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    func performSetup(with shelfPanel: HolzBarShelfPanel) {
        self.shelfPanel = shelfPanel
        configureObservers()
    }

    private func configureObservers() {
        guard let shelfPanel else {
            return
        }

        observations = [
            shelfPanel.observe(\.screen, options: [.initial, .new]) { [weak self] panel, _ in
                Task { @MainActor in
                    guard let self, let screen = panel.screen, screen == .main else {
                        return
                    }
                    updateWindowImage(for: screen)
                }
            },
            shelfPanel.observe(\.isVisible, options: [.initial, .new]) { [weak self] panel, _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    // The capture timer exists only while the Shelf is visible: a hidden
                    // Shelf shows no colour, so capturing for it only woke holzBar.
                    if panel.isVisible {
                        startRefreshTimer()
                        refresh()
                    } else {
                        stopRefreshTimer()
                    }
                }
            },
            shelfPanel.observe(\.frame, options: [.initial, .new]) { [weak self] panel, _ in
                Task { @MainActor in
                    self?.frameThrottle.throttle(latest: true) { [weak self, weak panel] in
                        guard
                            let self,
                            let panel,
                            let screen = panel.screen,
                            panel.isVisible,
                            screen == .main
                        else {
                            return
                        }
                        withAnimation(.interactiveSpring) {
                            self.updateColorInfo(with: panel.frame, screen: screen)
                        }
                    }
                }
            },
        ]

        let notifications: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (DistributedNotificationCenter.default(), DistributedNotificationCenter.interfaceThemeChangedNotification),
        ]
        observerTasks = notifications.map { center, name in
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    self?.refresh()
                }
            }
        }
    }

    /// Starts capturing every 5 seconds (with a tolerance, so macOS can coalesce it).
    func startRefreshTimer() {
        guard refreshTask == nil else {
            return
        }
        refreshTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
                } catch {
                    return
                }
                self?.refresh()
            }
        }
    }

    /// Stops the periodic capture.
    func stopRefreshTimer() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Captures the menu bar and wallpaper and, while the Shelf is visible, updates its colour.
    private func refresh() {
        guard
            let shelfPanel,
            let screen = shelfPanel.screen,
            screen == .main
        else {
            return
        }
        updateWindowImage(for: screen)
        if shelfPanel.isVisible {
            withAnimation {
                self.updateColorInfo(with: shelfPanel.frame, screen: screen)
            }
        }
    }

    private func updateWindowImage(for screen: NSScreen) {
        // Nothing captures the screen before Screen Recording is granted; the previous
        // colour stays.
        guard ScreenCapture.cachedCheckPermissions() else {
            return
        }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard let image = ScreenCapture.captureWindows(
            with: [menuBarWindow.windowID, wallpaperWindow.windowID],
            screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
            option: .nominalResolution
        ) else {
            return
        }

        windowImage = image
    }

    private func updateColorInfo(with frame: CGRect, screen: NSScreen) {
        guard let image = windowImage else {
            return
        }

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        let insetScreenFrame = screen.frame.insetBy(dx: frame.width / 2, dy: 0)
        let percentage = ((frame.midX - insetScreenFrame.minX) / insetScreenFrame.width).clamped(to: 0...1)

        let cropRect = CGRect(x: imageBounds.width * percentage, y: 0, width: 0, height: 1)
            .insetBy(dx: -150, dy: 0)
            .intersection(imageBounds)

        guard
            let croppedImage = image.cropping(to: cropRect),
            let averageColor = croppedImage.averageColor()
        else {
            return
        }

        // Just use `menuBarWindow` as the source for now, regardless
        // of whether its image contributed to the average.
        colorInfo = MenuBarAverageColorInfo(color: averageColor, source: .menuBarWindow)
    }

    func updateAllProperties(with frame: CGRect, screen: NSScreen) {
        updateWindowImage(for: screen)
        updateColorInfo(with: frame, screen: screen)
    }

    /// One flat colour for macOS 27, where the menu bar window cannot be captured.
    ///
    /// Item images are cut out of a capture of the bar, so a colour read off the bar
    /// would only match the moment of that capture: when a dark window later sits under
    /// the menu bar, or the holzBar Shelf opens on the other display, the panel and the items
    /// disagree. A flat colour that follows the system appearance always agrees with the
    /// glyphs, which the capture takes in that same appearance.
    static func flatColor27() -> CGColor {
        var color = NSColor.windowBackgroundColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? color
        }
        return color.cgColor
    }

    /// Sets the flat macOS 27 colour.
    func setColor27() {
        colorInfo = MenuBarAverageColorInfo(color: Self.flatColor27(), source: .menuBarWindow)
    }
}
