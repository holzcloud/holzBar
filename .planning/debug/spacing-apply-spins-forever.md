---
status: awaiting_human_verify
trigger: "After pressing Apply for Menu bar item spacing in General settings, the spinner spins forever, although the spacing change is applied."
created: 2026-10-09
updated: 2026-10-09
---

## Symptoms

- expected: Spinner stops once spacing is written and apps are relaunched.
- actual: Spinner (isApplyingItemSpacingOffset, GeneralSettingsPane.swift) never stops; the change itself takes effect.
- errors: none shown
- timeline: reported 2026-10-09 (beta3)
- reproduction: Settings > General > Menu bar item spacing > change value > Apply

## Current Focus

hypothesis: CONFIRMED (AND-gate). The spinner is cleared only after the error alert is dismissed; every Apply throws (SystemUIServer ignores and Control Center cancels the quit request, 2 x 10 s), and the alert sheet lands on the Settings window of a non-active app where it is not seen.
bug_class: Bohrbug (deterministic: every Apply on macOS 26.7.1 throws; the hidden alert depends on holzBar not being active at the 20 s mark)
next_action: human verification on a CI-built app (macOS 26 and, if possible, 27): Apply a spacing, switch to another app while it runs, confirm the spinner stops within a few seconds and no alert naming SystemUIServer / Control Center appears; then archive (resolved/ + knowledge-base.md)

reasoning_checkpoint:
  hypothesis: "GeneralSettingsPane keeps isApplyingItemSpacingOffset true until `await NSAlert(error:).present(attachedTo:)` returns, i.e. until the user dismisses the alert. applyOffset() always throws GroupedRelaunchError on macOS 26 because SystemUIServer ignores the quit Apple Event and Control Center answers NSTerminateCancel (each costs the full 10 s timeout). When holzBar is not the active app 20 s later, the alert sheet is ordered beneath the active app's windows, the user never sees it, and the spinner never stops."
  confirming_evidence:
    - "Unified log: quit events to SystemUIServer(856)/Control Center(855) at 13:57:32/13:57:42 and 13:57:59/13:58:09, both still running under the same pids; ControlCenter logs 'applicationShouldTerminate: NSTerminateCancel', SystemUIServer never handles the event."
    - "Unified log: alert sheet begun exactly 10 s after each Control Center quit (13:57:53, 13:58:19); run 2 logs 'ordered front from a non-active application and may order beneath the active application's windows' and the sheet is only dismissed at 13:59:08 after the user reopened Settings from the menu (13:59:05)."
    - "Code: GeneralSettingsPane.swift:355-362 sets isApplyingItemSpacingOffset = false after the awaited alert."
  falsification_test: "If applyOffset had hung, no alert sheet would have been begun; if the spinner were independent of the alert, it would have stopped at 13:58:19 in run 2 - the sheet log shows it was awaited until 13:59:08."
  fix_rationale: "Clearing the spinner when applyOffset returns or throws (before reporting) removes the dependency of the progress on a user dismissal - the root cause of 'spins forever'. Not asking processes that measurably refuse a quit request removes the guaranteed 20 s wait and the false failure alert on every Apply (the trigger), without changing the no-force-terminate policy (BUG-02)."
  blind_spots: "Not reproduced on macOS 27 (no device); other system agents could also refuse quit (only the owners seen on this Mac were measured: SystemUIServer, Spotlight, TextInputMenuAgent, Control Center). Could not run the app (no Xcode), so the UI fix is verified by type check + core test, not by clicking."
  candidate_causes:
    - "code: pane awaits the alert before clearing the spinner (GeneralSettingsPane)"
    - "environment: macOS system agents SystemUIServer / Control Center refuse quit requests, so applyOffset always throws after 20 s"
    - "environment: holzBar is a UIElement app that is usually not active when the alert appears, so the sheet is ordered beneath the active app"
  and_gate: "yes - the endless spinner needs (1) the spinner tied to the alert's dismissal AND (2) an alert at all (guaranteed by the refusing system agents) AND (3) the alert not being seen (holzBar not active). Run 1 had (1)+(2) but holzBar was active, so the user dismissed the alert after 1 s and the spinner stopped. Fix addresses (1) and (2); (3) is standard sheet behaviour and becomes harmless."

## Evidence

