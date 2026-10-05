---
phase: audit-remediation-xpc
plan: attribution
type: execute
wave: 2
depends_on: [remove-xpc]
chain: xpc
part: attribution
findings: [F-06]
decisions:
  - "indicators-1 — Schutz plus sichere Zuordnung (Recommended)"
base: "audit-manual/xpc-attribution @ 1694b9d6 (remove-xpc part complete: no XPC service, SourcePIDCache is an actor with batch scans, Shared/CodeSigning deleted)"
files_modified:
  - Package.swift
  - Shared/CodeSigning/CodeSignature.swift                         # new (path was deleted by remove-xpc; new content)
  - Tests/SharedCodeSigningTests/CodeSignatureTests.swift          # new (same)
  - Shared/Services/SourcePIDCache.swift
  - holzBar/Core/SourcePIDClaims.swift                             # new
  - Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift              # new
  - holzBar/Core/CaptureIndicatorItems.swift                       # new
  - Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift        # new
  - holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift
  - .planning/audit/remediation/xpc-attribution-PLAN.md            # this file, committed with the fix
  - .planning/audit/remediation/xpc-attribution-SUMMARY.md         # new, executor's summary
autonomous: true
requirements: [F-06]
user_setup: []

estimate:
  tokens: 120000
  raw_tokens: 120000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "On every macOS version, an item titled AudioVideoModule or FaceTime can never be hidden, whatever namespace (app) it is attributed to; there is no title rule for Item-0"
    - "On macOS 26 a source-PID scan asks the apps whose running code satisfies `anchor apple` first, then all others; inside each group, apps with a known extras menu bar come first; the signature is read once per running app, never inferred from a bundle identifier or name"
    - "The first Apple-signed app that reports an enabled item within 1 pt of a window's centre gets that window, also from a scan that ran out of time; no later claim changes it"
    - "A window that only apps not signed by Apple claim goes to such an app only when exactly one of them claimed it and the scan finished; two or more such apps make it contested, and it belongs to no app (UUID namespace, which SectionRestore never places)"
    - "The remove-xpc properties hold: the scan runs on the cache's own queue, 0.5 s per element, a 2 s budget that also covers the first scan's signature checks, a miss is cached only after a finished scan"
    - "swift test covers the signature helper (spawned /bin/sleep is Apple-signed; an ad hoc re-signed copy of it is not, on macOS 26+; an exited process is not), the claim decision and the indicator titles"
  artifacts:
    - path: Shared/CodeSigning/CodeSignature.swift
      provides: "nonisolated enum CodeSignature with static func isSignedByApple(processIdentifier:) -> Bool (SecCodeCopyGuestWithAttributes + kSecGuestAttributePid, SecRequirementCreateWithString(\"anchor apple\"), SecCodeCheckValidity)"
    - path: holzBar/Core/SourcePIDClaims.swift
      provides: "pure claim decision: Claim(pid:isSignedByApple:), add(_:), isSettled, decision(scanFinished:) -> .owner(pid) | .contested | .unresolved"
    - path: holzBar/Core/CaptureIndicatorItems.swift
      provides: "titles AudioVideoModule and FaceTime; isIndicator(title:)"
    - path: Shared/Services/SourcePIDCache.swift
      provides: "Apple-first app order, per-window claims, decisions committed to the cache"
    - path: Package.swift
      provides: "SharedCodeSigning target (Shared/CodeSigning) and SharedCodeSigningTests test target"
  key_links:
    - from: "SourcePIDCache.partitionApps()"
      to: "CodeSignature.isSignedByApple(processIdentifier:)"
      via: "CachedApplication.isSignedByApple (lazy, once per running app, on the cache's queue)"
    - from: "SourcePIDCache.scan(for:) child loop"
      to: "SourcePIDClaims.add(_:) / isSettled"
      via: "one Claim(pid:isSignedByApple:) per matching enabled child; a settled window leaves `remaining`"
    - from: "SourcePIDCache.pids(for:)"
      to: "SourcePIDClaims.decision(scanFinished:)"
      via: "Scan.decision(for:) — .owner is cached; .contested/.unresolved record a miss only after a finished scan"
    - from: "MenuBarItemTag.canBeHidden"
      to: "CaptureIndicatorItems.isIndicator(title:)"
      via: "namespace-independent title rule, read by isValidForCaching, the SectionRestore candidate filter and Concealer27"
---

# xpc / attribution: Apple-signed apps claim item windows first, contested windows go to no app, and the capture indicators never hide

<objective>
Implement exactly the maintainer's choice "Schutz plus sichere Zuordnung" (decision indicators-1) for F-06, on
top of the in-app source-PID lookup that the remove-xpc part of this chain created (the XPC service no longer
exists):

1. **Title rule.** `MenuBarItemTag.canBeHidden` returns `false` for the titles `AudioVideoModule` and
   `FaceTime` whatever the namespace. The macOS 27 menuBarAgent rule and the existing non-hideable tags stay.
   No title rule for `Item-0`.
2. **Attribution.** In `SourcePIDCache` (the actor's batch scan, which replaced `updatePID`), apps whose
   running code is signed by Apple (`anchor apple`, checked once per running app) are asked first. The first
   Apple-signed claim wins. A claim by any other app wins only if no other app claims the same centre within
   1 pt in a finished scan; a contested window belongs to no app. The claim decision is a pure, unit-tested
   type in `holzBar/Core`. The signature helper comes back as `Shared/CodeSigning/CodeSignature.swift` with a
   `SharedCodeSigning` package target pair, now holding only the Apple check.

Purpose: close F-06's failure scenario. A login item that reports Accessibility frames on Control Center's
item windows can no longer take the camera and microphone indicator, and could not make it hideable even if
it did. Other Apple items, such as the Screenshot tool's recording stop button, are protected by the
attribution order.

**Answer to the relayed user question ("Können wir das mit dem signieren nicht doch anders lösen?").** This
part needs no signing of holzBar: no Developer ID, no notarization, no certificate, and no change to how
releases are signed. It only *reads* the signature that Apple put on macOS's own processes, such as Control
Center and screencaptureui. Every Mac has those signatures, and ad hoc builds, CI artifacts and the
certificate-signed cask behave the same. The only "signing" anywhere in this part is an ad hoc signature on a
temporary copy of `/bin/sleep` inside one unit test, used as a non-Apple example; it needs no key. Signature-free
ways to recognise Apple's processes were weighed:
- bundle-ID prefix `com.apple.`: any app can declare one (F-44), so the decision context rules it out;
- executable path on the sealed system volume: would also work for system agents, but misses Apple's apps
  outside `/System`, and is not what the maintainer chose.

The signature check is cheap: on this Mac (macOS 26.7.1) checking all 81–115 running apps took 0.13–0.31 s
once (probe in `P/applecheck*.swift`, see Paths).

Output: one commit on `audit-manual/xpc-attribution`, a SUMMARY, and the hand-off list in "doc_updates_needed".
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/audit/FULL-AUDIT-2026-10-05.md (sections F-06, F-44, F-72, F-101)
@/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/indicators-1.md
@/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/xpc-trust-1.md (context only; already implemented)
@.planning/audit/remediation/xpc-remove-xpc-SUMMARY.md ("Impact on the F-06 part")
@Shared/Services/SourcePIDCache.swift
@holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift
@holzBar/Core/SourcePIDLookupSchedule.swift and Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift (style of a pure Core type and its tests)
@Package.swift (and `git show 7e7ed6bf:Package.swift` for the old SharedCodeSigning target shape)
</context>

## Paths used below

- `W` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution` (the worktree; the only repository you change)
- `S` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`
- `G` = `S/xpc-remove-probe` (gate script `swifttest.sh`, validated in the remove-xpc part)
- `P` = `S/f06-probe`. It holds:
  - `P/tree/`: a prototype of this plan's end state. It is a copy of `W` at 1694b9d6 with every change below
    applied. It passed `appcheck.sh` (0 errors), `swift test` (SharedCodeSigning 3, MacOS27 136,
    HolzBarCore 283), pinned SwiftLint, both privacy checks and the strings check.
  - `P/f06.patch`: the same changes as a patch against 1694b9d6. `git -C W apply --check` passes.
  - `P/applecheck.swift` and `P/applecheck2.swift`: the read-only probes behind the timing and
    behaviour facts in this plan.

  Copy files from `P/tree` as the tasks say. This plan's text is the specification: where the prototype
  and the plan differ, the plan wins. If `P` is gone, write the files from the specification below.

The verify commands spell out absolute paths, because shell state does not persist between calls.

## Ground rules for the executor

- Work only in `W` on the current branch. Never touch `/Users/cheidenreich/privat/holzBar` or other
  worktrees. Never switch branches, push, or run a gh command that writes. Never launch, quit or relaunch
  holzBar. Never change system state (tccutil, `defaults write` on real domains). Spawning `/bin/sleep`,
  `/usr/bin/true` and `/usr/bin/codesign` on a temporary copy, as the tests do, is fine.
- Do not edit anything under `.github/` or `Scripts/`, or `README.md`, `docs/`, `SECURITY.md`, `CLAUDE.md`,
  release notes, `holzBar.xcodeproj`. Record what they need in the SUMMARY's `doc_updates_needed` (copy the
  section below).
