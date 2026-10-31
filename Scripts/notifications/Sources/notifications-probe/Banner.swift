//
//  Banner.swift
//  notifications
//
//  The Accessibility observer on the Notification Center process and the read of a banner's
//  subtree. Every read is reduced to roles, subroles, identifiers and text lengths before a
//  line is written; the known texts (`--title`, `--body`) are compared inside the process
//  and only two booleans leave it. A string attribute is printed only with `--show-values`.
//

import AppKit
import ApplicationServices
import Foundation
import NotificationProbeCore

/// Accessibility elements and observers are reference types that any thread may use; these
/// wrappers hand them to the queue that reads or registers.
struct UncheckedElement: @unchecked Sendable {
    let element: AXUIElement
}

struct UncheckedObserver: @unchecked Sendable {
    let observer: AXObserver
}

/// Set by the interrupt handler; the run ends at the next turn of its loop and still writes
/// the report.
nonisolated(unsafe) var interrupted: sig_atomic_t = 0

/// What a run of `ax-banner` gave: an exit code when it could not start, else the
/// observation of its trigger.
struct BannerOutcome {
    var exitCode: Int32?
    var observation: TriggerObservation?
}

enum Banner {
    /// How long each call into the target waits for it to answer.
    static let messagingTimeout: Float = 0.25

    /// The Accessibility notifications asked for, as the criteria name them.
    static let notificationNames = [
        kAXWindowCreatedNotification,
        kAXCreatedNotification,
        kAXLayoutChangedNotification,
    ]

    static func run(_ options: Options) -> BannerOutcome {
        guard AXIsProcessTrusted() else {
            Out.emit("STEP this terminal has no Accessibility: grant it in System Settings, Privacy and Security, Accessibility, then quit the terminal and open it again")
            return BannerOutcome(exitCode: 3)
        }
        guard let target = NotificationCenterTarget.find() else {
            Out.emit("STEP no Notification Center process is running")
            return BannerOutcome(exitCode: 5)
        }
        Out.emit(ProbeLine.line("TARGET", [
            ("bundle", target.bundle),
            ("process", target.process),
            ("pid", String(target.pid)),
        ]))

        let application = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let watch = BannerWatch(options: options, application: application)
        guard let observer = register(target.pid, watch: watch, application: application) else {
            // No notification could be added: the process refused the observer, which the
            // criteria count as NO-GO, with no event.
            return BannerOutcome(observation: Verdict.observe(posted: options.post, eventCount: 0, samples: []))
        }
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        watch.resetTriggerClock()

        signal(SIGINT) { _ in interrupted = 1 }
        if options.post, let title = options.title, let body = options.body {
            Out.emit("STEP posting one test notification; watching for \(options.seconds) seconds (Ctrl-C ends the run early)")
            Post.start(title: title, body: body, watch: watch)
        } else {
            Out.emit("STEP trigger the notification of your app now; watching for \(options.seconds) seconds (Ctrl-C ends the run early)")
        }

        let end = DispatchTime.now().uptimeNanoseconds + UInt64(options.seconds) * 1_000_000_000
        while interrupted == 0, !watch.isBlocked, DispatchTime.now().uptimeNanoseconds < end {
            CFRunLoopRunInMode(.defaultMode, 0.5, true)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)

        let result = watch.finish()
        if result.blocked {
            Out.emit("STEP the target did not answer within 2 seconds; the run ended")
        }
        let observation = Verdict.observe(posted: options.post, eventCount: result.events, samples: result.samples)
        return BannerOutcome(observation: observation)
    }

