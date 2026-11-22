//
//  DiagnosticsReport.swift
//  holzBar
//

import Foundation

/// The facts of a bug report, already reduced to what is safe to share.
///
/// Every text field holds a version or an identifier of the system, never a name the user
/// chose; ``DiagnosticsReport`` still cleans each of them. The numbers count things (items,
/// profiles) and name none.
nonisolated struct DiagnosticsInput: Equatable, Sendable {
    var appVersion = ""
    var appBuild = ""
    var macOSVersion = ""
    var macOSBuild = ""
    /// The Mac's model identifier, such as `Mac15,6`; never the serial number or the name.
    var modelIdentifier = ""
    var architecture = ""
    /// The way items are read and moved, which depends on the macOS generation.
    var backend = ""
    var displayCount = 0
    var displaysWithNotch = 0
    var accessibilityGranted = false
    var screenRecordingGranted = false
    var launchesAtLogin = false
    var visibleItems = 0
    var hiddenItems = 0
    var alwaysHiddenItems = 0
    var profileCount = 0
    var groupCount = 0
    var spacerCount = 0
    var automationRuleCount = 0
    var snapshotCount = 0
    /// The state of macOS 27's own overflow control at the last read (none, collapsed, expanded
    /// or unknown). Empty before macOS 27, so the report of earlier versions stays as it was.
    var nativeOverflow = ""
    /// The state of the Apple Items module (macOS 27 only): off, or on with the number of hidden
    /// system items, whether they are applied and the number of replacements. Empty before
    /// macOS 27, so the report of earlier versions stays as it was.
    var appleItems = ""
    /// The last drop of Drag in the Menu Bar in fixed words (generation, zone, intent, result),
    /// such as `macOS 27, shelf, hide, applied`. Empty before the first drop or while the module
    /// is off, so the report stays as it was.
    var lastDrop = ""
    /// The last Command-drag that could set a section in fixed words and numbers
    /// (``CommandDragSection/summary(waitedMilliseconds:reads:decision:outcome:)``), such as
    /// `waited 1200 ms, 1 read, set hidden, applied`. Empty before the first one or while the
    /// switch is off, so the report stays as it was. Never a name.
    var lastCommandDrag = ""
    /// What the hiding fixes of 1.0.5 did, in fixed words and counts
    /// (``DiagnosticsReport/hidingSummary27(reveal:agentRestarts:lateAllowlist:youngRetries:forcedReads:heldBack:notchRechecks:hiddenAnyway:tapDisables:)``
    /// or ``DiagnosticsReport/hidingSummaryBefore27(anchor:iconPutBack:)``), such as `anchor
    /// icon, icon put back 0`. Empty keeps the report as it was. Never a name.
    var hiding = ""
    /// The last click on a Shelf tile in fixed words, such as `shown, clicked` or `failed, not
    /// shown and not reachable`. Empty before the first click or before macOS 27.
    var lastShelfClick = ""
    /// The Shelf's style and location in fixed lower-case words, such as `floating, screen
    /// edge`. Empty unless the Shelf is in use, so the report of a Mac that does not use it
    /// stays as it was.
    var shelf = ""
    /// Whether Accessory alerts can read accessory batteries on this Mac: one of the fixed words
    /// `available`, `not available` or `off`. Empty unless the module is on, so the report of a
    /// Mac that does not use it stays as it was. Never a device name.
    var accessoryBattery = ""
    /// The last clicks in the menu bar as ``BarClickTrace`` wrote them: numbers and fixed words
    /// only. Empty before the first click, so the report of a Mac without clicks stays as it was.
    var barClicks: [String] = []
    /// How many reopens of the running app opened Settings and how many were ignored, in
    /// fixed words (``DiagnosticsReport/reopenSummary(opened:ignored:)``), such as `opened 1,
    /// ignored 3`. Empty while holzBar got no reopen, so the report stays as it was. Never
    /// the name of a sender.
    var reopen = ""
    /// What the shared system readouts monitor does, in counts and fixed words
    /// (``DiagnosticsReport/readoutsSummary(visible:background:observers:isTimerArmed:samples:)``),
    /// such as `visible 2, background 0, observers 1, timer on, samples 314`, or `idle, samples
    /// 12` while nothing is measured. Counts of the monitor only, never a reading, an interface
    /// or a device name (D-14). Empty keeps the report as it was.
    var readouts = ""
    /// What System alerts does, in counts and fixed words
    /// (``DiagnosticsReport/alertsSummary(isModuleOn:rulesOn:firing:notifications:)``), such as
    /// `rules 4, firing 1, notifications allowed`, or `off` while the module is off. Never a
    /// reading, a threshold value, an alert title or a name (D-04). Empty keeps the report as it
    /// was.
    var alerts = ""
}

