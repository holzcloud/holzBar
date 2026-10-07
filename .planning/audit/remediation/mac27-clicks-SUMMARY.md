---
chain: mac27
part: clicks
findings: [F-26, F-27]
decision: mac27-clicks-1 — "Escape nur ans Panel (Recommended)"; mac27-clicks-2 — "Auf echte Freigabe warten (Recommended)"
status: complete
plan_head_before: 7e7ed6bf13a130ca62b2a627fb5cea99c6065f9c
plan_head_after: the F-27 commit that contains this file (child of b8e10631)
commits: 2
actuals:
  tasks: 3
  commits: 2
---

# mac27 / clicks: Escape only to a panel holzBar saw open; Shelf clicks and photos only after the show landed

Both changes affect macOS 27 only. Every app-target type touched is `@available(macOS 27.0, *)`.
The new logic lives in pure, swift-tested types in `holzBar/MenuBar/MacOS27/Core`
(`ItemClick27.PanelMemory`/`firstStep`/`stepAfterDismissal`/`openedPanel`, `ApplyLedger27`).
The deployment target stays 14.0, and macOS 14, 15 and 26 behave as before.

Not in scope: the user's question about signing ("Können wir das mit dem signieren nicht doch
anders lösen?"). Neither F-26 nor F-27 touches signing. That question belongs to the `release`
part (F-05, F-10, F-11, F-52, F-53, F-54), and the orchestrator has to take it back to the
user. No release, signing or CI file was changed here.

## F-26: Escape to the front app, and a swallowed clock click (commit b8e10631)

**Cause.** `SystemItemClickBridge27` remembered "a panel is showing" after every replayed
click, whether or not a panel opened, and forgot it only on a dismissing click. Any
Notification Center window at layer >= 20 and > 150 pt tall counted as an open panel, a banner
included. With that stale state and a banner up, the next clock click posted Escape at the HID
level, which reached the frontmost app: a dialog or sheet was cancelled, or fullscreen ended.
The bridge then returned without replaying the held-back click, so Notification Center opened
only on the second click.

**Fix (D-01, "Escape nur ans Panel").**
- `holzBar/MenuBar/MacOS27/Core/ItemClick27.swift`:
  - `PanelWindow` is the window tuple plus `ownerPID`.
  - `OpenPanel` (item, window, owner PID) is the panel that was seen open.
  - `PanelMemory` holds the panel and a click counter. `forget()` and
    `takeForBridgedClick()` advance the counter. `remember(_:openedBy:)` only stores a panel
    when no later click has arrived.
  - `BridgeStep` is `.dismiss`, `.press` or `.liftAndReplay`.
  - `firstStep(remembered:windows:mayOpenFromPress:)` dismisses only while the remembered
    window is on screen.
  - `stepAfterDismissal(...)` returns `.liftAndReplay` if the window stayed. It returns `nil`
    only if the window went and the same item was clicked.
  - `openedPanel(item:before:windows:)` only accepts a new panel-sized window.
- `holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift`:
  - The remembered-item string is replaced by `panelMemory`.
  - `handle(_:)` forgets the panel for every left click it lets through. `stop()` forgets it
    as well.
  - A bridged click takes the memory and follows `firstStep`.
  - Escape goes out through `CGEvent.postToPid(owner)`. No HID-level Escape is left.
  - `waitForPanelToGo` polls 4 x 50 ms for the window to leave the screen, then
    `stepAfterDismissal` decides.
  - The press path and the replay path record the panel only if a new panel window appeared
    (`waitForOpenedPanel`, 5 and 8 polls). The replay path takes its baseline right before
    `replayClick`.
  - The fixed 120 ms `panelDismissWait` is gone.
  - The comment block above the step logic is rewritten.

**Discretion (consistent with D-01, from the plan):**
- **X1:** with no remembered panel but an NC/CC panel-sized window already up, Control Centre
  is lifted and replayed instead of pressed. Otherwise the press would close it, be learned as
  "ignores the press", and the replay would open it again.
- **X2:** `stop()` forgets the panel.
- **X3:** the fixed post-Escape wait is replaced by waiting for the window to go.

**Tests.** New `Tests/HolzBarMacOS27CoreTests/ClickBridge27Tests.swift`:
- Suite "Click bridge steps", 12 tests: dismiss, stale memory with a banner, a banner without
  memory, press, X1, done after dismissal, another item after dismissal, a window that stays
  is replayed and never pressed, the overflow button, a new window, a reused window, and
  non-panels.
