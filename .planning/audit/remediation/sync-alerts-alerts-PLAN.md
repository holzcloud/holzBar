---
phase: audit-remediation-sync-alerts
plan: alerts
type: execute
wave: 2
depends_on: [sync]
files_modified:
  - holzBar/Core/MainRunLoop.swift
  - Tests/HolzBarCoreTests/MainRunLoopTests.swift
  - holzBar/Core/SettingsSyncPolicy.swift
  - Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
  - holzBar/Utilities/Extensions.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
  - holzBar/Utilities/SettingsBackup.swift
  - holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift
  - holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift
  - holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift
  - holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift
  - holzBar/Utilities/SettingsSync.swift
  - holzBar/MenuBar/ControlItem/ControlItem.swift
  - holzBar/Resources/Localizable.xcstrings
  - .planning/audit/remediation/sync-alerts-alerts-SUMMARY.md
autonomous: true
requirements: [F-14]

estimate:
  tokens: 190000
  raw_tokens: 190000
  tasks: 5
  confidence: low

must_haves:
  truths:
    - "A newer version from another Mac that arrives while holzBar runs opens no dialog and does not bring holzBar to the front; the holzBar menu shows the header 'Settings changed on another Mac' with 'Restart', and the sync row in Settings > Advanced shows the same line with a Restart button (D-26, D-31)"
    - "A conflict that arises in the background (both Macs changed, or a re-identified Mac) appears only as that hint, with 'Choose Settings…'; choosing it opens Settings on Advanced and shows the conflict choice as a sheet on the Settings window (D-32)"
    - "Turn On… and Change… with a folder whose settings differ ask in a sheet on the Settings window, never in a separate dialog, also when the window was closed while the folder was read (D-33)"
    - "While a version from another Mac waits (hint shown or sheet open), this Mac writes nothing to the sync file (D-28)"
    - "No alert runs a modal loop from inside a Task or async function: Settings-window alerts are sheets, 'Not enough room' and the relaunch failure run from the main run loop, so main-actor work (macOS 27 click replay, hover, Shelf, concealment) continues while any alert is open (D-24, D-25, D-27)"
    - "A Core test shows that a nested run loop started through MainRunLoop.run lets a separately spawned main-actor task run (D-30)"
    - "Exactly one new string, in en, de (Swiss spelling), fr, it and rm; strings-check.py passes (D-29)"
  artifacts:
    - path: holzBar/Core/MainRunLoop.swift
      provides: "MainRunLoop.run(_:): main-actor work run from the main run loop's default mode, awaited"
    - path: Tests/HolzBarCoreTests/MainRunLoopTests.swift
      provides: "Swift Testing proof that main-actor tasks run inside a nested run loop started through the helper"
    - path: holzBar/Utilities/Extensions.swift
      provides: "NSAlert.present(attachedTo:): sheet on an on-screen window, else app-modal dialog through MainRunLoop"
    - path: holzBar/Core/SettingsSyncPolicy.swift
      provides: "SettingsSyncPolicy.Hint and hint(for:): restart vs choice for a waiting version"
    - path: holzBar/Utilities/SettingsSync.swift
      provides: "Observable hint, restartWithWaitingSettings(), chooseSettings(), conflict sheets on the Settings window; no windowless prompt"
    - path: holzBar/MenuBar/ControlItem/ControlItem.swift
      provides: "Hint section at the top of the holzBar menu"
    - path: holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift
      provides: "Hint line and button in SettingsSyncToggle; Settings window passed to export/import"
  key_links:
    - from: "SettingsSync.handle(_:of:) (.apply / .ask)"
      to: "SettingsSync.hint"
      via: "setPending(remote.modified) first (push guard), then the hint; never a dialog"
    - from: "ControlItem menu item / SettingsSyncToggle button"
      to: "SettingsSync.restartWithWaitingSettings() / chooseSettings()"
      via: "@objc wrappers on ControlItem; SwiftUI Button actions"
    - from: "SettingsSync.chooseSettings() and finishJoin(.ask)"
      to: "NSAlert.beginSheetModal(for:) on navigationState.settingsWindow"
      via: "showSettings(then:): navigate to Advanced, open/activate Settings, wait for isSettingsPresented with ObservationLoop"
    - from: "NSAlert.present(attachedTo:) fallback"
      to: "MainRunLoop.run"
      via: "RunLoop.main.perform(inModes: [.default]) + MainActor.assumeIsolated + CFRunLoopWakeUp"
---

# Audit remediation plan: chain "sync-alerts", part "alerts" (F-14)

