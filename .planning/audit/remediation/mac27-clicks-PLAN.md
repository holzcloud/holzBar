---
phase: audit-remediation-mac27-clicks
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - holzBar/MenuBar/MacOS27/Core/ItemClick27.swift
  - holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift
  - Tests/HolzBarMacOS27CoreTests/Plan2Core27Tests.swift
  - Tests/HolzBarMacOS27CoreTests/ClickBridge27Tests.swift
  - holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift
  - Tests/HolzBarMacOS27CoreTests/ApplyLedger27Tests.swift
  - holzBar/MenuBar/MacOS27/Concealer27.swift
  - holzBar/MenuBar/MacOS27/ItemClicker27.swift
  - holzBar/MenuBar/MacOS27/ItemImageStore27.swift
  - .planning/audit/remediation/mac27-clicks-SUMMARY.md
autonomous: true
requirements: [F-26, F-27]

estimate:
  tokens: 150000
  raw_tokens: 150000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "On macOS 27 a bridged system-item click never posts Escape at the HID level: Escape goes only to the process that owns a panel window holzBar saw open (D-01)"
    - "After Notification Center was opened through holzBar and closed by a click elsewhere, a later clock click with a banner on screen sends no Escape and opens Notification Center on the first click (D-01)"
    - "A held-back bridged click is always acted on (press or lift+replay) unless the remembered panel's window actually left the screen after Escape (D-01)"
    - "clock->clock and clock->Control Centre still close the open panel through Escape, without lifting concealment, when the panel answers Escape (D-01)"
    - "A Shelf click on a concealed app clicks the item's frame only after the concealment apply that shows the app finished successfully, plus the measured 600 ms draw delay; otherwise it presses the item through Accessibility (D-02)"
    - "photographMissing captures an app only after its show was applied; captures wait for pending applies and measure the settle time from the moment the apply finished (D-02)"
    - "Glyphs stored before this fix are photographed again once (item image store version 10) (D-02)"
  artifacts:
    - path: holzBar/MenuBar/MacOS27/Core/ItemClick27.swift
      provides: "PanelWindow, OpenPanel, PanelMemory, BridgeStep, firstStep, stepAfterDismissal, openedPanel (pure, swift-tested)"
      contains: "struct PanelMemory"
    - path: holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift
      provides: "Numbered concealment applies and their waiters (pure, swift-tested)"
      contains: "struct ApplyLedger27"
    - path: Tests/HolzBarMacOS27CoreTests/ClickBridge27Tests.swift
      provides: "Tests of the bridge decision and panel memory"
      contains: "ClickBridgeStep27Tests"
    - path: Tests/HolzBarMacOS27CoreTests/ApplyLedger27Tests.swift
      provides: "Tests of the apply ledger"
      contains: "ApplyLedger27Tests"
    - path: holzBar/MenuBar/MacOS27/Concealer27.swift
      provides: "showTemporarily(bundleID:) async -> Bool, waitForPendingApplies()"
      contains: "func waitForPendingApplies"
  key_links:
    - from: SystemItemClickBridge27.handle(_:)
      to: ItemClick27.PanelMemory / ItemClick27.firstStep / stepAfterDismissal
      via: "panelMemory.forget() on let-through clicks, takeForBridgedClick() on bridged ones"
    - from: SystemItemClickBridge27 Escape helper
      to: CGEvent.postToPid(_:)
      via: "owner PID stored in OpenPanel from windowsForPanelCheck()"
    - from: Concealer27 apply Task (update)
      to: ApplyLedger27.finish -> CheckedContinuation.resume
      via: "applyFinished(_:succeeded:)"
    - from: ItemClicker27.click and ItemImageStore27.photographMissing
      to: Concealer27.showTemporarily(bundleID:) async -> Bool
      via: "await, then 600 ms draw delay only when true"
    - from: ItemImageStore27.performCapture
      to: Concealer27.waitForPendingApplies()
      via: "awaited before timeUntilSettled()"
---

# mac27-clicks: F-26 (click bridge Escape) and F-27 (Shelf clicks and photos on stale frames)

Audit remediation chain `mac27`, part `clicks`. Worktree:
`/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks`
(branch `audit-manual/mac27-clicks`, based on `audit/remediation-2026-10-05`).