- timestamp: 2026-10-09T14:00
  checked: Every await in applyOffset() and GeneralSettingsPane.applyTempItemSpacingOffset()
  found: Bounded - writeSpacingPreferences (sync), Task.sleep x2, quit()/waitUntil (10 s sleep child, AsyncStream iteration ends on cancel; covered by SpacingRelaunchTests), MenuBarItemProvider27.items() (continuation always resumed; AX calls have messaging timeouts). Unbounded - NSWorkspace.openApplication (no timeout), and in the pane the catch path `await NSAlert(error:).present(attachedTo: settingsWindow)` which only returns when the user dismisses the alert (sheet) or the runModal dialog.
  implication: The spinner can only stay forever if openApplication never completes or the error alert is never dismissed/shown.

- timestamp: 2026-10-09T14:03
  checked: Machine is macOS 26.7.1 (25G241), holzBar 0.0.7-beta3 at /Applications. `log show` for (aevt,quit) 13:56:30-14:00.
  found: Two Apply runs in holzBar pid 49394. Run 1 13:57:32.709 quit -> SystemUIServer(856), Spotlight(935), TextInputMenuAgent(1121); 13:57:42.853 (exactly 10 s later) quit -> Control Center(855). Run 2 13:57:59.355 quit -> SystemUIServer(856, same pid), TextInputMenuAgent(49521, new pid); 13:58:09.612 quit -> Control Center(855, same pid). holzBar was then quit and relaunched at ~13:59:35 (pid 50008). ByHost .GlobalPreferences modified 13:58; spacing prefs now absent (offset 0, i.e. run 2 was a reset).
  implication: SystemUIServer and Control Center do NOT quit on a quit Apple Event (same pids after the 10 s timeouts), so every Apply on macOS 26 ends with failedApps non-empty -> GroupedRelaunchError thrown -> the pane awaits NSAlert.present. The spinner therefore depends on the alert path, not on applyOffset hanging.

- timestamp: 2026-10-09T14:08
  checked: `log show` of pids 855/856/935/1121 around the quit events
  found: Spotlight and TextInputMenuAgent log "Handling Quit AppleEvent ... replyToApplicationShouldTerminate:YES" and quit. SystemUIServer (856) receives (aevt,quit) and never handles it. ControlCenter (855) logs "applicationShouldTerminate: NSTerminateCancel ... App termination canceled". Both still run under the same pids now (pgrep 856 SystemUIServer, 855 ControlCenter); both are launchd agents (com.apple.SystemUIServer.agent, com.apple.controlcenter). Bundle IDs com.apple.systemuiserver / com.apple.controlcenter.
  implication: Asking these two to quit can never succeed under holzBar's no-force-terminate policy (BUG-02). Each Apply waits 10 s for SystemUIServer (parallel phase) + 10 s for Control Center, then always reports both as failures. The code comment "Control Center relaunches itself once told to quit" is false on macOS 26.7.1 (it was only true in Ice, which force-terminated after 1 s).

- timestamp: 2026-10-09T14:10
  checked: AppKit window log of holzBar pid 49394 for the two error alerts
  found: Run 1: sheet begun 13:57:53.088 on Settings window 3f39 (holzBar active), "end modal sheet" 13:57:54.13 -> spinner stopped, user pressed Reset 13:57:59. Run 2: sheet begun 13:58:19.97 with "Window <SwiftUI.AppKitWindow> windowNumber=3f39 ordered front from a non-active application and may order beneath the active application's windows." No dismissal until the user chose Settings... (openSettingsWindow) from holzBar's menu at 13:59:05, which ordered the sheet 3f66 front; "end modal sheet 3f66" 13:59:08.8; holzBar quit 13:59:11.
  implication: The spinner stayed for ~70 s because GeneralSettingsPane only clears isApplyingItemSpacingOffset after `await NSAlert(...).present(...)` returns, i.e. after the user dismisses the alert; the alert sheet was placed on the Settings window of a non-active UIElement app, beneath the active app's windows, so the user never saw it ("no error shown").

- timestamp: 2026-10-09T14:30
  checked: Fix verification (commit 37169025 on release/0.0.7, local only)
  found: New/updated SpacingRelaunch tests were red before the fix (missing helper; SystemUIServer returned by processesToRelaunch) and green after; swapping finished()/reportFailure back to the old order makes "The progress ends before a failure is reported" fail. Full swift test 3 + 195 + 356 pass; Scripts/typecheck-app.sh passes (only pre-existing ScreenCapture deprecation warning); SwiftLint 0.65.1 --strict 0 violations; strings/privacy checks pass.
  implication: Fix accepted by the guardrail at unit level; the end-to-end UI check needs a CI-built app (no Xcode here).