> **Scope note.** The user message relayed with this run ("Können wir das mit dem signieren nicht
> doch anders lösen?") is about release signing. Signing belongs to the `release` chain (decision
> `decisions/release-1.md`, findings F-05, F-10, F-11, F-52, F-53, F-54; `docs/signing.md`). This
> part changes nothing about signing, release workflows or secrets. The orchestrator must route the
> question back to the maintainer (the sync part's SUMMARY already flagged it).

Paths used below:

- `WT` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sync-alerts` (the only tree to change; branch `audit-manual/sync-alerts`)
- `S` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad` (scratch files, build folders, gate scripts)

Never touch `/Users/cheidenreich/privat/holzBar` or another worktree, never switch branches, never
push, never run a writing `gh` command, never quit or relaunch holzBar, never change system state
(tccutil, `defaults write` on real domains, launching apps). Do not edit README.md, docs/,
SECURITY.md, release notes or CLAUDE.md (see section 8). Stage only the files listed in section 6;
leave this PLAN file and the sync part's PLAN file untracked.

<objective>
Implement the maintainer's decision **"Sheets und stiller Hinweis"** for F-14 exactly as
`S/decisions/modal-alerts-1.md` describes (options 2 and 3 together, plus option 1's run-loop
helper and Core test), reconciled with the sync part already committed on this branch
(`88921465`, `f2f8b9cc`, `ec55d265`):

1. A Foundation-only `MainRunLoop` helper in Core (tested) and an AppKit `NSAlert.present(attachedTo:)`
   wrapper. Windowless alerts ("Not enough room", relaunch failure) run from the main run loop.
2. Alerts that come from the Settings window become sheets on it (layout move error, spacing error,
   import confirmation, import/export errors, "not movable"/"unresponsive" item).
3. Settings sync never opens a dialog by itself: a newer version from another Mac becomes a quiet
   hint with "Restart" in the sync settings and in the holzBar menu; a background conflict is
   offered through the same hint and chosen in a sheet on the Settings window; Turn On…/Change…
   conflicts are sheets on the Settings window. Pushes stay paused while a version waits.

Purpose: F-14 (medium). `NSAlert.runModal()` inside main-actor Tasks starts a nested run loop inside
a main-queue job, which does not serve the main queue, so every other main-actor job (click replay
of SystemItemClickBridge27 on macOS 27, hover, concealment, Shelf, image cache) waits until the
alert closes. The sync alert is the worst case because another Mac can trigger it at any time.

Output: one new Core file with tests, one Core type extension with tests, changes in nine app files,
one new catalog string (one stale one removed), one commit `fix(alerts): resolve F-14 — …` on
`audit-manual/sync-alerts`, and `.planning/audit/remediation/sync-alerts-alerts-SUMMARY.md`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@WT/CLAUDE.md
@S/decisions/modal-alerts-1.md
@S/decisions/sync-1.md
@S/manual-questions.json (cluster "modal-alerts": the implementation notes of options 1, 2 and 3, which option 4 combines)
@WT/.planning/audit/FULL-AUDIT-2026-10-05.md (section "#### F-14")
@WT/.planning/audit/remediation/sync-alerts-sync-SUMMARY.md (what the sync part built; its user test steps 3 and 7 change here)
@S/audit-synth/modal.swift (the probe: case A blocks, case B does not)
@WT/holzBar/Core/BlockingWork.swift and @WT/Tests/HolzBarCoreTests/BlockingWorkTests.swift (precedent for helper + test)
@WT/holzBar/Core/ObservationLoop.swift
@WT/holzBar/Core/SettingsSyncPolicy.swift and @WT/Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
@WT/holzBar/Utilities/SettingsSync.swift (lines 246-313 state, 474-587 join, 591-633 checks/pushes, 832-868 handle, 1148-1279 questions)
@WT/holzBar/Utilities/SettingsBackup.swift (lines 92-180)
@WT/holzBar/Utilities/Extensions.swift (MARK sections, line 426 NSApplication)
@WT/holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift (lines 1035-1041)
@WT/holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift (lines 144-174, LayoutBarMoves.move)
@WT/holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift (lines 120-133, 471-494)
@WT/holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift (lines 352-364)
@WT/holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift (lines 227-247, 292-338)
@WT/holzBar/MenuBar/ControlItem/ControlItem.swift (lines 571-708)
@WT/holzBar/Main/AppState.swift (activate(for:), openWindow(_:), navigationState) and @WT/holzBar/Main/Navigation/AppNavigationState.swift
@WT/holzBar/Settings/SettingsWindow.swift (settingsWindow + isSettingsPresented come from window.isVisible KVO)
@WT/.github/scripts/strings-check.py
</context>

## 1. The maintainer's decision, as implemented here

Chosen: **Sheets und stiller Hinweis** ("Beides zusammen … KOMPLETT SELBST umsetzbar"). Rejected:
"Meldungen bleiben wie heute (Recommended)", "Sheets im Einstellungsfenster", "Sync-Meldung als
stiller Hinweis". Decision items continue the chain's numbering after the sync part's D-23.

| ID | Decision item | Source |
|----|---------------|--------|
| D-24 | The blockade is fixed in every case: no alert runs `runModal()` inside a main-actor Task or async function. Affected (verified in the decision context): SettingsSync's background prompt, MenuBarItemManager "Not enough room", LayoutBarMoves.move error (LayoutBarPaddingView.swift), GeneralSettingsPane spacing error, SettingsBackup relaunch failure. | modal-alerts-1 |
| D-25 | Settings-window alerts become sheets on the Settings window: LayoutBarMoves.move error, GeneralSettingsPane spacing error, SettingsBackup import confirmation and import/export errors, and for consistency LayoutBarItemView's "not movable"/"unresponsive" alerts. One wrapper `NSAlert.present(attachedTo:)`: sheet when the window is on screen, otherwise the usual dialog through the run-loop helper ("ist das Fenster zu, kommt der gewohnte Dialog"). | option 2 |
| D-26 | The sync notice replaces the sync NSAlert: observable state in SettingsSync, shown in the sync settings (secondary line + Restart) and as an item in the holzBar menu (`ControlItem.createMenu(with:)`); no activation, no modal. | option 3 |
| D-27 | The option-1 run-loop helper serves the remaining windowless alerts: "Not enough room" (MenuBarItemManager) and the relaunch failure (SettingsBackup.relaunch). It uses `RunLoop.main.perform(inModes: [.default])` only (a queued alert never opens inside another modal, a menu or a drag) and `MainActor.assumeIsolated` (the block is NS_SWIFT_SENDABLE). | option 1 |
| D-28 | Push guard while settings from another Mac are pending: no push while the hint is shown or the conflict sheet is open, so "Restart" never finds this Mac's own file. | modal-alerts-1 context (4) |
| D-29 | New strings in en, de (Swiss spelling, never "ß"), fr, it, rm; strings-check.py passes; strings kept minimal. | modal-alerts-1, orchestrator |
| D-30 | Core test from option 1: helper in holzBar/Core (precedent BlockingWork); a test runs a nested default-mode loop for about 0.3 s through the helper and expects a separately spawned main-actor Task to run inside it; `.timeLimit`; if the `swift test` host's main thread runs no CFRunLoop, keep a probe script instead. | option 1 |
| D-31 | Sync never shows an unsolicited modal dialog; background changes from another Mac become the quiet hint with "Restart" (sync settings and holzBar menu). | orchestrator scope |
| D-32 | A conflict that arises in the background is offered through that hint; choosing it opens the Settings window with the conflict choice as a sheet. | orchestrator scope |
| D-33 | A conflict the user triggers in Settings (Turn On…, Change…) is a sheet on the Settings window. | orchestrator scope |
| D-34 | The hint goes away when sync is turned off, when the folder changes, and when a later check finds nothing waiting (adopt, write, none). | option 3 note |
| D-35 | Synchronous contexts stay as they are: URLCommands' question (from `application(_:open:)`), and the NSOpenPanel/NSSavePanel modals in button and menu actions. ConflictingApps (pre-setup, relaunch path) is not in the chosen option's list and the decision context calls it optional with low impact: unchanged. | option 1 note, context (3) |

**Interpretations (Claude's discretion, documented in the SUMMARY):**

- **I-1 Hint kinds and strings.** A waiting version gives one of two hints, decided by a pure Core
  function: `restart` (this Mac's user settings equal its base) or `choice` (this Mac changed its
  settings since the base, or it joins). The header text reuses "Settings changed on another Mac",
  the restart action reuses "Restart", the choice action is the only new string, "Choose Settings…"
  (an ellipsis because it opens a dialog, HIG). A "Restart" button that opened a dialog would be
  misleading, so the conflict gets its own label.
- **I-2 No silent loss of this Mac's later changes.** While a restart hint shows, pushes are paused,
  so a setting changed on this Mac is not synced; "Restart" would then overwrite it. Therefore a
  local change re-evaluates the hint (restart becomes choice, after the existing 5 s debounce), and
  "Restart" re-evaluates at click time and opens the choice sheet instead when this Mac changed
  settings since.
- **I-3 "Later" with a quiet hint.** In the conflict sheet opened from the hint, "Later" closes the
  sheet; the version stays pending, pushes stay paused, the hint stays visible (it is quiet), and
  after the next launch the hint comes back (the sync decision's "asks again after the next launch").
  "Cancel" for a joining Mac keeps the sync part's meaning (sync turns off on this Mac).
- **I-4 Sheet fallback.** `NSAlert.present(attachedTo:)` uses a sheet only when the window is
  visible, not miniaturized and shows no other sheet; otherwise it runs the app-modal dialog through
  MainRunLoop (no queued sheets).
- **I-5 Item drag alerts.** `LayoutBarItemView.mouseDragged(with:)` fires repeatedly during one drag,
  so it starts the sheet synchronously on its own window and skips it while a sheet is attached:
  at most one sheet per drag, no Task.
- **I-6 Panels unchanged.** Option 2 marked moving the import/export panels to sheets as optional,
  and they run in synchronous button actions (unaffected). They stay app-modal. Moving a panel into
  a Task would re-create F-14 for the panel, so the panels stay in the synchronous part of each flow.
- **I-7 Stale string.** The informative text of the removed restart dialog ("holzBar can restart now
  to use the settings from the sync folder.") is no longer used; remove its catalog entry.
- **I-8 "Not enough room" is awaited** (as option 1 specifies): the caller waits for the answer, but
  the main actor does not.
- **I-9 One commit.** F-14 is one finding, so one atomic commit; the gates run after every task so a
  failure surfaces before the commit. The SUMMARY goes into the same commit, as in the sync part.

## 2. Reconciliation with the committed sync part (F-02, F-15, F-38, F-60)

What the sync part left that this part changes (all in `holzBar/Utilities/SettingsSync.swift`):

| Sync part today | After this part |
|-----------------|-----------------|
| `handle(_:of:)` `.apply` → `scheduleWindowlessPrompt(.restart(remote))` (run-loop `runModal`, preceded by an app activation) | `.apply` → `setPending`, then hint `.restart`; no dialog, no activation (D-26, D-31) |
| `handle(_:of:)` `.ask` → windowless conflict prompt | `.ask` → `setPending`, then hint `.choice(isJoining:)` (D-32) |
| `finishJoin` → sheet on `join.window` (keyWindow captured at click), else windowless prompt | sheet on `navigationState.settingsWindow`; when the window is not on screen, Settings is opened and the sheet follows (D-33) |
| `SyncPrompt.restart`, the restart branch of `makeAlert`/`answer`, `scheduleWindowlessPrompt`, `JoinRequest.window` | removed |
| "Later" in the restart dialog set `postponed` | no restart dialog; the hint stays until used, withdrawn, or the next launch decides (silent apply when unchanged) |
| "Later" in the conflict prompt sets `postponed` (decide → `.wait`) | unchanged; the hint stays visible (I-3) |
| Push guard = persisted `SettingsSyncPendingModified` (`needsExchange(.localChange)` is false while pending) | unchanged and relied on (D-28); `setPending` always runs before the hint is set |

<!-- planner-discipline-allow: scheduleWindowlessPrompt -->

Unchanged and not to be touched: the decision table (`SettingsSyncPolicy.decide`), digests, file
queue, launch read, device identity, `apply(_:removesMissingKeys:)`, the conflict alert's strings and
its three buttons (D-01…D-04 of the sync part). The policy's `postponed`/`.wait` stay as they are.

## 3. Design (read before coding)

### 3.1 Core helper (`holzBar/Core/MainRunLoop.swift`, D-27, D-30)

`enum MainRunLoop` (main-actor isolated by the Core default isolation; `convenience_type` wants an
enum). One function, `static func run<Value: Sendable>(_ work: @escaping @MainActor @Sendable () -> Value) async -> Value`:
`withCheckedContinuation`; inside it `RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated { continuation.resume(returning: work()) } }`,
then `CFRunLoopWakeUp(CFRunLoopGetMain())` (CFRunLoopPerformBlock does not wake a sleeping run loop by
itself; the wake-up is cheap and makes the block run without waiting for another event). Doc comment
(style of BlockingWork): a nested run loop started inside a main-queue job, which every main-actor
task job is, does not serve the main queue, so every other main-actor job waits until it ends; one
started from a run-loop block does serve it (probe `audit-synth/modal.swift`, macOS 26.7.1). Default
mode only, so queued work never starts inside another modal, a menu or a drag. Cancellation is ignored
on purpose (a cancelled caller still gets the answer). If Swift rejects the closure's capture,
the `@Sendable` on `work` is what makes it legal; keep it.

### 3.2 AppKit wrapper (`holzBar/Utilities/Extensions.swift`, new `// MARK: - NSAlert` before `// MARK: - NSApplication`, D-25, D-27)

`extension NSAlert { @discardableResult func present(attachedTo window: NSWindow? = nil) async -> NSApplication.ModalResponse }`:
when `window` is non-nil, `isVisible`, not `isMiniaturized` and `attachedSheet == nil`, return
`await beginSheetModal(for: window)`; otherwise return `await MainRunLoop.run { self.runModal() }`.
Doc comment: why (F-14), and that a sheet never starts a nested run loop.

### 3.3 Hint (Core, `SettingsSyncPolicy`, D-26, D-32, I-1, I-2)

`extension SettingsSyncPolicy { nonisolated enum Hint: Equatable, Sendable { case restart; case choice(isJoining: Bool) }; static func hint(for local: Local) -> Hint }`:
`local.isJoining` → `.choice(isJoining: true)`; else `local.hasChanges` → `.choice(isJoining: false)`;
else `.restart`. This is exactly the split `decide` makes between `.apply` and `.ask` for a newer
foreign version (`decide` line 306 and the joining row at 297), which a test pins.

### 3.4 SettingsSync state and flows (D-26, D-28, D-31…D-34)

New state: `private(set) var hint: SettingsSyncPolicy.Hint?` (observed by SwiftUI; read by the menu);
`@ObservationIgnored private var waitingVersion: RemoteVersion?` (the data "Restart"/"Use Settings
from Sync Folder" apply); `@ObservationIgnored private var settingsWindowObserver: ObservationLoop?`
and the pending presentation closure.

| Event | Effect |
|-------|--------|
| `handle` `.apply` / `.ask` with a remote | `Self.setPending(remote.modified)` FIRST, then `offer(remote, local: request.local)`: `waitingVersion = remote`, `hint = SettingsSyncPolicy.hint(for: request.local)`, one `logger.info` without values |
| `handle` `.none`, `.adopt`, `.write` (both branches) | after the existing pending/markSynced calls, `withdrawHint()` (D-34) |
| `handle` `.wait`, `.retry` | nothing (hint unchanged) |
| `forgetSyncState()` (sync off), `commitJoin(_:)` (folder changed), `use(_:join:)` | `withdrawHint()` (D-34) |
| `settingsDidChange()` while `hint != nil` | `refreshHint()`: rebuild `Local` from the live settings (userDigest of `syncedSettings()`, base, pending) and set `hint = SettingsSyncPolicy.hint(for:)` (I-2); then the existing push logic (which the pending key blocks, D-28) |
| `restartWithWaitingSettings()` (Restart in menu or Settings) | `refreshHint()`; `.restart` → `use(remote, join: nil)` (apply without removal, mark synced, relaunch); `.choice` → `chooseSettings()` (I-2) |
| `chooseSettings()` (Choose Settings… in menu or Settings) | `showSettings { window in presentChoice(on: window) }` |
| `presentChoice(on:)` | guard `!isAsking`, `waitingVersion`; isJoining from the refreshed hint (`.choice(let j)` → j, `.restart` → false); `isAsking = true`; Task: `await makeAlert(isJoining:).beginSheetModal(for: window)`, then the existing answer logic with `join: nil` |
| `finishJoin` `.ask` | `showSettings { window in … beginSheetModal … answer(…, join: join) }`; if `isAsking`, reset `isChoosingFolder` and return (as today) |
| `showSettings(then:)` | needs `appState`; `navigationState.settingsNavigationIdentifier = .advanced`; `appState.activate(for: .settings)`; if `navigationState.isSettingsPresented` and `settingsWindow` exists → `makeKeyAndOrderFront(nil)` and call now; else `appState.openWindow(.settings)` and keep one `ObservationLoop.observe { navigationState.isSettingsPresented }` whose first `true` cancels the loop and calls the closure with `navigationState.settingsWindow` (event-driven, no polling). A newer request replaces an older one; `withdrawHint()` cancels a waiting hint request (not a join request) |

Answers in the conflict sheet (unchanged meaning, sync part D-02…D-04): first button → `use(remote,
join:)`; second → `keepThisMac(join:)` (its `.write` withdraws the hint); third → join: nothing
stored; background joining Mac: `isEnabled = false`; otherwise `postponed = remote.modified`, hint
stays (I-3). `promptDidClose()` keeps running the check that waited.

### 3.5 Failure scenarios and how they close

| Scenario | Closed by |
|----------|-----------|
| F-14 audit scenario: another Mac writes a newer Settings.plist, holzBar opens "Settings changed on another Mac", the user leaves it open; macOS 27 clicks on clock/battery/Wi-Fi/Control Centre are held back, hover/ItemClicker27/concealment freeze; macOS 26 image cache, refreshes, Shelf freeze | No dialog at all for background sync (hint only, D-26/D-31/D-32); the Settings sheet for a conflict is window-modal and runs no nested loop; the main actor keeps running, so SystemItemClickBridge27's replay task runs at once |
| "Not enough room" (macOS 26, inside `temporarilyShow`, a Task) | `await alert.present()` → MainRunLoop: the modal loop starts from a run-loop block and serves the main queue (D-27) |
| Relaunch failure (inside `relaunch()`'s completion Task) | `await show(…, attachedTo: nil)` → MainRunLoop (D-27) |
| Layout move error (LayoutBarMoves.move Task), spacing error (GeneralSettingsPane Task) | sheet on the Settings window; dialog through MainRunLoop when it is not on screen (D-25) |
| New risk from the fix (context 4): the defaults observer and push Debouncer now run while a prompt is open and could push this Mac's settings over the newer file, so "Restart" applies nothing | pending key set before the hint; `needsExchange(.localChange)` is false while pending (tested in the sync part, `pendingBlocksPush`); a Core test pins hint ⇔ decide (D-28) |
| A local change after the restart hint would be lost on "Restart" | I-2: hint re-evaluated on change and at click |

<interfaces>
New and changed signatures (the executor implements these; bodies are described in section 3):

```swift
// holzBar/Core/MainRunLoop.swift (new)
enum MainRunLoop {
    static func run<Value: Sendable>(_ work: @escaping @MainActor @Sendable () -> Value) async -> Value
}

// holzBar/Core/SettingsSyncPolicy.swift (added at the end of the file)
extension SettingsSyncPolicy {
    nonisolated enum Hint: Equatable, Sendable {
        case restart
        case choice(isJoining: Bool)
    }
    static func hint(for local: Local) -> Hint
}

// holzBar/Utilities/Extensions.swift (new MARK section)
extension NSAlert {
    @discardableResult
    func present(attachedTo window: NSWindow? = nil) async -> NSApplication.ModalResponse
}

// holzBar/Utilities/SettingsBackup.swift
static func exportToFile(attachedTo window: NSWindow?)
static func importFromFile(attachedTo window: NSWindow?)
static func relaunch()                                   // signature unchanged
private static func show(_ error: Error, message: String, attachedTo window: NSWindow?) async

// holzBar/Utilities/SettingsSync.swift
private(set) var hint: SettingsSyncPolicy.Hint?
func restartWithWaitingSettings()
func chooseSettings()

// holzBar/MenuBar/ControlItem/ControlItem.swift
@objc private func restartWithWaitingSettings()          // → appState?.settingsSync.restartWithWaitingSettings()
@objc private func chooseSyncedSettings()                // → appState?.settingsSync.chooseSettings()
```

Existing APIs used: `NSAlert.beginSheetModal(for:) async -> NSApplication.ModalResponse` (already
used in SettingsSync), `NSAlert.beginSheetModal(for:completionHandler:)`,
`NSMenuItem.sectionHeader(title:)` (macOS 14.0, the deployment target: no `#available`),
`ObservationLoop.observe(_:onChange:)` (Equatable overload), `AppState.activate(for: .settings)`,
`AppState.openWindow(.settings)`, `AppNavigationState.settingsWindow` / `isSettingsPresented` /
`settingsNavigationIdentifier`.
</interfaces>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (tracer): MainRunLoop in Core, NSAlert.present, "Not enough room" off the task</name>
  <files>holzBar/Core/MainRunLoop.swift, Tests/HolzBarCoreTests/MainRunLoopTests.swift, holzBar/Utilities/Extensions.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift</files>
  <precondition>`git -C WT rev-parse --abbrev-ref HEAD` is `audit-manual/sync-alerts`, HEAD is `ec55d265` or a descendant, `git -C WT status --short` shows only the two untracked plan files, and `git -C WT log --oneline --grep='F-14'` is empty.</precondition>
  <read_first>WT/holzBar/Core/BlockingWork.swift, WT/Tests/HolzBarCoreTests/BlockingWorkTests.swift, S/audit-synth/modal.swift, WT/Package.swift (test targets use approachable concurrency without default isolation), WT/holzBar/Utilities/Extensions.swift lines 1-20 and 420-434, WT/holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift lines 985-1041</read_first>
  <behavior>
    - Test "The work runs on the main thread, from the main run loop's default mode": inside the work, Thread.isMainThread is true and RunLoop.current.currentMode == .default.
    - Test "Main-actor tasks run while the work runs a nested run loop": the work spawns a separate @MainActor Task that sets a flag (a @MainActor final class box, not a captured var), then runs RunLoop.current.run(mode: .default, before:) in a loop until the flag is set or about 0.3 s passed; the work returns the flag; expect true.
    - Test "The work's result is returned", arguments [0, 1, 42].
    - Suite is @MainActor, .serialized, .timeLimit(.minutes(1)).
  </behavior>
  <action>
Implements D-27 and D-30 (and the D-24 path for the first windowless call site).
RED: create Tests/HolzBarCoreTests/MainRunLoopTests.swift (no file header, like BlockingWorkTests; imports Foundation, Testing, @testable HolzBarCore; a short doc comment on the suite saying what F-14 was) with the three tests in behavior; run them and see them fail to compile (no MainRunLoop yet).
GREEN: create holzBar/Core/MainRunLoop.swift with the standard file header (//, //  MainRunLoop.swift, //  holzBar, //), import Foundation, and enum MainRunLoop with run(_:) exactly as section 3.1 describes (withCheckedContinuation, RunLoop.main.perform(inModes: [.default]), MainActor.assumeIsolated, CFRunLoopWakeUp(CFRunLoopGetMain())). Doc comment density like BlockingWork.swift.
Run the suite. If the tests hit the time limit because the swift test host's main thread runs no CFRunLoop (the work never starts), apply the decision's fallback (D-30): delete MainRunLoopTests.swift, write a probe under S/alerts-probe/ that compiles the real WT/holzBar/Core/MainRunLoop.swift together with an async @main file (swiftc -parse-as-library, target arm64-apple-macos14.0, CLT SDK) and prints when a spawned main-actor task runs inside a 0.3 s nested default-mode loop started through MainRunLoop.run, run it, keep its output for the SUMMARY, and report the fallback. Expected: the tests run (Swift's async main uses CFRunLoopRun when CoreFoundation is loaded).
Then add to holzBar/Utilities/Extensions.swift a new section "// MARK: - NSAlert" directly before "// MARK: - NSApplication" with NSAlert.present(attachedTo:) as section 3.2 describes (sheet only for a visible, non-miniaturized window without an attached sheet; otherwise MainRunLoop.run with the alert's own runModal), @discardableResult, doc comment naming F-14.
In MenuBarItemManager.temporarilyShow (line 1035-1041, the "Not enough room" branch) replace the direct modal call with an awaited present() without a window (I-8); keep the warning log and the return.
<!-- planner-discipline-allow: runModal() -->
  </action>
  <verify>
    <automated>zsh S/sync-test.sh --filter MainRunLoop | grep 'SWIFT TEST EXIT: 0' && zsh S/appcheck.sh WT alerts-t1 | tail -1 | grep '^ERRORS: 0  EXIT: 0' && cd WT && test -z "$(git grep -n 'runModal()' -- holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift | grep -v -E ':[0-9]+:[[:space:]]*///?')"</automated>
  </verify>
  <acceptance_criteria>
    - sync-test.sh prints "SWIFT TEST EXIT: 0" and the MainRunLoop suite passes 5 test cases (3 tests, one with 3 arguments), or the fallback probe output shows the spawned task running inside the nested loop and the SUMMARY records the fallback.
    - appcheck prints "ERRORS: 0  EXIT: 0".
    - MenuBarItemManager.swift contains no direct modal alert call; it calls present() on the alert.
  </acceptance_criteria>
  <done>The helper exists in Core with a passing Swift Testing proof (or the recorded probe fallback), the AppKit wrapper exists, and the first windowless alert runs from the main run loop; the app module type-checks.</done>
</task>

<task type="auto">
  <name>Task 2: Settings-window alerts become sheets; relaunch failure through the run loop</name>
  <files>holzBar/Utilities/SettingsBackup.swift, holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift, holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift, holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift, holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift</files>
  <read_first>WT/holzBar/Utilities/SettingsBackup.swift lines 92-180, WT/holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift lines 227-242, WT/holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift lines 133-174, WT/holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift lines 120-133 and 471-494, WT/holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift lines 352-364</read_first>
  <action>
Implements D-24, D-25, D-27 and D-35, with I-4, I-5 and I-6.
SettingsBackup: change exportToFile() and importFromFile() to exportToFile(attachedTo window: NSWindow?) and importFromFile(attachedTo window: NSWindow?). Keep each save/open panel exactly where it is, synchronous in the button action (I-6: a panel moved into a Task would re-create F-14). Export: the write stays synchronous; on error start a Task that awaits show(error, message:, attachedTo: window). Import: everything after the panel returned a URL (the file-URL check, reading, parsing, the "Replace your settings?" alert with its destructive Import and Restart button and Escape on Cancel, apply(settings, removesMissingKeys: true), the notice log, relaunch()) moves into one Task; the alert is awaited with present(attachedTo: window) and only the first button continues; errors go through the awaited show with the same window. Building the settings inside the Task keeps the non-Sendable dictionary in one region. relaunch(): the completion's main-actor Task awaits show(error, message:, attachedTo: nil) for the failure (windowless, D-27) and terminates otherwise. show becomes private static async with the window parameter and awaits present(attachedTo:) after logging (log line unchanged).
AdvancedSettingsPane.settingsBackup: pass appState.navigationState.settingsWindow to both calls.
LayoutBarMoves.move (LayoutBarPaddingView.swift): in the catch of the Task, after showItemCache(), await NSAlert(error: error).present(attachedTo: appState.navigationState.settingsWindow).
GeneralSettingsPane.applyTempItemSpacingOffset: in the catch, await NSAlert(error: error).present(attachedTo: appState.navigationState.settingsWindow); isApplyingItemSpacingOffset = false stays after it.
LayoutBarItemView.mouseDragged: both early-return branches call a new private helper showSheet(_ alert: NSAlert) that does nothing unless the view's window exists and has no attached sheet, and otherwise starts the alert synchronously as a sheet on that window with beginSheetModal(for:completionHandler: nil) (I-5). provideAlertForDisabledItem/provideAlertForUnresponsiveItem stay unchanged.
Leave ConflictingApps.swift and URLCommands.swift untouched (D-35).
<!-- planner-discipline-allow: runModal() -->
  </action>
  <verify>
    <automated>zsh S/appcheck.sh WT alerts-t2 | tail -1 | grep '^ERRORS: 0  EXIT: 0' && cd WT && test -z "$(git grep -n 'runModal()' -- holzBar/Utilities/SettingsBackup.swift holzBar/MenuBar/LayoutBar holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift | grep -v 'panel.runModal()' | grep -v -E ':[0-9]+:[[:space:]]*///?')" && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools S/swiftlint/swiftlint lint --strict --quiet</automated>
  </verify>
  <acceptance_criteria>
    - appcheck "ERRORS: 0"; SwiftLint exit 0.
    - In the five files, the only remaining modal calls are the two `panel.runModal()` in SettingsBackup.swift.
    - `git -C WT grep -n 'attachedTo:' -- holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift` shows the export and import calls with `appState.navigationState.settingsWindow`.
  </acceptance_criteria>
  <done>Every alert raised from the Settings window is a sheet on it (with the usual dialog as fallback), the relaunch failure runs from the main run loop, and no alert in these files runs a modal loop inside a Task.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: SettingsSyncPolicy.Hint (Core) with tests</name>
  <files>holzBar/Core/SettingsSyncPolicy.swift, Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift</files>
  <read_first>WT/holzBar/Core/SettingsSyncPolicy.swift lines 176-309, WT/Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift lines 1-60 and 74-150</read_first>
  <behavior>
    - hint(for: local(base, base: base)) == .restart; hint(for: local(changed, base: base)) == .choice(isJoining: false); hint(for: local(changed, base: nil)) == .choice(isJoining: true); hint(for: local(base, base: nil)) == .choice(isJoining: true).
    - For each of local(base, base: base), local(changed, base: base), local(changed, base: nil) and the newer foreign file version("other"): decide(.check) == .apply exactly when hint == .restart, and decide(.check) == .ask exactly when hint is .choice.
    - A local change turns a restart hint into a choice: with pending set, local(base, base: base, pending: d) gives .restart and local(changed, base: base, pending: d) gives .choice(isJoining: false).
  </behavior>
  <action>
Implements D-26, D-32 and I-1, I-2 (pure part).
RED: add a "// MARK: Hints" section to SettingsSyncPolicyTests with three tests for the behavior above, using the suite's local(_:base:pending:postponed:forcesWrite:) and version(_:…) helpers; run and see them fail to compile.
GREEN: append to SettingsSyncPolicy.swift an extension with the nonisolated enum Hint (cases restart and choice(isJoining:), Equatable, Sendable) and static func hint(for local: Local) as section 3.3 describes; doc comments say what each hint offers (restart: Restart in the sync settings and the holzBar menu; choice: the conflict question in a sheet in Settings) and that the split matches decide's apply/ask for a newer version. Do not change decide, needsExchange, Local or the existing tests.
  </action>
  <verify>
    <automated>zsh S/sync-test.sh --filter SettingsSyncPolicy | grep 'SWIFT TEST EXIT: 0'</automated>
  </verify>
  <acceptance_criteria>
    - "SWIFT TEST EXIT: 0"; the three new tests pass with the existing SettingsSyncPolicy tests.
    - `git -C WT diff --stat -- holzBar/Core/SettingsSyncPolicy.swift` shows only insertions.
  </acceptance_criteria>
  <done>The hint decision is a tested pure function consistent with the sync decision table.</done>
</task>

<task type="auto">
  <name>Task 4: Sync offers changes quietly; conflicts as sheets on the Settings window; menu and Settings hint; strings</name>
  <files>holzBar/Utilities/SettingsSync.swift, holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift, holzBar/MenuBar/ControlItem/ControlItem.swift, holzBar/Resources/Localizable.xcstrings</files>
  <read_first>WT/holzBar/Utilities/SettingsSync.swift (whole file; focus 13-40, 246-313, 474-633, 832-868, 1148-1279), WT/holzBar/Core/ObservationLoop.swift, WT/holzBar/Main/AppState.swift lines 355-430, WT/holzBar/Settings/SettingsWindow.swift, WT/holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift lines 292-338, WT/holzBar/MenuBar/ControlItem/ControlItem.swift lines 571-708, section 2 and 3.4 of this plan</read_first>
  <action>
Implements D-26, D-28, D-31, D-32, D-33, D-34, D-29 and I-1, I-2, I-3, I-7.
SettingsSync.swift, following the table in section 3.4:
(a) Add the hint state (observable hint, ignored waitingVersion, ignored settingsWindowObserver plus the pending presentation closure) next to the existing question state (lines 293-303), with one-line doc comments.
(b) handle(_:of:): replace both windowless prompt calls with setPending first and then offer(remote, local: request.local); add withdrawHint() after the pending/markSynced handling of .none, .adopt and both .write branches.
(c) Add private offer(_:local:), withdrawHint() (clears hint and waitingVersion, cancels a waiting hint presentation), refreshHint() (live Local from syncedSettings, baseKey, pendingKey; no-op without a waiting version).
(d) forgetSyncState(), commitJoin(_:) and use(_:join:) call withdrawHint().
(e) settingsDidChange(): when a hint is shown, call refreshHint() before the existing logic.
(f) Public restartWithWaitingSettings() and chooseSettings(), private presentChoice(on:) and showSettings(then:) as section 3.4 describes; showSettings selects the Advanced pane, activates for .settings, presents at once when Settings is on screen, otherwise opens it and waits with ObservationLoop on isSettingsPresented (no timers, no polling).
(g) finishJoin: present the join conflict through showSettings with the Settings window instead of the window captured at click; remove the window field of JoinRequest and the key-window capture in chooseFolder (its NSOpenPanel stays synchronous).
(h) Remove scheduleWindowlessPrompt entirely (including its app activation), the restart case of SyncPrompt (or collapse SyncPrompt to the conflict data), the restart branch of makeAlert and of answer. answer keeps the conflict semantics of section 3.4 (Later keeps the hint, I-3).
(i) Update the doc comments that describe the old behaviour: the type comment (lines 19-23: newer settings are applied at launch or after the user chooses Restart in a quiet hint in the sync settings and the holzBar menu; holzBar never opens a dialog by itself, F-14), chooseFolder's (a sheet on the Settings window), and the MARK "Questions" section.
AdvancedSettingsPane.SettingsSyncToggle: while sync is on, the HStack starts with Button("Restart") calling restartWithWaitingSettings() for .restart, or Button("Choose Settings…") calling chooseSettings() for .choice, before Change… and Turn Off; the label VStack gets, after the folder line, Text("Settings changed on another Mac") in .subheadline and .secondary while a hint is shown. The annotation text stays.
ControlItem.createMenu(with:): when appState.settingsSync.hint is non-nil, start the menu with NSMenuItem.sectionHeader(title: String(localized: "Settings changed on another Mac")), then an item titled String(localized: "Restart") with action restartWithWaitingSettings or String(localized: "Choose Settings…") with action chooseSyncedSettings (target self), then a separator, then the existing items. Add the two @objc wrappers next to toggleZenMode with one-line doc comments.
Localizable.xcstrings: add "Choose Settings…" (section 5 values, state translated, same JSON shape and key order style as "Change…"); remove the entry "holzBar can restart now to use the settings from the sync folder." after confirming with strings-check.py --list that no code uses it (I-7). German uses Swiss spelling: "ss", never the sharp s.
<!-- planner-discipline-allow: scheduleWindowlessPrompt -->
  </action>
  <verify>
    <automated>zsh S/appcheck.sh WT alerts-t4 | tail -1 | grep '^ERRORS: 0  EXIT: 0' && cd WT && python3 .github/scripts/strings-check.py && test "$(grep -c 'scheduleWindowlessPrompt' holzBar/Utilities/SettingsSync.swift)" = 0 && test "$(grep -c 'NSApp.activate' holzBar/Utilities/SettingsSync.swift)" = 0 && test "$(git grep -n 'runModal()' -- holzBar/Utilities/SettingsSync.swift | grep -v -E ':[0-9]+:[[:space:]]*///?' | wc -l | tr -d ' ')" = 1 && test "$(grep -c 'ß' holzBar/Resources/Localizable.xcstrings)" = 0</automated>
  </verify>
  <acceptance_criteria>
    - appcheck "ERRORS: 0"; strings-check exit 0; its string count stays at 373 (one key added, one stale key removed).
    - SettingsSync.swift: no windowless prompt function, no app activation, exactly one modal call left (the folder panel in chooseFolder).
    - `grep -n 'setPending(remote.modified)' WT/holzBar/Utilities/SettingsSync.swift` shows the call directly before each `offer(` call in handle (push guard first, D-28).
    - `grep -n 'withdrawHint()' WT/holzBar/Utilities/SettingsSync.swift` covers handle (.none, .adopt, .write), forgetSyncState, commitJoin and use.
    - ControlItem.swift contains `sectionHeader(title:` and both @objc wrappers; AdvancedSettingsPane.swift contains "Choose Settings…" and "Settings changed on another Mac".
  </acceptance_criteria>
  <done>Background sync never opens a dialog; the hint with Restart or Choose Settings… appears in Settings and the holzBar menu; conflicts are sheets on the Settings window; pushes stay paused while a version waits; strings complete in five languages.</done>
</task>

<task type="auto">
  <name>Task 5: Full gates, SUMMARY, one commit</name>
  <files>.planning/audit/remediation/sync-alerts-alerts-SUMMARY.md</files>
  <read_first>WT/.planning/audit/remediation/sync-alerts-sync-SUMMARY.md (format to mirror), sections 6-9 of this plan</read_first>
  <action>
Implements D-24…D-35 verification and I-9.
Run every gate of section 7 on the final tree (G1-G8). If one fails and cannot be fixed within the decision, restore the tracked files with git -C WT checkout -- on each listed source file, delete the new untracked source files, report fix-failed with the reason and stop (the PLAN files stay).
Write .planning/audit/remediation/sync-alerts-alerts-SUMMARY.md in the sync part's format: frontmatter (phase, plan: alerts, subsystem: alerts, tags, requirements [F-14], status, key-files, completed, plan_head_before, actuals), the decision, the per-finding account (call site → how it closed), gates table, deviations, interpretations I-1…I-9, known risks (section 8), doc updates needed (section 9), the maintainer's hand test (section 8), which of the sync part's user test steps changed (step 3: Later now in the sheet from the hint; step 7: replaced by hand test 8 below), and the out-of-scope signing question.
Commit once with the message of section 6 written to S/alerts-msg.txt, staging exactly the files of section 6.
  </action>
  <verify>
    <automated>zsh S/sync-test.sh | grep 'SWIFT TEST EXIT: 0' && zsh S/sync-gates.sh alerts-final && cd WT && test "$(git grep -n 'runModal()' -- holzBar | grep -v -E ':[0-9]+:[[:space:]]*///?' | grep -v 'panel.runModal()' | wc -l | tr -d ' ')" = 3 && git log --oneline -1 && git status --short</automated>
  </verify>
  <acceptance_criteria>
    - Full swift test green ("SWIFT TEST EXIT: 0"), all sync-gates lines exit 0, ERRORS 0, ESZETT 0.
    - G8 lists exactly three lines (Extensions.swift, ConflictingApps.swift, URLCommands.swift).
    - `git -C WT log --oneline ec55d265..HEAD` shows exactly one commit starting with "fix(alerts): resolve F-14 —".
    - `git -C WT status --short` shows only the two untracked PLAN files.
  </acceptance_criteria>
  <done>F-14 is fixed in one commit on audit-manual/sync-alerts with all local gates green and the SUMMARY committed.</done>
</task>

</tasks>

## 4. Tests to add (summary)

| File | Test | Proves |
|------|------|--------|
| Tests/HolzBarCoreTests/MainRunLoopTests.swift | work runs on the main thread in `.default` mode | the helper runs from the run loop, not inline in the task (D-27) |
| same | main-actor tasks run inside a nested run loop started through the helper | the F-14 mechanism is closed for windowless alerts (D-30, probe case B) |
| same | result returned, arguments [0, 1, 42] | the awaited answer arrives |
| Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift | hint for unchanged / changed / joining | I-1 |
| same | hint ⇔ decide(.check) apply/ask for a newer foreign version | the hint never offers Restart where the policy would ask (D-28, D-32) |
| same | a local change turns restart into choice | I-2 |

The app-side flows (sheets, menu, Settings row, window wait) live in the app target, which only CI
compiles with Xcode; locally they are type-checked by appcheck (G5) and verified by hand (section 8).

## 5. New string (D-29; machine-written, terms and ellipsis spacing as in the catalog)

Reused keys (no new entry): "Settings changed on another Mac", "Restart", "Later", "Cancel", "Use
Settings from Sync Folder", "Keep This Mac's Settings", "Which settings should holzBar use?", the
conflict informative text. Removed key (unused after this part): "holzBar can restart now to use the
settings from the sync folder."

| Key (en) | de | fr | it | rm |
|---|---|---|---|---|
| Choose Settings… | Einstellungen auswählen … | Choisir les réglages… | Scegli le impostazioni… | Tscherner ils parameters … |

(de and rm put a space before "…" as in "Ändern …", "Bild auswählen …", "Tscherner in maletg …"; fr
and it do not, as in "Choisir une image…", "Scegli immagine…". Shape: `"localizations"` with `de`,
`fr`, `it`, `rm`, each `{"stringUnit": {"state": "translated", "value": …}}`.)

## 6. Commit (git -C WT add <files> && git -C WT commit -F S/alerts-msg.txt)

Git identity is configured; do not change git config. Stage exactly: holzBar/Core/MainRunLoop.swift,
Tests/HolzBarCoreTests/MainRunLoopTests.swift (unless the D-30 fallback removed it),
holzBar/Core/SettingsSyncPolicy.swift, Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift,
holzBar/Utilities/Extensions.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift,
holzBar/Utilities/SettingsBackup.swift, holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift,
holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift, holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift,
holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift, holzBar/Utilities/SettingsSync.swift,
holzBar/MenuBar/ControlItem/ControlItem.swift, holzBar/Resources/Localizable.xcstrings,
.planning/audit/remediation/sync-alerts-alerts-SUMMARY.md.

    fix(alerts): resolve F-14 — keep holzBar running while an alert is open, offer synced changes quietly

    The maintainer chose sheets in Settings and a quiet sync hint.
    runModal() inside main-actor tasks started a nested run loop that does not
    serve the main queue, so all main-actor work, macOS 27 click replay included,
    waited until the alert closed; another Mac could open the sync alert anytime.
    Settings alerts are now sheets; windowless ones run from the main run loop
    (new Core MainRunLoop, tested). Sync opens no dialog: a hint with Restart sits
    in the sync settings and the holzBar menu, conflicts are a sheet in Settings,
    and pushes stay paused while another Mac's version waits.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

## 7. Gates (run from WT; all must pass before the commit; G5 also after each task)

| Gate | Command | Pass |
|------|---------|------|
| G1 | `zsh S/sync-test.sh` (swift test with `--scratch-path S/build-sync-alerts`, retries the TestingMacros transient) | "SWIFT TEST EXIT: 0", all suites pass (sync part ended at 307 tests; expect about 315) |
| G2 | `cd WT && python3 .github/scripts/strings-check.py` | exit 0 |
| G3 | `cd WT && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs` | exit 0 |
| G4 | `cd WT && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools S/swiftlint/swiftlint lint --strict --quiet` | exit 0 |
| G5 | `zsh S/appcheck.sh WT <label>` (whole app module, Swift 6, MainActor default isolation, CLT SDK 26.5, target 14.0) | `ERRORS: 0  EXIT: 0` |
| G6 | `cd WT && git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` | no output |
| G7 | `grep -c 'ß' WT/holzBar/Resources/Localizable.xcstrings` | 0 |
| G8 | `cd WT && git grep -n 'runModal()' -- holzBar \| grep -v -E ':[0-9]+:[[:space:]]*///?' \| grep -v 'panel.runModal()'` | exactly 3 lines: Utilities/Extensions.swift (inside MainRunLoop.run), Main/ConflictingApps.swift (D-35), Main/URLCommands.swift (D-35) |

`zsh S/sync-gates.sh <label>` runs G2-G7 plus the MenuBarItemService type check in one go. No Xcode
on this Mac: the real app build and the macOS 26/27 compat legs run in CI after the chain's single
push (not in this part).

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| sync folder → holzBar | Anyone who can write the synced folder (shared Dropbox/Nextcloud folder, network share, Syncthing peer) can make a new Settings.plist appear at any time; before this part that opened a modal dialog and stalled holzBar |
| user input → event tap (macOS 27) | Clicks on system items are held back by SystemItemClickBridge27 and replayed by a main-actor task |
| holzBar → local preferences | "Restart" and "Use Settings from Sync Folder" write the other Mac's settings into the defaults |

## STRIDE Threat Register

Continues the chain's numbering after the sync part's T-SA-05.

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-SA-06 | Denial of service | Sync folder writer → modal alert stalls the main actor and holds back macOS 27 system-item clicks | medium | mitigate | Background sync shows only a quiet hint (no dialog, no activation); conflicts are window-modal sheets opened by the user; remaining windowless alerts run through MainRunLoop so the main actor keeps running (Tasks 1, 4) |
| T-SA-07 | Tampering | Push while a newer foreign version waits overwrites it (new risk once the main actor runs during prompts) | medium | mitigate | `setPending` before every hint; `needsExchange(.localChange)` false while pending; Core test pins hint ⇔ decide (Tasks 3, 4) |
| T-SA-08 | Tampering | "Restart" applying the other Mac's settings over this Mac's changes made after the hint appeared | low | mitigate | Hint re-evaluated on local change and at click; changed settings lead to the conflict sheet instead (I-2) |
| T-SA-09 | Denial of service | Repeated alerts (drag events, repeated errors) stacking sheets or dialogs | low | mitigate | One sheet per drag (attachedSheet check); present() falls back to one queued run-loop dialog that only starts in default mode, never inside another modal |
| T-SA-10 | Spoofing | A folder writer re-writing the file to keep a hint visible | low | accept | The hint is passive and names no content; the user decides; the sync part's validation of applied values is unchanged |
| T-SA-SC | Tampering | npm/pip/cargo installs | high | accept | No package is installed; only system frameworks (Foundation, AppKit) are used; no network |
</threat_model>

## 8. Risks for macOS 26 and 27, and the maintainer's hand test

Risks:

1. **Run-loop behaviour on macOS 27 and with Swift 6.4's main executor.** The probe ran on macOS
   26.7.1. If a newer main executor schedules main-actor jobs differently, the nested modal from
   MainRunLoop could still delay them. Only the rare windowless alerts are exposed (Not enough room is
   macOS 26 only; relaunch failure; fallbacks when Settings is closed); sync no longer uses a modal.
   Hand test 8 checks it.
2. **Test host.** If `swift test` does not run a CFRunLoop on the main thread, the Core test cannot
   run; Task 1 then switches to the probe fallback (D-30) and the SUMMARY says so.
3. **Overlooked hint.** By the maintainer's choice nothing pushes itself forward. While a hint waits,
   this Mac's own changes are not synced (pushes paused, D-28) and the other Mac's settings apply only
   on Restart or silently at the next launch (when this Mac changed nothing). Accepted trade-off of the
   decision ("wer den Hinweis übersieht, behält die alten Einstellungen länger").
4. **Opening Settings for the sheet.** The sheet waits for `isSettingsPresented`, which follows the
   window's `isVisible` through KVO and a Task. If Settings is replaced by the permissions window
   (permissions missing), the request waits until Settings is shown; the hint stays usable.
5. **Sheets on SwiftUI windows.** AppKit sheets on the SwiftUI Settings window already work (sync part's
   join sheet). Section headers (`NSMenuItem.sectionHeader`) render in status-item menus on 14-27.
6. **Behaviour change of the import flow.** The confirmation is now a sheet after the open panel; the
   panel itself stays app-modal (I-6).
7. **Adjacent, not changed (scope).** `ControlItem.performAction` shows the menu for Control-click
   inside a Task (`Task { … showMenu() … }`), so menu tracking runs inside a main-queue job and stalls
   main-actor work while that menu is open. Same mechanism, not an alert and not in F-14 or the
   decision; reported for the maintainer, not fixed here. ConflictingApps (pre-setup) likewise (D-35).
8. **Compile coverage.** The app target is only type-checked locally (G5, CLT SDK 26.5); CI's Xcode 27
   build is the first real build. Sendable annotations of `RunLoop.perform` or `NSAlert` in the 27 SDK
   could differ; MainRunLoop's `@MainActor @Sendable` work closure is the conservative choice.

Maintainer hand test (macOS 26 and macOS 27; two Macs with the same sync folder where noted):

1. **Restart hint (two Macs).** Change a setting on Mac A. On Mac B no dialog appears and holzBar does
   not come to the front. Open the holzBar menu: header "Settings changed on another Mac", item
   "Restart". Settings > Advanced shows the same line and a Restart button. Choose Restart: B
   relaunches with A's setting.
2. **Hint turns into a choice.** With the Restart hint on B, change a setting on B and wait 5 s: the
   menu item and the button read "Choose Settings…". Within 5 s of a change, clicking Restart opens
   the sheet instead of restarting.
3. **Background conflict (two Macs).** Change a setting on B first (or make B offline), then on A.
   B shows "Choose Settings…" only. Choose it from the holzBar menu with Settings closed: Settings opens
   on Advanced with the question as a sheet. Later: the sheet closes, the hint stays, A's file is not
   overwritten (its modification date stays). Choose again → "Keep This Mac's Settings": B's hint goes,
   A shows the Restart hint.
4. **Turn On… / Change…** with a folder holding different settings: the question is a sheet on the
   Settings window. Choose a folder whose file is online-only and close Settings while it loads: Settings
   reopens with the sheet.
5. **Push guard.** While any hint is shown on B, change settings on B: A gets nothing (file date
   unchanged) until B restarts or chooses.
6. **Settings sheets.** Layout pane: drag a non-movable item (one sheet per drag, not a stack). Import…:
   after the open panel, "Replace your settings?" is a sheet; Cancel and Escape close it; Import and
   Restart relaunches. Export into a read-only folder: the error is a sheet. With Settings closed, an
   error from a layout move undo shows the usual dialog.
7. **Not enough room (macOS 26).** With a crowded menu bar, open a hidden item from the Shelf: the dialog
   appears and, while it is open, hover and the Shelf keep working.
8. **macOS 27 clicks.** With the conflict sheet (test 3) and the import sheet (test 6) open, click the
   clock, battery, Wi-Fi and Control Centre while items are concealed: their menus open at once.
9. **Languages.** In de, fr, it and rm (Language & Region > Apps > holzBar) the menu header, Restart,
   Choose Settings… and the Settings line fit and read naturally.

## 9. Doc updates needed (not done in this part)

- `docs/features.md` (sync bullet, line 59): changes from another Mac show a quiet hint with Restart in
  Settings > Advanced and the holzBar menu; when both Macs changed, Choose Settings… asks in Settings;
  holzBar never interrupts with a dialog.
- Release notes of the next beta (`docs/release-notes/v0.0.7-beta2.md`): Fixed F-14 (an open alert no
  longer pauses holzBar; on macOS 27 clicks on the clock, battery, Wi-Fi and Control Centre are no
  longer held back while one is open); Changed: alerts in Settings appear as sheets; the sync restart
  dialog became a quiet hint.
- README and the comparison table: no change (the sync row stays true).
- `SECURITY.md`: no change needed (no new permission, no new network or file access).
- The sync part's SUMMARY user test steps 3 and 7 are superseded by hand tests 3 and 8 above.

## 10. Source coverage audit

| SOURCE | ID | Item | Task | Status |
|--------|----|------|------|--------|
| GOAL | — | Implement "Sheets und stiller Hinweis" for F-14 | 1-5 | COVERED |
| REQ | F-14 | runModal inside main-actor Tasks blocks main-actor work | 1, 2, 4 | COVERED |
| RESEARCH | F-14 fix | sheets / non-modal; else start the modal from a run-loop source; start with the sync alert | 1, 2, 4 | COVERED |
| CONTEXT | D-24 … D-28, D-31 … D-35 | section 1 | 1, 2, 4 | COVERED |
| CONTEXT | D-29 | strings in five languages | 4 | COVERED |
| CONTEXT | D-30 | Core test (or probe fallback) | 1 | COVERED |
| OUT OF SCOPE | — | ConflictingApps alert, URLCommands question, file panels, Control-click menu in a Task | — | unchanged, reported (D-35, risk 7) |
| OUT OF SCOPE | — | Release signing question relayed by the user | — | routed to the maintainer |

<verification>
- G1-G8 green on the final tree; G5 green after every task.
- `git -C WT log --oneline ec55d265..HEAD` shows exactly one commit, "fix(alerts): resolve F-14 — …".
- Every row of section 3.5 maps to code in the diff; every truth in must_haves maps to a gate or a hand test.
</verification>

<success_criteria>
- No alert runs a modal loop inside a Task or async function anywhere in holzBar (G8).
- Background sync never opens a dialog or activates holzBar; the hint appears in Settings and the holzBar menu.
- Conflicts are sheets on the Settings window, from the hint and from Turn On…/Change….
- No push while a foreign version waits.
- MainRunLoop is tested in Core (or the probe fallback is recorded).
- One new string in five languages; strings-check passes; no "ß".
</success_criteria>

<output>
Report to the orchestrator and write `WT/.planning/audit/remediation/sync-alerts-alerts-SUMMARY.md`
(committed with the fix): commit hash and subject, gate results, interpretations I-1…I-9, risks and
the open hand test (section 8), doc_updates_needed (section 9), the adjacent Control-click menu
observation, and the out-of-scope signing question.
</output>
