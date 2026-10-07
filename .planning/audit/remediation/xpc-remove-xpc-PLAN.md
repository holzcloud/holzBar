---
phase: audit-remediation-xpc
plan: remove-xpc
type: execute
wave: 1
depends_on: []
chain: xpc
part: remove-xpc
findings: [F-04, F-12, F-37, F-48, F-05, F-52]
doc_only_findings: [F-49]
decisions:
  - "xpc-trust-1 — Hilfsdienst abschaffen (Recommended)"
  - "release-1 — PR-Pflicht plus Deploy Key (Recommended); only the project.pbxproj parts of F-05 and F-52"
base: "audit-manual/xpc-attribution @ 7e7ed6bf (audit/remediation-2026-10-05 + 66 automatic fixes, F-72 already in as 4466fcf2)"
files_modified:
  - holzBar.xcodeproj/project.pbxproj
  - holzBar.xcodeproj/xcshareddata/xcschemes/MenuBarItemService.xcscheme   # deleted
  - MenuBarItemService/main.swift                                          # deleted
  - MenuBarItemService/Listener.swift                                      # deleted
  - MenuBarItemService/Resources/Info.plist                                # deleted
  - holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift        # deleted
  - Shared/Services/MenuBarItemService.swift                               # deleted
  - Shared/CodeSigning/CodeSignature.swift                                 # deleted
  - Tests/SharedCodeSigningTests/CodeSignatureTests.swift                  # deleted
  - holzBar/Core/BlockingWork.swift                                        # deleted
  - Tests/HolzBarCoreTests/BlockingWorkTests.swift                         # deleted
  - Package.swift
  - Shared/Services/SourcePIDCache.swift
  - Shared/Utilities/AXHelpers.swift
  - holzBar/Core/SourcePIDLookupSchedule.swift                             # new
  - Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift              # new
  - holzBar/MenuBar/Backends/ServiceBackend26.swift
  - holzBar/MenuBar/Backends/MenuBarBackend.swift
  - holzBar/MenuBar/Backends/AccessibilityBackend27.swift
  - holzBar/Core/MenuBarBackendKind.swift
  - holzBar/Main/AppState.swift
  - holzBar/MenuBar/ControlItem/OwnStatusItemWindows.swift
  - Tests/HolzBarCoreTests/MenuBarBackendKindTests.swift
  - .planning/audit/remediation/xpc-remove-xpc-SUMMARY.md                  # new, executor's summary
autonomous: true
requirements: [F-04, F-12, F-37, F-48, F-05, F-52]
user_setup: []

estimate:
  tokens: 170000
  raw_tokens: 170000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "The built holzBar.app ships no nested executable: the project has one target (holzBar), no embed phase, no XPC product; on macOS 26 no second holzBar process runs"
    - "On macOS 26 the source process of every item window is looked up inside holzBar by an actor whose executor is its own serial dispatch queue; no main-thread code takes a lock or waits for a scan, so holzBar's own Accessibility replies are always served"
    - "One lookup call returns within about 2.7 s even when an app never answers: 0.5 s messaging timeout on every element, a 2 s budget checked between calls, at most 150 ms waiting for stable window bounds"
    - "An app that ran into the timeout is not asked for 10 s, doubling up to 60 s; holzBar's own process is never paused; an answer in time ends the pause"
    - "A window is cached as not found for 30 s only after a scan that finished; a scan cut short by the budget or by cancellation records no miss; a miss is retried early once an app the scan skipped (launching, unresponsive, paused) can be asked"
    - "All uncached windows of one ServiceBackend26.items call are resolved in one scan"
    - "Release builds of holzBar carry no com.apple.security.get-task-allow; Debug builds keep it for the debugger"
    - "The SwiftLint build phase runs nothing when CI is set or when the configuration is Release"
    - "macOS 14, 15 and 27 behave as before: their backends never create or start the cache"
  artifacts:
    - path: Shared/Services/SourcePIDCache.swift
      provides: "actor SourcePIDCache (dedicated DispatchSerialQueue executor): start(), pids(for:) batch lookup, KVO-driven app list"
    - path: holzBar/Core/SourcePIDLookupSchedule.swift
      provides: "pure, clock-free policy: messaging timeout, budget, children cap, per-app pauses, miss rescans"
    - path: Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift
      provides: "swift test coverage of the policy (10 tests)"
    - path: holzBar.xcodeproj/project.pbxproj
      provides: "single holzBar target; CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO in Release; guarded SwiftLint phase"
  key_links:
    - from: "ServiceBackend26.performSetup()"
      to: "SourcePIDCache.shared.start()"
      via: "await (macOS 26 only)"
    - from: "ServiceBackend26.items(on:option:)"
      to: "SourcePIDCache.shared.pids(for:)"
      via: "one await for all windows that are not holzBar's control items"
    - from: "NSWorkspace runningApplications KVO (main thread)"
      to: "SourcePIDCache.runningApplicationsDidChange()"
      via: "@Sendable handler that only starts a Task; no lock, no state access on the main thread"
    - from: "SourcePIDCache scan"
      to: "SourcePIDLookupSchedule"
      via: "mayAsk / record / didTimeOut / isOverBudget / shouldRescan / maximumChildren / messagingTimeout"
---

# xpc / remove-xpc: ship no XPC service; look up item sources in the app, off the main thread, with time limits

<objective>
Implement exactly the maintainer's choice "Hilfsdienst abschaffen" (decision xpc-trust-1) plus the
project.pbxproj parts of F-05 and F-52 (decision release-1):

- Remove the `MenuBarItemService` XPC service completely (target, embed phase, scheme, sources,
  connection, service protocol, the code-signing helpers and LightweightCodeRequirements use that only
  the service needed, and BlockingWork, which only the connection used). Nothing nested runs with
  holzBar's TCC grants any more (F-04, F-48).
- Make the in-app `SourcePIDCache` the only macOS 26 path, as an actor on its own serial dispatch queue,
  so the main thread never waits on it (F-12), with per-element timeouts, a per-lookup budget, a
  children cap, per-app back-off and batch resolution (F-37), keeping F-72's "miss only after a real
  scan" rule.
- Release builds stop injecting `get-task-allow` (F-05, project part); the SwiftLint phase never runs
  under CI or in Release builds (F-52, project part).

Purpose: close the swapped-nested-code route to holzBar's Accessibility and Screen Recording grants on
macOS 26 without a Developer ID or runtime signature checks (there is no nested code left to check), and
remove the freezes and stalls of the lookup that now becomes the only path.

Answer to the relayed user question ("Können wir das mit dem signieren nicht doch anders lösen?"): for
this part, yes. This plan needs no Developer ID, no notarization and no code-signature check at
runtime. Removing the nested service is the alternative to signing-based protection. The release
signing secrets (environment `release`, deploy key) belong to the release chain and are not touched
here.

Output: 4 commits on `audit-manual/xpc-attribution`, a SUMMARY, and the lists in
"doc_updates_needed" for the CI chain and the maintainer.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/audit/FULL-AUDIT-2026-10-05.md (sections F-04, F-05, F-12, F-37, F-48, F-49, F-52, F-72, and "Dependencies for the fix pipeline")
@/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/xpc-trust-1.md
@/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/release-1.md
@Shared/Services/SourcePIDCache.swift
@holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift
@holzBar/MenuBar/Backends/ServiceBackend26.swift
@Shared/Utilities/AXHelpers.swift
@holzBar/MenuBar/MacOS27/Core/AccessibilityScanSchedule27.swift (pattern for a pure per-process schedule)
@holzBar/Core/MoveBackoff.swift (pattern: every method takes the current time; tests without a clock)
@holzBar.xcodeproj/project.pbxproj
@Package.swift
</context>

## Paths used below

- `W` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution` (the worktree; the only repository you change)
- `S` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`
- `G` = `S/xpc-remove-probe` (validated gate scripts `pbxgate.py`, `lintphase.sh`, `swifttest.sh`; if
  missing, recreate them from Appendix A). `G/tree/` holds a prototype of the end state of Task 2
  (`SourcePIDLookupSchedule.swift`, its tests, `SourcePIDCache.swift`, `ServiceBackend26.swift`,
  `Package.swift`). It type-checks with `appcheck.sh`, and `swift test` passed on it with 273 + 136
  tests. Use it as a reference only: it lacks most doc comments and the lazy start, and this plan
  wins where they differ.

The verify commands below spell out the absolute paths, because shell state does not persist between
calls.

## Ground rules for the executor

- Work only in `W` on the current branch. Never touch `/Users/cheidenreich/privat/holzBar` or other
  worktrees. Never switch branches, push, or run a gh command that writes. Never launch, quit or relaunch
  holzBar, and never change system state (tccutil, `defaults write` on real domains).
- Do not edit anything under `.github/` or `Scripts/`, or `README.md`, `docs/`, `SECURITY.md`,
  `CLAUDE.md`, release notes. Record what they need in the SUMMARY's `doc_updates_needed` (copy the
  section below).
- English everywhere. Match the surrounding style and comment density. Use `privacy: .private` for
  values from other apps (pids, names), `.public` only for counts and durations.
- Keep the names `ServiceBackend26`, `MenuBarBackendKind.service26` and `SourcePIDCache`. They are
  internal and not persisted, and the next part of this chain (F-06) and F-101 edit these files, so a
  rename now is only churn. Fix their doc comments.
