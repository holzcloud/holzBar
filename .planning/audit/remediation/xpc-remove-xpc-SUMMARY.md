---
chain: xpc
part: remove-xpc
findings: [F-04, F-12, F-37, F-48, F-05, F-52]
doc_only_findings_open: [F-49]
decisions:
  - "xpc-trust-1 — Hilfsdienst abschaffen (Recommended)"
  - "release-1 — PR-Pflicht plus Deploy Key (Recommended); only the project.pbxproj parts of F-05 and F-52"
status: complete
plan: .planning/audit/remediation/xpc-remove-xpc-PLAN.md
key-files:
  created:
    - holzBar/Core/SourcePIDLookupSchedule.swift
    - Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift
  modified:
    - Shared/Services/SourcePIDCache.swift
    - holzBar/MenuBar/Backends/ServiceBackend26.swift
    - holzBar.xcodeproj/project.pbxproj
    - Package.swift
  deleted:
    - MenuBarItemService/ (main.swift, Listener.swift, Resources/Info.plist)
    - holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift
    - Shared/Services/MenuBarItemService.swift
    - Shared/CodeSigning/CodeSignature.swift
    - Tests/SharedCodeSigningTests/CodeSignatureTests.swift
    - holzBar/Core/BlockingWork.swift
    - Tests/HolzBarCoreTests/BlockingWorkTests.swift
    - holzBar.xcodeproj/xcshareddata/xcschemes/MenuBarItemService.xcscheme
actuals:
  tasks: 3
  commits: 4          # measured: git rev-list --count 7e7ed6bf..HEAD after the last commit (which carries this file)
plan_head_before: 7e7ed6bf13a130ca62b2a627fb5cea99c6065f9c
plan_head_after: "the commit that adds this file (fix(build): resolve F-52 …)"
---

# xpc / remove-xpc: no XPC service; item sources are looked up in the app, off the main thread, with time limits

The maintainer chose to stop shipping the helper service ("Hilfsdienst abschaffen").
holzBar.app now contains one executable, `Contents/MacOS/holzBar`, and starts no other
code. On macOS 26 the app looks up which app owns each menu bar item itself. The lookup runs
in `SourcePIDCache`, an actor that runs on its own serial dispatch queue, with a 0.5 s timeout
per Accessibility element, a 2 s budget per lookup, at most 64 children per app, and a
10-60 s pause for apps that time out. From the release decision, this part takes only the
two project-file changes: Release builds no longer get `get-task-allow`, and the SwiftLint
build phase does nothing under CI or in Release builds.

On the relayed question ("Können wir das mit dem signieren nicht doch anders lösen?"): for
this part, yes. It needs no Developer ID, no notarization and no code-signature check at
runtime. With no nested code left in the bundle, there is nothing left to check. The signing
secrets (environment `release`, deploy key) belong to the release chain, and this part does
not touch them.

## Commits

| # | Hash | Subject |
|---|------|---------|
| 1 | 8ea35478 | fix(services): resolve F-04, F-12, F-48 — ship no XPC service; look up item sources in the app |
| 2 | 62dd5816 | fix(services): resolve F-37 — bound macOS 26 source-PID lookups in time |
| 3 | 108452a3 | fix(build): resolve F-05 — no get-task-allow in Release builds |
| 4 | (this commit) | fix(build): resolve F-52 — skip the SwiftLint phase in CI and Release builds |

## F-04: the nested service ran with holzBar's grants and was never checked

**Cause.** On macOS 26 `ServiceBackend26.performSetup` started the `MenuBarItemService` XPC
service from `Contents/XPCServices`. It ran with holzBar's Accessibility and Screen Recording
grants. The bundle is user-writable and has no team, so in a copied bundle, a swapped service
got those grants without a prompt.

**Fix (commit 8ea35478).**
- Deleted `MenuBarItemService/` (main.swift, Listener.swift, Resources/Info.plist). The
  LightweightCodeRequirements import went with Listener.swift. The pbxproj never linked it.
