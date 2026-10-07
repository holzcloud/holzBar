---
phase: audit-remediation-sync-alerts
plan: alerts
subsystem: alerts
tags: [alerts, concurrency, sync, macos27, l10n]
requirements: [F-14]
status: complete
key-files:
  created:
    - holzBar/Core/MainRunLoop.swift
    - Tests/HolzBarCoreTests/MainRunLoopTests.swift
  modified:
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
completed: 2026-10-05
plan_head_before: ec55d265
actuals:
  tasks: 5
  commits: 1
---

# Chain sync-alerts, part alerts: keep holzBar running while an alert is open, offer synced changes quietly (F-14)

The maintainer chose **"Sheets und stiller Hinweis"** (decision `modal-alerts-1.md`: options 2
and 3 together, plus option 1's run-loop helper and its Core test). An alert that holzBar opens
from a task no longer pauses holzBar:
- alerts from the Settings window are sheets on it;
- the two remaining windowless alerts start from the main run loop through the new, tested
  Core helper `MainRunLoop`;
- settings sync never opens a dialog by itself. A newer version from another Mac becomes a quiet
  hint ("Settings changed on another Mac" with "Restart" or "Choose Settings…") in Settings >
  Advanced and at the top of the holzBar menu. Conflicts are asked in a sheet on the Settings
  window.

## Commit (branch audit-manual/sync-alerts, base ec55d265)

| Commit | Findings | Subject |
|--------|----------|---------|
| (this commit) | F-14 | fix(alerts): resolve F-14 — keep holzBar running while an alert is open, offer synced changes quietly |

## Per finding

**F-14 (medium).** `NSAlert.runModal()` called inside a main-actor task starts a nested run loop
inside a job of the main dispatch queue. That loop does not serve the main queue, so every other
main-actor job waited until the alert closed. This covered hover, the Shelf, concealment and the
image cache, and on macOS 27 the replay of held-back clicks on the clock, battery, Wi-Fi and
Control Centre (SystemItemClickBridge27). How each call site closed:

| Call site | Before | After |
|-----------|--------|-------|
| SettingsSync, newer version from another Mac (background) | windowless restart dialog, app activated | `setPending` first, then the hint `.restart`; no dialog, no activation |
| SettingsSync, conflict in the background (both Macs changed, or a re-identified Mac) | windowless conflict dialog, app activated | `setPending` first, then the hint `.choice`; "Choose Settings…" opens Settings on Advanced, and the question appears as a sheet on it |
| SettingsSync, Turn On…/Change… with different settings in the folder | sheet on the key window at click time, or a windowless dialog | sheet on the Settings window; if Settings was closed while the folder was read, it opens again and the sheet follows (ObservationLoop on `isSettingsPresented`, no polling) |
| MenuBarItemManager "Not enough room" (macOS 26, in a task) | `runModal()` in the task | `await alert.present()`, a dialog started from the main run loop through `MainRunLoop` |
| SettingsBackup relaunch failure (in the completion task) | `runModal()` in the task | `await show(…, attachedTo: nil)`, through `MainRunLoop` |
| LayoutBarMoves.move error (LayoutBarPaddingView, in a task) | `runModal()` in the task | sheet on the Settings window (dialog through `MainRunLoop` when Settings is not on screen) |
| GeneralSettingsPane spacing error (in a task) | `runModal()` in the task | sheet on the Settings window (same fallback) |
| SettingsBackup import confirmation, import and export errors | `runModal()` in the button action | sheets on the Settings window; the open and save panels stay where they were |
| LayoutBarItemView "not movable" / "unresponsive" (mouseDragged) | `runModal()` per drag event | one sheet on the view's window per drag (skipped while a sheet is attached) |

New code:
- `holzBar/Core/MainRunLoop.swift`: `MainRunLoop.run(_:)`. It uses `RunLoop.main.perform(inModes: [.default])`,
  `MainActor.assumeIsolated` and `CFRunLoopWakeUp`, and the caller awaits the result.
- `NSAlert.present(attachedTo:)` in `Extensions.swift`. It shows a sheet when the window is
  visible, not miniaturized and has no sheet; otherwise it shows the dialog through `MainRunLoop`.
- `SettingsSyncPolicy.Hint` and `hint(for:)` in Core. `.restart` when this Mac changed nothing
  since its base; `.choice(isJoining:)` when it changed settings or joins. This is the same split
  `decide` makes between `.apply` and `.ask` for a newer version from another Mac, and a test
  checks it.
- SettingsSync:
  - observable `hint`, `restartWithWaitingSettings()` and `chooseSettings()`;
  - the question as a sheet (`ask(about:isJoining:on:join:)`) and `showSettings(forHint:onCancel:then:)`;
  - `withdrawHint()` on `.none`, `.adopt` and `.write`, on sync off (`forgetSyncState`), on a folder
    change (`commitJoin`) and on `use`;
  - `refreshHint()` on every local change and on every Restart click.
  - Removed: `scheduleWindowlessPrompt` and its `NSApp.activate()`, `SyncPrompt`, the restart
    dialog and `JoinRequest.window`.
- The holzBar menu (`ControlItem.createMenu`) starts with a section header and the hint item while
  a hint is shown. The sync row in Settings > Advanced shows the same line and a Restart or
  Choose Settings… button.
- Strings: one new key, "Choose Settings…" (de "Einstellungen auswählen …", fr "Choisir les
  réglages…", it "Scegli le impostazioni…", rm "Tscherner ils parameters …"). One stale key was
  removed: "holzBar can restart now to use the settings from the sync folder." The count stays at
  373 strings.

**Push guard (the decision's risk 4).** With the main actor free while a hint or sheet is shown,
the defaults observer and push debouncer run again. Every `offer` follows `setPending(remote.modified)`,
and `needsExchange(.localChange)` is false while that key is set (tested in the sync part,
`pendingBlocksPush`). This Mac therefore writes nothing over the waiting version, and Restart never
finds this Mac's own file.

## Gates

| Gate | Result |
|------|--------|
| `swift test` (full, `S/sync-test.sh`) | 313 tests in 47 suites passed, SWIFT TEST EXIT 0 |
| appcheck (whole app module, Swift 6, SDK 26.5, target 14.0), after each task and on the final tree | ERRORS: 0 EXIT: 0 (labels alerts-t1, alerts-t2, alerts-t4, alerts-final); no new warnings |
| servicecheck (MenuBarItemService) | SERVICE EXIT: 0 |
| SwiftLint `--strict --quiet` | no output, exit 0 |
| privacy-check network / logs | exit 0 / exit 0 |
| strings-check.py | exit 0, "373 strings in 5 languages" |
| former-name check | no match |
| `ß` in Localizable.xcstrings | 0 |
| G8: `runModal()` outside comments and file panels | exactly 3: Extensions.swift (inside `MainRunLoop.run`), ConflictingApps.swift and URLCommands.swift (both left unchanged by D-35) |

MainRunLoop proof: the Core test "Main-actor tasks run while the work runs a nested run loop"
passes. A throwaway probe in the same `swift test` host ran the same nested loop directly in a
main-actor task, and the spawned task did not run (`INLINE RAN INSIDE: false`). So the test tells
the two cases apart and is not true either way. The D-30 fallback (a probe script) was not needed.

## Deviations from the plan

1. **[Rule 3] `hint(for:)` lives in a `nonisolated extension SettingsSyncPolicy`.** The plan put a
   `nonisolated enum Hint` in a plain extension. Under Core's main-actor default isolation that made
   `hint(for:)` main-actor isolated, and the nonisolated test suite could not call it. The
   extension is now `nonisolated`, like `decide`, and `Hint` inherits that.
2. **TDD order in Task 1.** The helper and its tests were written together, so there was no
   separate compile-fail run. The RED evidence is the inline probe above (nested loop in a task:
   the task does not run). Task 3 followed RED (compile failure "no member 'hint'") and then GREEN.
3. **Test count.** Swift Testing counts the parameterized result test as one test, so the
   MainRunLoop suite reports 3 tests (5 cases), and the full run is 313 tests instead of the
   plan's estimate of about 315. The hint-matches-decide test checks four candidates (the plan's
   three, plus joining with unchanged settings).
4. **Waiting for the Settings window.** One `SettingsWindowWait` value (loop, `isForHint` and
   `onCancel`) holds the pending sheet request. If a newer request replaces a waiting join, the
   join's `onCancel` resets `isChoosingFolder`. `withdrawHint()` cancels only a hint request.
   While permissions are missing, `openPermissionsWindowIfNeeded()` opens the permissions window
   instead and the request keeps waiting (the plan's risk 4).
5. **`isAsking` starts when the sheet starts, not when the wait starts.** Otherwise a Settings
   window that never appears (permissions) would hold back every check. Restart is ignored while
   a question sheet is open.
6. **Plan ledger.** The worktree's git dir is inside the main repository
   (`/Users/cheidenreich/privat/holzBar/.git/worktrees/sync-alerts`). The executor's head-before
   ledger was briefly written there and removed at once. It is kept in the scratchpad instead.
   Nothing else outside the worktree was touched.

## Interpretations (I-1 … I-9)

- I-1: two hint kinds. "Restart" is reused, and "Choose Settings…" is the only new string.
- I-2: a local change re-checks the hint (after the existing 5 s debounce), and Restart re-checks
  it at click time. A changed Mac gets the question sheet, never a silent overwrite.
- I-3: "Later" in the sheet keeps the hint, the pending key and paused pushes. The next launch
  asks again through the hint. "Cancel" for a joining Mac turns sync off (unchanged meaning).
- I-4: `present(attachedTo:)` uses a sheet only on a visible, non-miniaturized window without a
  sheet; otherwise it shows one dialog started from the run loop.
- I-5: drag alerts start synchronously as a sheet, at most one per drag.
- I-6: the import and export panels stay app-modal in the synchronous button action.
- I-7: the stale restart-dialog text was removed from the catalog.
- I-8: "Not enough room" is awaited by its caller; the main actor keeps running.
- I-9: one atomic commit together with this SUMMARY.

## Known risks and open items

1. Run-loop behaviour on macOS 27 and with Swift 6.4's main executor: the probe and the test ran
   on macOS 26.7.1 with the CLT toolchain. Only the rare windowless dialogs depend on it.
2. The app target was only type-checked locally (no Xcode on this Mac). CI's Xcode 27 build is the
   first real build.
3. An overlooked hint means this Mac's own changes are not synced until the user acts or
   relaunches (the decision's accepted trade-off).
4. **Adjacent, not changed:** `ControlItem.performAction` shows the menu for a Control-click from
   inside a `Task`. Menu tracking then runs inside a main-queue job and pauses main-actor work the
   same way while that menu is open. It is not an alert and not part of F-14 or the decision, so
   it is reported for the maintainer. ConflictingApps (before setup, relaunch path) and the
   URLCommands question are also unchanged (D-35).

## Doc updates needed (not done here)

- `docs/features.md` (sync bullet): changes from another Mac show a quiet hint with Restart in
  Settings > Advanced and the holzBar menu. When both Macs changed, Choose Settings… asks in
  Settings. holzBar never interrupts with a dialog.
- Release notes of the next beta:
  - Fixed F-14: an open alert no longer pauses holzBar; on macOS 27, clicks on the clock, battery,
    Wi-Fi and Control Centre are no longer held back while one is open.
  - Changed: alerts in Settings appear as sheets, and the sync restart dialog became a quiet hint.
- README and comparison table: no change. SECURITY.md: no change.
- The sync part's user test steps 3 and 7 are replaced by hand tests 3 and 8 below.

## User test steps (macOS 26 and 27; two Macs with one sync folder where noted)

1. Restart hint (two Macs): change a setting on Mac A. Mac B shows no dialog and does not come to
   the front. B's holzBar menu starts with "Settings changed on another Mac" and "Restart", and
   Settings > Advanced shows the same line with a Restart button. Restart relaunches B with A's
   setting.
2. Hint turns into a question: with the Restart hint on B, change a setting on B and wait 5 s.
   The item and the button now read "Choose Settings…". Clicking Restart within those 5 s opens
   the sheet instead of restarting.
3. Background conflict (two Macs): change a setting on B, then a different one on A. B shows only
   "Choose Settings…". Choose it from the holzBar menu with Settings closed: Settings opens on
   Advanced with the question as a sheet. Later closes the sheet and the hint stays; A's file
   date does not change. Choose again, then "Keep This Mac's Settings": the hint on B goes away and
   A shows the Restart hint.
4. Turn On… / Change… with a folder that holds different settings: the question is a sheet on the
   Settings window. With an online-only file, close Settings while it loads: Settings opens again
   with the sheet.
5. Push guard: while a hint is shown on B, change settings on B. A gets nothing until B restarts or
   chooses.
6. Settings sheets:
   - Layout pane: drag a non-movable item; one sheet per drag.
   - Import…: after the open panel, "Replace your settings?" is a sheet. Cancel and Escape close
     it; Import and Restart relaunches.
   - Export into a read-only folder: the error is a sheet.
7. Not enough room (macOS 26): with a crowded menu bar, open a hidden item from the Shelf. While
   the dialog is open, hover and the Shelf keep working.
8. macOS 27 clicks: with the sheet from test 3 or test 6 open, click the clock, battery, Wi-Fi and
   Control Centre while items are concealed. Their menus open at once.
9. Languages (de, fr, it, rm): the menu header, Restart, Choose Settings… and the Settings line fit
   and read naturally.

## Out of scope

The user message relayed with this run ("Können wir das mit dem signieren nicht doch anders
lösen?") is about release signing, which belongs to the `release` chain (decision `release-1.md`).
This part changes nothing about signing, release workflows or secrets. The question goes back to
the maintainer.

## Self-Check: PASSED

The two created files exist. The gates above passed on the final tree before the commit. The
commit contains exactly the files listed in the frontmatter plus this SUMMARY.
