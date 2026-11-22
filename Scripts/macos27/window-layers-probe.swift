// P8 probe of phase 93: which windows sit near the top of each display, at which layer, and how
// big are they? holzBar's auto-rehide needs to know the layer of a menu bar item's tooltip, which
// layers an app's popup uses on macOS 27 and how thin an edge window of a KVM or hot-border app is.
// Read-only: public CoreGraphics and AppKit calls only, no permission (owner, layer and bounds
// come without Screen Recording), no network, no private API, nothing is changed.
//
//   swift Scripts/macos27/window-layers-probe.swift --delay 3 2>&1 | tee ~/Desktop/tooltip.txt
//
// Rest the pointer on a menu bar item during the delay so its tooltip is on screen, or open an
// app's popover or popup from its item. The probe prints each display's bounds and menu bar
// height (frame.maxY - visibleFrame.maxY, at least the top safe area), then every on-screen window
// whose top lies within 120 points of a display's top or whose smaller side is under 8 points:
// owner process identifier, owner bundle identifier (or "other"), layer, bounds, alpha and whether
// its top lies above the bottom of that display's menu bar.
//
// Options:
//   --delay <s>      seconds to wait before the first snapshot (default 0)
//   --repeat <n>     number of snapshots (default 1)
//   --interval <s>   seconds between two snapshots (default 1)
//   --names          print non-Apple bundle identifiers instead of "other"
//   --help
import AppKit

struct Options {
    var delay = 0.0
    var repeatCount = 1
    var interval = 1.0
    var names = false
}

func parseOptions() -> Options {
    var parsed = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--delay":
            if let value = arguments.first, let seconds = Double(value) {
                parsed.delay = max(0, seconds)
                arguments.removeFirst()
            }
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
        case "--names":
            parsed.names = true
        case "--help", "-h":
            print("usage: swift window-layers-probe.swift [--delay S] [--repeat N] [--interval S] [--names]")
            exit(0)
        default:
            print("unknown option \(argument), see --help")
            exit(64)
        }
    }
    return parsed
}

func number(_ value: CGFloat) -> String {
    let rounded = (Double(value) * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", rounded)
}

func ownerName(_ processIdentifier: pid_t, names: Bool) -> String {
    let bundleID = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    guard let bundleID else { return "unknown" }
    return names || bundleID.hasPrefix("com.apple.") ? bundleID : "other"
}

/// A display with its bounds in the top-left coordinate space CoreGraphics windows use.
struct Display {
    let id: UInt32
    let bounds: CGRect
    let menuBarHeight: CGFloat
}

func displays() -> [Display] {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSScreen.screens.map { screen in
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let id = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
        let frame = screen.frame
        let bounds = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let height = max(frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
        return Display(id: id, bounds: bounds, menuBarHeight: height)
    }
}

func snapshot(_ options: Options) {
    let all = displays()
    print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    for display in all {
        let bounds = display.bounds
        print("display \(display.id): bounds \(number(bounds.minX)),\(number(bounds.minY)) \(number(bounds.width)) x \(number(bounds.height)), menu bar height \(number(display.menuBarHeight))")
    }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        print("no window list")
        return
    }
    var shown = 0
    for entry in list {
        guard let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              let owner = entry[kCGWindowOwnerPID as String] as? Int32 else { continue }
        let thin = min(bounds.width, bounds.height) < 8
        guard let display = all.first(where: { $0.bounds.insetBy(dx: -1, dy: -1).intersects(bounds) }) ?? all.first else { continue }
        let nearTop = bounds.minY - display.bounds.minY < 120 && bounds.minY - display.bounds.minY > -120
        guard nearTop || thin else { continue }
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
        let aboveBottom = bounds.minY < display.bounds.minY + display.menuBarHeight
        print("owner \(owner) \(ownerName(owner, names: options.names)) layer \(layer) bounds \(number(bounds.minX)),\(number(bounds.minY)) \(number(bounds.width)) x \(number(bounds.height)) alpha \(String(format: "%.2f", alpha)) topAboveMenuBarBottom \(aboveBottom ? "yes" : "no")")
        shown += 1
    }
    print("windows listed: \(shown)")
}

let options = parseOptions()
if options.delay > 0 {
    Thread.sleep(forTimeInterval: options.delay)
}
for round in 1...options.repeatCount {
    if options.repeatCount > 1 { print("--- snapshot \(round) ---") }
    snapshot(options)
    if round < options.repeatCount {
        Thread.sleep(forTimeInterval: options.interval)
    }
}
