---
status: awaiting_human_verify
trigger: "On macOS 26.7.1 the installed holzBar logs 'Missing sourcePID' for 13 menu bar items about once a minute (608 error lines in 1 day), followed by 'Clearing cached menu bar item windowIDs', so the item cache is rebuilt each cycle."
created: 2026-10-09
updated: 2026-10-09
---

## Symptoms

- expected: Every cached item has a sourcePID; no repeated cache clearing; no error-level log noise; no needless CPU work.
- actual: MenuBarItemManager.uncheckedCacheItems (MenuBarItemManager.swift ~line 444) logs "Missing sourcePID" for 13 items at once, then clears cached windowIDs, once per minute (also seen with launchservices cache lines each minute).
- errors: `log show --last 1d --predicate 'process == "holzBar"' --info --debug` shows 608 "Missing sourcePID" lines (E level shown, logger.warning).
- timeline: seen 2026-10-09 with the installed 0.0.7 beta3 on macOS 26.7.1.
- reproduction: run holzBar on macOS 26, watch the log.

## Current Focus

bug_class: Bohrbug (deterministic: same 13 windows every cycle, period = 60 s fallback timer)
hypothesis: (AND-gate, two contributing causes)
  1. SourcePIDScan counts Apple-signed processes that never report finishing launching (WebKit XPC services) as skipped Apple apps, so SourcePIDClaims leaves every third-party window unresolved for good (regression since beta2, bc8a9e48).
  2. MenuBarItemManager.uncheckedCacheItems treats every missing sourcePID as transient and empties cachedItemWindowIDs, so the 60 s fallback never skips: a full re-read, an Accessibility rescan of all apps (the 30 s miss interval has passed) and one warning per item, every minute.
next_action: user installs a build with the fix on macOS 26 and confirms (see Resolution.human_verification); then archive the session

reasoning_checkpoint:
  hypothesis: "Third-party item windows on macOS 26 get no sourcePID because SourcePIDScan.run skips the Apple-signed WebKit XPC processes (accessory policy, isFinishedLaunching permanently false) via skip(app, isSignedByApple: true), which sets skippedAppleApp, and SourcePIDClaims.decision returns .unresolved for non-Apple claims when appleAppsComplete is false. The manager then clears cachedItemWindowIDs for each miss, which turns the 60 s fallback into a full re-read + rescan + 13 warnings."
  confirming_evidence:
    - "14 Apple-signed WebKit XPC processes on this Mac report isFinishedLaunching == false and activationPolicy .accessory, some for days (probe)"
    - "exactly the 13 third-party (hidden) items miss a pid, the 7 Apple (visible) items do not (window probe + log hash counts)"
    - "the rule arrived with bc8a9e48 in beta2; the beta1 process 15143 (XPC helper era, no rule) logged no misses for a day"
    - "burst period 61-63 s = Task.sleep(60 s, tolerance 10 s) fallback in configureObservers; each burst ends with 'Clearing cached menu bar item windowIDs'"
  falsification_test: "After the fix the scan with an Apple process that never finished launching plus one third-party claimant must give .owner(third party); a still-launching Apple app must still block (unit tests). On the live Mac (after install): no 'Missing sourcePID' warnings and no 'Clearing cached menu bar item windowIDs' every minute; hidden third-party items show their app names in the Layout pane."
  fix_rationale: "Apple documents that some processes never report finishing launching, so 'not finished launching' is only a temporary state for a process that started recently. Treating a process that started longer ago than a launch grace as never finishing removes the permanent block while keeping the audit's protection for genuinely launching Apple apps (screencaptureui's recording item). The manager's forced re-read becomes conditional on lookups a re-read can actually change (unfinished scans, skipped apps that can now be asked, misses voided by a running-app change), so a window no app claims no longer causes a full re-read every minute."
  blind_spots: "Cannot run the app or query Accessibility from the probe (no AX permission), so the live claims of the 13 third-party apps after the fix are not observed; an Apple app that times out on every scan would still block third-party claims (paused, not stalled); the off-screen-frame hypothesis is not directly disproven."
  candidate_causes:
    - "code: SourcePIDScan/SourcePIDClaims Apple-completeness rule treats 'not finished launching' as temporary"
    - "environment: Apple-signed WebKit XPC services that never finish launching run whenever an app shows web content"
    - "code: MenuBarItemManager clears cachedItemWindowIDs for settled misses, defeating the skip of the 60 s fallback"
    - "data/environment (eliminated): second display's windows; off-screen frames of hidden items"
  and_gate: "yes - the log spam and per-minute rescans need both a permanent miss (causes 1+2: rule + never-finishing processes) and the manager's unconditional clear (cause 3). Either alone would not produce a 13-line burst every minute."