- Do not use `S/servicecheck.sh`: it type-checks the target this plan deletes. Do not use
  `appcheck.sh` with the macOS 27 SDK: the Command Line Tools lack its SwiftUI macro plugin (290 false
  errors). Use the default 26.5 SDK.
- `swift test` on this Mac sometimes fails with "plugin for module 'TestingMacros' not found". Only
  that message is retried, by `G/swifttest.sh`.
- No new user-facing strings are needed. If you add one anyway, it needs all five languages
  (en, de-CH with "ss", fr, it, rm), and `strings-check.py` must pass.
- If a gate fails and you cannot fix it, revert the uncommitted changes
  (`git -C W checkout -- . && git -C W clean -fd -- holzBar Shared Tests`), report `fix-failed` with the
  reason, and stop the part. Earlier commits of this part stay.

## Decisions (traceability)

Each item of the maintainer's implementation note gets an ID.

| ID | Source | Decision | Where |
|----|--------|----------|-------|
| D-01 | xpc-trust-1 | Chosen option: stop shipping the XPC service; the in-app SourcePIDCache is the only macOS 26 path | Task 1 |
| D-02 | xpc-trust-1 (1), F-12 | The runningApplications KVO handler (main thread) never takes the cache lock. The cache becomes an actor whose `unownedExecutor` is a dedicated `DispatchSerialQueue` (macOS 14+), so blocking AX stays off the main thread and the cooperative pool. No lock is held across AX calls or the stableBounds sleep. This replaces `BlockingWork.run(on: localQueue)` | Task 1 |
| D-03 | xpc-trust-1 (2), F-37 | A messaging timeout of about 0.5 s on the app element, the extras bar and each child | Task 2 |
| D-04 | xpc-trust-1 (2), F-37 | Re-check `isValidForAccessibility` (incl. `Bridging.isProcessUnresponsive`) before reusing a cached bar | Task 2 |
| D-05 | xpc-trust-1 (2), F-37 | Cap the children read per app; a total budget of about 2 s per lookup, checked between calls | Task 2 |
| D-06 | xpc-trust-1 (2), F-37 | Back off from an app that timed out | Task 2 |
| D-07 | xpc-trust-1 (2), F-37/F-72 | Record the 30 s failed lookup only after a complete scan | Task 2 |
| D-08 | xpc-trust-1 (2), F-37 | Resolve all uncached windows of one `ServiceBackend26.items` call in one pass | Task 2 |
| D-09 | xpc-trust-1 (2) | Update the `AXHelpers.application` doc comment (it names the removed service) | Task 1 |
| D-10 | xpc-trust-1 (3), optional | Skip holzBar's own PID once groups and spacers are recognised by frame. **Discretion: not done here.** The note's own default applies ("until then, keep the self-query, which is safe once the main thread never waits on the lookup"). Instead, the schedule never pauses holzBar's own process | Task 2 (own-PID exemption) |
| D-11 | xpc-trust-1 (4) | Delete `MenuBarItemService/`, its pbxproj objects (native target, Embed XPC Services phase, target dependency, container proxy, product reference, synchronized group and exception set, build phases, build configurations, configuration list, target attributes), the xcscheme, the connection file and `Shared/Services/MenuBarItemService.swift`. `ServiceBackend26.performSetup` starts the in-app cache | Task 1 |
| D-12 | xpc-trust-1 (4) | Remove `Shared/CodeSigning`, `Tests/SharedCodeSigningTests` and their Package.swift targets | Task 1 |
| D-13 | xpc-trust-1 (5) | CI changes for the removed service | **Excluded by scope** (another chain owns `.github/`); listed in doc_updates_needed |
| D-14 | xpc-trust-1 (6), F-49 | Docs: signing.md, SECURITY.md, upstream-bugs.md, release notes, CLAUDE.md, PROJECT.md | **Excluded by scope** (no doc edits in this part); listed in doc_updates_needed |
| D-15 | xpc-trust-1 | Verify with swift test, appcheck.sh and CI; the user tests a build on macOS 26 | All tasks + maintainer section |
| D-16 | release-1 (7), F-05 | No get-task-allow in Release builds of the app: `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release | Task 3 |
| D-17 | release-1 (5), F-52 | The SwiftLint Run Script phase does not run when `CI` is set and runs no unpinned code in Release builds | Task 3 |

## Source coverage audit

| Source item | Status |
|-------------|--------|
| GOAL: remove the service, lookup in the app, off the main thread, with a time limit | COVERED (Tasks 1, 2) |
| F-04 nested service runs with holzBar's grants, never checked | COVERED (Task 1: no nested code ships) |
| F-48 no code check of the service, wrong comment | COVERED (Task 1: the session code and comment are deleted) |
| F-12 main-thread KVO handler blocks on the lookup lock | COVERED (Task 1: actor on its own queue, no lock) |
| F-37 no overall time limit | COVERED (Task 2) |
| F-72 negative cache only after a real scan (already fixed) | KEPT and extended (Task 2, D-07) |
| F-05 get-task-allow (project part) | COVERED (Task 3); workflow parts → release chain |
| F-52 SwiftLint phase (project part) | COVERED (Task 3); release job split → release chain |
| F-49 docs claim "mitigated" | DOC-ONLY → doc_updates_needed (no doc edits allowed here) |
| D-01 … D-17 | D-13, D-14 excluded by scope with a written hand-off; D-10 discretion documented; all others COVERED |

<!-- planner-discipline-allow: MenuBarItemService -->
<!-- planner-discipline-allow: BlockingWork -->
<!-- planner-discipline-allow: CodeSignature -->
<!-- planner-discipline-allow: SharedCodeSigning -->
<!-- planner-discipline-allow: LightweightCodeRequirements -->
<!-- planner-discipline-allow: XPC -->
<!-- planner-discipline-allow: xpc -->
<!-- planner-discipline-allow: item service -->
<!-- planner-discipline-allow: OSAllocatedUnfairLock -->
<!-- planner-discipline-allow: func pid(for window -->
<!-- planner-region-allow: SourcePIDCache.shared.pid(for: -->
(Task 1 adds the single-window call in ServiceBackend26 on purpose; Task 2 replaces it with the batch call, so its ban is sequential, not a sibling conflict.)

## Interfaces after this plan

These are signatures and names only; the bodies are in the tasks and in `G/tree`.

- `holzBar/Core/SourcePIDLookupSchedule.swift`: `nonisolated struct SourcePIDLookupSchedule`
  - `static let messagingTimeout: Float = 0.5`
  - `static let timeoutThreshold = Duration.milliseconds(450)`
  - `static let lookupBudget = Duration.seconds(2)`
  - `static let maximumChildren = 64`
  - `static let firstPause = Duration.seconds(10)`
  - `static let longestPause = Duration.seconds(60)`
  - `static let failedLookupInterval = Duration.seconds(30)`
  - `init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier)`
  - `func mayAsk(_ pid: pid_t, at now: ContinuousClock.Instant) -> Bool`
  - `mutating func record(_ pid: pid_t, timedOut: Bool, at now: ContinuousClock.Instant)`
  - `mutating func retain(running pids: Set<pid_t>)`
  - `static func didTimeOut(after elapsed: Duration) -> Bool`
  - `static func isOverBudget(startedAt start: ContinuousClock.Instant, now: ContinuousClock.Instant) -> Bool`
  - `static func shouldRescan(failedAt: ContinuousClock.Instant, now: ContinuousClock.Instant, skippedAppIsReady: Bool) -> Bool`
- `Shared/Services/SourcePIDCache.swift`: `actor SourcePIDCache`
  - `nonisolated static let shared`
  - `private let queue: DispatchSerialQueue`, labelled `com.holzcloud.holzBar.SourcePIDCache`, QoS `.userInitiated`
  - `nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }`
  - `func start()`
  - `func pids(for windows: [WindowInfo]) -> [CGWindowID: pid_t]` (Task 2; Task 1 has the single-window form `pid(for:)`)
- `ServiceBackend26.performSetup()` awaits `SourcePIDCache.shared.start()`.
  `ServiceBackend26.items(on:option:)` makes one `await SourcePIDCache.shared.pids(for:)`.
- Gone: the XPC service, its connection and session, the service protocol enum, `CodeSignature`,
  `BlockingWork`, and the `SharedCodeSigning` and `SharedCodeSigningTests` package targets.

## How each finding's failure scenario is closed

- **F-04.** The scenario: copy the bundle, swap the nested service, open the copy, and the service
  runs with holzBar's grants. After this plan holzBar.app holds one executable,
  `Contents/MacOS/holzBar`, and starts no other code. Replacing that executable breaks the
  certificate-leaf designated requirement, so TCC asks again (the documented behaviour). An added
  helper is never launched, because the app connects to no XPC service. The CI chain adds a check that
  the bundle contains no Mach-O besides `Contents/MacOS/holzBar` (doc_updates_needed).
- **F-48.** The session code, its team-only peer requirement and its wrong comment are deleted. There
  is no nested code left to verify, so the check-then-relaunch gap the audit describes is gone too.
- **F-12.** The KVO handler on the main thread only starts a `Task`. The actor reads
  `NSWorkspace.shared.runningApplications` on its own queue (AppKit documents the property as thread
  safe). There is no lock, so the main thread never waits while a scan asks holzBar's own process
  through Accessibility. Callers on the main actor are suspended, not blocked, and AppKit answers the
  self-query.
- **F-37.** Every element has a 0.5 s messaging timeout. Before each app and each child, the scan
  checks the 2 s budget and `Task.isCancelled`. At most 64 children are read per app. An app whose call
  ran into the timeout is paused (10 s, doubling to 60 s). A cached bar is used only after
  `isValidForAccessibility` passed again. All uncached windows of one item read share one scan. A slow
  app therefore costs at most one timeout per pause interval instead of 6 s per call and per window.
  Its item stays unattributed until a later read (the trade-off the maintainer accepted).
- **F-05 (project part).** Xcode no longer injects `com.apple.security.get-task-allow` into Release
  builds: release.yml, build.yml and install.sh build Release with `CODE_SIGN_IDENTITY=-`. The
  re-signing step preserves the now-empty entitlements, so a hardened-runtime holzBar refuses a
  debugger attach. Debug keeps it.
- **F-52 (project part).** The phase exits before touching PATH when `CI` is set (GitHub Actions sets
  `CI=true`) or when `CONFIGURATION` is `Release` (release job, build job, install.sh). The pinned
  lint.yml image remains the linter of record.

<tasks>

<task type="tracer">
  <name>Task 1 (tracer): ship no XPC service — the source-PID lookup runs only in the app, on an actor with its own queue (F-04, F-48, F-12)</name>
  <files>Shared/Services/SourcePIDCache.swift, holzBar/MenuBar/Backends/ServiceBackend26.swift, holzBar.xcodeproj/project.pbxproj, Package.swift, Shared/Utilities/AXHelpers.swift, holzBar/Core/MenuBarBackendKind.swift, holzBar/MenuBar/Backends/MenuBarBackend.swift, holzBar/MenuBar/Backends/AccessibilityBackend27.swift, holzBar/Main/AppState.swift, holzBar/MenuBar/ControlItem/OwnStatusItemWindows.swift, Tests/HolzBarCoreTests/MenuBarBackendKindTests.swift; deleted: MenuBarItemService/ (main.swift, Listener.swift, Resources/Info.plist), holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift, Shared/Services/MenuBarItemService.swift, Shared/CodeSigning/CodeSignature.swift, Tests/SharedCodeSigningTests/CodeSignatureTests.swift, holzBar/Core/BlockingWork.swift, Tests/HolzBarCoreTests/BlockingWorkTests.swift, holzBar.xcodeproj/xcshareddata/xcschemes/MenuBarItemService.xcscheme</files>
  <read_first>Shared/Services/SourcePIDCache.swift (whole), holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift (lines 104-123: the fallback this task makes the only path), holzBar/MenuBar/Backends/ServiceBackend26.swift, holzBar.xcodeproj/project.pbxproj (whole), Package.swift, Shared/Utilities/AXHelpers.swift (lines 1-20 and 59-77), holzBar/Core/BlockingWork.swift (its doc comment holds the 0.6 deadlock lesson to carry over), G/tree/Shared/Services/SourcePIDCache.swift (reference only)</read_first>
  <action>
Order matters, because the service target compiles Shared/ and calls the cache synchronously: remove it in the same change that turns the cache into an actor.

1. Delete the service and its plumbing (D-01, D-11, D-12). Use `git rm` for:
   - `MenuBarItemService/main.swift`, `MenuBarItemService/Listener.swift` and `MenuBarItemService/Resources/Info.plist` (the whole directory goes);
   - `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift`;
   - `Shared/Services/MenuBarItemService.swift`;
   - `Shared/CodeSigning/CodeSignature.swift` and `Tests/SharedCodeSigningTests/CodeSignatureTests.swift`;
   - `holzBar/Core/BlockingWork.swift` and `Tests/HolzBarCoreTests/BlockingWorkTests.swift`. Nothing else uses BlockingWork once the connection is gone; per D-02 the actor replaces it.
   - `holzBar.xcodeproj/xcshareddata/xcschemes/MenuBarItemService.xcscheme`.

   LightweightCodeRequirements was linked only by `import` in Listener.swift, so it goes with that file. The pbxproj has no entry for it.

2. Edit `holzBar.xcodeproj/project.pbxproj` (D-11). Use Edit with exact strings; the line numbers are as of 7e7ed6bf. Remove every object whose ID starts with `7188A6` and ends with `2E27F9ED008F131D`, and every reference to such an ID. Keep `7188A69E2E280BB4008F131D` (the Shared synchronized group, used by the holzBar target). Concretely:
   - the whole PBXBuildFile section (lines 9-11);
   - the PBXContainerItemProxy section (13-21);
   - the PBXCopyFilesBuildPhase section "Embed XPC Services" (23-35);
   - the `.xpc` PBXFileReference (line 39);
   - the exception set `7188A6912E27F9ED008F131D` (43-49), keeping `71BDFC6C2C978E2A00EF145F`;
   - the synchronized root group `7188A6842E27F9ED008F131D` (line 60);
   - the frameworks phase `7188A6802E27F9ED008F131D` (73-79);
   - the main-group child (line 88) and the Products child (line 97);
   - in the holzBar target, the "Embed XPC Services" entry of buildPhases (line 113) and the PBXTargetDependency entry, leaving an empty `dependencies = (` `);` list (line 118);
   - the whole second PBXNativeTarget (131-153);
   - the TargetAttributes entry `7188A6822E27F9ED008F131D` (167-169);
   - the targets-list entry (line 192);
   - the resources phase `7188A6812E27F9ED008F131D` (205-211) and the sources phase `7188A67F2E27F9ED008F131D` (244-250);
   - the whole PBXTargetDependency section (253-259);
   - the two service XCBuildConfigurations (455-503) and its XCConfigurationList (525-533).

   Leave a single blank line between the remaining sections, as Xcode writes them. Do not touch any other setting in this task. A simulated result of exactly this edit list passed `plutil -lint` and `pbxgate.py structure` (`G/project.after.pbxproj`, which also contains the Task 3 lines).

3. Edit `Package.swift` (D-12). Remove the `SharedCodeSigning` target and the `SharedCodeSigningTests` test target. In the header comment, drop the sentence saying the package also compiles the shared code-signing helpers, and drop the closing sentence of the next paragraph about the code-signing helpers keeping nonisolated as their default. Keep the swift-tools-version, `approachableConcurrency`, `appCore` and the four remaining targets unchanged.

4. Rewrite `Shared/Services/SourcePIDCache.swift` as an actor (D-02). The lookup semantics of this task are those of today's `pid(for:)`, including F-72's rule. Only the isolation changes here; Task 2 changes the scan.
   - Declare `actor SourcePIDCache` with `nonisolated static let shared = SourcePIDCache()`.
   - Add a `private let queue: DispatchSerialQueue`, created in `private init()` as `DispatchSerialQueue(label: "com.holzcloud.holzBar.SourcePIDCache", qos: .userInitiated)`. Keep the `Bridging.setProcessUnresponsiveTimeout(3)` call. Implement `nonisolated var unownedExecutor: UnownedSerialExecutor` by returning `queue.asUnownedSerialExecutor()`. All of these are available from macOS 14.0, the deployment target, so no `#available` is needed.
   - Flatten the old `State` struct into actor stored properties: `apps`, `pids`, `failedLookups`, `observation`. `stableBounds(for:)`, `partitionApps()` and `updatePID(for:)` become private actor methods. Remove the lock and its import. Import `OSLog` for `Logger`.
   - Keep the nested `CachedApplication` and `FailedLookup` types marked `nonisolated private`. The module's default isolation is MainActor, and they hold `NSRunningApplication`/`AXUIElement`, which never leave the actor.
   - `start()` returns early when `observation` is set. Otherwise it installs `NSWorkspace.shared.observe(\.runningApplications, options: [.new])` with an explicitly `@Sendable [weak self]` handler whose only statement starts a `Task` that awaits `self?.runningApplicationsDidChange()`. This way the main-thread KVO delivery never touches actor state or a lock (F-12). Then it calls `runningApplicationsDidChange()` once directly for the current list; this replaces `.initial`.
   - `runningApplicationsDidChange()` reads `NSWorkspace.shared.runningApplications` itself, on the cache's queue. AppKit documents that property as thread safe, and reading it at processing time makes the order of queued Tasks irrelevant. It also reads `Bridging.getMenuBarWindowList(option: .itemsOnly)`, then rebuilds `apps` (reusing cached `CachedApplication` objects by pid), keeps `pids` only for current windows whose pid is still running, and empties `failedLookups`. This matches today's `update(runningApps:)`. Keep its debug log.
   - `pid(for window: WindowInfo) -> pid_t?` starts the cache lazily (it calls `start()` when `observation` is nil, so an item read before `performSetup` still works), asserts `dispatchPrecondition(condition: .onQueue(queue))`, and then has the body of today's `pid(for:)`.
   - Rewrite the type's doc comment. Keep the opening paragraphs about source processes and macOS 26 Control Center ownership. Replace the paragraph about doing the heavy lifting in a dedicated helper service with three points:
     - Accessibility calls block their thread, so the cache is an actor whose executor is its own serial dispatch queue: scans never run on the main thread or the Swift concurrency pool.
     - A scan asks holzBar's own process too (its group and spacer items), and AppKit answers that on the main thread, so main-actor callers must be suspended, not blocked. This carries over the 0.0.6 lesson from BlockingWork's comment.
     - Earlier versions ran this lookup in a nested helper process. Code nested in the bundle runs with holzBar's Accessibility and Screen Recording permission and could be swapped in a copy of the app, so holzBar ships none.

     Do not name the removed technology in comments, because the Task 1 grep gate bans it.

