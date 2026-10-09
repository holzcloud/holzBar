// Prints every public signal that could report the user's transparency and Liquid Glass
// choices, once or on every public change, so a person can see on macOS 27 which of them
// react while the Liquid Glass slider moves (UAT item U-13 of phase 23, spike M27-04).
//
// Public API only: no private framework, no class or selector looked up by name, no system
// preference file or defaults domain read. Notification names are printed, never their
// payload or sender.
//
// Build and run:
//
//   swiftc -O Scripts/macos27/glass-signals.swift -o /tmp/glass-signals
//   /tmp/glass-signals --once                       one snapshot, then exit
//   /tmp/glass-signals                              watch mode, until interrupted (Ctrl-C)
//   /tmp/glass-signals --all-notifications          watch mode plus every notification name
//
// (It also compiles with `-swift-version 6`.)
//
// Procedure of U-13, on macOS 27: start watch mode, open System Settings, Appearance, and
// move the Liquid Glass slider across its three steps while the probe runs; then paste the
// output into 23-01-SPIKE.md under "Observations". A snapshot line reads
//
//   t=<seconds> <event> reduceTransparency=<bool> increaseContrast=<bool>
//       differentiateWithoutColor=<bool> reduceMotion=<bool> appearance=<name>
//       glassStyle=<raw value or n/a> glassTint=<description or nil>
//
// The glass style and tint come from a freshly created NSGlassEffectView on purpose: if the
// system ever surfaced the user's glass choice in a default, it would show there.
//
// In --all-notifications mode the probe's own application posts a burst of NSApplication
// notifications at start; those lines are noise. A name seen only while the slider moves is
// what matters. A name that appears in no SDK header is recorded in the spike note and never
// used by holzBar.
import AppKit

// Lines reach a pipe or a file as they are printed, not when the buffer fills.
setvbuf(stdout, nil, _IOLBF, 0)

@MainActor
final class GlassSignals {
    let once = CommandLine.arguments.contains("--once")
    let allNotifications = CommandLine.arguments.contains("--all-notifications")
    let startTime = ProcessInfo.processInfo.systemUptime

    // Observer tokens stay alive for the life of the process.
    var observers: [any NSObjectProtocol] = []
    var appearanceObservation: NSKeyValueObservation?

    func stamp() -> String {
        String(format: "t=%.1f", ProcessInfo.processInfo.systemUptime - startTime)
    }

    func snapshot(_ event: String) {
        let workspace = NSWorkspace.shared
        var style = "n/a"
        var tint = "n/a"
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            style = String(view.style.rawValue)
            tint = view.tintColor.map { String(describing: $0) } ?? "nil"
        }
        print(
            "\(stamp()) \(event)"
                + " reduceTransparency=\(workspace.accessibilityDisplayShouldReduceTransparency)"
                + " increaseContrast=\(workspace.accessibilityDisplayShouldIncreaseContrast)"
                + " differentiateWithoutColor=\(workspace.accessibilityDisplayShouldDifferentiateWithoutColor)"
                + " reduceMotion=\(workspace.accessibilityDisplayShouldReduceMotion)"
                + " appearance=\(NSApp.effectiveAppearance.name.rawValue)"
                + " glassStyle=\(style) glassTint=\(tint)"
        )
    }

    func printNotification(center: String, name: String) {
        print("\(stamp()) notification \(center) \(name)")
    }

    /// Observes a public change and prints a snapshot named after it.
    func snapshotOn(_ center: NotificationCenter, _ name: Notification.Name, event: String) {
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { [self] _ in
                MainActor.assumeIsolated { snapshot(event) }
            }
        )
    }

    /// Observes every notification of a center without a name filter and prints its name only.
    func printAll(_ center: NotificationCenter, label: String) {
        observers.append(
            center.addObserver(forName: nil, object: nil, queue: .main) { [self] notification in
                let name = notification.name.rawValue
                MainActor.assumeIsolated { printNotification(center: label, name: name) }
            }
        )
    }

    func run() {
        let application = NSApplication.shared
        // An accessory application: a probe with a Dock icon would take the front from
        // whatever is being watched.
        application.setActivationPolicy(.accessory)

        if once {
            snapshot("snapshot")
            exit(0)
        }

        print("\(allNotifications ? "watch mode with all notifications" : "watch mode"), interrupt to stop")
        snapshot("snapshot")

        snapshotOn(
            NSWorkspace.shared.notificationCenter,
            NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            event: "accessibilityDisplayOptionsDidChange"
        )
        snapshotOn(
            .default, NSApplication.didChangeScreenParametersNotification, event: "didChangeScreenParameters"
        )
        snapshotOn(.default, NSColor.systemColorsDidChangeNotification, event: "systemColorsDidChange")
        appearanceObservation = application.observe(\.effectiveAppearance, options: [.new]) { [self] _, _ in
            MainActor.assumeIsolated { snapshot("effectiveAppearanceDidChange") }
        }

        if allNotifications {
            printAll(.default, label: "default")
            printAll(NSWorkspace.shared.notificationCenter, label: "workspace")
            printAll(DistributedNotificationCenter.default(), label: "distributed")
        }

        application.run()
    }
}

MainActor.assumeIsolated { GlassSignals().run() }
