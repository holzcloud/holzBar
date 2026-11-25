// P3 probe of phase 93: does NSRunningApplication see MenuBarAgent, and does terminating it bring
// the menu bar (and holzBar's hiding) back? This is the probe behind holzBar's "Restart menu bar"
// command (D-07). Public AppKit calls only: no network, no private API, and it never starts a
// process.
//
// Read-only by default:
//
//   swift Scripts/macos27/agent-probe.swift 2>&1 | tee ~/Desktop/agent.txt
//
// It prints MenuBarAgent's bundle identifier, process identifier, activation policy, whether it
// is terminated and its bundle path, and the process identifiers of Control Centre, the Dock and
// the Finder, or "not running".
//
// Only --force-terminate changes anything. It restarts the menu bar of this Mac: it prints a
// warning, waits 3 seconds (Control-C stops it), remembers the old process identifier, calls
// forceTerminate(), prints its result, and then checks every 100 ms for up to 10 seconds for a
// MenuBarAgent with a new process identifier and prints how many milliseconds it took.
//
//   swift Scripts/macos27/agent-probe.swift --force-terminate
//   swift Scripts/macos27/agent-probe.swift --force-terminate --repeat 5 --interval 10
//
// Options:
//   --force-terminate   terminate MenuBarAgent once (see above)
//   --repeat <n>        repeat the termination n times (default 1), for the breaker test
//   --interval <s>      seconds between two repetitions (default 10)
//   --help
import AppKit

let agentBundleID = "com.apple.MenuBarAgent"

func activationPolicyWord(_ policy: NSApplication.ActivationPolicy) -> String {
    switch policy {
    case .regular: "regular"
    case .accessory: "accessory"
    case .prohibited: "prohibited"
    @unknown default: "unknown"
    }
}

func agent() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first
}

func processIdentifierLine(_ bundleID: String) -> String {
    guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        return "\(bundleID): not running"
    }
    return "\(bundleID): \(application.processIdentifier)"
}

func printState() {
    if let application = agent() {
        print("bundle identifier: \(application.bundleIdentifier ?? "nil")")
        print("process identifier: \(application.processIdentifier)")
        print("activation policy: \(application.activationPolicy.rawValue) (\(activationPolicyWord(application.activationPolicy)))")
        print("isTerminated: \(application.isTerminated)")
        print("bundle path: \(application.bundleURL?.path ?? "nil")")
    } else {
        print("\(agentBundleID): not running")
    }
    for bundleID in ["com.apple.controlcenter", "com.apple.dock", "com.apple.finder"] {
        print(processIdentifierLine(bundleID))
    }
}

struct Options {
    var forceTerminate = false
    var repeatCount = 1
    var interval = 10.0
}

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--force-terminate":
            parsed.forceTerminate = true
        case "--repeat":
            if let value = arguments.first, let count = Int(value) {
                parsed.repeatCount = max(1, count)
                arguments.removeFirst()
            }
        case "--interval":
            if let value = arguments.first, let seconds = Double(value) {
                parsed.interval = max(0, seconds)
                arguments.removeFirst()
            }
        case "--help", "-h":
            print("usage: swift agent-probe.swift [--force-terminate [--repeat N] [--interval SECONDS]]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
    return parsed
}

func terminateAndWait(round: Int) {
    guard let application = agent() else {
        print("round \(round): \(agentBundleID) is not running, nothing to terminate")
        return
    }
    let oldProcessIdentifier = application.processIdentifier
    let start = ProcessInfo.processInfo.systemUptime
    let result = application.forceTerminate()
    print("round \(round): old process identifier \(oldProcessIdentifier), forceTerminate() returned \(result)")
    let deadline = start + 10
    while ProcessInfo.processInfo.systemUptime < deadline {
        Thread.sleep(forTimeInterval: 0.1)
        let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == agentBundleID }
        if let running, running.processIdentifier != oldProcessIdentifier {
            let milliseconds = Int((ProcessInfo.processInfo.systemUptime - start) * 1000)
            print("round \(round): back after \(milliseconds) ms with process identifier \(running.processIdentifier)")
            return
        }
    }
    print("round \(round): not back after 10 s")
}

let options = parseOptions()
printState()

if options.forceTerminate {
    print("")
    print("WARNING: this restarts the menu bar of this Mac in 3 seconds. Control-C stops it.")
    Thread.sleep(forTimeInterval: 3)
    for round in 1...options.repeatCount {
        terminateAndWait(round: round)
        if round < options.repeatCount {
            Thread.sleep(forTimeInterval: options.interval)
        }
    }
    print("")
    printState()
}