5. Edit `holzBar/MenuBar/Backends/ServiceBackend26.swift` (D-01, D-11):
   - `performSetup()` awaits `SourcePIDCache.shared.start()`, and its doc comment becomes "Starts the source-PID cache."
   - In `items(on:option:)`, the per-window lookup becomes `await SourcePIDCache.shared.pid(for: window)`.
   - The type's doc comment says that the process behind an item is looked up in holzBar through Accessibility, on the cache's own queue (``SourcePIDCache``).

6. Update doc comments that name the removed helper (D-09). Comment text only; no behaviour changes:
   - `Shared/Utilities/AXHelpers.swift` line 9: "Accessibility calls for the app, made directly through the `AXUIElement` C API." In the `application(for:messagingTimeout:)` parameter doc, end the `messagingTimeout` description after "or `nil` for the default timeout (6 s)."
   - `holzBar/Core/MenuBarBackendKind.swift` lines 13-14 and 20: on macOS 26 the process behind an item is looked up through Accessibility in the app.
   - `holzBar/MenuBar/Backends/MenuBarBackend.swift` lines 16-17: the window list with source processes looked up through Accessibility (``SourcePIDCache``).
   - `holzBar/Main/AppState.swift` line 154: "The source-PID cache on macOS 26, the synthetic bounds on macOS 27."
   - `holzBar/MenuBar/Backends/AccessibilityBackend27.swift` line 38: the owning process is known directly, without a source-PID lookup.
   - `holzBar/MenuBar/ControlItem/OwnStatusItemWindows.swift` lines 10-21: on macOS 26 the application behind an item is looked up through Accessibility (``SourcePIDCache``). Before holzBar matched its control items by frame, a lookup without an answer left even its own section dividers unrecognised. The last sentence ends "without Accessibility or window titles".
   - `Tests/HolzBarCoreTests/MenuBarBackendKindTests.swift` line 12: rename the test's display name to "macOS 26 uses the window list with source processes from Accessibility".