/// Writes the text a user can copy into a bug report. It holds an allowlist of facts and
/// nothing else: no item or application names, no profile, rule or network names, no paths,
/// no user or computer name. It also names the state of macOS 27's overflow button (a fixed
/// word, still no names).
nonisolated enum DiagnosticsReport {
    /// The longest text kept for the last drop, whose fixed words (the longest line is `macOS 27,
    /// outsideBar, refused, outside the bar, not applied`) are longer than other fields.
    static let maximumLastDropLength = 64

    /// The longest text kept for the last command-drag (the longest line has five-digit waiting
    /// time, two-digit reads and `ignored: not an app item`).
    static let maximumLastCommandDragLength = 80

    /// The longest text kept for the Hiding line (the longest reveal word, the breaker word and
    /// seven counts, each capped at five digits, fit with their words).
    static let maximumHidingLength = 240

    /// The longest text kept for the System readouts line (four counts of five digits, their
    /// words and the timer word fit).
    static let maximumReadoutsLength = 96

    /// The longest text kept for the System alerts line (two counts of five digits, their words and
    /// the longest notification word fit).
    static let maximumAlertsLength = 80

    /// The longest text kept for a field.
    static let maximumFieldLength = 40

    /// The report as plain text, in English: it is meant for an issue.
    static func make(_ input: DiagnosticsInput) -> String {
        var lines = [
            "holzBar: \(field(input.appVersion)) (\(field(input.appBuild)))",
            "macOS: \(field(input.macOSVersion)) (\(field(input.macOSBuild)))",
            "Mac: \(field(input.modelIdentifier)), \(field(input.architecture))",
            "Backend: \(field(input.backend))",
            "Displays: \(input.displayCount), with a notch: \(input.displaysWithNotch)",
            "Accessibility: \(yesNo(input.accessibilityGranted))",
            "Screen Recording: \(yesNo(input.screenRecordingGranted))",
            "Launch at login: \(yesNo(input.launchesAtLogin))",
            "Items: \(input.visibleItems) visible, \(input.hiddenItems) hidden, \(input.alwaysHiddenItems) always hidden",
            "Profiles: \(input.profileCount), groups: \(input.groupCount), spacers: \(input.spacerCount)",
            "Automation rules: \(input.automationRuleCount), snapshots: \(input.snapshotCount)",
        ]
        if !input.nativeOverflow.isEmpty {
            lines.append("macOS 27 overflow: \(field(input.nativeOverflow))")
        }
        if !input.appleItems.isEmpty {
            lines.append("Apple Items: \(field(input.appleItems))")
        }
        if !input.lastDrop.isEmpty {
            lines.append("Last drop: \(field(input.lastDrop, limit: maximumLastDropLength))")
        }
        if !input.lastCommandDrag.isEmpty {
            lines.append("Last command-drag: \(field(input.lastCommandDrag, limit: maximumLastCommandDragLength, punctuation: ":"))")
        }
        if !input.hiding.isEmpty {
            lines.append("Hiding: \(field(input.hiding, limit: maximumHidingLength))")
        }
        if !input.lastShelfClick.isEmpty {
            lines.append("Last Shelf click: \(field(input.lastShelfClick, limit: maximumLastDropLength))")
        }
        if !input.shelf.isEmpty {
            lines.append("Shelf: \(field(input.shelf))")
        }
        if !input.accessoryBattery.isEmpty {
            lines.append("Accessory battery: \(field(input.accessoryBattery))")
        }
        if !input.readouts.isEmpty {
            lines.append("System readouts: \(field(input.readouts, limit: maximumReadoutsLength))")
        }
        if !input.alerts.isEmpty {
            lines.append("System alerts: \(field(input.alerts, limit: maximumAlertsLength))")
        }
        if !input.reopen.isEmpty {
            lines.append("Reopen: \(field(input.reopen))")
        }
        for (index, click) in input.barClicks.suffix(BarClickTrace.capacity).enumerated() {
            lines.append("Click \(index + 1): \(field(click, limit: maximumClickLength))")
        }
        return lines.joined(separator: "\n")
    }

    /// The Hiding line on macOS 27: the reveal state the concealment follows, how often the
    /// fixes of 1.0.5 acted (MenuBarAgent restarts, allowlist refreshes for apps read late, young
    /// apps asked again, reads forced and held back by busy apps, notch rechecks) and how many
    /// visible apps MenuBarAgent cannot name and so hides anyway (found by their install location
    /// or by `HiddenAnyway27`; a count, never a name) and how often macOS disabled the click
    /// bridge's event tap.
    ///
    /// - Parameters:
    ///   - reveal: One of the fixed words `all hidden`, `hidden revealed`, `all revealed`.
    ///   - breaker: One of the fixed words `ok`, `tripped` (``AgentRestartBreaker``).
    static func hidingSummary27(
        reveal: String,
        agentRestarts: Int,
        breaker: String,
        lateAllowlist: Int,
        youngRetries: Int,
        forcedReads: Int,
        heldBack: Int,
        notchRechecks: Int,
        hiddenAnyway: Int,
        tapDisables: Int
    ) -> String {
        [
            "reveal \(word(reveal))",
            "agent restarts \(count(agentRestarts))",
            "breaker \(word(breaker))",
            "late allowlist \(count(lateAllowlist))",
            "young retries \(count(youngRetries))",
            "forced reads \(count(forcedReads))",
            "held back \(count(heldBack))",
            "notch rechecks \(count(notchRechecks))",
            "hidden anyway \(count(hiddenAnyway))",
            "tap disables \(count(tapDisables))",
        ].joined(separator: ", ")
    }

    /// The Hiding line before macOS 27: what the last menu bar hit test took the bar's state
    /// from and how often a read put the holzBar icon back right of the hidden divider.
    ///
    /// - Parameter anchor: One of the fixed words `icon`, `divider`, `none`.
    static func hidingSummaryBefore27(anchor: String, iconPutBack: Int) -> String {
        "anchor \(word(anchor)), icon put back \(count(iconPutBack))"
    }

    /// The Reopen line: how many reopens of the running app (a click on the Dock icon, a
    /// double-click in the Finder, Spotlight, Launchpad, or another sender) opened Settings and
    /// how many were ignored. Counts only, never who sent them.
    static func reopenSummary(opened: Int, ignored: Int) -> String {
        "opened \(count(opened)), ignored \(count(ignored))"
    }

    /// The System readouts line: how many consumers of the shared monitor show a surface and how
    /// many watch, how many events it observes, whether its one timer is armed and how many
    /// samples it took; `idle, samples N` while no consumer and no observer exists, which is
    /// what "measures nothing" looks like. Counts and fixed words only, never a reading or a name.
    static func readoutsSummary(visible: Int, background: Int, observers: Int, isTimerArmed: Bool, samples: Int) -> String {
        guard visible > 0 || background > 0 || observers > 0 else {
            return "idle, samples \(count(samples))"
        }
        let timer = isTimerArmed ? "on" : "off"
        return "visible \(count(visible)), background \(count(background)), observers \(count(observers)), "
            + "timer \(timer), samples \(count(samples))"
    }

    /// The System alerts line: `off` while the module is off, else how many rules are on, how many
    /// alerts are firing and the state of the optional notifications. Counts and fixed words only,
    /// never a reading, a threshold, an alert title or a name.
    ///
    /// - Parameter notifications: One of the fixed words `off`, `not asked`, `allowed`, `denied`.
    static func alertsSummary(isModuleOn: Bool, rulesOn: Int, firing: Int, notifications: String) -> String {
        guard isModuleOn else {
            return "off"
        }
        return "rules \(count(rulesOn)), firing \(count(firing)), notifications \(word(notifications))"
    }

    /// A fixed word of a summary: lowercase letters and spaces only.
    private static func word(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz ")
        return String(text.lowercased().filter { allowed.contains($0) })
    }

    /// The highest count a summary shows; a higher one shows as this, so the line always fits.
    static let maximumSummaryCount = 99_999

    /// A count of a summary, never negative and at most ``maximumSummaryCount``.
    private static func count(_ value: Int) -> String {
        String(min(max(0, value), maximumSummaryCount))
    }

    /// The longest text kept for a click of the trace (the longest line has a dozen extents).
    static let maximumClickLength = 400

    private static func yesNo(_ value: Bool) -> String {
        value ? "granted or on" : "not granted or off"
    }

    /// The text of a field: only letters, digits and the punctuation of versions and model
    /// identifiers, shortened. Anything else, such as a path or a line break, is dropped.
    ///
    /// - Parameters:
    ///   - limit: The most characters kept.
    ///   - punctuation: More characters to keep, for a field of fixed words that uses them.
    static func field(_ text: String, limit: Int = maximumFieldLength, punctuation: String = "") -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,-_" + punctuation)
        let cleaned = String(text.filter { allowed.contains($0) }.prefix(limit))
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}