- Do not edit `holzBar/MenuBar/Backends/ServiceBackend26.swift`. Other chains (ax-observers,
  appearance-split) add methods to it, and this part needs no change there.
- English everywhere. Match the surrounding style and comment density. Do not name audit IDs (F-06) in
  code comments; the commit message carries them.
- Log only counts and durations as `.public`; pids and names of other apps are `.private`. Do not log from
  `CodeSignature`.
- The new code must not name the removed service. The leftovers gate still forbids the removed names
  (see Task 3). This part deliberately re-creates `Shared/CodeSigning/CodeSignature.swift` and the
  `SharedCodeSigning`/`SharedCodeSigningTests` targets with new content. It does not bring back
  LightweightCodeRequirements, cdhash pinning or any peer check.
- No new user-facing strings are needed (no UI change). If you add one anyway, it needs all five
  languages (en, de-CH with "ss", fr, it, rm), and `strings-check.py` must pass.
- `swift test` on this Mac sometimes fails with "plugin for module 'TestingMacros' not found". Only that
  message is retried, by `G/swifttest.sh`.
- Use `S/appcheck.sh` with its default 26.5 SDK. The Command Line Tools lack the macOS 27 SDK's SwiftUI
  macro plugin.
- If a gate fails and you cannot fix it, revert the uncommitted changes and report `fix-failed` with the
  reason, then stop the part. To revert: `git -C W checkout -- .`, then `git -C W clean -fd -- holzBar
  Shared Tests`, then remove `W/.planning/audit/remediation/xpc-attribution-SUMMARY.md` if you created it.
  Leave this PLAN file in place.

## Decisions (traceability)

Each point of the maintainer's implementation note gets an ID.

| ID | Source | Decision | Where |
|----|--------|----------|-------|
| D-01 | indicators-1 | Chosen option: protection plus safe attribution (both parts below) | Tasks 1-3 |
| D-02 | indicators-1 (1) | `MenuBarItemTag.canBeHidden` returns false for the titles AudioVideoModule and FaceTime whatever the namespace; keep the menuBarAgent and UUID rules | Task 3 |
| D-03 | indicators-1 (1) | Never add a title rule for Item-0 (the default title of third-party status items) | Task 3 (test asserts it) |
| D-04 | indicators-1 (2) | Apple-signature check in `Shared/CodeSigning/CodeSignature.swift`: `SecCodeCopyGuestWithAttributes` with `kSecGuestAttributePid`, then `SecRequirementCreateWithString("anchor apple")`, then `SecCodeCheckValidity` | Task 1 |
| D-05 | indicators-1 (2) | Evaluated once per CachedApplication | Task 1 |
| D-06 | indicators-1 (2) | Scan Apple-signed apps first, then the rest, keeping the hasExtrasMenuBar partition inside each group | Task 1 |
| D-07 | indicators-1 (2) | Accept the first Apple-signed match | Task 2 |
| D-08 | indicators-1 (2) | For a non-Apple match, keep scanning; leave the window unmapped (UUID namespace) if another app claims a centre within 1 pt | Task 2 |
| D-09 | indicators-1 (2) | The claim decision is a pure function with unit tests | Task 2 |
| D-10 | indicators-1 (2) | Test the helper in SharedCodeSigningTests with a spawned /bin/sleep (positive) and an ad hoc re-signed copy (negative); not the test process (xctest is Apple-signed) | Task 1 |
| D-11 | indicators-1 (2) | A full scan runs once per uncached window and is cached; consider one frame index per scan | Task 2: already met by remove-xpc's batch scan, which builds one map of window centres per scan and shares one scan across all pending windows. No extra index |
| D-12 | indicators-1 (2) | Coordinate with F-12, F-37, F-72 (same file) and F-44 (can reuse the Apple check) | Tasks 1-2 keep the actor, budget and miss rules; `CodeSignature.isSignedByApple` is internal and reusable; F-44 itself is not in scope |
| D-13 | indicators-1 (2) | CI compiles the app; the host has no Xcode | Gates: appcheck.sh + swift test here; CI later |
| D-14 | indicators-1 (2) | The user checks on macOS 26 that the Layout pane still names and places every item, and that Wi-Fi, Battery, Clock and AudioVideoModule stay Control Center's | Maintainer section |
| D-15 | indicators-1 context (c) | Apple status comes from the code signature, never from a `com.apple.` prefix | Task 1 (grep gate) |
| D-16 | computed task, additional scope | Build on the in-app lookup; the service is gone. Re-create a small code-signing file and package target pair (remove-xpc SUMMARY), without LightweightCodeRequirements or service code | Task 1 |

Claude's discretion (documented choices):

| ID | Choice | Why |
|----|--------|-----|
| C-01 | A claim by an app not signed by Apple is accepted only after a **finished** scan (every app asked or skipped). If the scan ran out of budget or was cancelled, the window stays pending: not cached, no miss, retried at the next read | D-08 requires knowing whether another app claims the centre, which an unfinished scan cannot tell. Apple claims need no finished scan (D-07) |
| C-02 | A contested window is recorded as a miss after a finished scan, like a window nobody claimed (30 s, or earlier when the running apps change or a skipped app becomes askable) | Avoids a full rescan at every read while two apps keep claiming the same centre; keeps F-72's rule |
| C-03 | The two titles live in a pure `CaptureIndicatorItems` type in `holzBar/Core`, so the rule and "never Item-0" are unit tested; `MenuBarItemTag` is not in the test package. The separate UUID-only AudioVideoModule clause in `canBeHidden` is removed because the namespace-independent title rule covers it: an AudioVideoModule item in a UUID namespace still cannot be hidden ("keep the UUID rule" is kept in behaviour). The `nonHideableItems` list stays unchanged | Testability; no dead code |
| C-04 | The `SharedCodeSigning` target uses `appCore` (main actor as default isolation), not the old `approachableConcurrency` | The app compiles `Shared/` with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and the package's stated rule is "the tests check the semantics the app ships". The old setting mirrored the deleted service target |
| C-05 | The ad hoc copy test is `@available(macOS 26.0, *)`; the positive and exited-process tests run everywhere | CI runs `swift test` on macOS 14 and 15 too. There, a non-Apple arm64e program may not be allowed to run on Apple silicon. On macOS 26.7.1 the copy runs (verified). Only the macOS 26 backend uses the check |
| C-06 | Terminated and `.prohibited` apps are sorted last without a signature check. A cached app object is reused for a pid only while it is not terminated | No check for apps a scan skips anyway. A reused pid must get a fresh signature check |
| C-07 | The per-scan debug line also reports the number of contested windows (`.public` count) | Lets the maintainer see contests in `log stream` |
| C-08 | One commit for F-06 (both parts), which also carries this PLAN and the SUMMARY | "Commit each finding atomically"; remove-xpc precedent for the planning files |