7. Run every Task 1 verify command. Then commit (Commit 1 under "Commits") with `git -C W add -A -- MenuBarItemService holzBar Shared Tests Package.swift holzBar.xcodeproj` and `git -C W commit`. Check first that `git -C W status --porcelain` lists nothing outside these paths.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution remove-xpc-t1 > /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/appcheck-t1.out; tail -1 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/appcheck-t1.out | grep -F "ERRORS: 0  EXIT: 0"</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/swifttest.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution MenuBarBackendKind   # expect "SWIFTTEST OK"; HolzBarCoreTests = 266 - 3 = 263 tests</automated>
    <automated>plutil -lint /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/holzBar.xcodeproj/project.pbxproj && plutil -convert json -o - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/holzBar.xcodeproj/project.pbxproj | python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/pbxgate.py structure   # expect "PBXGATE structure: OK"</automated>
    <automated>! git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution grep -n -i -E "xpc|item service|MenuBarItemService|CodeSignature|BlockingWork|LightweightCodeRequirements|SharedCodeSigning" -- holzBar Shared Tests Package.swift holzBar.xcodeproj   # expect no output</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && test ! -e MenuBarItemService && test ! -e Shared/CodeSigning && test ! -e Tests/SharedCodeSigningTests && grep -q "^actor SourcePIDCache" Shared/Services/SourcePIDCache.swift && grep -q "asUnownedSerialExecutor" Shared/Services/SourcePIDCache.swift && ! grep -n -E "OSAllocatedUnfairLock|withLock" Shared/Services/SourcePIDCache.swift && grep -q "SourcePIDCache.shared.start()" holzBar/MenuBar/Backends/ServiceBackend26.swift && echo T1-STRUCT-OK</automated>
    <automated>python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/privacy-check.py network && python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/privacy-check.py logs && python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/strings-check.py --root /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swiftlint/swiftlint lint --strict --quiet --no-cache   # expect no output, exit 0</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && test -z "$(git status --porcelain -- .github Scripts README.md docs SECURITY.md CLAUDE.md)" && ! git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py' && echo SCOPE-OK</automated>
  </verify>
  <done>Commit 1 exists. The project has exactly one target, holzBar, with build phases Sources, Frameworks, Resources and SwiftLint, and no dependencies. The repository has no service sources, connection, code-signing helpers, BlockingWork or service scheme. `SourcePIDCache` is an actor on its own DispatchSerialQueue, and the main-thread KVO handler only starts a Task. `ServiceBackend26` starts and queries the in-app cache. The app module type-checks with 0 errors, and `swift test` passes (HolzBarCoreTests 263, HolzBarMacOS27CoreTests unchanged). Lint, the privacy checks and the strings check pass. F-04, F-12 and F-48 are resolved per D-01, D-02, D-09, D-11 and D-12.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: bound macOS 26 source-PID lookups in time and resolve one item read in one scan (F-37, keeps F-72)</name>
  <files>holzBar/Core/SourcePIDLookupSchedule.swift (new), Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift (new), Shared/Services/SourcePIDCache.swift, holzBar/MenuBar/Backends/ServiceBackend26.swift</files>
  <read_first>holzBar/MenuBar/MacOS27/Core/AccessibilityScanSchedule27.swift, holzBar/Core/MoveBackoff.swift and Tests/HolzBarCoreTests/MoveBackoffTests.swift (style of a clock-free policy and its tests), holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift lines 172-189 (per-element timeout pattern), Shared/Services/SourcePIDCache.swift as left by Task 1, G/tree/holzBar/Core/SourcePIDLookupSchedule.swift, G/tree/Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift and G/tree/Shared/Services/SourcePIDCache.swift (reference)</read_first>
  <behavior>
    - An app that answers in time is always asked; record(timedOut: false) keeps it askable.
    - One timeout pauses that app for exactly 10 s: not askable at +9.999 s, askable at +10 s. Other apps are unaffected.
    - Timeouts in a row pause for 10, 20, 40, 60, 60 s (doubling, capped at 60 s).
    - An answer in time ends the pause and restarts the doubling at 10 s.
    - holzBar's own process (`ownPID`) is never paused.
    - `retain(running:)` forgets apps that quit; a relaunched pid starts at 10 s again.
    - `didTimeOut(after:)`: 449 ms is false; 450 ms and 6 s are true.
    - `isOverBudget(startedAt:now:)`: +1.999 s is false; +2 s is true.
    - `shouldRescan(failedAt:now:skippedAppIsReady:)`: +29 s without a ready skipped app is false; +30 s is true; +1 s with a ready skipped app is true.
    - The limits: `messagingTimeout == 0.5`, `timeoutThreshold < 500 ms`, `maximumChildren > 0`, `lookupBudget <= 2 s`.
  </behavior>
  <action>
1. RED. Create `Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift` with the ten behaviours above:
   - `import Foundation` (needed for `pid_t` under MemberImportVisibility), `import Testing`, `@testable import HolzBarCore`;
   - `@Suite("SourcePIDLookupSchedule")` on `struct SourcePIDLookupScheduleTests`, with `private let start = ContinuousClock.now`;
   - mutate the schedule outside `#expect`, as MoveBackoffTests does.

   Run `G/swifttest.sh W SourcePIDLookupSchedule` and see it fail, because the type does not exist yet. Do not commit the red state; the commit format allows one `fix` commit per finding.

2. GREEN. Create `holzBar/Core/SourcePIDLookupSchedule.swift` (file header `//  holzBar`) as `nonisolated struct SourcePIDLookupSchedule`, with the constants and methods listed under "Interfaces" (D-03, D-05, D-06, D-07):
   - Pauses live in a private dictionary `[pid_t: Pause]`, where `Pause` is a `private nonisolated struct` with `length: Duration` and `until: ContinuousClock.Instant`.
   - `record(_:timedOut:at:)` removes the entry when the app did not time out or the pid is `ownPID`. Otherwise the new length is `firstPause` for a first timeout, or `min(previous.length * 2, longestPause)`.
   - `mayAsk` is true without an entry, or once `now >= until`.
   - `retain(running:)` filters the entries.
   - The three static functions compare with `>=`.
   - The doc comment explains why. On macOS 26 Control Center owns every item window, so holzBar asks every app with an extras menu bar where its items are, and one slow app must not hold up every item read. holzBar's own process is never paused: it answers on the main thread, which a lookup never blocks, and pausing it would leave its group and spacer items without their app (D-10). Every method takes the current time, so the type is tested without a clock.
   - Explain `maximumChildren = 64`: well above Control Center's roughly twenty items, and it bounds an app that reports thousands.

   Run swifttest.sh until it is green. The type must be `nonisolated`, because the package and the app compile holzBar/Core with MainActor as the default isolation, and the actor calls it synchronously.