- Suite "Panel memory", 5 tests: hand-over, forget, rapid double click, a click let through
  meanwhile, and nil clearing the memory.

The existing "System item panel" suite only switched its literals to `PanelWindow`; its
expectations are unchanged.

## F-27: Shelf clicks and photos at a stale frame (this commit)

**Cause.** `Concealer27.showTemporarily` only called `update()`. That changed
`concealedPIDs`/`lastChangeAt` at once and queued the apply behind earlier ones, and each
apply can take up to 3 s. `ItemClicker27.click` and `ItemImageStore27.photographMissing` slept
a fixed 600 ms and then trusted the AX frame. For an app that was still concealed, that frame
was where the item was last drawn, so another item's menu opened, or another item's glyph was
stored under this app and never retaken.

**Fix (D-02, "Auf echte Freigabe warten").**
- New `holzBar/MenuBar/MacOS27/Core/ApplyLedger27.swift`: numbers the applies
  (`queue`, `nextApply`, `hasPending`) and tracks waiters (`wait`, `finish`, `abandon`).
  Each waiter is handed out once.
- `holzBar/MenuBar/MacOS27/Concealer27.swift`:
  - `update()` now calls `applyChanges() -> Bool`. It returns `false` when concealment is
    paused or unavailable, and `true` when it queued the apply or when concealment is suspended
    (the change is applied when the suspension ends).
  - The apply Task calls `applyFinished(sequence, succeeded:)`, which stamps `lastChangeAt`
    and resumes the waiters.
  - `waitForApply` uses a checked continuation with a 3 s sleep-raced `abandon`, the
    `MenuBarAssessmentAssertion27.activate` pattern. It does not use the shared timeout
    helpers (F-01).
  - New `showTemporarily(bundleID:) async -> Bool` and `waitForPendingApplies()`.
  - `suspend`/`suspendReleased` stamp `lastChangeAt` after the release, not before it.
  - The sync `showTemporarily` overloads and their callers (`revealBriefly`, launch grace)
    are unchanged.
- `holzBar/MenuBar/MacOS27/ItemClicker27.swift`: awaits the show. Only when it landed does it
  sleep 600 ms and look for the drawn frame. Otherwise it logs a notice (item hashed) and takes
  the Accessibility press / show-menu path. There is still exactly one `endTemporaryShow` on
  every path.
- `holzBar/MenuBar/MacOS27/ItemImageStore27.swift`:
  - `photographMissing` captures only after a show landed, and records `stored: shown &&
    hasImage`.
  - `performCapture` awaits `waitForPendingApplies()` before the settle wait.
  - `storeVersion` is `"10"`. The F-74 precondition held: the appearance observer is installed
    before the version check, at lines 100/107.

**Tests.** New `Tests/HolzBarMacOS27CoreTests/ApplyLedger27Tests.swift`, suite "ApplyLedger27",
8 tests:
- numbering
- success
- failure
- an apply that already finished
- earlier waiters, answered in order
- abandon once
- abandon after finish
- a wait for the next apply made while suspended

## Gates (run before each commit, all passed)

| Gate | F-26 | F-27 |
|------|------|------|
| `appcheck.sh` (whole app module, Swift 6, 26.5 SDK) | ERRORS: 0 EXIT: 0 | ERRORS: 0 EXIT: 0 |
| `servicecheck.sh` | SERVICE EXIT: 0 | SERVICE EXIT: 0 |
| `swift test` (full) | 6 + 153 + 266 passed | 6 + 161 + 266 passed |
| SwiftLint `--strict --quiet` | no output, exit 0 | no output, exit 0 |
| privacy-check network / logs | pass / pass | pass / pass |
| strings-check | 369 strings in 5 languages | 369 strings in 5 languages |
| former name check | nothing found | nothing found |
| F-27 extras: no `Task(timeout`/`value(of:`; no `lastChangeAt = .now` in `applyChanges` | n/a | pass |