    /// Creates the observer and adds the notifications off the main thread, each call bounded
    /// by the messaging timeout. A notification that is unsupported or timed out is a STEP
    /// line, never an error. Returns nil when none could be added.
    private static func register(_ pid: pid_t, watch: BannerWatch, application: AXUIElement) -> AXObserver? {
        let queue = DispatchQueue(label: "notifications-probe.register", qos: .userInitiated)
        let group = DispatchGroup()
        let wrappedApplication = UncheckedElement(element: application)
        nonisolated(unsafe) var created: UncheckedObserver?
        nonisolated(unsafe) var added = 0
        let context = Unmanaged.passUnretained(watch).toOpaque()
        let contextBox = UnsafeSendable(pointer: context)
        group.enter()
        queue.async {
            var observer: AXObserver?
            guard AXObserverCreate(pid, bannerCallback, &observer) == .success, let observer else {
                Out.emit("STEP the observer could not be created")
                group.leave()
                return
            }
            for name in notificationNames {
                let result = AXObserverAddNotification(observer, wrappedApplication.element, name as CFString, contextBox.pointer)
                if result == .success {
                    added += 1
                    Out.emit("STEP registered \(name)")
                } else {
                    Out.emit("STEP not registered \(name) (AXError \(result.rawValue))")
                }
                // A process that did not answer once would cost the next wait too.
                if result == .cannotComplete {
                    break
                }
            }
            created = UncheckedObserver(observer: observer)
            group.leave()
        }
        if group.wait(timeout: .now() + 10) == .timedOut {
            Out.emit("STEP registering the observer did not finish within 10 seconds")
            return nil
        }
        return added > 0 ? created?.observer : nil
    }
}

/// A raw pointer that is only handed to the C callback as its context.
struct UnsafeSendable: @unchecked Sendable {
    let pointer: UnsafeMutableRawPointer
}

/// The observer's callback; it runs on the main run loop.
private let bannerCallback: AXObserverCallback = { _, element, notification, context in
    guard let context else {
        return
    }
    let watch = Unmanaged<BannerWatch>.fromOpaque(context).takeUnretainedValue()
    watch.handle(element: element, name: notification as String)
}

enum NotificationCenterTarget {
    struct Target {
        let bundle: String?
        let process: String?
        let pid: pid_t
    }

    /// The Notification Center process: the application whose bundle is `NotificationCenter.app`
    /// (not `UserNotificationCenter.app`).
    static func find() -> Target? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleURL?.lastPathComponent == "NotificationCenter.app" }
            .map {
                Target(
                    bundle: $0.bundleIdentifier,
                    process: $0.executableURL?.lastPathComponent,
                    pid: $0.processIdentifier
                )
            }
    }
}

/// The events of one run and the reads they trigger. The callback runs on the main thread;
/// the subtree is read on a serial queue so a slow target never holds the run loop.
final class BannerWatch: @unchecked Sendable {
    /// Events beyond this many are counted but not read.
    static let maximumReads = 20
    /// A read that takes longer is reported as blocked and ends the run.
    static let blockedAfterNanoseconds: UInt64 = 2_000_000_000

    private let options: Options
    private let application: AXUIElement
    private let lock = NSLock()
    private let readQueue = DispatchQueue(label: "notifications-probe.read", qos: .userInitiated)
    private var triggerStart = DispatchTime.now().uptimeNanoseconds
    private var events = 0
    private var samples = [ReadSample]()
    private var blocked = false

    init(options: Options, application: AXUIElement) {
        self.options = options
        self.application = application
    }

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    /// Starts the clock the EVENT times count from: the start of the run, or the start of the
    /// post when the probe posts the trigger itself.
    func resetTriggerClock(to nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        triggerStart = nanoseconds
        lock.unlock()
    }

    /// Called on the main thread for every Accessibility event.
    func handle(element: AXUIElement, name: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        events += 1
        let number = events
        let start = triggerStart
        lock.unlock()
        let eventMs = (Double(now) - Double(start)) / 1_000_000
        Out.emit(ProbeLine.line("EVENT", [
            ("n", String(number)),
            ("name", name),
            ("tMs", Report.millis(eventMs)),
        ]))
        guard number <= Self.maximumReads else {
            if number == Self.maximumReads + 1 {
                Out.emit("STEP more than \(Self.maximumReads) events: the further ones are counted but not read")
            }
            return
        }
        let wrapped = UncheckedElement(element: element)
        readQueue.async {
            self.read(number: number, eventMs: eventMs, element: wrapped.element)
        }
    }

    /// Waits for the reads under way and returns what the run saw.
    func finish() -> (events: Int, samples: [ReadSample], blocked: Bool) {
        readQueue.sync {}
        lock.lock()
        defer { lock.unlock() }
        return (events, samples, blocked)
    }

    // MARK: Reading