3. Rework the scan in `Shared/Services/SourcePIDCache.swift` (D-03 … D-08):
   - Replace the single-window method with `func pids(for windows: [WindowInfo]) -> [CGWindowID: pid_t]`. Keep the lazy `start()` and the `dispatchPrecondition`. Add `private var schedule = SourcePIDLookupSchedule()`. Delete the cache's own `failedLookupInterval` (the schedule owns it now).
   - **Partition the windows.** Use `now = ContinuousClock.now`.
     - A window with a cached pid goes straight into the result.
     - A window with a `FailedLookup` is skipped while `SourcePIDLookupSchedule.shouldRescan` is false. `skippedAppIsReady` is true when any of the failure's `skippedApps` is `isValidForAccessibility` and `schedule.mayAsk` at `now`. Memoise that per pid within the call, so each app's unresponsive check runs once.
     - Every other window is pending.
     - Return early when nothing is pending, or when `AXHelpers.isProcessTrusted()` is false. That records no miss, as today.
   - **Stable bounds for all pending windows at once.** Run up to five rounds. Read `Bridging.getWindowBounds(for:)` for every window not yet stable. A window whose bounds equal the previous reading (starting from `WindowInfo.bounds`) is stable, and its centre is kept. A window without bounds is dropped. Sleep n/100 s between rounds (at most 150 ms in total, instead of up to 150 ms per window). Windows that never settle are dropped for this read and record no miss.
   - **One scan over the apps.** Order the apps with known bars first, as `partitionApps` does today. For each app:
     - stop when no window remains;
     - before asking it, stop the scan as not finished if `Task.isCancelled` or `SourcePIDLookupSchedule.isOverBudget(startedAt:now:)`;
     - skip terminated apps and apps whose activation policy is `.prohibited` silently, as today;
     - if `!schedule.mayAsk(pid, at:)` or `!isValidForAccessibility`, add the app to `skippedApps` and go on. This re-checks validity, including `Bridging.isProcessUnresponsive`, before a cached bar is reused (D-04);
     - read the bar through a private generic helper `timed(_:)`. It returns the value and whether the call took at least `SourcePIDLookupSchedule.timeoutThreshold`. Only a call that ran into the 0.5 s per-element timeout takes that long, so this is the timeout signal (D-06). `.cannotComplete` also comes back instantly for some failures that cost nothing, which is why elapsed time is used instead;
     - `CachedApplication.getOrCreateExtrasMenuBar()` creates the app element with `AXHelpers.application(for:messagingTimeout: SourcePIDLookupSchedule.messagingTimeout)` and sets the same timeout on the bar with `AXHelpers.setMessagingTimeout` before caching it (D-03);
     - on a bar timeout, call `schedule.record(pid, timedOut: true, at: .now)`, add the app to `skippedApps`, and go on. On no bar, record `timedOut: false` and go on;
     - read the children through `timed`, then take at most `SourcePIDLookupSchedule.maximumChildren` of them (D-05);
     - for each child: check the budget and cancellation again (not finished: leave both loops); set the 0.5 s timeout on the child (D-03); read its frame through `timed`; find every pending window whose centre is within 1 pt of the frame's centre; only for such a match, read `AXHelpers.isEnabled` through `timed`; when enabled, assign this app's pid to all matching windows and remove them from the pending set. Reading the frame first and `isEnabled` only on a match gives the same result as today's order with about half the calls;
     - a frame or isEnabled timeout ends this app's children, records `timedOut: true` and adds the app to `skippedApps`. After an app's children, call `schedule.record(pid, timedOut: false, at: .now)` when nothing timed out.
   - **Commit the results.** Found windows go into `pids` and the result, and their `failedLookups` entries are cleared. For each window still unresolved, store `FailedLookup(failedAt: now, skippedApps:)` only if the scan finished: it was neither out of budget nor cancelled (D-07, extends F-72). `FailedLookup` keeps one field, `skippedApps: [CachedApplication]` (launching, unresponsive or paused apps), which replaces `launchingApps`.
   - In `runningApplicationsDidChange()`, also call `schedule.retain(running:)` with the running pids.
   - **Logging.** One `Logger(category: "SourcePIDCache")` debug line per scan: found count, window count, finished flag and duration, all `.public` (counts and durations only). Optionally one debug line when an app is paused, with the pid `.private`. Nothing else.
   - Update the type and method doc comments. Name the limits and the reason (F-37: one app that answers slowly must not stall every item read). Keep the jordanbaird/Ice#911 rationale for the negative cache. Say that an item whose app could not be asked in time stays without its app until a later read, which SectionRestore never places (UUID namespace).

4. Edit `holzBar/MenuBar/Backends/ServiceBackend26.swift`, `items(on:option:)` (D-08):
   - keep reading the windows and matching the control items with `OwnStatusItemWindows.controlItems` synchronously first;
   - collect the windows without a control item, and make a single `await SourcePIDCache.shared.pids(for:)` for them (skip the call when the list is empty);
   - map every window in its original order to `MenuBarItem(uncheckedItemWindow:controlItem:)` or `MenuBarItem(uncheckedItemWindow:sourcePID:)`, with `sourcePIDs[window.windowID]`.

   Adjust the doc comment: all control items are matched before the one lookup suspends.

5. Run every Task 2 verify command, then make Commit 2: `git -C W add -A -- holzBar Shared Tests` and `git -C W commit`.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/swifttest.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution SourcePIDLookupSchedule MenuBarBackendKind MoveBackoff   # expect "SWIFTTEST OK"; HolzBarCoreTests = 273</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution remove-xpc-t2 > /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/appcheck-t2.out; tail -1 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/appcheck-t2.out | grep -F "ERRORS: 0  EXIT: 0"</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && F=Shared/Services/SourcePIDCache.swift && grep -q "func pids(for windows: \[WindowInfo\]) -> \[CGWindowID: pid_t\]" $F && ! grep -n "func pid(for window" $F && [ "$(grep -c 'SourcePIDLookupSchedule.messagingTimeout' $F)" -ge 3 ] && grep -q "maximumChildren" $F && grep -q "isOverBudget" $F && grep -q "Task.isCancelled" $F && grep -q "schedule.retain(running:" $F && grep -q "dispatchPrecondition(condition: .onQueue(queue))" $F && grep -q 'SourcePIDCache.shared.pids(for:' holzBar/MenuBar/Backends/ServiceBackend26.swift && ! grep -n "SourcePIDCache.shared.pid(for:" holzBar/MenuBar/Backends/ServiceBackend26.swift && echo T2-STRUCT-OK</automated>
    <automated>python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/privacy-check.py logs && python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/privacy-check.py network && python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/strings-check.py --root /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swiftlint/swiftlint lint --strict --quiet --no-cache   # expect no output, exit 0</automated>
    <automated>! git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution grep -n -i -E "xpc|item service|MenuBarItemService|CodeSignature|BlockingWork|LightweightCodeRequirements|SharedCodeSigning" -- holzBar Shared Tests Package.swift holzBar.xcodeproj   # still no output</automated>
  </verify>
  <done>Commit 2 exists. `SourcePIDLookupSchedule` and its ten tests pass under `swift test` (HolzBarCoreTests 273). One `ServiceBackend26.items` call makes one lookup. Every AX element of a scan has a 0.5 s timeout. The scan stops at 2 s or on cancellation and reads at most 64 children per app. An app that timed out is paused 10-60 s, and holzBar's own process never is. Cached bars are re-validated. Misses are recorded only for finished scans and are retried early when a skipped app becomes askable. The app type-checks with 0 errors; lint, the privacy checks and the strings check pass. F-37 is resolved per D-03 … D-08 and D-10.</done>
</task>