## Source coverage audit

| Source item | Status |
|-------------|--------|
| GOAL: the camera/microphone indicator can never be hidden; windows go to Apple's signature-checked processes first; contested windows go to no app | COVERED (Tasks 1-3) |
| F-06 failure scenario steps 1-3 | COVERED (see "How the failure scenario is closed") |
| F-06 fix 1 (title rule; Item-0 only via attribution) | COVERED (Task 3; Item-0 explicitly excluded, D-03) |
| F-06 fix 2 (Apple processes first; refuse a match two apps claim) | COVERED (Tasks 1-2) |
| F-06 "Or decide canBeHidden from the window owner" | NOT APPLICABLE: on macOS 26 Control Center owns every window (decision context (a)) |
| F-44 (namespace spoofing) | OUT OF SCOPE (no decision yet); the Apple check is left reusable (D-12) |
| F-12, F-37, F-72 | ALREADY FIXED by remove-xpc; properties kept (must_haves truth 5) |
| F-101 (spacing skips unresolved PIDs) | OUT OF SCOPE; contested windows add to the unresolved set (Risks) |
| D-01 … D-16 | All COVERED; D-11 met by the existing batch scan; D-13/D-14 are gates and hand-offs |

<!-- planner-discipline-allow: XPC -->
<!-- planner-discipline-allow: xpc -->
<!-- planner-discipline-allow: LightweightCodeRequirements -->
<!-- planner-discipline-allow: nonisolated(unsafe) -->
<!-- planner-discipline-allow: com.apple. -->
<!-- planner-discipline-allow: scan.found -->
<!-- planner-discipline-allow: Item-0 -->
(The service and LightweightCodeRequirements are named above only to say they stay gone. `com.apple.` is named only as the rejected approach. `Item-0` is named only as the title that must not be added.)

## Interfaces after this plan

Signatures and names only; the bodies are in the tasks and in `P/tree`.

- `Shared/CodeSigning/CodeSignature.swift` (file header `//  Shared`):
  - `nonisolated enum CodeSignature`
  - `static func isSignedByApple(processIdentifier: pid_t) -> Bool`
- `holzBar/Core/SourcePIDClaims.swift` (file header `//  holzBar`):
  - `nonisolated struct SourcePIDClaims`, with nested `nonisolated struct Claim: Equatable { let pid: pid_t; let isSignedByApple: Bool }`
  - nested `nonisolated enum Decision: Equatable { case owner(pid_t), contested, unresolved }`
  - `private(set) var claims: [Claim]`, `init()`, `mutating func add(_ claim: Claim)`
  - `var isSettled: Bool`: true once any claim is Apple-signed
  - `func decision(scanFinished: Bool) -> Decision`
- `holzBar/Core/CaptureIndicatorItems.swift` (file header `//  holzBar`):
  - `nonisolated enum CaptureIndicatorItems`
  - `static let titles: Set<String> = ["AudioVideoModule", "FaceTime"]`
  - `static func isIndicator(title: String) -> Bool`
- `Shared/Services/SourcePIDCache.swift`:
  - `CachedApplication.isSignedByApple` (`private(set) lazy var`)
  - `Scan.claims: [CGWindowID: SourcePIDClaims]`, which replaces the `found` dictionary
  - `Scan.decision(for windowID: CGWindowID) -> SourcePIDClaims.Decision`
  - `partitionApps()` orders five groups: Apple with a bar, Apple without, others with a bar, others without, then terminated or prohibited apps
- `Package.swift`: the targets `SharedCodeSigning` (path `Shared/CodeSigning`, `appCore`) and
  `SharedCodeSigningTests` (path `Tests/SharedCodeSigningTests`, `approachableConcurrency`, depends on
  `SharedCodeSigning`).
- Unchanged: `SourcePIDCache.pids(for:)`, `start()`, `ServiceBackend26`, `SourcePIDLookupSchedule`.

## How the failure scenario is closed

The audit's scenario (F-06):
1. A login item's status item reports AX frames centred on Control Center's item windows.
2. When a capture starts, it claims the AudioVideoModule window.
3. The next reconcile moves the indicator into Hidden, if "Place new menu bar items in" is Hidden or a
   saved ItemSections entry exists.