The only appcheck warning is the existing `ScreenCapture.swift` deprecation, which these
changes did not introduce. `swift test` hit the known Command Line Tools flake ("plugin for
module 'TestingMacros' not found") on some first runs and passed on the rerun. No new
user-facing strings, Defaults keys or autosave names were added.

## Deviations from the plan

- The plan asked for tests first, failing (RED), then the code. In practice the tests and the
  Core types were written in the same step. The tests could not have compiled without the new
  types, so there is no separate RED run.
- The ledger tests use `#require` on a value bound beforehand (`let waiting = …`), and three
  single `#expect`s instead of an array comparison. The `#expect`/`#require` macro expansion
  cannot call a mutating method or resolve the array `==`. Behaviour is unchanged.
- Otherwise the plan was followed as written. STATE.md and ROADMAP.md were not touched, because
  this audit chain does not track them.

## Risks (from the plan, still open until the macOS 27 session)

- **R1:** it is not measured whether NC/CC act on an Escape posted to their PID. If they do
  not, every close takes about 200 ms and then lift+replay: correct, but slower.
- **R2:** if a panel window lingers for more than 200 ms after a successful Escape, the
  fall-through replay re-opens it. M4 checks this. If it happens, raise `escapeAnswerPolls`.
- **R3:** NC closed by a swipe or the Escape key, then a banner in the very same window
  number: Escape goes to NC only, and NC may open only on the second click. No front app is
  affected.
- **R4/R5:** after a click inside a panel, or while a banner is up, closing or opening takes
  the slower lift+replay path.
- **R6/R7:** Shelf clicks wait for the apply (at most 3 s). When MenuBarAgent is slow, they fall
  back to the Accessibility press.
- **R8:** store version 10 drops all glyphs once; they are photographed again over the next
  passes.
- **R9/R10:** sync and async `showTemporarily(bundleID:)` overloads exist side by side. Only CI's
  Xcode 27 build compiles against the 27 SDK.
- **R11:** the timeout Task keeps `Concealer27` alive for at most 3 s.

## Manual test on macOS 27 (maintainer, one session)

Setup: install with `Scripts/install.sh`, grant Accessibility, conceal at least one app, and
turn the Shelf on. Then run
`log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "ClickBridge27"'`.

- **M1:** `Scripts/macos27/verify-clock.sh`: both PASS.
- **M2:**
  1. Open NC from the clock, then close it by clicking the desktop.
  2. Post a banner with `osascript -e 'display notification "test"'`.
  3. With a TextEdit Save sheet or a fullscreen video in front, click the clock.

  Expected: the sheet or fullscreen stays, and NC opens on the first click.
- **M3:** M2 again, with NC closed by a swipe, then by the Escape key. The front app is never
  affected; note whether NC opens on the first click (R3).
- **M4:** clock, then clock, 10 times: NC opens, then closes quickly and stays closed. Note the
  "Escape closed the panel in N ms" values.
- **M5:** clock, then Control Centre: NC closes and CC opens. CC, then CC: opens and closes.
- **M6:** open CC, toggle something inside it, then click CC: it closes and does not reopen.
- **M7:** quick double click on the clock: holzBar stays responsive, and the next click opens NC.
- **M8:** `Scripts/macos27/verify-shelf-click.sh <ext-x> <ext-y> <builtin-x> <builtin-y>`:
  all PASS.
- **M9:** right after launch, and right after a light/dark switch, click hidden Shelf items
  several times. Each click opens the right menu, never a neighbour's menu and never NC.
- **M10:** after the first run of the update, every Shelf and Layout pane icon shows its own
  app.
- **M11 (optional):** Console, `ItemClicker27`/`ItemImageStore27`: no "not shown in time" lines
  in normal use.

## Doc updates needed (not done here)

- Release notes of the next beta, under Fixed:
  - macOS 27: a clock click while a banner showed could cancel the dialog in front or end
    fullscreen, and Notification Center then needed a second click.
  - macOS 27: a Shelf click right after opening could open another item's menu, and Shelf icons
    could show another app's glyph (icons are photographed once more after updating).
- `docs/features.md` (macOS 27 limitations): once measured, add that closing a panel after
  clicking inside it takes extra time, and that a Shelf click waits until macOS has shown the
  item.
- `docs/privacy-and-permissions.md`, Accessibility row (optional): on macOS 27, holzBar sends
  Escape to Notification Center or Control Centre to close a panel it opened.

## Self-Check: PASSED

- Files exist: `Core/ItemClick27.swift`, `Core/ApplyLedger27.swift`, `ClickBridge27Tests.swift`,
  `ApplyLedger27Tests.swift`.
- Commit b8e10631 (F-26) is an ancestor of HEAD. The F-27 commit contains this file.