## Evidence

- timestamp: 2026-10-09
  checked: `log show --last 1d` for subsystem com.holzcloud.holzBar (646 lines)
  found: the same 13 item hashes log "Missing sourcePID" in every burst; bursts every ~61-63 s (14:00:37, 14:01:37, 14:02:40, 14:03:43, 14:04:46, 14:05:49), each followed by "Clearing cached menu bar item windowIDs". Extra bursts come with events (launches, activations). The spam starts with process 47497 (13:42, new binary); the earlier process 15143 (binary UUID FBC90B03…, ran since 2026-10-08 14:16) logged none overnight. Running binary is /Applications/holzBar.app 0.0.7-beta3 (UUID 3C09E170…).
  implication: the ~60 s period matches the fallback timer in MenuBarItemManager.configureObservers (`Task.sleep(for: .seconds(60), tolerance: .seconds(10))` -> cacheItemsIfNeeded).

- timestamp: 2026-10-09
  checked: MenuBarItemManager.uncheckedCacheItems + cacheItemsIfNeeded + CacheActor
  found: any cached item with sourcePID == nil sets shouldClearCachedItemWindowIDs, which empties cachedItemWindowIDs. cacheItemsIfNeeded compares the window-ID signature with cachedItemWindowIDs, so after a clear the next trigger (the 60 s fallback) never skips and runs a full cacheItemsRegardless (window list, SourcePIDCache lookup, control item order, uncheckedCacheItems) - which again finds the same 13 items without a pid and clears again.
  implication: a self-sustaining cycle: as long as one item can never get a pid, the skip optimisation is disabled for good and every 60 s fallback (and every event) does a full re-read plus 13 error-level log lines.

- timestamp: 2026-10-09
  checked: Shared/Services/SourcePIDCache.swift, holzBar/Core/SourcePIDScan.swift, SourcePIDClaims.swift, SourcePIDLookupSchedule.swift
  found: a window that a finished scan did not find (no claim, or contested) is recorded in failedLookups and not rescanned for failedLookupInterval (30 s) unless a skipped app becomes ready. The item then has sourcePID nil until a later scan finds it. So "no pid" is an expected, persistent state for windows no running app claims through Accessibility.
  implication: uncheckedCacheItems treats an expected, persistent outcome of the macOS 26 lookup as a transient error that must force a re-read.

- timestamp: 2026-10-09
  checked: live window list (scratchpad probe replicating Bridging.getMenuBarWindowList([.itemsOnly, .activeSpace]) via CGS) on this Mac: 2 displays (P34WD-40 main, built-in at x=-1512), "Displays have separate Spaces" on
  found: 46 item windows (23 per display) but the .activeSpace filter keeps only the 23 of the main display (space 1). Of these: 3 holzBar control items (16269 icon, 16271 hidden divider 5016 pt, 16216 always-hidden divider), 7 visible items (25 clock, 27, 23, 26, 24, 14927, 283) and exactly 13 hidden items off screen (x -2483…-2032: 34, 7408, 73, 91, 90, 103, 8022, 15313, 13516, 11016, 3662, 258, 1760).
  implication: the second display's windows are not in the list, so a multi-display cause is out. 13 = the hidden items, which in this layout are the third-party ones (13516/13517 was created with DockDoor's window 13515); the 7 visible ones are Apple's.

- timestamp: 2026-10-09
  checked: running applications (scratchpad probe: activationPolicy, isFinishedLaunching, `anchor apple` code signature, launchDate, bundleURL)
  found: 14 Apple-signed processes with activationPolicy .accessory and isFinishedLaunching == false: com.apple.WebKit.Networking / .GPU / .WebContent XPC services (pids 5085-5087, 30544, 34647-34661, 38216, 81677-81679, 92994-92996), some running for days. launchDate is nil for them (and for many finished apps too). Apple's NSRunningApplication.isFinishedLaunching docs: "Some applications do not post this notification and so are never reported as finished launching."
  implication: SourcePIDCache.CachedApplication.isValidForAccessibility is false for them for good. SourcePIDScan.run skips them with skip(app, isSignedByApple: true), which sets skippedAppleApp; SourcePIDClaims.decision(scanFinished:appleAppsComplete: false) then returns .unresolved for every window that only a non-Apple app claims. While any app shows web content, no third-party item ever gets its app. The failure records list these processes as skipped apps, which never become ready, so only the 30 s rescan remains - and the manager's cleared window IDs make the 60 s fallback trigger exactly that rescan every minute.