After this plan:
- **Step 2 fails.** Control Center is signed by Apple, so it is in the first group of every scan (D-06).
  Its enabled AudioVideoModule child claims the window, and the first Apple-signed claim wins and settles
  the window (D-07). The login item, which is not Apple-signed, is asked later, and its claim cannot
  change the decision. Before, the scan went in running-apps order with known bars first, which put
  login items (indices 4-7 in the audit's probe) before Control Center (11).
- **Step 3 fails even if step 2 succeeded.** For example, Control Center might be skipped as unresponsive
  or paused, so that the login item is the only claimant. Its tag would then be `<app>:AudioVideoModule`.
  `canBeHidden` is false for that title in every namespace (D-02), so `isValidForCaching`
  (MenuBarItemManager), the SectionRestore candidate filter and Concealer27 all leave it alone. A saved
  ItemSections entry or a Hidden new-items setting therefore never moves it.
- **Other Apple items.** Examples are screencaptureui's `Item-0` (the recording stop button), Wi-Fi,
  Battery and Clock. They are protected by the order: Apple apps are asked first, including
  screencaptureui, which starts on demand and has no known bar yet. That group still comes before every
  third-party app with a bar.
- **Third-party items.** One app can no longer steal another's window. If two such apps claim the same
  centre, the window is contested and belongs to neither (D-08). It gets a UUID namespace, which
  SectionRestore never places, so a contested item stays where macOS put it.
- **Spoofed identity.** Apple status comes only from the code signature (D-15). A process that declares
  `com.apple.*` or names itself like an Apple process stays in the second group.

Residual routes, which are documented and not closed, are under Risks.

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (tracer): read Apple's code signature of a running process and ask Apple-signed apps first</name>
  <files>Package.swift, Shared/CodeSigning/CodeSignature.swift (new), Tests/SharedCodeSigningTests/CodeSignatureTests.swift (new), Shared/Services/SourcePIDCache.swift</files>
  <read_first>Package.swift (whole; and `git -C W show 7e7ed6bf:Package.swift` for the old target pair), Shared/Services/SourcePIDCache.swift (whole: CachedApplication lines 44-109, runningApplicationsDidChange 188-206, partitionApps 239-243, scan 264-342), P/tree/Shared/CodeSigning/CodeSignature.swift, P/tree/Tests/SharedCodeSigningTests/CodeSignatureTests.swift, P/tree/Package.swift</read_first>
  <behavior>
    - CodeSignature.isSignedByApple(processIdentifier:) is true for a just-spawned /bin/sleep (on every macOS).
    - It is false for a running copy of /bin/sleep that was re-signed ad hoc (`codesign --force --sign -`), on macOS 26 and later; the test first requires that the copy is really running (`kill(pid, 0) == 0`), so the result cannot pass vacuously.
    - It is false for the pid of a process that has exited (/usr/bin/true after waitUntilExit).
    - The test process itself is never used (xctest is Apple-signed with Xcode or the Command Line Tools).
  </behavior>
  <action>
1. RED (per D-10, D-16).
   - Add the two targets to `Package.swift` after `HolzBarCoreTests`:
     - `.target(name: "SharedCodeSigning", path: "Shared/CodeSigning", swiftSettings: appCore)` (C-04);
     - `.testTarget(name: "SharedCodeSigningTests", dependencies: ["SharedCodeSigning"], path: "Tests/SharedCodeSigningTests", swiftSettings: approachableConcurrency)`.
   - In the header comment, after "The app compiles the same files through the synchronized `holzBar`
     folder group.", add: "It also compiles `Shared/CodeSigning`, which tells whether a running process is
     signed by Apple; the app compiles it through the synchronized `Shared` folder group."
   - In the next paragraph, change "for the app's Core code (SWIFT_DEFAULT_ACTOR_ISOLATION)" to "for the
     app's code (SWIFT_DEFAULT_ACTOR_ISOLATION)". Keep everything else. Compare with `P/tree/Package.swift`,
     which is the intended result.
   - Copy `P/tree/Tests/SharedCodeSigningTests/CodeSignatureTests.swift` to the same path in `W`. It has
     `@Suite("CodeSignature")` and three tests:
     - "A running program of macOS is signed by Apple";
     - "An ad hoc signed copy of that program is not", marked `@available(macOS 26.0, *)` with a one-line
       comment why (C-05);
     - "A process that has exited is not".

     The private helper `withRunningProgram(at:_:)` starts the program with the argument "30", requires
     `kill(pid, 0) == 0`, runs the body, and in `defer` terminates the process and waits for it.

     The ad hoc test copies `/bin/sleep` into a fresh `FileManager.default.temporaryDirectory`
     subfolder named with a UUID, which it removes in `defer`. It runs `/usr/bin/codesign --force --sign -
     <copy>` with `standardError` set to `FileHandle.nullDevice`, and requires exit status 0.

     The suite's doc comment says why the test process is not used.
   - Run `zsh G/swifttest.sh W CodeSignature` and see it fail, because `Shared/CodeSigning` does not exist
     yet. Do not commit the red state.

2. GREEN (per D-04, D-15). Copy `P/tree/Shared/CodeSigning/CodeSignature.swift`, or write it to this spec:
   - File header `//  CodeSignature.swift` / `//  Shared`; `import Foundation` and `import Security`.
   - `nonisolated enum CodeSignature`. The doc comment says:
     - bundle identifiers and process names are chosen by the app itself, so they cannot tell whether a
       process belongs to macOS;
     - only code that Apple signed satisfies `anchor apple`; third-party apps do not, also those from the
       App Store or signed with a Developer ID;
     - the calls block while they read the signature, so call them off the main thread.
   - `static func isSignedByApple(processIdentifier: pid_t) -> Bool`:
     1. Build the guest attributes `[kSecGuestAttributePid as String: processIdentifier] as CFDictionary`.
     2. Call `SecCodeCopyGuestWithAttributes(nil, attributes, [], &code)`.
     3. Create the requirement on every call with `SecRequirementCreateWithString("anchor apple" as
        CFString, [], &requirement)`. Do not cache it in a static: `SecRequirement` is not `Sendable`, and
        a `nonisolated(unsafe)` static is not worth saving microseconds on a call made once per app.
     4. Return `SecCodeCheckValidity(code, [], requirement) == errSecSuccess`.

     Every failed status or nil out-parameter returns `false`: the process does not exist (any more), the
     code is invalid, or it is signed by anyone else, ad hoc included.
   - No logging, and no bundle-identifier or name comparison anywhere. All APIs exist since macOS 10.6, and
     none is deprecated in the 26.5 SDK (it compiled without warnings under `-swift-version 6
     -default-isolation MainActor`), so no `#available` is needed.
   - Run `zsh G/swifttest.sh W CodeSignature` until it is green: 3 tests on this macOS 26.7.1 host.

3. Wire the check into `Shared/Services/SourcePIDCache.swift` (D-05, D-06, C-06):
   - In `CachedApplication`, after `isTerminated`, add `private(set) lazy var isSignedByApple =
     CodeSignature.isSignedByApple(processIdentifier: processIdentifier)`. Its doc comment says the value is
     read from the code signature once, the first time it is used, on the cache's queue, because the check
     blocks while it reads the signature.
   - In `runningApplicationsDidChange()`, build `cachedApps` only from apps that are not terminated. Add
     the comment "A terminated app's process identifier may already belong to a new process."; the
     prototype uses `apps.lazy.filter { !$0.isTerminated }.map { … }`. A reused pid then gets a fresh
     `CachedApplication`, and with it a fresh signature check.
   - Replace `partitionApps()` with a stable five-group order. A local function `group(of:)` returns:
     - 4 for a terminated or `.prohibited` app, checked first, so such apps get no signature check;
     - otherwise `(isSignedByApple ? 0 : 2) + (hasExtrasMenuBar ? 0 : 1)`.

     Map every app to its group once, then concatenate the groups 0…4 with `flatMap` and `filter`, which
     keeps the running-apps order inside each group. Each app's group is computed once per call, so an
     app that terminates during the call cannot appear twice.

     Doc comment: those signed by Apple first, then the others; in each group, those confirmed to have an
     extras menu bar first; apps that a scan skips anyway come last, without a signature check.
   - `partitionApps()` is already called after `let start = ContinuousClock.now` in `scan(for:)`. So the
     first scan's signature checks count toward the 2 s budget (F-37 bound kept; measured 0.13–0.31 s for
     81–115 apps). Do not move that call.
   - Leave the scan's claim logic as it is in this task: the first match still wins. Task 2 changes it.

4. Run every verify command below. Do not commit yet (C-08).
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/swifttest.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution CodeSignature SourcePIDLookupSchedule   # expect "SWIFTTEST OK" and "Test run with 3 tests in 1 suite passed"</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution f06-t1 | tail -1 | grep -F "ERRORS: 0  EXIT: 0"</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && C=Shared/CodeSigning/CodeSignature.swift && grep -q "static func isSignedByApple(processIdentifier: pid_t) -> Bool" $C && grep -q "kSecGuestAttributePid" $C && grep -q "SecCodeCopyGuestWithAttributes" $C && grep -q 'SecRequirementCreateWithString("anchor apple"' $C && grep -q "SecCodeCheckValidity" $C && ! grep -n -E "nonisolated\(unsafe\)|hasPrefix|bundleIdentifier|Logger|LightweightCodeRequirements" $C && grep -q 'name: "SharedCodeSigning"' Package.swift && grep -q 'name: "SharedCodeSigningTests"' Package.swift && grep -q "lazy var isSignedByApple = CodeSignature.isSignedByApple(processIdentifier: processIdentifier)" Shared/Services/SourcePIDCache.swift && grep -q -F "isSignedByApple ? 0 : 2" Shared/Services/SourcePIDCache.swift && grep -q -F 'filter { !$0.isTerminated }' Shared/Services/SourcePIDCache.swift && ! grep -n -F 'hasPrefix("com.apple' Shared/Services/SourcePIDCache.swift && echo T1-STRUCT-OK</automated>
  </verify>
  <done>`swift test` runs the new SharedCodeSigning suite: 3 tests pass on this macOS 26.7.1 host. The ad hoc copy is proven to run and is reported as not Apple-signed. The app type-checks with 0 errors. On macOS 26 the cache orders the apps Apple-signed first (each with known bars first), and checks each running app's signature once, inside the scan budget. D-04, D-05, D-06, D-10, D-15 and D-16 are done.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: the first Apple-signed claim wins; other apps win only uncontested in a finished scan; contested windows go to no app</name>
  <files>holzBar/Core/SourcePIDClaims.swift (new), Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift (new), Shared/Services/SourcePIDCache.swift</files>
  <read_first>holzBar/Core/SourcePIDLookupSchedule.swift and Tests/HolzBarCoreTests/SourcePIDLookupScheduleTests.swift (style), Shared/Services/SourcePIDCache.swift as left by Task 1 (Scan struct, the child loop of scan(for:), the log line, the commit loop in pids(for:)), P/tree/holzBar/Core/SourcePIDClaims.swift, P/tree/Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift, P/tree/Shared/Services/SourcePIDCache.swift</read_first>
  <behavior>
    - No claims: `.unresolved` whether or not the scan finished; not settled.
    - One Apple-signed claim: `.owner(apple)` whether or not the scan finished; settled.
    - Apple claim plus a non-Apple claim, in either order (also after two non-Apple claims): `.owner(apple)`.
    - Two Apple-signed claims: the first one wins.
    - One non-Apple claim: `.owner(it)` if the scan finished, `.unresolved` if not; not settled.
    - The same non-Apple pid twice (two of its items at the centre): `.owner(it)` after a finished scan.
    - Two different non-Apple pids: `.contested` whether or not the scan finished; not settled.
  </behavior>
  <action>