- `holzBar.xcodeproj/project.pbxproj`: removed the service's PBXNativeTarget, the "Embed XPC
  Services" copy phase and its build file, the PBXTargetDependency and container proxy, the
  `.xpc` product reference, the synchronized root group and its exception set, the service's
  Sources, Frameworks and Resources phases, its target attributes, its two build
  configurations and its configuration list. The holzBar target now has the build phases
  Sources, Frameworks, Resources and SwiftLint, and no dependencies. The result is identical
  to the plan's simulated `project.after.pbxproj`.
- Deleted the `MenuBarItemService.xcscheme`, `MenuBarItemServiceConnection.swift` (the
  connection, the session and the fallback) and `Shared/Services/MenuBarItemService.swift`
  (the request and response protocol).
- `ServiceBackend26.performSetup` now awaits `SourcePIDCache.shared.start()`.

## F-48: no code check of the service, and a wrong comment

**Cause.** The connection set a peer requirement only for team-signed builds, and holzBar
ships without a team. Its comment claimed the ad hoc case was safe.

**Fix (commit 8ea35478).** The session code, its peer requirement and the comment are gone,
together with `Shared/CodeSigning/CodeSignature.swift`, `Tests/SharedCodeSigningTests` and
the `SharedCodeSigning` / `SharedCodeSigningTests` package targets, which only the session
used. There is no nested code left to verify, so the gap between a check and a forced
relaunch is gone too.

## F-12: the main-thread KVO handler waited on the lookup lock

**Cause.** `SourcePIDCache` kept its state behind an `OSAllocatedUnfairLock`. The
`runningApplications` KVO handler runs on the main thread and took that lock. A scan held the
lock while it asked holzBar's own process through Accessibility, and AppKit answers that on
the main thread. So when an app launched or quit during a scan, the main thread could wait
for the whole Accessibility timeout.

**Fix (commit 8ea35478).**
- `SourcePIDCache` is now an `actor` with `nonisolated static let shared`. Its
  `unownedExecutor` is a dedicated
  `DispatchSerialQueue(label: "com.holzcloud.holzBar.SourcePIDCache", qos: .userInitiated)`
  (macOS 14.0 API, the deployment target). Blocking Accessibility calls and the bounds sleep
  run only on that queue, never on the main thread or the Swift concurrency pool. There is no
  lock.
- The KVO handler is an explicit `@Sendable [weak self]` closure. It only starts a `Task`
  that awaits `runningApplicationsDidChange()`. That method reads
  `NSWorkspace.shared.runningApplications` on the cache's queue (AppKit documents the
  property as thread safe), so the order of the queued tasks does not matter.
- `start()` runs `runningApplicationsDidChange()` once directly, in place of `.initial`. A
  lookup before `performSetup` starts the cache lazily. The lookup asserts
  `dispatchPrecondition(condition: .onQueue(queue))`.
- `BlockingWork` and its tests are deleted. The connection was its only user, and the actor
  replaces it. Its lesson (main-actor callers must be suspended, not blocked, because holzBar
  answers its own Accessibility queries on the main thread) moved into the cache's doc
  comment.
- Doc comments that named the service were updated: `AXHelpers`,
  `MenuBarBackendKind`, `MenuBarBackend`, `AppState`, `AccessibilityBackend27`,
  `OwnStatusItemWindows`, and the display name of the `MenuBarBackendKindTests` macOS 26 test.

## F-37: no overall time limit on a lookup

**Cause.** Every lookup asked every running app through Accessibility with the 6 s default
timeout, one window at a time, with no overall limit. One slow app therefore stalled every
item read, and did so once per window.

**Fix (commit 62dd5816, test-first).**
- New `holzBar/Core/SourcePIDLookupSchedule.swift` (`nonisolated struct`, clock-free like
  `MoveBackoff`). It holds the limits: `messagingTimeout` 0.5 s, `timeoutThreshold` 450 ms,
  `lookupBudget` 2 s, `maximumChildren` 64, pauses of 10 s doubling to 60 s, and
  `failedLookupInterval` 30 s. Its methods are `mayAsk`, `record(_:timedOut:at:)`,
  `retain(running:)`, `didTimeOut(after:)`, `isOverBudget(startedAt:now:)` and
  `shouldRescan(failedAt:now:skippedAppIsReady:)`. holzBar's own pid is never paused.
