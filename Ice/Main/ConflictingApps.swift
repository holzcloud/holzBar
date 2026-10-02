//
//  ConflictingApps.swift
//  Ice
//

import AppKit
import OSLog

/// Keeps holzIce from running alongside another menu bar manager.
///
/// Two managers fight over the same items. The original Ice in particular sees
/// holzIce's section dividers as items of its own to arrange and keeps moving
/// them: every move hides the pointer and posts synthetic mouse events, so in a
/// loop the pointer disappears and nothing on the screen can be clicked until
/// the Mac restarts. holzIce therefore asks to quit such an app before it starts.
@MainActor
enum ConflictingApps {
    private static let logger = Logger(category: "ConflictingApps")

    /// Bundle identifiers of menu bar managers that conflict with holzIce.
    private static let bundleIdentifiers: Set<String> = [
        "com.jordanbaird.Ice",
        "com.surteesstudios.Bartender",
        "com.dwarvesv.minimalbar",
    ]

    /// Names of conflicting menu bar managers whose bundle identifier is not known.
    private static let names: Set<String> = ["Ice", "Thaw", "Bartender", "Hidden Bar"]

    /// The running menu bar managers other than holzIce.
    static var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app != .current else {
                return false
            }
            if let bundleIdentifier = app.bundleIdentifier, bundleIdentifiers.contains(bundleIdentifier) {
                return true
            }
            return app.localizedName.map(names.contains) ?? false
        }
    }

    /// Asks to quit any other running menu bar manager, and quits it.
    ///
    /// - Returns: `false` if the user chose to quit holzIce instead.
    static func resolve() -> Bool {
        let apps = running
        guard !apps.isEmpty else {
            return true
        }
        let names = apps.compactMap(\.localizedName).joined(separator: ", ")
        logger.notice("Other menu bar managers are running: \(names, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit \(names) first?"
        alert.informativeText = """
            holzIce and \(names) would both try to manage the menu bar. They get in \
            each other's way, and can leave the pointer unable to click anything. \
            holzIce can quit \(names) for you.
            """
        alert.addButton(withTitle: "Quit \(names) and Continue")
        alert.addButton(withTitle: "Quit holzIce")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }

        for app in apps {
            app.terminate()
        }
        let deadline = Date.now.addingTimeInterval(3)
        while apps.contains(where: { !$0.isTerminated }), Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
        }
        for app in apps where !app.isTerminated {
            logger.warning("\(app.localizedName ?? "An app", privacy: .public) did not quit, forcing it")
            app.forceTerminate()
        }
        return true
    }
}