<task type="auto">
  <name>Task 3: project settings — no get-task-allow in Release (F-05) and no SwiftLint phase under CI or in Release (F-52); write the SUMMARY</name>
  <files>holzBar.xcodeproj/project.pbxproj, .planning/audit/remediation/xpc-remove-xpc-SUMMARY.md</files>
  <read_first>holzBar.xcodeproj/project.pbxproj (the holzBar target's Release configuration 7166833B2A767E6B006ABF84 and the SwiftLint phase 1720D48F2BB9B60500A7AC63), Appendix B of this plan, .github/workflows/lint.yml lines 1-25 (read only, the pinned linter), .github/workflows/release.yml lines 55-140 (read only, so the SUMMARY names the CI follow-ups correctly)</read_first>
  <action>
1. F-05, project part (D-16). In the holzBar target's Release configuration (`7166833B2A767E6B006ABF84 /* Release */`) add the line `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;` between the quoted `CODE_SIGN_IDENTITY[sdk=macosx*]` line and `CODE_SIGN_STYLE = Automatic;`. That is Xcode's alphabetical order and four tabs of indentation. Do not add it to the Debug configuration, which must keep `get-task-allow` so Xcode can debug, or to the project-level configurations. Run the pbx gate in mode `structure entitlements` and `plutil -lint`. Commit 3: stage only `holzBar.xcodeproj/project.pbxproj`; its diff is exactly one added line.

2. F-52, project part (D-17). Replace the SwiftLint phase's `shellScript` value with the exact string in Appendix B. It prepends one comment line and a guard that prints `note: SwiftLint skipped (CI or Release build)` and exits 0 when `CI` is set or `CONFIGURATION` is `Release`, before PATH is changed. The rest of the old script is kept verbatim, so local Debug builds still lint with the developer's own SwiftLint.
   - Keep `alwaysOutOfDate`, `shellPath` and the other keys.
   - Do not enable `ENABLE_USER_SCRIPT_SANDBOXING` for the target. The synchronized folder groups give the phase no input file list, so a sandboxed swiftlint could not read the sources and every local Debug build would fail. The guard already keeps unpinned code out of CI and Release; the risk is noted in the SUMMARY.

   Run `lintphase.sh`, the pbx gate and `plutil -lint`.

3. Write `.planning/audit/remediation/xpc-remove-xpc-SUMMARY.md`, modelled on `ax-observers-background-registration-SUMMARY.md` in the sibling worktree.
   - Front matter: chain `xpc`, part `remove-xpc`, findings, decisions, status.
   - Per finding: cause and fix.
   - The design choices: actor executor; timing-based timeout signal; own-PID exemption; D-10 not done; names kept; BlockingWork and the code-signing helpers removed; F-06's need to recreate a code-signing target.
   - The gate results with test counts.
   - The "doc_updates_needed" section and the "Maintainer verification" steps of this plan, copied and updated with commit hashes.

   Commit 4: the pbxproj plus the SUMMARY, with the F-52 message.

4. Final checks: `git -C W log --oneline -5` shows the four commits on top of 7e7ed6bf, and `git -C W status --porcelain` is empty.
  </action>
  <verify>
    <automated>plutil -lint /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/holzBar.xcodeproj/project.pbxproj && plutil -convert json -o - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/holzBar.xcodeproj/project.pbxproj | python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/pbxgate.py structure entitlements   # expect "PBXGATE entitlements structure: OK"</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/lintphase.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/holzBar.xcodeproj/project.pbxproj   # expect "LINTPHASE OK" (skipped under CI, in Release, in CI+Release; runs in local Debug)</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && SUBJECTS=$(git log --format=%s 7e7ed6bf..HEAD) && COUNT=$(git rev-list --count 7e7ed6bf..HEAD) && STATUS=$(git status --porcelain) && [ "$COUNT" = 4 ] && ! printf '%s\n' "$SUBJECTS" | grep -v '^fix(' && test -z "$STATUS" && test -f .planning/audit/remediation/xpc-remove-xpc-SUMMARY.md && echo T3-OK</automated>
    <human-check>On macOS 26, with a CI-built test app, after the CI chain's workflow changes are in the same PR: run the "Maintainer verification" steps 1-7 below. On macOS 27, run step 8.</human-check>
  </verify>
  <done>Commits 3 and 4 exist. The holzBar Release configuration sets `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` and Debug does not. The SwiftLint phase skips under CI and in Release and lints local Debug builds. The project lints, and both pbx gate modes pass. The SUMMARY is committed with the doc_updates_needed hand-off and the maintainer steps. The worktree is clean. F-05 and F-52 project parts are resolved per D-16 and D-17.</done>
</task>

</tasks>

## Commits

Make exactly four commits, each ending with the two trailer lines, with an empty line before them.

1. Commit 1 (end of Task 1)
   - Subject: `fix(services): resolve F-04, F-12, F-48 — ship no XPC service; look up item sources in the app`
   - Body:
     - The maintainer chose to stop shipping the menu bar item service (decision xpc-trust-1).
     - On macOS 26 it ran with holzBar's Accessibility and Screen Recording grants, and nothing checked it. A swapped service in a copied bundle got those grants (F-04); the app's partial check was missing and its comment wrong (F-48).
     - The source-PID lookup now always runs in holzBar, in SourcePIDCache, an actor whose executor is its own serial dispatch queue. The main-thread running-apps observer no longer takes a lock that a scan holds while it waits for holzBar's own Accessibility replies (F-12).
     - Removed: the service target, embed phase, scheme and sources; the connection; the service protocol; the code-signing helpers and their tests; BlockingWork.
2. Commit 2 (end of Task 2)
   - Subject: `fix(services): resolve F-37 — bound macOS 26 source-PID lookups in time`
   - Body:
     - Every lookup asked every app through Accessibility with the 6 s default timeout, one window at a time, with no overall limit, so one slow app stalled every item read.
     - Now every element gets a 0.5 s timeout, a lookup stops after 2 s or when cancelled, at most 64 children are read per app, and an app that timed out is paused 10-60 s. holzBar itself is never paused.
     - Cached bars are re-validated, and all windows of one item read share one scan.
     - Misses are cached only after a finished scan (keeps F-72) and are retried once a skipped app can be asked. The policy is SourcePIDLookupSchedule, with tests.
3. Commit 3 (Task 3, step 1)
   - Subject: `fix(build): resolve F-05 — no get-task-allow in Release builds`
   - Body:
     - Release builds were signed ad hoc by xcodebuild, which injected com.apple.security.get-task-allow, and the certificate re-signing kept it. A debugger could then attach and run code with holzBar's grants.
     - The holzBar target now sets CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO for Release; Debug keeps the entitlement.
     - The workflow parts (preserve-metadata, an empty-entitlements check in CI) belong to the release chain (decision release-1).
4. Commit 4 (Task 3, steps 2-3)
   - Subject: `fix(build): resolve F-52 — skip the SwiftLint phase in CI and Release builds`
   - Body:
     - The build phase ran whatever swiftlint was on PATH, unsandboxed, in every build, including the release job with write and OIDC tokens.
     - It now exits first when CI is set or the configuration is Release. lint.yml's pinned image stays the linter of record, and local Debug builds still lint.
     - The release-job split belongs to the release chain (decision release-1).
     - Adds the remove-xpc SUMMARY.

Trailer lines, for every commit:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## Gates (summary)

| Gate | Command (see the task verify blocks for absolute paths) | Pass | Baseline at 7e7ed6bf |
|------|----------------|------|----------------------|
| App type-check | `zsh S/appcheck.sh W <label>` | `ERRORS: 0  EXIT: 0` | 0 errors, ~6 s |
| Unit tests | `zsh G/swifttest.sh W <suites>` | `SWIFTTEST OK` | HolzBarCoreTests 266, MacOS27 136, SharedCodeSigning 6 |
| Project file | `plutil -lint` + `pbxgate.py structure [entitlements]` | `OK` | fails structure (2 targets) and entitlements |
| SwiftLint phase | `G/lintphase.sh W/holzBar.xcodeproj/project.pbxproj` | `LINTPHASE OK` | fails (runs under CI and in Release) |
| Lint | pinned `S/swiftlint/swiftlint lint --strict --quiet --no-cache` with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` | no output, exit 0 | passes |
| Privacy | `privacy-check.py network` and `logs` | exit 0 | passes |
| Strings | `strings-check.py --root W` | exit 0 | passes |
| Leftovers | `git grep -i -E "xpc|item service|…"` over holzBar Shared Tests Package.swift holzBar.xcodeproj | no output | many hits |
| Scope | no changes under .github, Scripts, README.md, docs, SECURITY.md, CLAUDE.md; former-name grep empty | empty | — |

CI cannot be run from here. Once this branch and the CI chain's workflow changes are in one PR,
`build`, `test`, `compat` (macos-26, xcode-27), `no-network`, `strings` and `former-name` must pass. The
build log must show "note: SwiftLint skipped (CI or Release build)".

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| holzBar.app bundle on disk → processes started with holzBar's TCC grants | The bundle is user-writable, has no quarantine flag (cask) and is team-less, so any code holzBar starts inherits Accessibility and Screen Recording |
| Other apps → holzBar via Accessibility answers | Every app chooses how fast, and with what frames and child counts, it answers |
| Debugger → holzBar task port | Allowed only with get-task-allow under the hardened runtime |
| Build host PATH → Xcode run-script phase | Whatever `swiftlint` is on PATH runs during the build |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-xpc-01 | Elevation of privilege | Nested XPC service in a copied bundle (F-04) | medium | mitigate | Task 1 deletes the service target, embed phase and sources, so no nested executable ships. pbxgate `structure` asserts one target and no copy-files phase. The CI chain adds the "only Contents/MacOS/holzBar is Mach-O" bundle check |
| T-xpc-02 | Spoofing | Unverified service code and peer (F-48) | low | mitigate | No session code remains (Task 1 leftovers grep) |
| T-xpc-03 | Denial of service | Main-thread KVO handler waiting on a lock held during self-Accessibility (F-12) | medium | mitigate | Actor on its own DispatchSerialQueue; the KVO handler only starts a Task; no lock in SourcePIDCache (Task 1 grep: no lock types); `dispatchPrecondition(.onQueue)` in the lookup |
| T-xpc-04 | Denial of service | A slow or hostile app answering Accessibility slowly or with huge child lists (F-37) | medium | mitigate | 0.5 s per element, 2 s budget, 64-children cap, 10-60 s pauses, cancellation, one scan per item read (Task 2; SourcePIDLookupSchedule tests) |
| T-xpc-05 | Elevation of privilege | get-task-allow on Release builds (F-05) | medium | mitigate | `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` for Release (Task 3; pbxgate `entitlements`). The workflow check is transferred to the release chain |
| T-xpc-06 | Tampering | Unpinned swiftlint executed in CI and Release builds (F-52) | low | mitigate | Guard in the phase (Task 3; lintphase.sh). Local Debug builds still run the developer's own swiftlint: accepted, it is the developer's own machine and choice |
| T-xpc-07 | Spoofing | Another app's Accessibility frames claiming a Control Center item window (F-06) | medium | transfer | Not changed here. The batch scan keeps today's first-app-wins order; the next part of this chain (indicators-1, F-06) reworks the claim decision in the same scan |
| T-xpc-SC | Tampering | npm/pip/cargo installs | high | accept | No package is installed by this plan. Nothing is added to Package.swift or the project; the code-signing package targets are removed |
</threat_model>

<verification>
- Every Task 1, 2 and 3 verify command passes, in task order, before each commit.
- `git -C W log --oneline 7e7ed6bf..HEAD` lists exactly the four commits, with the subjects under "Commits".
- `git -C W show --stat HEAD~3` (Commit 1) shows the deletions listed in `files_modified` and no file under `.github`, `Scripts` or `docs`.
- Not verifiable here, and handed on: CI (after the CI chain's workflow edits) and live Accessibility behaviour on macOS 26 (maintainer).
</verification>

<success_criteria>
- holzBar builds one target; no XPC service, connection, code-signing helpers or BlockingWork remain; Package.swift has four targets and `swift test` passes.
- On macOS 26 the lookup runs in the app on the cache's own queue, under the limits in must_haves.
- Release builds carry no get-task-allow; the SwiftLint phase skips under CI and in Release.
- The four commits use the mandated message format and trailers; the SUMMARY holds the doc and CI hand-off.
</success_criteria>

## Maintainer verification by hand

The maintainer has to test a built app; the agent's Mac has only the Command Line Tools and cannot
grant Accessibility to a test build.

Get the `holzBar-app` artifact of the PR's `build` job. It is signed ad hoc, so macOS asks for
Accessibility again. Alternatively, test the next beta, which is signed with the certificate and keeps
the permission. Then:

1. Bundle (any macOS):
   - `ls holzBar.app/Contents` shows no `XPCServices`;
   - `find holzBar.app -type f -perm +111` lists only `Contents/MacOS/holzBar`;
   - `codesign -d --entitlements - --xml holzBar.app` prints no `get-task-allow` (empty);
   - `codesign -dv holzBar.app` still shows `flags=…(runtime)`.
2. macOS 26, launch: `pgrep -lf MenuBarItemService` prints nothing. holzBar's icon and dividers appear as before.
3. macOS 26, Settings → Menu Bar Layout:
   - every item appears with its app's name and icon;
   - holzBar's own dividers, item groups and spacers are recognised and in their sections;
   - Wi-Fi, Battery, Clock and the camera/microphone indicator belong to Control Center.
4. macOS 26, the decision's test: open the Shelf, and while it is open start an app with a menu bar item (and quit another). Then do the same with the Layout pane open.
   - No beachball, and the UI stays responsive.
   - The new item appears with its app after the list refreshes.
   - Repeat a few times.
5. macOS 26, slow app:
   - pick a third-party menu bar app and stop it with `kill -STOP <pid>`;
   - open the Layout pane and the Shelf: both open within about 3 s, and the other items are correct;
   - `kill -CONT <pid>`: within about a minute, or at the next refresh, its item has its app again.
6. Optional, macOS 26: `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "SourcePIDCache"'`. Scan lines report durations well under 2 s normally, and "finished" for complete scans.
7. macOS 26, Settings → item spacing → Apply: the apps relaunch as before (watch for skipped apps; F-101 is a separate finding).
8. macOS 27 smoke test: launch, open the Layout pane and the Shelf. Nothing should differ; the cache is never started there.
9. Optional, with Xcode: a Debug run from Xcode still attaches the debugger (Debug keeps get-task-allow).

## Risks (macOS 26 / 27 and process)

- **CI is red until the CI chain lands.**
  - build.yml "Check the signature", "Check the identifiers" (it reads the deleted Swift file and the service's Info.plist) and the network-binary loop all fail.
  - So does the compat job's `chmod` of the service binary, and release.yml's hardened-runtime loop.
  - This branch and the CI chain's `.github` edits must ship in one PR (CLAUDE.md: one PR, push once).
- **macOS 26: the in-app path was only a fallback until now.**
  - It shipped in da53d80, but the maintainer's 26.7.1 Mac runs the service, so the fallback has had little real use. The manual steps 3-5 matter.
  - `Bridging.setProcessUnresponsiveTimeout(3)` now always applies to holzBar's own WindowServer connection; before, only in the service or the fallback.
- **macOS 26: the 0.5 s timeout and 2 s budget can leave items without their app.**
  - This affects apps that are slow but alive, and many apps at login or after a Control Center restart.
  - Such items get a UUID namespace until a later read. SectionRestore never places those, profiles skip them for that read, and spacing skips their apps (F-101).
  - There is no timer retry, by design (events over polling): the next read triggered by an event retries.
- **macOS 26: holzBar asks itself through Accessibility.**
  - This covers its group and spacer items. It is safe because the main actor is only suspended.
  - If the main thread is busy for more than 0.5 s, that read misses holzBar's own non-control items (never paused, so the next read retries).
  - D-10 (frame matching for groups and spacers) would remove this. It is left for later on purpose.
- **Timeout signal.** Detection is by elapsed time (≥ 450 ms with a 0.5 s per-element timeout). A legitimately slow call that takes over 450 ms on an overloaded Mac counts as a timeout and pauses that app for 10 s. Accepted: that app was slow.
- **macOS 27:** no functional change. AccessibilityBackend27 never touches the cache, and Shared/ code only compiles. The risk is limited to build breakage, which CI's xcode-27 build covers.
- **macOS 14/15:** `DispatchSerialQueue` and `asUnownedSerialExecutor()` are macOS 14.0 API (the deployment target). The cache is never created on 14/15, and the compat legs launch the app.
- **Release builds without get-task-allow:** lldb and Instruments can no longer attach to Release or install.sh builds. Debug builds are unaffected.
- **Conflicts with other chains:**
  - The next part of this chain (F-06, decision indicators-1) planned to add an Apple-anchor check to `Shared/CodeSigning/CodeSignature.swift` and tests to `SharedCodeSigningTests`. Both are deleted here, so that part must recreate a small code-signing file and a package target pair from scratch: `git show 7e7ed6bf:Package.swift` shows the old target shape. It must not bring back LightweightCodeRequirements or any service code.
  - F-06 also edits the scan this plan restructures (`SourcePIDCache.scan`, the claim per child).
  - F-101 edits spacing for unresolved PIDs.
  - The release chain must not also edit `project.pbxproj` for F-05 and F-52, or the two changes conflict.
- **Upgrade path:** a running 0.0.7-beta1 service exits with the old app. The app's designated requirement does not change (same certificate), so no new TCC prompt for certificate-signed releases.

## doc_updates_needed

The executor copies this section into the SUMMARY.

**CI (the CI or release chain; `.github/` is out of scope here):**

1. `.github/workflows/build.yml`:
   - "Check the signature": drop `SERVICE` and the loop over two bundles; check the app only, and update the comment and echo text.
   - "Check the identifiers": drop the service lines (`SERVICE`, `SERVICE_ID`, the `sed` on the deleted `Shared/Services/MenuBarItemService.swift`, and both service comparisons); keep the app ID, name, display name and URL scheme output; update the step comment.
   - "Check the binaries for network code": loop over `Contents/MacOS/holzBar` only; entitlements check on the app only.
   - compat "Launch the app": `chmod +x` only `Contents/MacOS/holzBar`.
   - New step: fail if the bundle contains any Mach-O file other than `Contents/MacOS/holzBar` (for example `find holzBar.app -type f -exec file {} + | grep Mach-O`), and fail if `Contents/XPCServices` exists.
   - New step (release-1, F-05): fail when `codesign -d --entitlements - --xml` on the app lists any key.
2. `.github/workflows/release.yml`:
   - remove the comment at about lines 78-80 ("The XPC service keeps working …");
   - the hardened-runtime/ad hoc loop at about line 128 checks the app only;
   - the nested-signing `find` loop may stay (it finds nothing) or go;
   - the release chain also drops `entitlements` from `--preserve-metadata` and may pass `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` explicitly (now redundant with the project setting, but harmless). It does not need to edit the SwiftLint phase: the project now guards it.
3. `.github/scripts/privacy-check.py`: remove `"MenuBarItemService"` from `SOURCE_DIRS` and the directory from the header comment (line 8). It walks a missing directory without error today, so this is cleanup.
4. `Scripts/install.sh`: nothing required. The project setting already removes get-task-allow from its Release build; the release chain may add the explicit override for symmetry.

**Docs (maintainer or a docs part; F-49):**

1. `docs/signing.md`:
   - line 7: state that holzBar ships no nested code, so a replaced binary anywhere in the bundle does not get the permission;
   - line 10: "no entitlements" becomes true for Release only with this F-05 change; re-check after the release chain;
   - line 23: drop the XPC-service reason for leaving Organizational Unit empty;
   - line 61: sign only `holzBar.app`;
   - line 87: "signs the app" (no XPC service);
   - lines 97-99: replace the "The XPC service" section with a short "No nested code" note. On macOS 26 the item lookup runs inside holzBar on its own queue. Nested helpers would run with holzBar's permissions and could be swapped in a copied bundle, so holzBar ships none, and CI checks the bundle.
2. `SECURITY.md`:
   - line 14: "the hardened runtime on the app" (drop "and its XPC service");
   - T-06-M4: keep it, and narrow its wording to the main executable;
   - add a row: "Code nested in a copied holzBar.app runs with holzBar's grants (macOS 26)", Mitigated from the next beta, because holzBar ships no nested code;
   - F-05 (get-task-allow) stays a separate row: Mitigated once the project setting ships and the release chain's CI check lands.
3. `docs/upstream-bugs.md:28`: the macOS 26 "Loading menu bar items…" row. holzBar recognises its own dividers by their window frames and looks up the other items in the app, on a queue of its own, with time limits; the item service is gone.
4. `docs/comparison.md:66` (and the README and website tables if they carry the row): replace "Menu bar item service accepts only holzBar's own code" with a row such as "No helper process runs with holzBar's permissions (macOS 26)". Re-check the README's "holzBar vs. Ice and Thaw" table and https://holzcloud.ch/holzbar.
5. Next beta's release notes (`docs/release-notes/v<next>.md`):
   - Changed (macOS 26): holzBar no longer ships the menu bar item service; it finds each item's app itself, off the main thread, with time limits. One process fewer, and no nested code runs with holzBar's permissions.
   - Fixed: short freezes when apps launch or quit while the Shelf or Layout pane reads items; one slow app no longer stalls every item read.
   - Security: Release builds no longer allow a debugger to attach.
6. `CLAUDE.md`, Naming: propose this to the user, do not edit it. Drop ", the XPC service is `com.holzcloud.holzBar.MenuBarItemService`".
7. `.planning/PROJECT.md:50`: "macOS 26 (in-app Accessibility lookup on its own queue)". Also refresh `.planning/codebase/*` (ARCHITECTURE, STRUCTURE, STACK, INTEGRATIONS, CONVENTIONS, TESTING, CONCERNS), which name the service; `/gsd-map-codebase` does this.

## Appendix A: gate scripts

Validated copies are in `G`; recreate them only if they are missing. Each was run against the
current project (fails as expected) and against a simulated result of this plan (passes).

`G/pbxgate.py`:

```python
#!/usr/bin/env python3
# usage: plutil -convert json -o - holzBar.xcodeproj/project.pbxproj | python3 pbxgate.py structure|entitlements ...
import json, re, sys
project = json.load(sys.stdin)
objects = project["objects"]
checks = set(sys.argv[1:]) or {"structure", "entitlements"}
errors = []
targets = [o for o in objects.values() if o.get("isa") == "PBXNativeTarget"]
app = next(t for t in targets if t.get("name") == "holzBar")
configs = {objects[c]["name"]: objects[c]["buildSettings"] for c in objects[app["buildConfigurationList"]]["buildConfigurations"]}
if "structure" in checks:
    ref = re.compile(r"^[0-9A-F]{24}$")
    def walk(value, where):
        if isinstance(value, str):
            if ref.match(value) and value not in objects:
                errors.append(f"dangling reference {value} in {where}")
        elif isinstance(value, list):
            for item in value:
                walk(item, where)
        elif isinstance(value, dict):
            for key, item in value.items():
                walk(item, f"{where}.{key}")
    for key, obj in objects.items():
        walk(obj, key)
    walk(project["rootObject"], "rootObject")
    if [t["name"] for t in targets] != ["holzBar"]:
        errors.append(f"targets are {[t['name'] for t in targets]}, expected only holzBar")
    for key, obj in objects.items():
        text = json.dumps(obj)
        if obj.get("isa") in ("PBXCopyFilesBuildPhase", "PBXTargetDependency", "PBXContainerItemProxy") or "xpc" in text.lower() or "MenuBarItemService" in text:
            errors.append(f"service leftover {key}: {obj.get('isa')}")
    if app.get("dependencies"):
        errors.append("holzBar still has target dependencies")
    phases = [objects[p].get("name", objects[p]["isa"]) for p in app["buildPhases"]]
    if phases != ["PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase", "SwiftLint"]:
        errors.append(f"holzBar build phases are {phases}")
    groups = [objects[g]["path"] for g in app["fileSystemSynchronizedGroups"]]
    if sorted(groups) != ["Shared", "holzBar"]:
        errors.append(f"holzBar synchronized groups are {groups}")
if "entitlements" in checks:
    if configs["Release"].get("CODE_SIGN_INJECT_BASE_ENTITLEMENTS") != "NO":
        errors.append("the holzBar Release configuration does not set CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO")
    if "CODE_SIGN_INJECT_BASE_ENTITLEMENTS" in configs["Debug"]:
        errors.append("the Debug configuration must keep the default (get-task-allow for the debugger)")
for error in errors:
    print("FAIL:", error)
print(f"PBXGATE {' '.join(sorted(checks))}: {'OK' if not errors else 'FAILED'}")
sys.exit(1 if errors else 0)
```

`G/lintphase.sh`:

```zsh
#!/bin/zsh
# usage: lintphase.sh <pbxproj> — runs the SwiftLint phase script under CI, Release and Debug with a fake swiftlint
PBX=${1:?}
T=${0:A:h}/lintphase-$$; mkdir -p $T
plutil -convert json -o - "$PBX" | python3 -c 'import json,sys; o=json.load(sys.stdin)["objects"]; print(next(v["shellScript"] for v in o.values() if v.get("isa")=="PBXShellScriptBuildPhase" and v.get("name")=="SwiftLint"), end="")' > $T/phase.sh
mkdir $T/bin && printf '#!/bin/sh\ntouch "%s/ran"\n' $T > $T/bin/swiftlint && chmod +x $T/bin/swiftlint
run() { rm -f $T/ran; env -i HOME=$HOME PATH=$T/bin:/usr/bin:/bin "$@" /bin/sh $T/phase.sh > $T/out 2>&1; [ -e $T/ran ] && echo ran || echo skipped; }
FAIL=0
[ "$(run CI=true CONFIGURATION=Debug)" = skipped ] || { echo "FAIL: runs under CI"; FAIL=1; }
[ "$(run CONFIGURATION=Release)" = skipped ] || { echo "FAIL: runs in Release"; FAIL=1; }
[ "$(run CI=true CONFIGURATION=Release)" = skipped ] || { echo "FAIL: runs under CI in Release"; FAIL=1; }
[ "$(run CONFIGURATION=Debug)" = ran ] || { echo "FAIL: does not lint local Debug builds"; FAIL=1; }
rm -rf $T
echo "LINTPHASE $([ $FAIL = 0 ] && echo OK || echo FAILED)"
exit $FAIL
```

`G/swifttest.sh`:

```zsh
#!/bin/zsh
# usage: swifttest.sh <repo-root> [suite-that-must-pass ...]
# Runs swift test, retrying only the Command Line Tools flake "plugin for module
# 'TestingMacros' not found" (up to 6 runs). Passes when both test products report
# "Test run with N tests ... passed" and every named suite passed.
ROOT=${1:?usage: swifttest.sh <repo-root> [suite ...]}; shift
LOG=${0:A:h}/swifttest-$$.log
for i in 1 2 3 4 5 6; do
  swift test --package-path "$ROOT" > "$LOG" 2>&1 && break
  grep -q "plugin for module 'TestingMacros' not found" "$LOG" || break
  echo "run $i: TestingMacros plugin flake, retrying"
done
sed 's/\x1b\[[0-9;]*m//g' "$LOG" > "$LOG.plain"
grep -E "Test run with .* (passed|failed)" "$LOG.plain"
FAIL=0
[ "$(grep -cE 'Test run with .* passed' "$LOG.plain")" -ge 2 ] || FAIL=1
grep -E "✘|error:" "$LOG.plain" | head -20
for SUITE in "$@"; do
  grep -q "Suite \"$SUITE\" passed" "$LOG.plain" || { echo "FAIL: suite $SUITE did not pass"; FAIL=1; }
done
echo "SWIFTTEST $([ $FAIL = 0 ] && echo OK || echo FAILED) (log: $LOG.plain)"
exit $FAIL
```

## Appendix B: exact project.pbxproj lines for Task 3

F-05, in `7166833B2A767E6B006ABF84 /* Release */`, between the `"CODE_SIGN_IDENTITY[sdk=macosx*]"` and
`CODE_SIGN_STYLE` lines (four tabs):

```
				CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO;
```

F-52, the whole `shellScript` line of `1720D48F2BB9B60500A7AC63 /* SwiftLint */` (three tabs):

```
			shellScript = "# CI lints with the pinned SwiftLint image (lint.yml). Never run whatever swiftlint is on PATH there or in Release builds (releases, install.sh).\nif [ -n \"${CI:-}\" ] || [ \"${CONFIGURATION:-}\" = Release ]; then\n  echo \"note: SwiftLint skipped (CI or Release build)\"\n  exit 0\nfi\n\nif [[ \"$(uname -m)\" == arm64 ]]; then\n    export PATH=\"/opt/homebrew/bin:$PATH\"\nfi\n\nif which swiftlint > /dev/null; then\n  swiftlint\nelse\n  echo \"warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint\"\nfi\n";
```

<output>
Create `.planning/audit/remediation/xpc-remove-xpc-SUMMARY.md` (Task 3, step 3), committed with Commit 4.
</output>