- timestamp: 2026-10-09
  checked: git history and the persisted log of the earlier process 15143
  found: the rule "no app gets a window while an Apple app was skipped" came with bc8a9e48 (2026-10-05 19:28, audit XPC-05), first released in v0.0.7-beta2. Process 15143 logged from "MenuBarItemService.Connection", the XPC helper that exists only up to v0.0.7-beta1 (removed by 8ea35478), so it ran beta1 - without the rule - and logged no misses. The audit (xpc-attribution SUMMARY, residual route 2 / T-xpc-11) assumed a skipped Apple app is temporary ("slower naming of new third-party items while any Apple app is unresponsive") and that the launching case protects screencaptureui's recording item, which is skipped "only while it is launching".
  implication: regression in beta2 and beta3; the protection for genuinely launching Apple apps must stay, only processes that never finish launching must stop blocking.

- timestamp: 2026-10-09
  checked: new regression test SourcePIDScanTests "An app signed by Apple that never finishes launching does not keep other apps from their windows" (three Apple-signed apps, isValid false, neverFinishesLaunching true, plus a login item claiming the window), run before the scan change
  found: RED - `!scan.skippedAppleApp`, `scan.skippedApps.isEmpty` and `decision(for: window) == .owner(20)` all fail: the decision is .unresolved, exactly the live symptom. (Note: a fresh `swift test` build flakily fails once on SharedCodeSigningTests with "plugin for module 'TestingMacros' not found"; a retry builds - unrelated to this change.)
  implication: the root cause reproduces deterministically in the pure scan logic.

- timestamp: 2026-10-09
  checked: scratchpad probe running the exact sysctl(KERN_PROC_PID) start-time code and the 10 s rule against the live processes
  found: all 14 WebKit XPC processes classify as never finishing launching (running 4078 s to 616707 s); 64 launched apps are not affected (isFinishedLaunching short-circuits); a non-existent pid gives nil (treated as still launching).
  implication: the live input of the new rule behaves as intended on this Mac.

- timestamp: 2026-10-09
  checked: MenuBarItemManager reconcile path
  found: every cacheItemsRegardless ends with reconcileSections(.itemListChange), so a pending re-read that newly attributes an item also places it.
  implication: making the forced re-read conditional on pending lookups keeps section placement for items attributed late.

## Eliminated

- hypothesis: the 13 windows are the second display's copies of the items (Accessibility reports frames only for the active menu bar)
  evidence: Bridging.getMenuBarWindowList with .activeSpace returns only the 23 windows of the active display (space 1); the 23 windows on the built-in display (space 166) are filtered out before any lookup.
  timestamp: 2026-10-09
- hypothesis: hidden items pushed off screen report Accessibility frames that do not match their windows
  evidence: weaker than the Apple-skip mechanism: StatusItemWindowFrame documents that frames match Control Center windows also while a divider is expanded (5016 pt), beta1 resolved the same hidden items (no misses for a day), and the skip mechanism alone explains every third-party window going unresolved. Not tested directly (no Accessibility permission for the probe), kept as a blind spot.
  timestamp: 2026-10-09

## Resolution

root_cause: >
  Two causes together (AND-gate).
  (1) Since v0.0.7-beta2 (bc8a9e48, audit XPC-05) a non-Apple app gets an item window only from a scan that skipped no
  Apple-signed app. SourcePIDScan skipped every app that is not finished launching as "launching", and Apple-signed WebKit
  XPC services (Networking, GPU, WebContent; accessory policy) never report finishing launching, as NSRunningApplication
  documents for some apps. While any app shows web content they run, so every scan "skipped an Apple app" and every
  third-party item window stayed unresolved for good (on this Mac: the 13 hidden third-party items).
  (2) MenuBarItemManager.uncheckedCacheItems treated each missing sourcePID as transient: it logged a warning and emptied
  cachedItemWindowIDs, so cacheItemsIfNeeded never skipped. The 60 s fallback timer then did a full re-read, a full
  Accessibility rescan (the 30 s miss interval had passed) and 13 warnings, every minute.