1. RED (D-09). Copy `P/tree/Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift`. Its seven tests cover
   exactly the behaviour list above:
   - `import Foundation`, `import Testing`, `@testable import HolzBarCore`;
   - `@Suite("SourcePIDClaims")`, with fixtures `controlCenter` (10, Apple), `screenCaptureUI` (11, Apple),
     `loginItem` (20) and `otherApp` (21);
   - a private `claims(_:)` builder that mutates outside `#expect`, as SourcePIDLookupScheduleTests does.

   Run `zsh G/swifttest.sh W SourcePIDClaims` and see it fail, because the type is missing.

2. GREEN. Copy `P/tree/holzBar/Core/SourcePIDClaims.swift`, or write it to the "Interfaces" spec (D-07,
   D-08, C-01).
   - `decision(scanFinished:)`:
     - if any claim is Apple-signed, return `.owner` of the **first** such claim, regardless of
       `scanFinished`;
     - otherwise take the distinct pids: two or more give `.contested`;
     - exactly one gives `.owner(pid)` only when `scanFinished`, else `.unresolved`;
     - none gives `.unresolved`.
   - `isSettled` is `claims.contains(where: \.isSignedByApple)`.
   - The type must be `nonisolated` (holzBar/Core compiles with MainActor as default isolation; the actor
     calls it synchronously).
   - The type doc comment says why:
     - on macOS 26 Control Center owns every item window, so holzBar asks the apps through Accessibility,
       and those frames are self-reported;
     - Apple-signed apps are asked first and win (the first of them);
     - another app gets a window only when a scan that asked every app found no other app claiming it;
     - a window two such apps claim belongs to none;
     - the type knows nothing about Accessibility or windows, so it is tested on its own.

   Run swifttest until it is green.

3. Wire it into `Shared/Services/SourcePIDCache.swift`. The result must equal `P/tree/Shared/Services/SourcePIDCache.swift`; copying that file over Task 1's version is fine. Then check `git -C W diff -- Shared/Services/SourcePIDCache.swift` shows only the hunks below and Task 1's.
   - `Scan`: replace the `found` dictionary with `var claims = [CGWindowID: SourcePIDClaims]()`. Its doc
     comment: the apps that report an item at each window's centre. Add `func decision(for windowID:
     CGWindowID) -> SourcePIDClaims.Decision`, which returns `claims[windowID, default:
     SourcePIDClaims()].decision(scanFinished: isFinished)`.
   - In the child loop, where an enabled child matches pending windows: build one
     `SourcePIDClaims.Claim(pid: pid, isSignedByApple: app.isSignedByApple)`. For each matching window,
     add it to `scan.claims[windowID, default: SourcePIDClaims()]`, and remove the window from `remaining`
     only when its claims are now `isSettled` (D-07/D-08: an Apple claim ends the search for that window;
     after a non-Apple claim, the scan keeps asking the other apps). The loop condition `for app in apps
     where !remaining.isEmpty` stays.
   - The per-scan debug line (C-07): before it, count the decisions over `centers.keys` with a `switch`:
     `.owner` → found, `.contested` → contested, `.unresolved` → nothing. Log "Source PID scan found
     <found> of <count> windows, <contested> contested, finished: <isFinished>, in <duration>". Every
     interpolation is `.public`; they are counts, a flag and a duration.
   - In `pids(for:)`, the commit loop:
     - `if case .owner(let pid) = scan.decision(for: windowID)`: cache and return it and clear the miss,
       as before;
     - `else if scan.isFinished`: record the `FailedLookup` as before, with the comment "Not found, or
       contested: a contested window belongs to no app." (C-02).

     A window that only one non-Apple app claimed in an unfinished scan therefore gets neither cache nor
     miss and is asked again at the next read (C-01).
   - Add one bullet to the type's doc comment, after the time-limit bullet: the frames come from each app
     itself, so any app could report an item where another app's item is, such as Control Center's camera
     and microphone indicator. Apple-signed apps are asked first, and the first of them to claim a window
     gets it. Any other app gets a window only when a finished scan found no other app claiming it
     (``SourcePIDClaims``).
   - Do not change `stableCenters`, the budget and cancellation checks, `timed`, the schedule calls,
     `failedLookups`, `shouldRescan` or `start()`. D-11 is met by the existing single map of centres per
     scan: no extra index.

4. Run every verify command below. Do not commit yet (C-08).
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/swifttest.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution SourcePIDClaims SourcePIDLookupSchedule CodeSignature   # expect "SWIFTTEST OK"; HolzBarCoreTests 280</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution f06-t2 | tail -1 | grep -F "ERRORS: 0  EXIT: 0"</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && F=Shared/Services/SourcePIDCache.swift && grep -q -F "var claims = [CGWindowID: SourcePIDClaims]()" $F && grep -q -F "decision(scanFinished: isFinished)" $F && grep -q -F "SourcePIDClaims.Claim(pid: pid, isSignedByApple: app.isSignedByApple)" $F && grep -q -F "isSettled" $F && grep -q -F "if case .owner(let pid) = scan.decision(for: windowID)" $F && grep -q -F "contested, finished:" $F && ! grep -n -F "scan.found" $F && grep -q "dispatchPrecondition(condition: .onQueue(queue))" $F && grep -q "isOverBudget" $F && grep -q "nonisolated struct SourcePIDClaims" holzBar/Core/SourcePIDClaims.swift && echo T2-STRUCT-OK</automated>
    <automated>python3 /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution/.github/scripts/privacy-check.py logs --root /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution</automated>
  </verify>
  <done>SourcePIDClaims and its 7 tests pass (HolzBarCoreTests 280). In the scan, the first Apple-signed claim settles a window. A non-Apple claim keeps the scan going. The cache stores `.owner` decisions only. Contested and unresolved windows record a miss only after a finished scan. The app type-checks with 0 errors, and the logs check passes. D-07, D-08, D-09 and D-11 are done, plus C-01, C-02 and C-07.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: the capture indicators never hide, whatever app they are attributed to; full gates, SUMMARY and the F-06 commit</name>
  <files>holzBar/Core/CaptureIndicatorItems.swift (new), Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift (new), holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift, .planning/audit/remediation/xpc-attribution-SUMMARY.md (new)</files>
  <read_first>holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift (lines 19-35 canBeHidden, 125-140 nonHideableItems, 158-187 the special tags), holzBar/Core/InterfaceWindowRule.swift (style of a small pure rule), P/tree/holzBar/Core/CaptureIndicatorItems.swift, P/tree/Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift, .planning/audit/remediation/xpc-remove-xpc-SUMMARY.md (SUMMARY format)</read_first>
  <behavior>
    - "AudioVideoModule" and "FaceTime" are indicators.
    - "Item-0" is not (D-03).
    - Titles compare exactly: "audiovideomodule", "AudioVideoModule-1", "Clock" and "" are not indicators.
  </behavior>
  <action>
1. RED. Copy `P/tree/Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift`. It has three tests matching
   the behaviour list: `import Testing`, `@testable import HolzBarCore`, `@Suite("CaptureIndicatorItems")`.
   Run `zsh G/swifttest.sh W CaptureIndicatorItems` and see it fail.

2. GREEN (D-02, D-03, C-03). Copy `P/tree/holzBar/Core/CaptureIndicatorItems.swift`, or write it to the
   "Interfaces" spec.
   - File header `//  holzBar`; `import Foundation`; `nonisolated enum CaptureIndicatorItems`;
     `static let titles: Set<String> = ["AudioVideoModule", "FaceTime"]`; `static func isIndicator(title:
     String) -> Bool { titles.contains(title) }`.
   - The doc comment says:
     - these are the system items that show that the camera, the microphone or the screen is in use
       (AudioVideoModule), or that a FaceTime call is running;
     - they never hide, whichever app holzBar attributes them to, because on macOS 26 an item's app comes
       from Accessibility frames that apps report about themselves;
     - the default title of every app's first status item is deliberately not in the set. The Screenshot
       tool's recording item, which has that title, is protected by its namespace instead
       (`MenuBarItemTag.screenCaptureUI`, plain code font, not a DocC link, because the package does not
       compile MenuBarItemTag).

   Run swifttest until green.