    private func read(number: Int, eventMs: Double, element: AXUIElement) {
        let began = DispatchTime.now().uptimeNanoseconds
        let deadline = began + Self.blockedAfterNanoseconds
        AXUIElementSetMessagingTimeout(element, Banner.messagingTimeout)

        let reader = TreeReader(deadline: deadline)
        var root = reader.read(element, depth: 0) ?? RawNode()
        // The element that fired may be an inner one: when it holds no text, look at the
        // application's windows too and keep the richer of the two.
        if !reader.blocked, AXTree.textNodeCount(AXTree.summarise(root)) == 0 {
            let applicationReader = TreeReader(deadline: deadline)
            let windows = applicationReader.readWindows(of: application)
            if AXTree.textNodeCount(AXTree.summarise(windows)) > 0 {
                root = windows
                Out.emit("STEP read \(number) used the application's windows")
            }
            reader.blocked = reader.blocked || applicationReader.blocked
        }
        let readMs = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000

        if reader.blocked {
            Out.emit(ProbeLine.line("BANNER", [
                ("n", String(number)), ("trigger", options.trigger), ("textNodes", nil),
                ("titleMatch", nil), ("bodyMatch", nil), ("readMs", Report.millis(readMs)), ("nodes", "blocked"),
            ]))
            lock.lock()
            blocked = true
            samples.append(ReadSample(
                eventMs: eventMs, readMs: readMs, textNodes: 0, titleMatched: nil, bodyMatched: nil, blocked: true
            ))
            lock.unlock()
            return
        }

        let infos = AXTree.summarise(root)
        let textNodes = AXTree.textNodeCount(infos)
        // The comparison with the known texts happens here; the texts go no further.
        let texts = AXTree.allTexts(root)
        let titleMatch = options.title.map { expected in texts.contains { TextMatcher.matches($0, expected: expected) } }
        let bodyMatch = options.body.map { expected in texts.contains { TextMatcher.matches($0, expected: expected) } }

        for info in infos {
            Out.emit(ProbeLine.line("NODE", [
                ("n", String(number)),
                ("depth", String(info.depth)),
                ("role", info.role),
                ("subrole", info.subrole),
                ("identifier", options.showValues ? info.identifier : AXTree.printableIdentifier(info.identifier)),
                ("textLen", info.textLength.map(String.init)),
            ]))
        }
        if options.showValues {
            for text in texts {
                Out.emit(ProbeLine.line("VALUE", [("n", String(number)), ("text", text)]))
            }
        }
        Out.emit(ProbeLine.line("BANNER", [
            ("n", String(number)),
            ("trigger", options.trigger),
            ("textNodes", String(textNodes)),
            ("titleMatch", titleMatch.map(Report.yesNo)),
            ("bodyMatch", bodyMatch.map(Report.yesNo)),
            ("readMs", Report.millis(readMs)),
            ("nodes", String(infos.count)),
        ]))
        lock.lock()
        samples.append(ReadSample(
            eventMs: eventMs, readMs: readMs, textNodes: textNodes, titleMatched: titleMatch, bodyMatched: bodyMatch
        ))
        lock.unlock()
    }
}

/// Copies a subtree out of Accessibility into `RawNode` values, to the depth and node caps
/// of the core and before a deadline; a call that does not answer within the messaging
/// timeout yields nothing for that attribute.
final class TreeReader {
    var blocked = false
    private var count = 0
    private let deadline: UInt64

    init(deadline: UInt64) {
        self.deadline = deadline
    }

    func read(_ element: AXUIElement, depth: Int) -> RawNode? {
        guard depth <= AXTree.defaultMaximumDepth, count < AXTree.defaultMaximumNodes else {
            return nil
        }
        if DispatchTime.now().uptimeNanoseconds > deadline {
            blocked = true
            return nil
        }
        count += 1
        var node = RawNode(
            role: string(element, kAXRoleAttribute),
            subrole: string(element, kAXSubroleAttribute),
            identifier: string(element, kAXIdentifierAttribute),
            texts: [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .compactMap { string(element, $0) }
                .filter { !$0.isEmpty }
        )
        if depth < AXTree.defaultMaximumDepth {
            node.children = elements(element, kAXChildrenAttribute).compactMap { read($0, depth: depth + 1) }
        }
        return node
    }

    /// The application with its windows as children.
    func readWindows(of application: AXUIElement) -> RawNode {
        var node = RawNode(role: "AXApplication")
        node.children = elements(application, kAXWindowsAttribute).compactMap { read($0, depth: 1) }
        return node
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }
}