fix: >
  (1) SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching:runningFor:) with launchGrace = 10 s: an app that
  has not reported finishing launching 10 s after its process started (kernel start time via sysctl KERN_PROC_PID) never
  will. SourcePIDScan leaves such apps out (neither asked nor skipped), so they no longer hold back other apps' claims; an
  Apple app that is still launching (screencaptureui), unresponsive, paused or timed out still does. SourcePIDCache puts
  them last without a signature check, and a miss that a then-launching app held back is looked up again once that app
  can be asked or turns out never to finish.
  (2) MenuBarBackend.hasPendingItemLookups(in:) (ServiceBackend26 -> SourcePIDCache.hasPendingLookups(in:); false on
  macOS 14/15/27): cacheItemsIfNeeded re-reads an unchanged window list only while a read could find more (a lookup that
  could not run or did not finish, a miss voided by a change of the running applications, or a miss whose skipped app no
  longer holds it back). uncheckedCacheItems no longer clears the cached window IDs for a missing sourcePID and logs it at
  debug level.
files_changed:
  - holzBar/Core/SourcePIDLookupSchedule.swift
  - holzBar/Core/SourcePIDScan.swift
  - Shared/Services/SourcePIDCache.swift
  - holzBar/MenuBar/Backends/MenuBarBackend.swift
  - holzBar/MenuBar/Backends/ServiceBackend26.swift
  - holzBar/MenuBar/Backends/WindowListBackend.swift
  - holzBar/MenuBar/Backends/AccessibilityBackend27.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
  - Tests/HolzBarCoreTests/SourcePIDScanTests.swift
  - Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift
commit: 027eed88 (local only, not pushed)
oracle_type: specified (the audit's claim rules: a launching/unresponsive/paused Apple app blocks, a process that never finishes launching does not) plus boundary neighbours of the 10 s grace (0, 9.999 s, 10 s, 1 day, unknown age, finished app)
verification:
  target_test: { result: pass, test: "Tests/HolzBarCoreTests/SourcePIDScanTests.swift: An app signed by Apple that never finishes launching does not keep other apps from their windows" }
  mutation_check: { result: pass, reason_if_skipped: "no Stryker for Swift; manual mutants instead", mutant_killed: "'>=' -> '>' at the grace boundary killed by SourcePIDLookupScheduleTests (10 s case); ignoring isFinishedLaunching killed (launched app case); removing the scan guard killed by the target test" }
  no_op_deletion: { result: pass, deletion_justified_by_rca: true, note: "the only removal is the unconditional clear of cachedItemWindowIDs for a missing sourcePID (cause 2), replaced by the backend's pending-lookup check" }
  adjacent_tests: { result: pass, detail: "swift test: 359 + 195 + 3 tests in 92 suites pass (HolzBarMacOS27CoreTests, HolzBarCoreTests, SharedCodeSigningTests); Scripts/typecheck-app.sh passes (only the pre-existing ScreenCapture.swift deprecation warning); SwiftLint 0.65.1 --strict over the repo: 0 violations; privacy-check.py logs and network pass" }
  revert_and_reconfirm: { result: pass, detail: "scan guard removed -> target test fails with .unresolved / skippedAppleApp (the live symptom); reapplied -> 12/12 SourcePIDScan tests pass" }
  live_input_probe: { result: pass, detail: "the sysctl start-time code classifies all 14 live WebKit XPC processes as never finishing launching, no launched app" }
  manager_retry_rule: { result: not unit-tested, reason: "app-target code (MenuBarItemManager/SourcePIDCache actor) is outside the Swift package; type-checked and reviewed only" }
  guardrail_verdict: accepted
human_verification: >
  Build and install the fix on macOS 26 (Scripts/install.sh on a Mac with Xcode, or the next beta), with an app that shows
  web content running (e.g. Mail, Safari or any WKWebView app). Then, after a few minutes:
  `/usr/bin/log show --last 10m --predicate 'process == "holzBar" AND subsystem == "com.holzcloud.holzBar"' --info`
  must show no "Missing sourcePID" lines and no "Clearing cached menu bar item windowIDs" every minute; the Layout pane
  and the holzBar Shelf must name the hidden third-party items after their apps, and SectionRestore must keep placing
  them; Wi-Fi, Battery, Clock and the camera/microphone indicator must stay Control Center's.
blind_spots: >
  The 13 apps' Accessibility claims after the fix are not observed live (the probe has no Accessibility permission).
  An Apple app that times out on every scan would still hold back third-party claims (by the audit's design). An Apple
  app that takes longer than 10 s to finish launching is left out of scans until it finishes, and a window it owns that
  failed meanwhile is retried only by the next natural read after 30 s.
environment_note: >
  A fresh `swift test` build with the Command Line Tools fails intermittently on SharedCodeSigningTests ("plugin for module
  'TestingMacros' not found"): SwiftPM compiles that target with -external-plugin-path (swift-plugin-server) while the
  other test targets use -plugin-path. Retrying the build (a few times at most) gets through. Unrelated to this fix.