3. Edit `MenuBarItemTag.canBeHidden` (`holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift`, lines 27-34):
   - keep the `#available(macOS 27.0, *), namespace == .menuBarAgent` early `return false` unchanged;
   - keep `!MenuBarItemTag.nonHideableItems.contains(self)`;
   - replace the UUID-only AudioVideoModule clause with `!CaptureIndicatorItems.isIndicator(title: title)`,
     indented as the clause it replaces;
   - put the comment "On macOS 26 an item's app is found from frames that apps report about themselves, so
     the capture indicators stay visible whichever app they are attributed to." directly above the
     `return`.

   Do not change `nonHideableItems`, the special tags or anything else in the file. The result must equal
   `P/tree/holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift`.

4. Run every verify command below (the full gate set).

5. Write `W/.planning/audit/remediation/xpc-attribution-SUMMARY.md` in the format of
   `xpc-remove-xpc-SUMMARY.md`:
   - **Frontmatter**: chain xpc, part attribution, findings [F-06], decision "indicators-1 — Schutz plus
     sichere Zuordnung (Recommended)", status, plan, key-files created/modified, actuals,
     `plan_head_before: 1694b9d6…` (full hash from `git -C W rev-parse HEAD` before committing).
   - **Body sections**:
     - the answer to the relayed question (copy the paragraph from this plan's objective);
     - Commits;
     - "F-06: what changed", for both parts;
     - "How the failure scenario is closed";
     - Design choices: C-01…C-08, and D-11 met by the batch scan;
     - Deviations from the plan, if any;
     - a Gates table with the actual numbers;
     - `doc_updates_needed` (copy the section below);
     - Maintainer verification (copy the section below);
     - Risks (copy the section below);
     - "Open questions for the maintainer": the two residual routes (Apple-signed script hosts, a skipped
       Apple owner) and the follow-up options listed under Risks; and that F-44 can reuse
       `CodeSignature.isSignedByApple`.

6. Make the single commit (C-08). Write the message to `S/f06-probe/commit-msg.txt` (exact text under
   "Commit" below). Then run:
   - `git -C W add -- Package.swift Shared/CodeSigning Shared/Services/SourcePIDCache.swift
     holzBar/Core/SourcePIDClaims.swift holzBar/Core/CaptureIndicatorItems.swift
     holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift Tests/SharedCodeSigningTests
     Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift
     Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift
     .planning/audit/remediation/xpc-attribution-PLAN.md
     .planning/audit/remediation/xpc-attribution-SUMMARY.md`
   - `git -C W commit -F S/f06-probe/commit-msg.txt`

   Then `git -C W status --porcelain` must print nothing.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/xpc-remove-probe/swifttest.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution CaptureIndicatorItems SourcePIDClaims CodeSignature SourcePIDLookupSchedule MenuBarBackendKind   # expect "SWIFTTEST OK"; lines "3 tests in 1 suite", "136 tests", "283 tests"</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution f06-t3 | tail -1 | grep -F "ERRORS: 0  EXIT: 0"</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && T=holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift && grep -q -F "namespace == .menuBarAgent" $T && grep -q -F "MenuBarItemTag.nonHideableItems.contains(self)" $T && grep -q -F "CaptureIndicatorItems.isIndicator(title: title)" $T && ! grep -n -F 'namespace.isUUID && title == "AudioVideoModule"' $T && grep -q -F 'namespace.isUUID && title == "System Status Item Clone"' $T && grep -q -F 'static let titles: Set<String> = ["AudioVideoModule", "FaceTime"]' holzBar/Core/CaptureIndicatorItems.swift && ! grep -n -E 'static let titles.*Item-' holzBar/Core/CaptureIndicatorItems.swift && grep -q -F 'screenCaptureUI = MenuBarItemTag(namespace: .screenCaptureUI, title: "Item-0")' $T && echo T3-STRUCT-OK</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swiftlint/swiftlint lint --strict --quiet --no-cache   # expect no output, exit 0</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/strings-check.py --root .</automated>
    <automated>! git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution grep -n -i -E "xpc|item service|MenuBarItemService|BlockingWork|LightweightCodeRequirements|holz[ -]?[i]ce" -- holzBar Shared Tests Package.swift   # no output</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && test -z "$(git status --porcelain -- .github Scripts README.md docs SECURITY.md CLAUDE.md holzBar.xcodeproj holzBar/MenuBar/Backends)" && git diff --quiet 1694b9d6 -- .github Scripts README.md docs SECURITY.md CLAUDE.md holzBar.xcodeproj holzBar/MenuBar/Backends && echo SCOPE-OK</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/xpc-attribution && M=/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/f06-probe/head-msg.txt && test "$(git rev-list --count 1694b9d6..HEAD)" = 1 && git log -1 --format=%B > $M && head -1 $M | grep -q -F "fix(services): resolve F-06 — " && grep -q -x -F "Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji" $M && grep -q -x -F "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" $M && test -z "$(git status --porcelain)" && echo COMMIT-OK   # after step 6</automated>
  </verify>
  <done>CaptureIndicatorItems and its 3 tests pass (HolzBarCoreTests 283). `canBeHidden` is false for AudioVideoModule and FaceTime in every namespace, and still false for the menuBarAgent items and the listed tags. There is no rule for the default third-party title. Every gate passes: swift test, appcheck, SwiftLint, privacy, strings, leftovers and scope. Exactly one commit sits on top of 1694b9d6, with the mandated subject and trailers, and the worktree is clean. D-02, D-03 and C-03 are done, and F-06 is resolved.</done>
</task>

</tasks>

## Commit

One commit at the end of Task 3 (C-08). Exact message for `S/f06-probe/commit-msg.txt`:

```
fix(services): resolve F-06 — Apple-signed apps claim item windows first; capture indicators never hide

- The maintainer chose protection plus safe attribution (decision indicators-1, "Schutz plus sichere Zuordnung").
- On macOS 26 the first app whose self-reported Accessibility frame sat within 1 pt of a Control Center item window got it, in running-apps order. A login item could claim the camera and microphone indicator, which then became hideable as "<app>:AudioVideoModule".
- Items titled AudioVideoModule or FaceTime now never hide, whatever app they are attributed to. The default title of third-party status items gets no such rule.
- Apps whose running code satisfies "anchor apple" (read from the code signature once per app, never from a bundle ID) are asked first, and the first of them to claim a window gets it. Any other app gets a window only when a finished scan found no other app claiming it; a contested window belongs to no app.
- New: CodeSignature.isSignedByApple (package target SharedCodeSigning again), SourcePIDClaims and CaptureIndicatorItems, with tests. Adds the attribution PLAN and SUMMARY.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## Gates (summary)

| Gate | Command (absolute paths in the verify blocks) | Pass | Prototype result (`P/tree`) |
|------|------|------|------|
| App type-check | `zsh S/appcheck.sh W <label>` | `ERRORS: 0  EXIT: 0` | 0 errors; the same 2 warnings as the baseline |
| Unit tests | `zsh G/swifttest.sh W <suites>` | `SWIFTTEST OK` | SharedCodeSigning 3, MacOS27 136, HolzBarCore 283 (baseline 273) |
| Lint | pinned `S/swiftlint/swiftlint lint --strict --quiet --no-cache`, `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` | no output, exit 0 | clean (lint covers `holzBar/` only) |
| Privacy | `privacy-check.py network` and `logs` | exit 0 | pass |
| Strings | `strings-check.py --root W` | exit 0 | 369 strings × 5 languages, unchanged |
| Leftovers | `git grep -i -E "xpc|item service|MenuBarItemService|BlockingWork|LightweightCodeRequirements|<former name>"` | no output | empty. `CodeSignature` and `SharedCodeSigning` are no longer in this list: this part re-creates them on purpose |
| Scope | nothing changed under .github, Scripts, README.md, docs, SECURITY.md, CLAUDE.md, holzBar.xcodeproj, holzBar/MenuBar/Backends | `SCOPE-OK` | — |
| Commit | one commit on 1694b9d6, subject and trailers, clean tree | `COMMIT-OK` | — |

CI cannot run from here. Once this branch and the CI chain's workflow changes are in one PR (CI is red
until then, see remove-xpc), the following jobs must pass:
- `test` (xcode-27): runs 3 SharedCodeSigning tests;
- `compat`: macos-14 and macos-15 run 2 (the ad hoc test is skipped there), macos-26 runs 3;
- `build`, `lint`, `no-network`, `strings` and `former-name`.

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Other apps → holzBar through Accessibility | Every app reports its own extras-menu-bar children and their frames; nothing in AX proves ownership of a Control Center-owned window |
| Kernel / Security framework → holzBar | A running process's code signature (`SecCodeCopyGuestWithAttributes` by pid, `anchor apple`) is the only identity holzBar trusts for "Apple" |
| Same-user processes → holzBar's defaults | Any same-user process can write ItemSections or the new-items setting (F-06 step 3) |

## STRIDE Threat Register

IDs continue after the remove-xpc part (T-xpc-01 … T-xpc-07, T-xpc-SC).

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-xpc-07 | Spoofing | Control Center item window claimed through self-reported AX frames (F-06; transferred here by remove-xpc) | medium | mitigate | Task 1 orders Apple-signed apps first; Task 2 makes the first Apple claim final; Task 3 makes AudioVideoModule and FaceTime unhideable in every namespace (tests: SourcePIDClaims "Control Center keeps its indicator…", CaptureIndicatorItems) |
| T-xpc-08 | Spoofing | A process that declares a `com.apple.*` bundle ID or an Apple-like name | medium | mitigate | Apple status comes only from `anchor apple` on the running code (Task 1; grep gate: no prefix or bundle-ID test in CodeSignature or SourcePIDCache) |
| T-xpc-09 | Spoofing | One third-party app claims another third-party app's window | low | mitigate | Contested → no app (Task 2, test "A window two other apps claim belongs to neither") |
| T-xpc-10 | Spoofing | Attacker code run by an Apple-signed host (`osascript -l JavaScript` with the ObjC bridge, the Command Line Tools' python3) creates a status item with crafted AX frames and is ordered inside the Apple group | medium | accept | The title rule keeps AudioVideoModule and FaceTime visible regardless. Residual: screencaptureui's recording item can be claimed when such a host has a known bar and screencaptureui, started on demand, does not yet. Then the attacker also needs a Hidden new-items setting or a defaults write. Follow-up options are in Risks; not part of the decision |
| T-xpc-11 | Spoofing | The Apple owner is skipped (launching, unresponsive, paused) and a non-Apple app is the only claimant in a finished scan | low | accept | The title rule covers the capture indicators. For screencaptureui's recording item the window is short, because it is skipped only while it is launching. A follow-up option is in Risks |
| T-xpc-12 | Tampering | pid reuse between NSRunningApplication and the pid-based signature lookup | low | mitigate | Cached app objects are reused only while not terminated (Task 1), so a new process gets a new check. NSRunningApplication exposes no audit token; the remaining race (exit and pid reuse within the same check) is accepted |
| T-xpc-13 | Denial of service | Signature checks block the first scan | low | mitigate | Once per running app, on the cache's own queue, inside the 2 s budget (Task 1). Measured: 0.13–0.31 s for 81–115 apps, the slowest single check 90 ms (cold) |
| T-xpc-14 | Denial of service | An attacker contests windows (other apps' items, holzBar's own group and spacer items) so that they stay unattributed | low | accept | The items stay where they are (UUID namespace, never auto-placed) and show as "Menu Bar Item". The attacker already runs code as the user |
| T-xpc-15 | Information disclosure | New log output | low | mitigate | Counts only (`.public`); CodeSignature does not log; `privacy-check.py logs` gate |
| T-xpc-SC | Tampering | npm/pip/cargo installs | high | accept | No package is installed. Package.swift only adds a local target pair; `privacy-check.py network` keeps "no package dependencies" enforced |
</threat_model>

<verification>
- Every verify command of Tasks 1, 2 and 3 passes, in task order. The Task 3 commit gate runs after step 6.
- `git -C W show --stat HEAD` lists exactly the eleven paths of `files_modified` (four new source/test
  files plus two new code-signing files, three modified files, PLAN, SUMMARY), and nothing under
  `.github`, `Scripts`, `docs`, `holzBar.xcodeproj` or `holzBar/MenuBar/Backends`.
- `git -C W apply --check` of `P/f06.patch` is no longer needed after the commit; the committed code
  equals `P/tree` except for deviations recorded in the SUMMARY.
- Handed on, not verifiable here: CI (after the CI chain's workflow edits) and live Accessibility
  behaviour on macOS 26 (maintainer).
</verification>

<success_criteria>
- `canBeHidden` never allows AudioVideoModule or FaceTime to hide, in any namespace, and adds no rule for the
  default third-party title.
- On macOS 26 the source-PID scan asks Apple-signed apps (by code signature) first. The first Apple claim
  wins, a non-Apple claim needs an uncontested, finished scan, and a contested window belongs to no app.
- The remove-xpc bounds (queue, timeouts, budget, misses) are unchanged.
- `swift test` passes with SharedCodeSigning 3, MacOS27 136 and HolzBarCore 283 on this host. One commit
  with the mandated format; the SUMMARY carries the doc and CI hand-off and the open questions.
</success_criteria>

## Maintainer verification by hand

The agent's Mac has only the Command Line Tools and cannot grant Accessibility to a test build. Use the
`holzBar-app` artifact of the PR's `build` job, which is signed ad hoc, so macOS asks for Accessibility
again. Or use the next beta, which is signed with the certificate and keeps the permission. The CI chain's
workflow changes must be in the same PR.

1. **macOS 26, Settings → Menu Bar Layout** (D-14). Compare with the current build.
   - Every third-party item still shows its app's name and icon. No new "Menu Bar Item" entries.
   - holzBar's own dividers, item groups and spacers are recognised and in their sections.
   - Wi-Fi, Battery and Clock show Control Center's names ("WiFi"/"Wi-Fi", "Battery", "Clock"), not
     another app's name.
   - Items sit in the sections they were in before.
2. **macOS 26, the camera and microphone indicator.**
   - Set Settings → Advanced → "Place new menu bar items in" to **Hidden**.
   - Start a capture, for example a Photo Booth camera preview or a Voice Memos recording. The indicator
     appears and stays visible: it is not moved into the hidden section, also after a minute and after
     opening the Layout pane.
   - The indicator is not offered in the Layout pane, because non-hideable items are not listed.
   - Stop the capture.
3. **macOS 26, the Screenshot tool's stop button.** With the same Hidden setting, press ⌘⇧5 → Record
   Entire Screen → Record. The stop button appears in the menu bar and stays visible. Stop the
   recording, then set "Place new menu bar items in" back to its previous value.
4. **macOS 26, launch an app with a menu bar item while the Layout pane is open.** The new item appears
   with its app's name after the list refreshes. Quit the app and start it again: the item gets the same
   name.
5. **Optional, macOS 26.** Run `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar"
   AND category == "SourcePIDCache"'`.
   - Scan lines read "… 0 contested, finished: true, in …".
   - The first scan after launch may take up to a few hundred ms longer than before (signature checks,
     once).
   - Any non-zero "contested" count during normal use is a finding to report: it means two apps claim
     the same item.
6. **macOS 27 smoke test.** Launch, open the Layout pane and the Shelf, and conceal and reveal once.
   Nothing should differ: the cache never runs there, and the title rule only affects items titled
   AudioVideoModule or FaceTime outside MenuBarAgent.
7. **Optional, macOS 14 or 15.** Launch and open the Layout pane. Nothing should differ.

## Risks (macOS 26 / 27 and process)

- **Residual route 1: Apple-signed script hosts (T-xpc-10).**
  - `osascript` (JavaScript with the ObjC bridge) and the Command Line Tools' `python3` are signed by
    Apple. Code they run can create a status item and set its accessibility frame.
  - Such a host is ordered inside the Apple group, and the first Apple claim wins.
  - The capture indicators stay protected by the title rule. screencaptureui's recording item does not,
    if the host already has a known bar and screencaptureui (started on demand) does not.
  - Follow-up options for the maintainer, not part of this decision:
    - (a) treat a window that two Apple-signed apps claim as contested too. This needs a full scan for
      every pending window, since there is no early stop;
    - (b) count as "Apple" only processes that are Apple-signed and have a bundle identifier
      (`osascript` and `python3` run unbundled);
    - (c) combine either with F-44's namespace hardening.
- **Residual route 2: a skipped Apple owner (T-xpc-11).**
  - If the owning Apple app is launching, unresponsive or paused, a sole non-Apple claim in a finished
    scan wins.
  - Follow-up option: accept non-Apple claims only from scans in which no Apple-signed app was skipped.
    The cost is a delay in naming new third-party items while any Apple app is unresponsive.
- **macOS 26 regression risk: an Apple process claims a third-party window.**
  - This would happen if some Apple process exposed enabled extras-menu-bar children at third-party
    items' positions; the item would then show that Apple process's name.
  - The old order already put Control Center among the first apps, and attribution was correct on
    26.7.1, so this is unlikely.
  - Maintainer step 1 checks it.
- **macOS 26: more items may stay unattributed for one read.**
  - A non-Apple claim from a scan that ran out of its 2 s budget or was cancelled is no longer accepted
    (C-01). The item keeps a UUID namespace until the next read finishes a scan.
  - A scan with any third-party window pending now always asks every app, because a non-Apple claim no
    longer ends the search.
  - Measured cost: one extras-bar query per app without a known bar. Cancelled refreshes (F-56) delay
    third-party naming to the next complete read.
- **macOS 26: contested items.**
  - They show as "Menu Bar Item", are never auto-placed, and their apps are skipped by the spacing
    relaunch (F-101, separate finding).
  - In normal use there should be none (maintainer step 5).
- **macOS 26: signature check cost.**
  - The first scan after launch pays 0.1–0.3 s once (measured on 26.7.1), inside the budget.
  - An app whose binary was replaced on disk while it runs (an update) fails the check and counts as
    not Apple. Only Apple's own apps are affected this way, and only until they relaunch.
- **All macOS versions: the title rule.**
  - A third-party item whose title is exactly "AudioVideoModule" or "FaceTime" can no longer be hidden or
    concealed (also on macOS 27 in Concealer27). Such an app can only keep itself visible; it cannot
    hide anything else.
  - The decision accepted this ("no downside"). It is the same class as F-70.
- **macOS 27 and 14/15:** no attribution change. `ServiceBackend26` is the only creator of the cache, and
  `CodeSignature` only compiles there. CI's xcode-27, macos-14 and macos-15 legs cover compilation and
  tests.
- **CI:**
  - The ad hoc copy test is skipped before macOS 26 (C-05).
  - It relies on `/usr/bin/codesign` and `/bin/sleep`, both present on every runner.
  - CI stays red until the CI chain lands (remove-xpc).
- **Merges with other chains:**
  - Other `audit-manual/*` branches still contain the old `Shared/CodeSigning/CodeSignature.swift` and its
    tests unchanged from the base. This branch's new content wins without conflict.
  - Nothing here touches `ServiceBackend26.swift` (edited by ax-observers and appearance-split) or
    `holzBar.xcodeproj`.
  - The F-08 chain (mac27-agents-dot) may add capture-related Core types: check for name clashes with
    `CaptureIndicatorItems` at merge time.
  - F-44, when decided, should reuse `CodeSignature.isSignedByApple`.

## doc_updates_needed

The executor copies this section into the SUMMARY. The remove-xpc items (CI and F-49 docs) are still open
as well.

1. `SECURITY.md`, threat register: add a row "macOS 26: another app's Accessibility frames claim a Control
   Center item window and make the camera and microphone indicator hideable", Medium, Mitigate.
   - Status: **Mitigated** from the next beta.
   - How: the camera, microphone and FaceTime indicators can never be hidden, whatever app they are
     attributed to. Apps whose code is signed by Apple are asked first. A window two other apps claim
     belongs to none.
   - Residual: code run by Apple-signed script hosts.
   - In "What holzBar promises", nothing changes. Optionally note under "Least privilege" that reading
     other apps' code signatures needs no permission.
2. `docs/privacy-and-permissions.md`, after the permissions table: one sentence for transparency. On
   macOS 26 holzBar reads the code signatures of running apps on the Mac to tell macOS's own processes
   from other apps when it works out which app a menu bar item belongs to. This needs no permission, and
   nothing leaves the Mac.
3. `docs/features.md`: in the items or sections part, say that the camera and microphone indicator, the
   FaceTime item and the Screenshot tool's recording item can be moved but are never hidden.
4. Next beta's release notes (`docs/release-notes/v<next>.md`):
   - Security (macOS 26): another app can no longer make the camera and microphone indicator hideable by
     claiming its menu bar item. holzBar asks Apple's own processes first, checked by their code
     signature. These indicators never hide.
   - Changed (macOS 26): a menu bar item that two apps claim is listed as "Menu Bar Item" and is never
     moved automatically.
5. README comparison table (and https://holzcloud.ch/holzbar): optionally add a row such as "Privacy
   indicators can't be hidden by another app (macOS 26)", only after the maintainer's step 2 and 3 pass.
6. `.planning/codebase/*`: on the next `/gsd-map-codebase`, record `Shared/CodeSigning` (Apple check),
   `SourcePIDClaims` and `CaptureIndicatorItems`.

<output>
Create `.planning/audit/remediation/xpc-attribution-SUMMARY.md` (Task 3, step 5) and commit it with the fix
(Task 3, step 6).
</output>
