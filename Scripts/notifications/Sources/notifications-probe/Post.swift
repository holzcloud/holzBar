//
//  Post.swift
//  notifications
//
//  Trigger T1: the probe posts one test notification itself with `osascript -e 'display
//  notification ...'` after the observer is registered, and starts the clock the EVENT times
//  count from. This is the only file that starts a process; the probe is a throwaway that
//  ships nowhere, so the app's rule on starting processes does not apply to it.
//

import Foundation

enum Post {
    /// The text as an AppleScript string literal's content: backslash and double quote escaped.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func script(title: String, body: String) -> String {
        "display notification \"\(escape(body))\" with title \"\(escape(title))\""
    }

    /// Starts `osascript` off the main thread. The clock of `watch` is set at the moment the
    /// process is started, so the first event's time counts from the start of `osascript`.
    static func start(title: String, body: String, watch: BannerWatch) {
        let script = script(title: title, body: body)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                watch.resetTriggerClock()
                try process.run()
                process.waitUntilExit()
                Out.emit("STEP osascript ended with status \(process.terminationStatus); if no banner appears, allow Script Editor in System Settings, Notifications")
            } catch {
                Out.emit("STEP osascript could not be started")
            }
        }
    }
}