- New `Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift` with 10 tests. They failed
  first (type missing) and then passed.
- `SourcePIDCache.pids(for: [WindowInfo]) -> [CGWindowID: pid_t]` replaces the single-window
  `pid(for:)`:
  - Cached windows are answered straight away. A recorded miss is skipped until
    `shouldRescan` says otherwise: after 30 s, or as soon as one of the apps the scan skipped
    is valid for Accessibility and may be asked (memoised per pid within the call).
  - Stable bounds for all pending windows are read in one pass of up to five rounds, at
    most 100 ms of sleep in total. A window that never settles records no miss.
  - One scan covers all pending windows. Apps with a known bar come first. Before each app and
    each child, the scan checks `Task.isCancelled` and the 2 s budget. Terminated apps and
    apps with the `.prohibited` policy are skipped silently. A paused or invalid app, which
    includes `Bridging.isProcessUnresponsive`, is skipped and remembered. Validity is checked
    again before a cached bar is reused.
  - The app element, the extras bar and every child get the 0.5 s messaging timeout.
  - A call that takes 450 ms or more counts as a timeout. It pauses the app, ends that app's
    children and remembers the app as skipped. An app whose calls all came back in time ends
    its pause.
  - At most 64 children are read per app. The frame is read first, and `isEnabled` only for
    a child at a window's centre.
  - A miss is stored only when the scan finished, meaning it was neither out of budget nor
    cancelled (F-72's rule, extended).
  - `runningApplicationsDidChange()` also calls `schedule.retain(running:)`.
  - One debug log line per scan: found and window counts, the finished flag and the
    duration, all `.public`. One debug line when an app is paused, with its pid `.private`.
- `ServiceBackend26.items(on:option:)` matches all control items synchronously first, then
  makes one `await SourcePIDCache.shared.pids(for:)` for the other windows (none when the
  list is empty), and maps the windows in their original order.

## F-05 (project part): get-task-allow in Release builds

**Fix (commit 108452a3).** The holzBar target's Release configuration
(`7166833B2A767E6B006ABF84`) sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`. Debug and the
project-level configurations keep the default, so Xcode can still attach its debugger to
Debug builds. The workflow parts of F-05 (dropping `entitlements` from `--preserve-metadata`
and a CI check for an empty entitlements list) belong to the release chain.

## F-52 (project part): the SwiftLint phase ran unpinned code in CI and Release builds

**Fix (this commit).** The SwiftLint phase script (`1720D48F2BB9B60500A7AC63`) now starts with
a comment and a guard. When `CI` is set or `CONFIGURATION` is `Release`, it prints
`note: SwiftLint skipped (CI or Release build)` and exits 0 before PATH is changed. The rest
of the script is unchanged, so local Debug builds still lint with the developer's own
SwiftLint. `ENABLE_USER_SCRIPT_SANDBOXING` stays off. The synchronized folder groups give the
phase no input file list, so a sandboxed swiftlint could not read the sources, and every
local Debug build would fail. Accepted risk: local Debug builds still run whatever swiftlint
is on the developer's PATH. lint.yml's pinned image stays the linter of record. The
release-job split belongs to the release chain.

## F-49 (docs only): still open

This part may not edit docs. The changes are listed under "doc_updates_needed" below.

## Design choices

- **Actor executor instead of a lock.** Following the decision, the cache is an actor whose
  executor is its own `DispatchSerialQueue`. Main-actor callers are suspended, never blocked,
  and AppKit stays free to answer holzBar's own Accessibility queries.
- **Timeout detected by elapsed time.** A call that takes 450 ms or more under a 0.5 s
  messaging timeout counts as a timeout. `.cannotComplete` also comes back at once for some
  failures that cost nothing, so the error code alone is not a reliable signal. Accepted
  side effect: on an overloaded Mac, a legitimately slow answer pauses that app for 10 s.
- **holzBar's own process is never paused.** Pausing it would leave its group and spacer
  items without their app. Its answers come from the main thread, which no lookup blocks.
- **D-10 (skip holzBar's own pid once groups and spacers are matched by frame) is not
  done.** The decision note's own default applies ("until then, keep the self-query").
- **Names kept.** `ServiceBackend26`, `MenuBarBackendKind.service26` and `SourcePIDCache`
  are internal and not persisted. The next part (F-06) and F-101 edit these files, so a
  rename now would only add churn. Only their doc comments changed.
- **Removed, not kept:** `BlockingWork` (its only user was the connection) and the
  code-signing helpers (only the session used them).
- **Impact on the F-06 part.** The F-06 decision planned an Apple-anchor check in
  `Shared/CodeSigning/CodeSignature.swift` and tests in `SharedCodeSigningTests`. Both are
  deleted here. That part must add back a small code-signing file and a package target pair
  (see `git show 7e7ed6bf:Package.swift` for the old target shape), without
  LightweightCodeRequirements or any service code. F-06 also edits the scan restructured
  here (the claim per child in `SourcePIDCache.scan(for:)`). The batch scan keeps today's
  first-app-wins order.

## Deviations from the plan

- **Commit 1 staging.** The plan's `git add -A -- MenuBarItemService …` fails with "pathspec
  did not match", because `git rm` had already removed and staged the directory. Commit 1
  therefore used `git add -A -- holzBar Shared Tests Package.swift holzBar.xcodeproj`, and
  its content is as planned.
- **One extra test assertion.** "Apps that quit are forgotten" also checks that a relaunched
  pid is still paused at +9.999 s, as the plan's behaviour line says ("starts at 10 s
  again").
- **Stable-bounds sleep.** No sleep after the fifth round, since its result is never read.
  This makes at most 100 ms instead of the plan's 150 ms upper bound.
- **The plan file is committed.** `xpc-remove-xpc-PLAN.md` was untracked. It goes into
  commit 4 together with this SUMMARY, so that the worktree is clean, as the plan's final
  check requires.
- **servicecheck.sh** was not run: `MenuBarItemService/` no longer exists after commit 1,
  and the task makes this gate conditional on that directory.

## Gates

Run after each commit's change, in the worktree:

| Gate | Commit 1 | Commit 2 | Commit 3 | Commit 4 |
|------|----------|----------|----------|----------|
| `appcheck.sh` (Swift 6, macOS 26.5 SDK) | ERRORS: 0 EXIT: 0 | ERRORS: 0 EXIT: 0 | ERRORS: 0 EXIT: 0 | ERRORS: 0 EXIT: 0 |
| `swift test` (via `swifttest.sh`, which retries only the TestingMacros plugin flake) | HolzBarCoreTests 263, MacOS27 136 passed | 273 + 136 passed (SourcePIDLookupSchedule 10/10) | n/a (project file only) | 273 + 136 passed (full run) |
| SwiftLint `--strict --quiet` (pinned) | clean, exit 0 | clean, exit 0 | clean, exit 0 | clean, exit 0 |
| `privacy-check.py network` / `logs`, `strings-check.py` (369 strings × 5 languages) | pass | pass | pass | pass |
| Former-name grep | empty | empty | empty | empty |
| `plutil -lint` + `pbxgate.py` | structure OK | — | structure + entitlements OK | structure + entitlements OK |
| `lintphase.sh` (skipped under CI, Release, CI+Release; runs in local Debug) | — | — | — | LINTPHASE OK |
| Leftovers grep (`xpc`, `item service`, `MenuBarItemService`, `CodeSignature`, `BlockingWork`, `LightweightCodeRequirements`, `SharedCodeSigning`) over holzBar, Shared, Tests, Package.swift, holzBar.xcodeproj | empty | empty | empty | empty |
| Scope (nothing changed under .github, Scripts, README.md, docs, SECURITY.md, CLAUDE.md) | OK | OK | OK | OK |
| `servicecheck.sh` | not applicable (service removed) | n/a | n/a | n/a |

Not runnable here: CI (red until the CI chain lands; see below) and live Accessibility
behaviour on macOS 26 (maintainer, see below). The final project file is byte-identical to
the plan's validated simulation `project.after.pbxproj`.

## doc_updates_needed

**CI (the CI or release chain; `.github/` is out of scope here). This branch and those
workflow changes must ship in one PR. Until then, CI is red:**

1. `.github/workflows/build.yml`:
   - "Check the signature": drop `SERVICE` and the loop over two bundles; check the app only,
     and update the comment and echo text.
   - "Check the identifiers": drop the service lines (`SERVICE`, `SERVICE_ID`, the `sed` on
     the deleted `Shared/Services/MenuBarItemService.swift`, and both service comparisons);
     keep the app ID, name, display name and URL scheme output; update the step comment.
   - "Check the binaries for network code": loop over `Contents/MacOS/holzBar` only; run
     the entitlements check on the app only.
   - compat "Launch the app": `chmod +x` only `Contents/MacOS/holzBar`.
   - New step: fail if the bundle contains any Mach-O file other than
     `Contents/MacOS/holzBar` (for example `find holzBar.app -type f -exec file {} + | grep
     Mach-O`), and fail if `Contents/XPCServices` exists.
   - New step (release-1, F-05): fail when `codesign -d --entitlements - --xml` on the app
     lists any key.
2. `.github/workflows/release.yml`:
   - remove the comment at about lines 78-80 ("The XPC service keeps working …");
   - the hardened-runtime/ad hoc loop at about line 128 checks the app only;
   - the nested-signing `find` loop may stay (it finds nothing) or go;
   - the release chain also drops `entitlements` from `--preserve-metadata` and may pass
     `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` explicitly (now redundant with the project
     setting, but harmless). It does not need to edit the SwiftLint phase, and must not edit
     `project.pbxproj` for F-05/F-52 again (conflict).
3. `.github/scripts/privacy-check.py`: remove `"MenuBarItemService"` from `SOURCE_DIRS` and
   from the header comment (line 8). It walks the missing directory without error today, so
   this is cleanup.
4. `Scripts/install.sh`: nothing required. The project setting already removes
   get-task-allow from its Release build; the release chain may add the explicit override
   for symmetry.

**Docs (maintainer or a docs part; F-49):**

1. `docs/signing.md`:
   - line 7: holzBar ships no nested code, so a replaced binary anywhere in the bundle does
     not get the permission;
   - line 10: "no entitlements" becomes true for Release only with this F-05 change; re-check
     after the release chain;
   - line 23: drop the XPC-service reason for leaving Organizational Unit empty;
   - line 61: sign only `holzBar.app`;
   - line 87: "signs the app" (no XPC service);
   - lines 97-99: replace "The XPC service" with a short "No nested code" note. On macOS 26
     the item lookup runs inside holzBar on its own queue. Nested helpers would run with
     holzBar's permissions and could be swapped in a copied bundle, so holzBar ships none,
     and CI checks the bundle.
2. `SECURITY.md`:
   - line 14: "the hardened runtime on the app" (drop "and its XPC service");
   - T-06-M4: keep it, and narrow its wording to the main executable;
   - add a row "Code nested in a copied holzBar.app runs with holzBar's grants (macOS 26)",
     Mitigated from the next beta, because holzBar ships no nested code;
   - F-05 (get-task-allow) stays a separate row: Mitigated once the project setting ships and
     the release chain's CI check lands.
3. `docs/upstream-bugs.md:28` (the macOS 26 "Loading menu bar items…" row): holzBar
   recognises its own dividers by their window frames and looks up the other items in the
   app, on a queue of its own, with time limits; the item service is gone.
4. `docs/comparison.md:66` (and the README and website tables if they carry the row):
   replace "Menu bar item service accepts only holzBar's own code" with, for example, "No
   helper process runs with holzBar's permissions (macOS 26)". Re-check the README's
   "holzBar vs. Ice and Thaw" table and https://holzcloud.ch/holzbar.
5. Next beta's release notes (`docs/release-notes/v<next>.md`):
   - Changed (macOS 26): holzBar no longer ships the menu bar item service; it finds each
     item's app itself, off the main thread, with time limits. One process fewer, and no
     nested code runs with holzBar's permissions.
   - Fixed: short freezes when apps launch or quit while the Shelf or Layout pane reads
     items; one slow app no longer stalls every item read.
   - Security: Release builds no longer allow a debugger to attach.
6. `CLAUDE.md`, Naming: to propose to the user, not edited. Drop ", the XPC service is
   `com.holzcloud.holzBar.MenuBarItemService`".
7. `.planning/PROJECT.md:50`: "macOS 26 (in-app Accessibility lookup on its own queue)". Also
   refresh `.planning/codebase/*` (ARCHITECTURE, STRUCTURE, STACK, INTEGRATIONS, CONVENTIONS,
   TESTING, CONCERNS), which name the service; `/gsd-map-codebase` does this.

## Maintainer verification

The agent's Mac has only the Command Line Tools and cannot grant Accessibility to a test
build. Get the `holzBar-app` artifact of the PR's `build` job (after the CI chain's changes
are in the same PR). It is signed ad hoc, so macOS asks for Accessibility again.
Alternatively, test the next beta, which is signed with the certificate and keeps the
permission. Then:

1. Bundle (any macOS):
   - `ls holzBar.app/Contents` shows no `XPCServices`;
   - `find holzBar.app -type f -perm +111` lists only `Contents/MacOS/holzBar`;
   - `codesign -d --entitlements - --xml holzBar.app` prints no `get-task-allow`;
   - `codesign -dv holzBar.app` still shows `flags=…(runtime)`.
2. macOS 26, launch: `pgrep -lf MenuBarItemService` prints nothing. holzBar's icon and
   dividers appear as before.
3. macOS 26, Settings → Menu Bar Layout:
   - every item appears with its app's name and icon;
   - holzBar's own dividers, item groups and spacers are recognised and in their sections;
   - Wi-Fi, Battery, Clock and the camera/microphone indicator belong to Control Center.
4. macOS 26, the decision's test: open the Shelf, and while it is open start an app with a
   menu bar item (and quit another). Then do the same with the Layout pane open.
   - No beachball, and the UI stays responsive.
   - The new item appears with its app after the list refreshes.
   - Repeat a few times.
5. macOS 26, slow app:
   - pick a third-party menu bar app and stop it with `kill -STOP <pid>`;
   - open the Layout pane and the Shelf: both open within about 3 s, and the other items
     are correct;
   - `kill -CONT <pid>`: within about a minute, or at the next refresh, its item has its
     app again.
6. Optional, macOS 26: `log stream --level debug --predicate 'subsystem ==
   "com.holzcloud.holzBar" AND category == "SourcePIDCache"'`. Scan lines report durations
   well under 2 s normally, and "finished: true" for complete scans.
7. macOS 26, Settings → item spacing → Apply: the apps relaunch as before (watch for skipped
   apps; F-101 is a separate finding).
8. macOS 27 smoke test: launch, open the Layout pane and the Shelf. Nothing should differ;
   the cache is never started there.
9. Optional, with Xcode: a Debug run from Xcode still attaches the debugger (Debug keeps
   get-task-allow).

## Risks

- CI is red until the CI chain's workflow changes land in the same PR (see above).
- On macOS 26 the in-app path was only a fallback until now (da53d80). The maintainer's
  26.7.1 Mac ran the service, so steps 3-5 above matter.
- `Bridging.setProcessUnresponsiveTimeout(3)` now always applies to holzBar's own
  WindowServer connection on macOS 26. Before, it applied only in the service or the fallback.
- The 0.5 s timeout and 2 s budget can leave items without their app. This affects apps that
  are slow but alive, and many apps at login. Such items get a UUID namespace until a later
  read, which SectionRestore never places. There is no timer retry, by design (events over
  polling).
- holzBar still asks itself through Accessibility for its group and spacer items. If the
  main thread is busy for more than 0.5 s, that read misses them. holzBar is never paused,
  so the next read retries. D-10 would remove this.
- Release and install.sh builds can no longer be attached with lldb or Instruments. Debug
  builds are unaffected.
- macOS 14/15/27: no functional change. `DispatchSerialQueue` and
  `asUnownedSerialExecutor()` are macOS 14.0 API, and only `ServiceBackend26` creates the cache.
