// P1 probe of phase 93: who sends the "reopen" Apple event that macOS gives a running app when it
// is launched again (Dock icon, Finder, Spotlight, Siri, ...)? holzBar opens Settings on a reopen;
// on macOS 27 Siri causes reopens the user did not ask for, so holzBar needs to tell the senders
// apart. This is a tiny Dock-visible app that only logs. Public AppKit and Apple event calls only:
// no network, no private API, and it starts no process.
//
// Build it into a signed (ad hoc) app bundle in the git-ignored build folder:
//
//   APP=build/phase93/ReopenProbe.app
//   mkdir -p "$APP/Contents/MacOS"
//   /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string ReopenProbe" \
//       -c "Add :CFBundleIdentifier string com.holzcloud.holzBar.ReopenProbe" \
//       -c "Add :CFBundlePackageType string APPL" \
//       "$APP/Contents/Info.plist"
//   swiftc -O Scripts/macos27/reopen-probe.swift -o "$APP/Contents/MacOS/ReopenProbe"
//   codesign --force --sign - "$APP"
//
// LSUIElement is deliberately not set: the app is a regular application with a Dock icon, which
// is what receives reopen events.
//
// Open it once (`open build/phase93/ReopenProbe.app`), leave it running, and then launch it again
// by each of these paths, one at a time, with a pause between them:
//
//   - its Dock icon
//   - a Finder double-click on ReopenProbe.app
//   - Spotlight, then Return
//   - Launchpad or Apps
//   - `open -a ReopenProbe` in Terminal
//   - Raycast or Alfred, if installed
//   - a chat in the Siri app that opens it ("open ReopenProbe")
//   - running a Shortcut with the Open App action
//
// Every reopen appends one line to ~/Library/Logs/ReopenProbe.log: the time, whether the current
// Apple event was nil, the sender process identifier and bundle identifier, the original sender
// (process identifier and bundle identifier), whether the app had visible windows, and, 300 ms
// later, whether the app was active. Missing values print as nil. The log names third-party
// launchers, so it stays in the private probes folder and never goes into a public file.
import AppKit

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 90),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ReopenProbe"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let senderPID = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
            .map { Int32($0.int32Value) }
        let original = event?.attributeDescriptor(forKeyword: AEKeyword(keyOriginalAddressAttr))?
            .coerce(toDescriptorType: DescType(typeKernelProcessID))
        let originalPID = original.map { Int32($0.int32Value) }
        let line = [
            ISO8601DateFormatter().string(from: Date()),
            "currentAppleEvent nil: \(event == nil)",
            "sender pid: \(Self.text(senderPID))",
            "sender: \(Self.bundle(senderPID))",
            "original pid: \(Self.text(originalPID))",
            "original: \(Self.bundle(originalPID))",
            "hasVisibleWindows: \(flag)",
        ].joined(separator: "; ")
        Self.append(line)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            Self.append("  300 ms later: isActive: \(NSApp.isActive)")
        }
        return false
    }

    private static func text(_ value: Int32?) -> String {
        value.map { String($0) } ?? "nil"
    }

    private static func bundle(_ processIdentifier: Int32?) -> String {
        guard let processIdentifier else { return "nil" }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier ?? "nil"
    }

    private static func append(_ line: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ReopenProbe.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = Delegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