**Relayed user message (not part of this part's scope).** The user's message that started this
run asks, in German, whether the *signing* could be solved differently after all. Neither F-26 nor
F-27 involves code signing; the signing questions belong to the `release` part (F-05, F-10, F-11,
F-52, F-53, F-54; decision `release-1.md`). This plan does not answer or change anything about
signing. The orchestrator must route that question back to the user (multiple choice, per
CLAUDE.md) before the `release` part runs. The executor of this plan must not touch release,
signing or CI files.

**Decision IDs used below**

| ID | Source | Chosen option |
|----|--------|---------------|
| D-01 | `scratchpad/decisions/mac27-clicks-1.md` (F-26) | "Escape nur ans Panel (Recommended)": remember a panel only when it really opened, send Escape only to its owner, replay otherwise |
| D-02 | `scratchpad/decisions/mac27-clicks-2.md` (F-27) | "Auf echte Freigabe warten (Recommended)": click and photograph only once macOS applied the show (about 3 s bound), otherwise Accessibility press / no photo; re-photograph glyphs once |

Rejected options (must NOT be implemented): F-26 "Nur Audit-Vorschlag umsetzen" and "Escape-Abkürzung
ganz streichen"; F-27 "Nur Audit-Vorschlag umsetzen" and "Vorerst nichts ändern"; F-27 audit
alternative 3 (wait until the item's frame differs from the concealed one).

<objective>
Close F-26 and F-27 on macOS 27 exactly as the maintainer decided (D-01, D-02), with the decision
logic in pure, swift-tested types in `holzBar/MenuBar/MacOS27/Core`, the app-target wiring kept
thin, and one atomic commit per finding.

Purpose: a clock click must never send Escape to the app in front (a dialog or sheet would cancel,
fullscreen would end) or swallow the click; a click or photo in the holzBar Shelf must never hit
the item that happens to stand at a concealed app's stale frame.

Output: two commits (`fix(macos27): resolve F-26 …`, `fix(macos27): resolve F-27 …`), new Core
types `ItemClick27.PanelMemory`/`BridgeStep`/`OpenPanel` and `ApplyLedger27` with tests, and
`.planning/audit/remediation/mac27-clicks-SUMMARY.md`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
Absolute paths. WT = the worktree above; SP = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`.

- Decisions: `SP/decisions/mac27-clicks-1.md` (D-01), `SP/decisions/mac27-clicks-2.md` (D-02).
- Findings: `WT/.planning/audit/FULL-AUDIT-2026-10-05.md`, sections "#### F-26" (line 1084) and
  "#### F-27" (line 1119); related F-01 (line 169, the broken timeout helper), F-74, F-77 (already
  fixed on this branch).
- Rules: `WT/CLAUDE.md` (English everywhere, modern Swift 6, events over polling, privacy in logs,
  naming, persisted keys never renamed), `WT/.swiftlint.yml` (file header, trailing commas,
  no force unwrapping).
- Code (read once each):
  - `WT/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift` (300 lines; `handle(_:)` 77-177,
    comments 124-135, remembered-item property 40-42, `windowsForPanelCheck()` 214-223, Escape
    helper 229-238, `waitForPanel` 240-249).
  - `WT/holzBar/MenuBar/MacOS27/Core/ItemClick27.swift` (67 lines).
  - `WT/Tests/HolzBarMacOS27CoreTests/Plan2Core27Tests.swift` lines 101-129 and 391-450.
  - `WT/holzBar/MenuBar/MacOS27/Concealer27.swift` (771 lines; `update()` 210-281,
    `applyDidFail` 289-309, `suspend` 475-488, `suspendReleased` 496-517, `timeUntilSettled`
    564-568, `showTemporarily`/`endTemporaryShow` 570-612).
  - `WT/holzBar/MenuBar/MacOS27/ItemClicker27.swift` (118 lines).
  - `WT/holzBar/MenuBar/MacOS27/ItemImageStore27.swift` (520 lines; `storeVersion` 31-38, `init`
    88-118, `performCapture` 204-304, `photographMissing` 306-345).
  - `WT/holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift` lines 98-128 (the
    resume-once continuation raced by a sleep that D-02 names as the pattern).
  - `WT/holzBar/MenuBar/MacOS27/Core/LaunchGrace27.swift` and
    `WT/Tests/HolzBarMacOS27CoreTests/Displays27Tests.swift` lines 57-100 (Core value-type and
    test style: `nonisolated struct`, mutate outside `#expect`).
- Callers verified (do not change their call style): sync `showTemporarily(bundleID:)` is called
  from `MenuBarManager.revealBriefly(itemKey:)` (sync, `holzBar/MenuBar/MenuBarManager.swift:543`)
  and `Concealer27.applicationDidLaunch(bundleID:)` (sync, line 177). The only async callers are
  `ItemClicker27.click` and `ItemImageStore27.photographMissing`, which switch to the new async
  overload.
- Already on this branch (prerequisites, do not redo): F-74 (appearance observation installed
  before the version check, commits 77da3ee6 and a95eef60), F-77 (apply retry, 0ea4b9a8 and
  ea01023d), F-78 (suspension owner, 95fa7a10 and b77a6ed8), F-46 and F-58 (image store discards
  and ordered file I/O).
- Measurement caveats from history (read, do not re-measure): commit 230ab8d ("a banner is drawn
  in the same window as Notification Center's panel"); header comment of
  `WT/Scripts/macos27/system-click.swift` ("Notification Center can keep a full-screen host window
  on screen with its panel closed (measured)").
- Probes already run by the planner (no need to repeat): a sync method and an `async -> Bool`
  overload with the same label resolve correctly under the project's flags (sync context picks
  the sync one; an un-awaited call in an async context is a compile error, not a silent switch);
  `CGEvent.postToPid(_:)` typechecks with deployment target 14.0; a generic ledger with
  `CheckedContinuation` waiters and a `PanelMemory` value type typecheck with
  `-default-isolation MainActor` and approachable concurrency.
</context>

## Interfaces to create (signatures only; the executor writes the bodies)

In `holzBar/MenuBar/MacOS27/Core/ItemClick27.swift` (inside `nonisolated enum ItemClick27`):

```swift
typealias PanelWindow = (number: Int, layer: Int, height: CGFloat, ownerPID: Int32)

nonisolated struct OpenPanel: Equatable, Sendable {
    let item: String      // the system item's identifier
    let window: Int       // the panel's window number
    let ownerPID: Int32   // the process that draws the panel
}

nonisolated struct PanelMemory {
    private(set) var panel: OpenPanel?
    private(set) var click: Int
    mutating func forget()
    mutating func takeForBridgedClick() -> (remembered: OpenPanel?, click: Int)
    mutating func remember(_ opened: OpenPanel?, openedBy click: Int)
}

nonisolated enum BridgeStep: Equatable {
    case dismiss(OpenPanel)
    case press
    case liftAndReplay
}

static func panelWindow(before: Set<Int>, windows: [PanelWindow]) -> Int?          // type change only
static func panelOpened(before: Set<Int>, windows: [PanelWindow]) -> Bool          // type change only
static func openPanelWindow(windows: [PanelWindow]) -> Int?                        // type change only
static func panelIsOnScreen(window: Int, windows: [PanelWindow]) -> Bool           // type change only
static func firstStep(remembered: OpenPanel?, windows: [PanelWindow], mayOpenFromPress: Bool) -> BridgeStep
static func stepAfterDismissal(of panel: OpenPanel, clickedItem: String?, windowWent: Bool,
                               windows: [PanelWindow], mayOpenFromPress: Bool) -> BridgeStep?
static func openedPanel(item: String?, before: Set<Int>, windows: [PanelWindow]) -> OpenPanel?
```

New file `holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift`:

```swift
nonisolated struct ApplyLedger27<Waiter> {
    private(set) var lastQueued: Int        // 0 before the first apply
    private(set) var lastFinished: Int
    private(set) var lastSucceeded: Bool    // true before the first apply
    var hasPending: Bool { get }            // lastFinished < lastQueued
    var nextApply: Int { get }              // lastQueued + 1
    mutating func queue() -> Int
    mutating func wait(for apply: Int, waiter: Waiter) -> Int?     // nil = already finished
    mutating func finish(_ apply: Int, succeeded: Bool) -> [Waiter]
    mutating func abandon(_ id: Int) -> Waiter?
}
```

In `Concealer27` (app target, `@MainActor`):

```swift
func showTemporarily(bundleID: String) async -> Bool      // new overload; the sync one stays
func waitForPendingApplies() async
```

## Source audit (GOAL / REQ / RESEARCH / CONTEXT)

| Source item | Covered by |
|-------------|-----------|
| GOAL: macOS 27 clock clicks never send Escape to the front app nor swallow the click | Task 1 |
| GOAL: Shelf clicks and photos never act on a stale frame | Task 2 |
| REQ F-26 | Task 1 |
| REQ F-27 | Task 2 |
| D-01a replace the remembered-item String with (item, window, ownerPID); add ownerPID to `windowsForPanelCheck()` | Task 1 A2, C1, C5 |
| D-01b remember only a NEW panel window: press path via `panelWindow(before:windows:)`; replay path baseline before `replayClick`, poll 50 ms x 8 | Task 1 A7, C4, C7 |
| D-01c forget on every left mouse down the bridge lets through | Task 1 A3, C3 |
| D-01d dismiss only while `panelIsOnScreen(window:windows:)`; otherwise forget, normal path, no Escape | Task 1 A5 |
| D-01e Escape with `CGEvent.postToPid(ownerPID)` | Task 1 C6 |
| D-01f poll up to about 200 ms for the window to go; if it stays, lift+replay (not press) | Task 1 A6, C8 |
| D-01g never return without acting on the held-back click unless the window went | Task 1 A6 + tests |
| D-01h generation counter for rapid double clicks | Task 1 A3 (`PanelMemory.click`) |
| D-01i decision as a pure function in ItemClick27.swift with swift tests | Task 1 A, B |
| D-01j update the comments at SystemItemClickBridge27.swift:124-135 | Task 1 C10 |
| D-01k/D-02k no new user-facing strings | Task 3 gate (strings-check) |
| D-02a number each apply; the apply Task records completion and success; resume continuation waiters | Task 2 A, C3-C5 |
| D-02b `showTemporarily(bundleID:) async -> Bool`, about 3 s, resume-once continuation raced by a sleep, not the shared timeout helper (F-01) | Task 2 C5, C6 |
| D-02c early returns: suspended -> wait for the update at suspension end; paused/unavailable -> false | Task 2 C2, C6 |
| D-02d set `lastChangeAt` when an apply finishes | Task 2 C4, C8 |
| D-02e `performCapture` waits for pending applies before its settle wait | Task 2 E2 |
| D-02f `ItemClicker27.click`: await the show, keep 600 ms; on false the AX element path | Task 2 D |
| D-02g `photographMissing`: await the show; on false skip the capture and record not stored | Task 2 E1 |
| D-02h `storeVersion` "10", only together with the F-74 fix (present on this branch) | Task 2 E3 + precondition |
| D-02i keep the sync `showTemporarily` for revealBriefly and the launch grace | Task 2 C6 |
| D-02j bookkeeping as a pure type in Core with swift tests | Task 2 A, B |
| D-01l/D-02l maintainer verification on macOS 27 | "Manual test on macOS 27" section |
| RESEARCH: F-01 pitfall (timeout helper never times out) | Task 2 C5 + negative grep |
| RESEARCH: banner may share the panel's window (230ab8d) | Task 1 (D-01c/e/f safeguards), Risk R3 |
| RESEARCH: NC may keep a host window on screen (system-click.swift) | Risk R2, manual test M4 |

Planner's discretion (documented, consistent with the decisions):
- **X1 (Task 1 A5):** with no remembered panel but a panel-sized NC/CC window already on screen,
  a press-eligible item (Control Centre) takes lift+replay, not the press. Without this, D-01c
  (forget on a click inside the panel) would make the next Control Centre click press an open
  Control Centre: the press closes it, no new window appears, Control Centre is learned as
  "ignores the press", and the replay then opens it again. The existing comment at 133-135 already
  states this intent ("a panel opened some other way is closed by the replayed click").
- **X2 (Task 1 C2):** `stop()` forgets the remembered panel, because the stopped tap can no longer
  see the clicks that close it (same reasoning as D-01c).
- **X3 (Task 1 C9):** the fixed 120 ms post-Escape wait is replaced by the D-01f window poll,
  which waits exactly as long as the panel takes to go.
- The decision's `openPanel` tuple is implemented as `ItemClick27.OpenPanel` (same three fields,
  Equatable for tests) held in `PanelMemory.panel` together with the D-01h click counter.

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (F-26): remember only a panel holzBar saw open, dismiss it with Escape to its owner, replay otherwise</name>
  <files>holzBar/MenuBar/MacOS27/Core/ItemClick27.swift, Tests/HolzBarMacOS27CoreTests/Plan2Core27Tests.swift, Tests/HolzBarMacOS27CoreTests/ClickBridge27Tests.swift, holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift</files>
  <read_first>
    - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/mac27-clicks-1.md (D-01, whole file)
    - WT/.planning/audit/FULL-AUDIT-2026-10-05.md lines 1084-1117 (F-26)
    - WT/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift (whole file)
    - WT/holzBar/MenuBar/MacOS27/Core/ItemClick27.swift (whole file)
    - WT/Tests/HolzBarMacOS27CoreTests/Plan2Core27Tests.swift lines 101-129 and 391-450
    - WT/Scripts/macos27/system-click.swift lines 1-7 (host-window caveat)
  </read_first>
  <behavior>
    New file Tests/HolzBarMacOS27CoreTests/ClickBridge27Tests.swift, header as in the other test files (import CoreGraphics, Foundation, Testing, @testable import HolzBarMacOS27Core). Window literals typed `[ItemClick27.PanelWindow]`; use NC panel window 45 (layer 21, height 1080, owner 300), CC panel window 46 (layer 101, height 964, owner 400), a banner window 47 (layer 21, height 1080, owner 300), clock id "com.apple.menuextra.clock", Control Centre id "com.apple.menuextra.controlcenter".
    Suite "Click bridge steps" (struct ClickBridgeStep27Tests):
    - Remembered NC panel (window 45) with window 45 on screen, clock clicked -> firstStep == .dismiss(panel)
    - Remembered NC panel whose window 45 is gone while banner window 47 is up, clock (mayOpenFromPress false) -> .liftAndReplay (no Escape for a stale memory; the F-26 scenario)
    - No remembered panel, banner window 47 up, clock -> .liftAndReplay (never Escape without a remembered panel)
    - No remembered panel, nothing on screen, Control Centre (mayOpenFromPress true) -> .press
    - No remembered panel, CC window 46 already up, Control Centre -> .liftAndReplay (X1: a press would close it and be learned as ignoring the press)
    - stepAfterDismissal: window went, clicked item == panel.item -> nil (the click is done)
    - stepAfterDismissal: window went, another item clicked, nothing left on screen, mayOpenFromPress true -> .press; mayOpenFromPress false -> .liftAndReplay
    - stepAfterDismissal: window stayed -> .liftAndReplay, for the same item, for another item, and even when mayOpenFromPress is true (never return without acting, never the press)
    - stepAfterDismissal: clicked item nil (overflow button), window went -> not nil (the click still opens)
    - openedPanel: window 45 new since baseline [10, 11], item clock -> OpenPanel(item: clock, window: 45, ownerPID: 300)
    - openedPanel: window 45 already in the baseline (a banner window reused) -> nil
    - openedPanel: item nil -> nil; a new window of height 28 or layer 0 -> nil
    Suite "Panel memory" (struct PanelMemory27Tests; mutate outside #expect as LaunchGrace27Tests does):
    - remember(panel, openedBy: the click taken) then takeForBridgedClick() returns that panel and leaves panel nil
    - forget() drops a remembered panel
    - a panel opened by click 1 is not remembered after click 2 was taken (rapid double click)
    - a panel opened by a bridged click is not remembered after forget() (a click let through meanwhile)
    - the latest click's remember(nil, openedBy:) clears the memory
    Existing suite "System item panel" in Plan2Core27Tests.swift: only the literal types change to `[ItemClick27.PanelWindow]` with an `ownerPID:` element added to each tuple; every expectation stays as it is.
  </behavior>
  <action>
    Work in WT only. Write the tests of the behavior block first and run them (RED: they do not compile yet), then implement (GREEN). Per D-01 throughout; no audit IDs in code or comments; English; match the file's comment style (measured facts, why); SwiftLint file header on the new test file is not required (Tests are not linted) but keep the same header comment block as the other test files.

    A. Core, holzBar/MenuBar/MacOS27/Core/ItemClick27.swift (pure, nonisolated, swift-tested; D-01i):
    A1. Add the typealias PanelWindow (number, layer, height, ownerPID: Int32) with a doc comment ("a window on screen that may be a system item's panel, with the process that draws it"). Change the windows parameter of panelWindow(before:windows:), panelOpened(before:windows:), openPanelWindow(windows:) and panelIsOnScreen(window:windows:) to [PanelWindow]. Keep their return types and behavior. Factor the layer >= panelLayer and height > panelHeight rule into a private static isPanel(_:) used by panelWindow and openedPanel.
    A2. Add nonisolated struct OpenPanel: Equatable, Sendable with item (String), window (Int), ownerPID (Int32), documented as "a system item's panel that holzBar saw open after a bridged click" (this is D-01's (item, window, ownerPID) state).
    A3. Add nonisolated struct PanelMemory (D-01c, D-01h): private(set) var panel: OpenPanel? and private(set) var click = 0. forget() increments click and sets panel to nil. takeForBridgedClick() increments click, returns (the panel held before, the new click number) and sets panel to nil (the bridged click either closes that panel or proves it gone). remember(_:openedBy:) stores the given panel (or nil) only when openedBy equals the current click, so a panel found after a later click arrived is dropped. Doc comments say why: a click the bridge lets through can close the panel (a click on the desktop closes Notification Center), and a banner can show in the same window afterwards (measured on macOS 27.0).
    A4. Add nonisolated enum BridgeStep: Equatable with cases dismiss(OpenPanel), press, liftAndReplay, each documented.
    A5. Add static func firstStep(remembered:windows:mayOpenFromPress:) -> BridgeStep (D-01d): when remembered is non-nil and panelIsOnScreen(window: remembered.window, windows:) holds, return .dismiss(remembered). Otherwise, when mayOpenFromPress is true and openPanelWindow(windows:) is nil, return .press. Otherwise return .liftAndReplay (X1: a panel already up that holzBar did not see open is closed by the replayed click, as it would be without holzBar; a press would close it, look like a press the item ignores, and the replay would open it again).
    A6. Add static func stepAfterDismissal(of:clickedItem:windowWent:windows:mayOpenFromPress:) -> BridgeStep? (D-01f, D-01g): when windowWent is false return .liftAndReplay (never .press: the replayed click also closes the other panel). When the window went and clickedItem equals panel.item return nil (the click did its job). Otherwise return firstStep(remembered: nil, windows: windows, mayOpenFromPress: mayOpenFromPress).
    A7. Add static func openedPanel(item:before:windows:) -> OpenPanel? (D-01b): nil when item is nil; otherwise the first window not in before that isPanel, as OpenPanel(item, its number, its ownerPID).

    B. Tests: create ClickBridge27Tests.swift with the two suites of the behavior block, and update the eight window literals in SystemPanel27Tests (Plan2Core27Tests.swift 391-450) to the new element type. Run the filtered swift test until green.

    C. App target, holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift (D-01):
    C1. Replace the remembered-item String property at lines 40-42 with private var panelMemory = ItemClick27.PanelMemory(), doc comment: the panel holzBar saw open after a bridged click, forgotten whenever a click may have closed it unseen. Do not mention the old property's name in any comment.
    C2. In stop(), after tap.disable(), call panelMemory.forget() (X2).
    C3. In handle(_:), in the else branch of the ClockBridgeZone27.shouldBridge guard (the click is let through), call panelMemory.forget() before returning the event (D-01c). The replayed-click guard and the mouse-up branch return earlier and must not touch the memory (the replay is what opens the panel). For a bridged click, take let taken = panelMemory.takeForBridgedClick() right before creating the Task and use taken.remembered and taken.click inside it.
    C4. Rewrite the Task body as this sequence: (1) var step = ItemClick27.firstStep(remembered: taken.remembered, windows: Self.windowsForPanelCheck(), mayOpenFromPress: mayOpenFromPress). (2) If step is .dismiss(panel): post Escape to panel.ownerPID (C6); let went = await Self.waitForPanelToGo(window: panel.window, polls: Self.escapeAnswerPolls) (C8); log the outcome (debug, timing as .public); then guard let next = ItemClick27.stepAfterDismissal(of: panel, clickedItem: systemItem?.identifier, windowWent: went, windows: Self.windowsForPanelCheck(), mayOpenFromPress: mayOpenFromPress) else return; step = next. (3) If step is .press and systemItem is non-nil: baseline = Self.windowNumbers(); await Self.press(systemItem.element); if let opened = await Self.waitForOpenedPanel(item: systemItem.identifier, baseline: baseline, polls: 5) then self.panelMemory.remember(opened, openedBy: taken.click) and return; otherwise insert the identifier into systemItemsIgnoringPress as today. (4) Lift and replay as today (clock cover, suspendReleased, timing log), but take let baseline = Self.windowNumbers() immediately before Self.replayClick(at:); after clockCover.hide(after:) and the existing log line, let opened = await Self.waitForOpenedPanel(item: systemItem?.identifier, baseline: baseline, polls: 8) (Notification Center's window appears about 166 ms after the click, measured on macOS 27.0) and self.panelMemory.remember(opened, openedBy: taken.click). The unconditional assignment after the replay disappears.
    C5. windowsForPanelCheck() returns [ItemClick27.PanelWindow]: same owner filter, map adds ownerPID: window.ownerPID. Update its doc comment.
    C6. Replace the Escape helper with private static func postEscape(to pid: pid_t) that builds the same key down and key up (virtual key 53, CGEventSource hidSystemState) and delivers each with postToPid(pid), not at the HID event tap. Doc comment: Escape at the HID level reaches whichever app has keyboard focus, so a dialog or sheet in front was cancelled or fullscreen ended; addressed to the panel's own process it can reach nothing else. Whether Notification Center and Control Centre act on an Escape sent to their process is not measured yet; when they do not, the click is replayed (C4 step 2).
    C7. Replace waitForPanel(baseline:pollsOf50ms:) -> Bool with private static func waitForOpenedPanel(item: String?, baseline: Set<Int>, polls: Int) async -> ItemClick27.OpenPanel?: up to polls rounds of a 50 ms sleep followed by ItemClick27.openedPanel(item:before:windows: windowsForPanelCheck()); return the first non-nil. Bounded poll: there is no event for another process's window appearing.
    C8. Add private static func waitForPanelToGo(window: Int, polls: Int) async -> Bool: up to polls rounds of a 50 ms sleep, true as soon as ItemClick27.panelIsOnScreen(window:windows:) is false. Add private static let escapeAnswerPolls = 4 (about 200 ms; doc: how long a panel gets to answer Escape before the click is replayed instead, D-01f; measured value pending on macOS 27).
    C9. Delete the fixed post-Escape wait constant and its use (X3).
    C10. Rewrite the comment block at lines 124-135 (D-01j) to say, in the file's style: a click on the item whose panel holzBar opened, while that panel's window is still up, dismisses it with Escape and no lift of concealment; only a panel holzBar saw open in a new window is remembered, and any click the bridge lets through forgets it, because that click may have closed it and a banner shows in the same window as the panel (measured on macOS 27.0); Escape goes to the panel's own process only; unless the panel's window really goes, the held-back click is replayed, so it is never lost; a panel opened some other way is closed by the replayed click, as it would be without holzBar. Keep the existing first paragraph (why Escape instead of lifting).
    Log lines: bridgeLogger.debug only; interpolate only timings and counts with privacy: .public; no item identifiers or window titles.
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm --filter 'SystemPanel27Tests|ItemClick27Tests|ClickBridgeStep27Tests|PanelMemory27Tests'</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks mac27-clicks-f26 | tail -1 | grep -q 'ERRORS: 0  EXIT: 0'</automated>
    <automated>! grep -n 'itemShowingPanel' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift</automated>
    <automated>! grep -n 'panelDismissWait' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift</automated>
    <automated>grep -A3 'virtualKey: 53' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift | grep -q 'postToPid' && ! (grep -A3 'virtualKey: 53' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift | grep -q 'post(tap:')</automated>
    <automated>grep -n 'panelMemory.forget()' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift && grep -n 'takeForBridgedClick()' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift && grep -n 'ItemClick27.stepAfterDismissal' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift</automated>
    <human-check>Maintainer, macOS 27 session: manual tests M1-M7 below.</human-check>
  </verify>
  <acceptance_criteria>
    - Every test listed in the behavior block exists, each one fails before step A and passes after it.
    - The filtered swift test run passes; the full swift test run passes (Task 3).
    - appcheck.sh reports ERRORS: 0 for the whole app module.
    - The bridge contains no HID-tap Escape; 'itemShowingPanel' and 'panelDismissWait' no longer occur in SystemItemClickBridge27.swift.
    - The bridge forgets the panel on every left mouse down it lets through and in stop(), and acts on every held-back click unless the remembered window went (proved by the stepAfterDismissal tests).
  </acceptance_criteria>
  <done>F-26 committed atomically after the Task 3 gates pass (commit message in "Commits" below). The F-26 failure scenario (NC closed by a desktop click, later a banner, clock click with a dialog or fullscreen in front) no longer posts Escape anywhere and replays the click, so NC opens on the first click.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2 (F-27): number concealment applies, and click or photograph a shown app only once its apply landed</name>
  <files>holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift, Tests/HolzBarMacOS27CoreTests/ApplyLedger27Tests.swift, holzBar/MenuBar/MacOS27/Concealer27.swift, holzBar/MenuBar/MacOS27/ItemClicker27.swift, holzBar/MenuBar/MacOS27/ItemImageStore27.swift</files>
  <precondition>F-74 is fixed on this branch: in ItemImageStore27.init the appearanceObservation assignment comes before the version.txt check (verify: grep -n 'appearanceObservation = NSApp.observe\|let versionFile' on the file lists the observation first). If not, stop and report fix-failed for F-27 (D-02h forbids the version bump without it).</precondition>
  <read_first>
    - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/mac27-clicks-2.md (D-02, whole file)
    - WT/.planning/audit/FULL-AUDIT-2026-10-05.md lines 1119-1151 (F-27) and 169-215 (F-01, why the shared timeout helper must not be used)
    - WT/holzBar/MenuBar/MacOS27/Concealer27.swift (whole file)
    - WT/holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift lines 98-128
    - WT/holzBar/MenuBar/MacOS27/ItemClicker27.swift (whole file)
    - WT/holzBar/MenuBar/MacOS27/ItemImageStore27.swift lines 31-118 and 204-345
    - WT/holzBar/MenuBar/MacOS27/Core/LaunchGrace27.swift (style of a pure Core value type)
  </read_first>
  <behavior>
    New file Tests/HolzBarMacOS27CoreTests/ApplyLedger27Tests.swift, suite "ApplyLedger27" (struct ApplyLedger27Tests), Waiter = String, mutations outside #expect:
    - Applies are numbered 1, 2, 3 in the order they are queued; hasPending is true after queue() and false once the last queued one finished
    - A wait for a queued apply returns an id; finish(that apply, succeeded: true) returns its waiter and lastSucceeded is true
    - finish(apply, succeeded: false) returns its waiters and lastSucceeded is false
    - A wait for an apply that already finished returns nil (the caller answers with lastSucceeded at once)
    - Finishing apply 2 returns the waiters of applies 1 and 2, in the order they began waiting, and not the waiter of apply 3
    - abandon(id) returns the waiter once; a later finish no longer returns it; abandon(id) again returns nil (resume once)
    - abandon(id) after finish returned the waiter returns nil (resume once, from the other side)
    - A wait for nextApply made before queue() (a show made while concealment is suspended) is answered by the apply queue() then numbers, when it finishes
  </behavior>
  <action>
    Work in WT only. Tests first (RED), then implement (GREEN). Per D-02 throughout; no audit IDs in code or comments; English; file style.

    A. New file holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift (D-02a, D-02j) with the SwiftLint header block (two slashes, filename, holzBar, two slashes) and import Foundation. nonisolated struct ApplyLedger27 generic over Waiter, with the members listed in "Interfaces to create": lastQueued and lastFinished start at 0, lastSucceeded starts true; waiters kept as a dictionary from a running id to (apply, waiter). queue() increments and returns lastQueued. wait(for:waiter:) returns nil when apply is at most lastFinished, else stores the waiter under a new id and returns the id. finish(_:succeeded:) sets lastFinished to the maximum of itself and apply, sets lastSucceeded when apply is at least the previous lastFinished, removes and returns every waiter whose apply is at most the finished one, sorted by id. abandon(_:) removes and returns the waiter, or nil. Doc comments: why (MenuBarAgent applies a change some time after holzBar records it, so whoever needs the change on screen waits for the apply that carries it), applies finish in the order they were queued because each waits for the one before.

    B. Tests: create ApplyLedger27Tests.swift as in the behavior block; run the filtered swift test until green.

    C. holzBar/MenuBar/MacOS27/Concealer27.swift:
    C1. Add @ObservationIgnored private var applyLedger = ApplyLedger27 of CheckedContinuation of (Bool, Never), and private static let applyWaitLimit = Duration.seconds(3) with doc "MenuBarAgent answers an activation within 3 s or the activation times out (MenuBarAssessmentAssertion27), so a show that has not landed by then is not waited for".
    C2. Move the body of update() into @discardableResult private func applyChanges() -> Bool and make update() call it. Return false for the early returns when appState is nil or the assertions are unavailable and when systemActivityMonitor.isPaused; return true when concealment is suspended (the change is applied at the suspension's end) and after queueing the apply (D-02c).
    C3. In applyChanges(), take let sequence = applyLedger.queue() right before creating the apply Task. In the Task, after a successful controller.apply keep self?.failedApplies = 0 and then call self?.applyFinished(sequence, succeeded: true); in the catch keep the log line and applyDidFail(generation:) and then call self?.applyFinished(sequence, succeeded: false). Remove the stamp of lastChangeAt that update() took before queueing the apply (D-02d).
    C4. Add private func applyFinished(_ sequence: Int, succeeded: Bool): stamp lastChangeAt with the current instant (the bar starts moving when the apply lands), then resume every waiter applyLedger.finish(sequence, succeeded:) returns with succeeded.
    C5. Add private func waitForApply(_ apply: Int) async -> Bool built like MenuBarAssessmentAssertion27.activate (D-02b): withCheckedContinuation; inside, applyLedger.wait(for:waiter:) - nil means resume at once with applyLedger.lastSucceeded; otherwise start a Task that sleeps applyWaitLimit and then resumes applyLedger.abandon(id) with false if it is still there. Capture self strongly in that bounded Task so the continuation is always resumed. Do not use the shared timeout helpers in holzBar/Utilities/ConcurrencyHelpers.swift: they wait for an operation that ignores cancellation.
    C6. Add func showTemporarily(bundleID: String) async -> Bool next to the sync overload (D-02b, D-02i): increment temporarilyShown for the bundle ID directly (do not call the sync overload), let carrying = applyLedger.nextApply, guard applyChanges() else return false, return await waitForApply(carrying). Doc comment: shows an application for a moment and returns once MenuBarAgent applied the change that shows it - true when it did, false when concealment is paused or unavailable, the apply failed, or it took longer than 3 s; every call must be balanced by endTemporaryShow(bundleID:) whatever it returns. Keep the sync showTemporarily(bundleID:) and showTemporarily(bundleIDs:) unchanged (revealBriefly and the launch grace use them).
    C7. Add func waitForPendingApplies() async: return at once unless applyLedger.hasPending, else await waitForApply(applyLedger.lastQueued) and ignore the result. Doc: captures call it so they never photograph a bar whose concealment change is still on its way.
    C8. suspend(for:): remove the stamp at the top and stamp lastChangeAt with the current instant inside the release Task after controller.releaseAll() (capture self weakly there). suspendReleased(for:): remove the stamp at the top and stamp it right after await release.value. Update the doc comments of lastChangeAt ("when the last concealment change landed on the bar, which is when the bar starts moving") and timeUntilSettled().

    D. holzBar/MenuBar/MacOS27/ItemClicker27.swift, click(item:mouseButton:shelfDisplayID:appState:) (D-02f): replace the sync show and the fixed sleep with let shown = await concealer.showTemporarily(bundleID: bundleID); only when shown sleep the measured 600 ms (keep the comment, now counted from the moment the change landed). Read drawn only when shown; when not shown log a notice that the item was not shown in time and is pressed through Accessibility (item.logString with privacy .private(mask: .hash)) and take the existing element path (kAXPressAction / kAXShowMenuAction). Keep exactly one endTemporaryShow(bundleID:) on every path. Update the type's doc comment: the application is allowed, and its item is clicked where it is drawn once the change that shows it has landed; if it does not land within 3 s, the item is pressed through Accessibility instead.

    E. holzBar/MenuBar/MacOS27/ItemImageStore27.swift:
    E1. photographMissing (D-02g): let shown = await appState.concealer27.showTemporarily(bundleID: bundleID); when shown, keep the 600 ms sleep and the forced capture; always call endTemporaryShow(bundleID:); record the attempt with stored: shown and hasImage(forBundleID:). Debug log (no bundle ID) when a show did not land. Update the loop comment: each application is captured once its show has landed, not on a timer.
    E2. performCapture (D-02e): await appState.concealer27.waitForPendingApplies() before the timeUntilSettled() check; extend the comment above it.
    E3. storeVersion becomes "10" (D-02h) and the doc comment gains: version 9 could hold another item's glyph for an application photographed while the change that showed it was still on its way.
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm --filter 'ApplyLedger27Tests|LaunchGrace27Tests|ConcealmentController27Tests'</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks mac27-clicks-f27 | tail -1 | grep -q 'ERRORS: 0  EXIT: 0'</automated>
    <automated>grep -n 'await concealer.showTemporarily(bundleID: bundleID)' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemClicker27.swift && grep -n 'await appState.concealer27.showTemporarily(bundleID: bundleID)' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemImageStore27.swift && grep -n 'waitForPendingApplies()' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemImageStore27.swift && grep -n 'storeVersion = "10"' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemImageStore27.swift</automated>
    <automated>! grep -n -E 'Task\(timeout|value\(of:' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/Concealer27.swift /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemClicker27.swift /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/ItemImageStore27.swift</automated>
    <automated>! awk '/private func applyChanges/,/applyTask = task/' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks/holzBar/MenuBar/MacOS27/Concealer27.swift | grep -n 'lastChangeAt = .now'</automated>
    <human-check>Maintainer, macOS 27 session: manual tests M8-M11 below.</human-check>
  </verify>
  <acceptance_criteria>
    - Every ApplyLedger27 test of the behavior block exists, fails before step A and passes after it; the full swift test run passes (Task 3).
    - appcheck.sh reports ERRORS: 0 for the whole app module.
    - ItemClicker27.click and ItemImageStore27.photographMissing await the async show; the positional click and the capture happen only when it returned true.
    - Concealer27 contains no use of the shared timeout helpers, and applyChanges() no longer stamps lastChangeAt before the apply is queued.
    - storeVersion is "10" and the F-74 ordering (observer before version check) is unchanged.
    - The sync showTemporarily overloads and their two callers are unchanged.
  </acceptance_criteria>
  <done>F-27 committed atomically after the Task 3 gates pass (commit message in "Commits" below). A Shelf click or photo never trusts a frame read before the apply that shows the app landed; glyphs stored under the bug are retaken once.</done>
</task>

<task type="auto">
  <name>Task 3: full gate run before each commit, the two atomic commits, and the part summary</name>
  <files>.planning/audit/remediation/mac27-clicks-SUMMARY.md</files>
  <read_first>
    - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/ax-observers/.planning/audit/remediation/ax-observers-background-registration-SUMMARY.md (format of a part summary; read only, never modify another worktree)
  </read_first>
  <action>
    Run the gate set below in WT after Task 1 (then commit F-26) and again after Task 2 (then commit F-27). Never push, never switch branches, never change git config, never launch, quit or relaunch holzBar, never run tccutil or defaults write.
    Gate set, all must pass:
    G1 full swift test: cd WT, then swift test with --scratch-path SP/mac27-clicks-swiftpm. If it fails only with "plugin for module 'TestingMacros' not found", run it once more (a known flake of the Command Line Tools on this host; it passed on the second run for the planner and for the sibling part).
    G2 whole-app typecheck: zsh SP/appcheck.sh WT with label mac27-clicks-f26 or mac27-clicks-f27, last line "ERRORS: 0  EXIT: 0". This is the only local compile check of the app target (macOS 26.5 SDK, Swift 6, MainActor default isolation); CI's Xcode 27 build stays the final word.
    G3 lint: cd WT, then TOOLCHAIN_DIR=/Library/Developer/CommandLineTools SP/swiftlint/swiftlint lint --strict --quiet, no output and exit 0.
    G4 python3 .github/scripts/privacy-check.py logs, python3 .github/scripts/privacy-check.py network, python3 .github/scripts/strings-check.py (no new strings expected; the catalog count stays 369).
    G5 former name: cd WT, then the negated git grep for the former app name pattern with the excludes from .github/workflows/build.yml (.planning, .claude, .github/cms-version.py) prints nothing.
    G6 git -C WT status --short lists only the files of the finding being committed (plus the summary for the last commit).
    Commit with git -C WT add (explicit paths, never -A) and git -C WT commit, using the messages in "Commits" below verbatim (they follow the required shape: subject, 3-8 body lines, both trailers).
    After the F-27 gates pass, write .planning/audit/remediation/mac27-clicks-SUMMARY.md in the sibling format: frontmatter chain mac27, part clicks, findings [F-26, F-27], decision "mac27-clicks-1 - Escape nur ans Panel (Recommended); mac27-clicks-2 - Auf echte Freigabe warten (Recommended)", status complete; then per finding Cause, Fix (files and functions), Tests, the discretion items X1-X3, Gates with their real output, Risks R1-R11 and the manual test list M1-M11 for the maintainer, and the doc updates still needed. Include it in the F-27 commit. Leave this PLAN file untouched.
    If a gate fails and cannot be fixed within the decision: git -C WT restore and git -C WT clean only the paths of the uncommitted finding, report fix-failed with the failing gate output, and stop the part (an already committed F-26 stays).
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swiftlint/swiftlint lint --strict --quiet && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/strings-check.py && ! git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'</automated>
    <automated>git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks log --format=%s -2</automated>
    <human-check>The two subjects printed are the F-27 subject first, then the F-26 subject, exactly as in "Commits".</human-check>
  </verify>
  <done>Both commits exist on audit-manual/mac27-clicks with the required message shape, every gate passed on each, the summary is committed with F-27, nothing was pushed.</done>
</task>

</tasks>

## Commits (use verbatim; the subject dash is an em dash)

F-26 (after Task 1, files: ItemClick27.swift, SystemItemClickBridge27.swift, Plan2Core27Tests.swift, ClickBridge27Tests.swift):

```
fix(macos27): resolve F-26 — dismiss only a panel holzBar saw open, with Escape to its owner

The maintainer chose to keep the Escape shortcut but aim it at the panel only.
The click bridge remembered a panel after every replayed click, forgot it only on a
dismissing click, and took a banner for an open panel, so a clock click could post
Escape at the HID level to the app in front and swallow the click. It now remembers
a panel only when a new panel window appeared, forgets it on every click it lets
through, sends Escape to the panel's process with postToPid, and replays the click
unless that window really went (ItemClick27.PanelMemory, firstStep, tested).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

F-27 (after Task 2, files: ApplyLedger27.swift, ApplyLedger27Tests.swift, Concealer27.swift, ItemClicker27.swift, ItemImageStore27.swift, mac27-clicks-SUMMARY.md):

```
fix(macos27): resolve F-27 — click and photograph a shown app once its concealment change landed

The maintainer chose to wait for the real apply. showTemporarily only queued an
apply, and the Shelf click and the photo pass trusted the item's frame after a fixed
600 ms, so a queued change left them at a stale frame where another item or the
clock stood. Applies are now numbered (ApplyLedger27, tested); the async
showTemporarily(bundleID:) waits up to 3 s for the apply that carries the show, the
click falls back to the Accessibility press and the photo is skipped when it does
not land, captures wait for pending applies, and store version 10 retakes glyphs.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## How each failure scenario is closed

**F-26** (audit steps 1-4):
1. NC opened from the clock through holzBar: the replay path finds the new NC window and remembers
   (clock, window, NC's PID). Closing NC by clicking the desktop: that click is let through by the
   tap, so `PanelMemory.forget()` drops it (D-01c).
2. Later, banner up, clock clicked with a dialog, sheet or fullscreen video in front: nothing is
   remembered, so `firstStep` returns `.liftAndReplay` for the clock: no Escape at all (3 closed),
   and the held-back click is replayed, so NC opens on the first click (4 closed).
- Variant, NC closed by a swipe or the Escape key (no mouse down): the memory survives. If the
  banner shows in a different window, `panelIsOnScreen` is false, the memory is dropped, and the
  click is replayed. If the banner reuses NC's window number, the click is treated as a dismissal,
  but Escape goes only to NC's process (the front app is never touched; step 3 closed in every
  variant). The click is then replayed unless that window actually went (D-01f). See R3 for the
  one residual case.
- Rapid double clicks: `PanelMemory.remember(_:openedBy:)` ignores the panel found for a click
  once a later click arrived (D-01h).

**F-27**:
- Click at a stale frame: `ItemClicker27.click` clicks a frame only after the apply that carries
  the show finished successfully, plus the measured 600 ms draw delay. A show that does not land
  within 3 s (or is paused or unavailable) uses the Accessibility press, never a positional click.
  So it can no longer hit the neighbour or the clock, and the click bridge no longer fires on it.
- Wrong glyph: `photographMissing` captures only after the show landed. `performCapture` first
  waits for pending applies, then waits out the settle time, now measured from the moment the
  apply landed. So both reads of `settledTags` see the bar after it moved. Glyphs stored under the
  bug are dropped once by store version 10. The F-74 observer ordering is already in place.

## Risks (macOS 26 and 27)

- **R0 macOS 14, 15 and 26:** no behaviour change. Every changed app-target type is
  `@available(macOS 27.0, *)`. The new Core types are pure and need no availability.
  `CGEvent.postToPid` exists since macOS 10.11. The deployment target stays 14.0.
- **R1 (macOS 27, F-26):** nobody has measured whether Notification Center or Control Centre act on
  an Escape posted to their process. If they do not, every closing click waits about 200 ms and then
  takes lift+replay. That is correct but slower, and the cover shows briefly. The debug log line
  tells which branch ran.
- **R2 (macOS 27, F-26):** if NC or CC keep their panel window on screen longer than about 200 ms
  after a successful Escape (a close animation, or the "host window" noted in
  `Scripts/macos27/system-click.swift`), the fall-through replay re-opens the panel that Escape just
  closed. M4 catches this. If it happens, record the measured close time from the log and raise
  `escapeAnswerPolls`, or report back. Do not drop the fall-through (D-01g).
- **R3 (macOS 27, F-26, accepted by D-01):** NC closed by a swipe or the Escape key, then a banner
  in the very same window number. The next clock click sends Escape to NC. If that removes the
  banner's window, the click counts as done and NC opens only on the second click. No app in front
  is affected.
- **R4 (macOS 27, F-26):** after clicking inside an open panel (toggling Wi-Fi in Control Centre,
  scrolling notifications), that click made holzBar forget the panel. Closing it then takes the
  slower lift+replay path. X1 makes this a correct close, not a close-and-reopen.
- **R5 (macOS 27, F-26):** while a banner is on screen, Control Centre and other press-opened items
  take lift+replay instead of the faster press (X1 treats the banner window as a panel already up).
- **R6 (macOS 27, F-27):** Shelf clicks now wait for the apply, normally about 100-300 ms and at
  most 3 s, before the 600 ms draw delay. Photo passes (up to six apps) get longer by the same
  amount per app.
- **R7 (macOS 27, F-27):** when MenuBarAgent is slow (after login or wake), Shelf clicks fall back
  to the Accessibility press. Apps that ignore the press then do nothing on that click. The F-77
  retry may still show the app afterwards, while its menu is open.
- **R8 (macOS 27, F-27):** store version 10 drops every stored glyph once after the update. The
  Shelf and the Layout pane show missing icons until the photo passes retake them, and concealed
  apps flash briefly into the bar during those passes. This happens once.
- **R9 (compile):** `showTemporarily(bundleID:)` now has sync and async overloads. A future
  un-awaited call in an async context fails to compile (it does not silently change behaviour).
  The current callers are verified.
- **R10 (compile):** only CI's Xcode 27 build compiles the app target with the 27 SDK. `appcheck.sh`
  (26.5 SDK) is a close but not identical check. Push once, at the end of the chain (CLAUDE.md).
- **R11 (concurrency):** the 3 s timeout Task keeps `Concealer27` alive for at most 3 s.
  Continuations are resumed exactly once, because the ledger removes a waiter before anyone resumes
  it and everything runs on the main actor.

## Manual test on macOS 27 (maintainer, one session for both findings)

Setup: build installed with `Scripts/install.sh`, Accessibility granted, holzBar concealing at
least one app, Shelf on. Watch the bridge in Terminal with
`log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "ClickBridge27"'`.

- **M1:** `Scripts/macos27/verify-clock.sh`: both PASS.
- **M2:** open NC from the clock, close it by clicking the desktop. Make a banner
  (`osascript -e 'display notification "test"'`). While it shows, bring up a dialog or sheet
  (TextEdit, Save) or play a fullscreen video, then click the clock. Expected: the dialog stays
  open and fullscreen stays; NC opens on the first click.
- **M3:** M2 again, with NC closed by a two-finger swipe, then by the Escape key. Expected: the
  dialog or fullscreen is never affected. Note whether NC opens on the first click (R3).
- **M4:** clock, then clock: NC opens, then closes quickly and stays closed (R2). Do it 10 times.
  Note the "Escape closed the panel in N ms" values.
- **M5:** clock, then Control Centre: NC closes and CC opens quickly. CC, then CC: opens and closes.
- **M6:** open CC, toggle something inside it, click CC: it closes (slower is fine, R4) and does
  not reopen.
- **M7:** quick double click on the clock: NC opens and closes, holzBar stays responsive, and the
  next single click opens NC.
- **M8:** `Scripts/macos27/verify-shelf-click.sh <ext-x> <ext-y> <builtin-x> <builtin-y>`: all
  PASS.
- **M9:** right after launching holzBar (a photo pass is running), and right after a light/dark
  switch, open the Shelf and click hidden items several times in a row. Expected: the right menu
  each time, never a neighbour's menu and never Notification Center.
- **M10:** after the update's first run, wait about a minute with the Shelf open now and then. Every
  Shelf and Layout pane icon shows its own app (store version 10 retook them).
- **M11 (optional):** Console, categories `ItemClicker27` and `ItemImageStore27`: no "not shown in
  time" lines in normal use.

## Doc updates needed (not by the executor; for the maintainer or a docs part)

- Release notes of the next beta (`docs/release-notes/v0.0.7-betaN.md`), under Fixed: "macOS 27:
  clicking the clock while a banner was showing could cancel the dialog in front or end
  fullscreen, and Notification Center then needed a second click" and "macOS 27: clicking an item
  in the holzBar Shelf right after opening it could open another item's menu, and a Shelf icon
  could show another app's glyph (icons are photographed once more after updating)".
- `docs/features.md` line 83 (macOS 27 limitations): once M4 and M6 are measured, add that closing
  a system item's panel after clicking inside it takes the same extra time, and that a Shelf click
  waits until macOS has shown the item (longer while icons are being photographed).
- `docs/privacy-and-permissions.md` Accessibility row (optional, for transparency): on macOS 27
  holzBar sends an Escape key press to Notification Center or Control Centre to close a panel it
  opened.

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| other processes -> holzBar (window list) | Window numbers, layers, sizes and owner PIDs of NC/CC windows decide whether a click dismisses a panel |
| holzBar -> other processes (synthetic events) | Escape key events and replayed clicks posted with Accessibility trust |
| MenuBarAgent -> holzBar (assertion completion) | When an apply counts as landed |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-M27C-01 | Tampering | Escape helper in SystemItemClickBridge27 | medium | mitigate | Escape goes only to the owner PID stored when the bridge saw a panel window open after its own click. That PID comes from windows filtered to the running NC/CC apps. No HID-level Escape remains, so the app in front cannot receive it (grep gate in Task 1) |
| T-M27C-02 | Spoofing | windowsForPanelCheck owner filter by bundle ID | low | accept | A process that claims NC's or CC's bundle ID can make its window look like a panel. The worst case is one Escape to that process and one replayed click; the app in front is unaffected. Same class as F-45 (separate finding) |
| T-M27C-03 | Denial of Service | Concealer27.showTemporarily async wait | low | mitigate | The wait is bounded to 3 s by a resume-once continuation raced by a sleep (not the timeout helper broken by F-01). On timeout the click uses the Accessibility press and the photo is skipped |
| T-M27C-04 | Information Disclosure | new log lines | low | mitigate | Logs carry only timings and counts as .public, and item descriptions as .private(mask: .hash); no bundle IDs or titles. Gate: privacy-check.py logs |
| T-M27C-05 | Tampering | item image cache | low | mitigate | Store version 10 drops glyphs that may have been stored under the wrong key |
| T-M27C-SC | Tampering | npm/pip/cargo/Swift package installs | low | accept | None added; the project has no package dependencies (CI gate) |
</threat_model>

<verification>
- Task 1 and Task 2 verify blocks pass; the Task 3 gate set (G1-G6) passes before each commit.
- `git -C WT log --format=%s -2` shows the two subjects; `git -C WT status --short` is empty after the
  F-27 commit, except for this untracked PLAN file.
- No file outside `files_modified` changed; no README, docs, SECURITY.md, release notes or CLAUDE.md
  edits; no new user-facing strings; no persisted Defaults key renamed or added.
</verification>

<success_criteria>
- F-26: a bridged click never posts Escape at the HID level. A stale or banner-only state leads to
  lift+replay. A click is never dropped unless the remembered window left the screen. All of this
  is covered by the ClickBridgeStep27Tests and PanelMemory27Tests suites.
- F-27: positional Shelf clicks and photos happen only after the carrying apply finished
  successfully. Captures wait for pending applies. Store version 10 is in place. The rules are
  covered by ApplyLedger27Tests.
- Both commits atomic, gates green, summary committed, nothing pushed.
- The maintainer has the M1-M11 checklist for the macOS 27 session.
</success_criteria>

<output>
Create `.planning/audit/remediation/mac27-clicks-SUMMARY.md` (sibling format, see Task 3) and commit
it with the F-27 commit. Do not modify this PLAN file.
</output>