## Eliminated

- hypothesis: applyOffset() never returns (quit()/waitUntil, openApplication or MenuBarItemProvider27.items() hangs)
  evidence: In both logged runs the error alert was presented ~20 s after Apply (13:57:32 -> 13:57:53, 13:57:59 -> 13:58:19), i.e. applyOffset threw GroupedRelaunchError after exactly two 10 s quit timeouts. It returns; the waits are bounded. (macOS 26 path; Provider27 not involved on this Mac.)
  timestamp: 2026-10-09T14:10

## Resolution

root_cause: "(1) GeneralSettingsPane.applyTempItemSpacingOffset cleared isApplyingItemSpacingOffset only after `await NSAlert(error:).present(attachedTo:)` returned, i.e. after the user dismissed the error alert; (2) applyOffset() threw GroupedRelaunchError on every Apply on macOS 26 because SystemUIServer ignores a quit Apple Event and Control Center answers NSTerminateCancel, so both always ran into the 10 s quit timeout (20 s total) and were reported as failures (the comment 'Control Center relaunches itself once told to quit' was only true in Ice, which force-terminated after 1 s); (3) by then holzBar (a UIElement app) is often not active, and the alert sheet was ordered beneath the active app's windows, so the user never saw it and the spinner never stopped."
fix: "SpacingRelaunch.apply(_:finished:reportFailure:) (core, tested) ends the progress as soon as the apply returns or throws and only then awaits the report; GeneralSettingsPane uses it. SpacingRelaunch.processesToRelaunch also skips SystemUIServer (com.apple.systemuiserver) besides Control Center and MenuBarAgent, and applyOffset no longer asks Control Center to quit at the end (plus its 100 ms pre-sleep). No change to the no-force-terminate policy (BUG-02)."
oracle_type: specified (event order apply -> finished -> report; skip set membership measured from the unified log)
verification:
  target_test: { result: pass, tests: ["SpacingRelaunch/The progress ends before a failure is reported", "SpacingRelaunch/The progress ends once the spacing is applied, with nothing to report", "SpacingRelaunch/Control Center, SystemUIServer and MenuBarAgent are never relaunched"] }
  mutation_check: { result: pass, reason: "no Stryker for Swift; manual mutants at the fix sites", mutant_killed: "swapping finished()/reportFailure order -> 'progress ends before a failure is reported' fails; skip set without SystemUIServer -> 'never relaunched' fails (observed red before the fix)" }
  no_op_deletion: { result: flagged, deletion_justified_by_rca: true, note: "the removed Control Center quit step could only fail (NSTerminateCancel measured); the SystemUIServer skip removes a request it ignores (measured). Neither app was ever relaunched by holzBar since 02-01 (BUG-02), so no working behaviour is lost." }
  adjacent_tests: { result: pass, suites_run: ["swift test: 3 + 195 + 356 tests in HolzBarMacOS27CoreTests / SharedCodeSigningTests / HolzBarCoreTests", "Scripts/typecheck-app.sh (swiftc -emit-sil -wmo, 26.5 SDK): only the pre-existing ScreenCapture deprecation warning", "SwiftLint 0.65.1 --strict: 0 violations", "strings-check.py, privacy-check.py network|logs: pass"] }
  revert_and_reconfirm: { result: pass_unit_level, bug_returned_on_revert: true, fixed_on_reapply: true, note: "at unit level only; the app cannot be built or run here (no Xcode), so the UI repro needs the human checkpoint" }
  guardrail_verdict: accepted
files_changed:
  - holzBar/Core/SpacingRelaunch.swift
  - holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift
  - holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift
  - Tests/HolzBarCoreTests/SpacingRelaunchTests.swift
follow_ups:
  - "Product decision for the user: Control Center and SystemUIServer (system items) keep the old spacing until the next login. Ice restarted them by force-terminating (launchd respawns them; `killall ControlCenter SystemUIServer` is the usual recipe). Restarting just these two KeepAlive system agents with SIGTERM would apply the spacing to the system items at once but relaxes BUG-02 for them - not done without the user's decision."
  - "Separate, already known: on macOS 26 the 13 items logged as 'Missing sourcePID' fall back to Control Center's pid and their apps are not relaunched (v0.0.7-beta2 known issue; see .planning/debug/missing-sourcepid-log-spam.md)."
  - "Release notes of the next beta: Fixed - applying the menu bar item spacing no longer waits 20 s and no longer leaves the spinner running behind an alert holzBar could not show."
