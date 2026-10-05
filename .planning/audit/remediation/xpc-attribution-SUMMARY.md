---
chain: xpc
part: attribution
findings: [F-06]
decisions:
  - "indicators-1 — Schutz plus sichere Zuordnung (Recommended)"
status: complete
plan: .planning/audit/remediation/xpc-attribution-PLAN.md
subsystem: menu-bar-items (macOS 26 source-PID attribution)
tags: [security, macos26, accessibility, code-signing]
requires: [xpc/remove-xpc]
provides:
  - CodeSignature.isSignedByApple(processIdentifier:)
  - SourcePIDClaims (pure claim decision)
  - CaptureIndicatorItems (namespace-independent title rule)
key-files:
  created:
    - Shared/CodeSigning/CodeSignature.swift
    - Tests/SharedCodeSigningTests/CodeSignatureTests.swift
    - holzBar/Core/SourcePIDClaims.swift
    - Tests/HolzBarCoreTests/SourcePIDClaimsTests.swift
    - holzBar/Core/CaptureIndicatorItems.swift
    - Tests/HolzBarCoreTests/CaptureIndicatorItemsTests.swift
    - .planning/audit/remediation/xpc-attribution-SUMMARY.md
  modified:
    - Package.swift
    - Shared/Services/SourcePIDCache.swift
    - holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift
    - .planning/audit/remediation/xpc-attribution-PLAN.md (added; written by the planner)
actuals:
  tokens: 9000        # chars/4 over the code diff (23 kB) plus this SUMMARY
  tasks: 3
  commits: 1          # measured: git rev-list --count 1694b9d6..HEAD after the commit that carries this file
plan_head_before: 1694b9d6777bb950d4b0db57e1675cf591dc34d3
plan_head_after: "the commit that adds this file (fix(services): resolve F-06 …)"
---

# xpc / attribution: Apple-signed apps claim item windows first, contested windows go to no app, and the capture indicators never hide

The maintainer chose protection plus safe attribution ("Schutz plus sichere Zuordnung",
decision indicators-1). Both parts are implemented on top of the in-app source-PID lookup
that the remove-xpc part created (the XPC service no longer exists):

1. **Title rule.** Items titled `AudioVideoModule` (camera, microphone, screen capture) or
   `FaceTime` can never be hidden, whatever app they are attributed to. The default title
   of third-party status items gets no such rule.
2. **Attribution.** On macOS 26 the source-PID scan asks apps whose running code satisfies
   `anchor apple` first (read from the code signature once per running app). The first
   Apple-signed claim gets the window. Any other app gets a window only when a finished scan
   found no other app claiming it; a window two such apps claim belongs to no app.

**On the relayed question ("Können wir das mit dem signieren nicht doch anders lösen?").**
This part needs no signing of holzBar: no Developer ID, no notarization, no certificate,
and no change to how releases are signed. It only *reads* the signature that Apple put on
macOS's own processes, such as Control Center and screencaptureui. Every Mac has those
signatures, and ad hoc builds, CI artifacts and the certificate-signed cask behave the same.
The only "signing" anywhere in this part is an ad hoc signature on a temporary copy of
`/bin/sleep` inside one unit test, used as a non-Apple example; it needs no key.
Signature-free ways to recognise Apple's processes were weighed: a `com.apple.` bundle-ID
prefix can be declared by any app (F-44), so the decision rules it out; the executable path
on the sealed system volume would miss Apple's apps outside `/System` and is not what the
maintainer chose. The check is cheap: 0.13–0.31 s once for all 81–115 running apps on
macOS 26.7.1.

## Commits

| # | Hash | Subject |
|---|------|---------|
| 1 | (this commit) | fix(services): resolve F-06 — Apple-signed apps claim item windows first; capture indicators never hide |

## F-06: what changed

### Part 1 — the capture indicators never hide

- New `holzBar/Core/CaptureIndicatorItems.swift`: `nonisolated enum CaptureIndicatorItems`
  with `titles = ["AudioVideoModule", "FaceTime"]` and `isIndicator(title:)` (exact match).
- `MenuBarItemTag.canBeHidden` returns `false` when `CaptureIndicatorItems.isIndicator(title:)`
  is true, in every namespace. The macOS 27 menuBarAgent rule and `nonHideableItems`
  (AudioVideoModule, FaceTime, screencaptureui's Item-0, MusicRecognition before 15.3.2) are
  unchanged. The former UUID-only AudioVideoModule clause is replaced, because the new rule
  covers it.
- `canBeHidden` is read by `isValidForCaching` (MenuBarItemManager), the SectionRestore
  candidate filter and Concealer27, so a misattributed `<app>:AudioVideoModule` is never
  moved into Hidden, by a saved ItemSections entry or by "Place new menu bar items in: Hidden".
- Tests: `CaptureIndicatorItemsTests` (3): both titles are indicators; `Item-0` is not;
  titles compare exactly.

### Part 2 — Apple-signed apps first, contested windows to no app

- New `Shared/CodeSigning/CodeSignature.swift`: `nonisolated enum CodeSignature` with
  `isSignedByApple(processIdentifier:)`: `SecCodeCopyGuestWithAttributes` with
  `kSecGuestAttributePid`, `SecRequirementCreateWithString("anchor apple")`,
  `SecCodeCheckValidity`. Any failure returns `false`. No logging, no bundle-ID or name
  comparison, no LightweightCodeRequirements, no cdhash pinning or peer check.
- `Package.swift`: the targets `SharedCodeSigning` (path `Shared/CodeSigning`, `appCore`) and
  `SharedCodeSigningTests` are back, with new content; header comment updated.
- `SourcePIDCache`:
  - `CachedApplication.isSignedByApple` is a `private(set) lazy var`: read once per running
    app, on the cache's queue.
  - `runningApplicationsDidChange()` reuses only cached apps that are not terminated, so a
    reused pid gets a new `CachedApplication` and a fresh signature check.
  - `partitionApps()` orders five groups, stable inside each: Apple with a known bar, Apple
    without, others with a bar, others without, then terminated or `.prohibited` apps
    (which get no signature check). It still runs after the scan's start time, so the first
    scan's signature checks count toward the 2 s budget.
  - `Scan.found` is replaced by `Scan.claims: [CGWindowID: SourcePIDClaims]` and
    `Scan.decision(for:)`. Every enabled child at a window's centre adds a
    `Claim(pid:isSignedByApple:)`; a window leaves `remaining` only when its claims are
    settled (an Apple claim). A non-Apple claim keeps the scan asking.
  - `pids(for:)` caches only `.owner` decisions. `.contested` and `.unresolved` record a miss
    only after a finished scan.
  - The per-scan debug line now also counts contested windows (all `.public` counts).
  - Unchanged: `stableCenters`, budget and cancellation checks, `timed`, the schedule,
    `failedLookups`, `shouldRescan`, `start()`, `ServiceBackend26`.
- New `holzBar/Core/SourcePIDClaims.swift`: pure, `nonisolated`. `decision(scanFinished:)`
  returns `.owner` of the first Apple-signed claim (also from an unfinished scan); else two or
  more distinct pids give `.contested`; one pid gives `.owner` only after a finished scan,
  else `.unresolved`; none gives `.unresolved`. `isSettled` is true once any claim is
  Apple-signed.
- Tests: `SourcePIDClaimsTests` (7) and `CodeSignatureTests` (3): a spawned `/bin/sleep` is
  Apple-signed; an ad hoc re-signed copy of it (proven running with `kill(pid, 0)`) is not
  (macOS 26+); an exited process is not. The test process itself is never used.

## How the failure scenario is closed

- **Step 2 (a login item claims the AudioVideoModule window) fails.** Control Center is
  Apple-signed, so it is in the first group of every scan; its claim settles the window, and
  later non-Apple claims cannot change it.
- **Step 3 (the indicator is moved into Hidden) fails even if step 2 succeeded**, for example
  if Control Center was skipped as unresponsive: `canBeHidden` is false for the title in every
  namespace.
- **Other Apple items** (screencaptureui's recording stop button, Wi-Fi, Battery, Clock) are
  protected by the order: the Apple group, including on-demand screencaptureui without a known
  bar, comes before every third-party app.
- **Third-party items**: one app can no longer steal another's window; a contested window
  gets a UUID namespace, which SectionRestore never places.
- **Spoofed identity**: Apple status comes only from the code signature; a process declaring
  `com.apple.*` stays in the non-Apple groups.

## Design choices

- **C-01** A non-Apple claim is accepted only after a finished scan; an unfinished scan leaves
  the window pending (no cache, no miss, retried at the next read).
- **C-02** A contested window records a miss after a finished scan, like an unclaimed window.
- **C-03** The titles live in the pure, tested `CaptureIndicatorItems`; the UUID-only
  AudioVideoModule clause is removed as covered; `nonHideableItems` unchanged.
- **C-04** `SharedCodeSigning` uses `appCore` (main actor default isolation), matching how the
  app compiles `Shared/`.
- **C-05** The ad hoc copy test is `@available(macOS 26.0, *)`; the other two run everywhere.
- **C-06** Terminated and `.prohibited` apps are sorted last without a signature check; cached
  app objects are reused only while not terminated.
- **C-07** The per-scan debug line reports the contested count.
- **C-08** One commit for F-06, carrying the PLAN and this SUMMARY.
- **D-11** (one frame index per scan) is already met by remove-xpc's batch scan: one map of
  window centres per scan, shared by all pending windows. No extra index.

## Deviations from the plan

None. The committed code is byte-identical to the prototype `f06-probe/tree` for all nine
code and test files. The TDD RED steps were observed for all three tasks (the package failed
with "invalid custom path 'Shared/CodeSigning'", then "cannot find type 'SourcePIDClaims'",
then a build failure for `CaptureIndicatorItems`) and not committed, as the plan says.

## Gates

| Gate | Result |
|------|--------|
| `appcheck.sh` (Swift 6, macOS 26.5 SDK), after each task | `ERRORS: 0  EXIT: 0` (f06-t1, f06-t2, f06-t3); the same 2 deprecation warnings as the baseline (`ScreenCapture.swift:86`) |
| `servicecheck.sh` | not applicable: `MenuBarItemService/` does not exist |
| `swift test` (full run, via `swifttest.sh`) | SharedCodeSigning 3, HolzBarMacOS27Core 136, HolzBarCore 283 tests passed (baseline 273). Retried only the known "TestingMacros plugin not found" flake |
| SwiftLint (pinned, `--strict --quiet --no-cache`) | no output, exit 0 |
| `privacy-check.py network` / `logs` | pass / pass |
| `strings-check.py` | 369 strings in 5 languages (unchanged; no new user-facing strings) |
| Former name check | no matches |
| Leftovers (`xpc`, `MenuBarItemService`, `BlockingWork`, `LightweightCodeRequirements`, …) in holzBar, Shared, Tests, Package.swift | no matches |
| Scope (.github, Scripts, README, docs, SECURITY.md, CLAUDE.md, xcodeproj, MenuBar/Backends) | unchanged (`SCOPE-OK`) |
| Structure greps T1/T2/T3 | `T1-STRUCT-OK`, `T2-STRUCT-OK`, `T3-STRUCT-OK` |

Not runnable here: CI (after the CI chain's workflow changes; `test` on xcode-27 runs 3
SharedCodeSigning tests, `compat` macos-14/15 run 2, macos-26 runs 3) and live Accessibility
behaviour on macOS 26.

## doc_updates_needed

The remove-xpc items (CI and F-49 docs) are still open as well.

1. `SECURITY.md`, threat register: add a row "macOS 26: another app's Accessibility frames
   claim a Control Center item window and make the camera and microphone indicator hideable",
   Medium, Mitigate. Status: **Mitigated** from the next beta. How: the camera, microphone and
   FaceTime indicators can never be hidden, whatever app they are attributed to; apps whose
   code is signed by Apple are asked first; a window two other apps claim belongs to none.
   Residual: code run by Apple-signed script hosts. Optionally note under "Least privilege"
   that reading other apps' code signatures needs no permission.
2. `docs/privacy-and-permissions.md`, after the permissions table: on macOS 26 holzBar reads
   the code signatures of running apps on the Mac to tell macOS's own processes from other
   apps when it works out which app a menu bar item belongs to. This needs no permission, and
   nothing leaves the Mac.
3. `docs/features.md`: the camera and microphone indicator, the FaceTime item and the
   Screenshot tool's recording item can be moved but are never hidden.
4. Next beta's release notes: Security (macOS 26): another app can no longer make the camera
   and microphone indicator hideable by claiming its menu bar item; holzBar asks Apple's own
   processes first, checked by their code signature; these indicators never hide. Changed
   (macOS 26): a menu bar item that two apps claim is listed as "Menu Bar Item" and is never
   moved automatically.
5. README comparison table (and https://holzcloud.ch/holzbar): optionally a row such as
   "Privacy indicators can't be hidden by another app (macOS 26)", only after maintainer steps
   2 and 3 pass.
6. `.planning/codebase/*`: on the next `/gsd-map-codebase`, record `Shared/CodeSigning` (Apple
   check), `SourcePIDClaims` and `CaptureIndicatorItems`.

## Maintainer verification

Use the PR's `build` artifact (ad hoc signed, so macOS asks for Accessibility again) or the
next beta. The CI chain's workflow changes must be in the same PR.

1. **macOS 26, Settings → Menu Bar Layout.** Compare with the current build: every third-party
   item still shows its app's name and icon (no new "Menu Bar Item" entries); holzBar's
   dividers, groups and spacers are recognised and in their sections; Wi-Fi, Battery and Clock
   show Control Center's names; items sit in the sections they were in before.
2. **macOS 26, camera and microphone indicator.** Set Settings → Advanced → "Place new menu bar
   items in" to Hidden. Start a capture (Photo Booth preview or a Voice Memos recording). The
   indicator stays visible, also after a minute and after opening the Layout pane. Stop it.
3. **macOS 26, Screenshot stop button.** With the same setting, ⌘⇧5 → Record Entire Screen →
   Record. The stop button stays visible. Stop, then restore "Place new menu bar items in".
4. **macOS 26, new app while the Layout pane is open.** Launch an app with a menu bar item: it
   appears with its app's name; quit and relaunch: same name.
5. **Optional, macOS 26:** `log stream --level debug --predicate 'subsystem ==
   "com.holzcloud.holzBar" AND category == "SourcePIDCache"'`. Scan lines read "… 0
   contested, finished: true, in …"; the first scan after launch may take a few hundred ms
   longer (signature checks, once). A non-zero contested count in normal use is worth reporting.
6. **macOS 27 smoke test:** launch, open the Layout pane and the Shelf, conceal and reveal once.
   Nothing should differ.
7. **Optional, macOS 14 or 15:** launch and open the Layout pane. Nothing should differ.

## Risks

- **Residual route 1: Apple-signed script hosts.** `osascript` (JavaScript with the ObjC bridge)
  and the Command Line Tools' `python3` are Apple-signed; code they run can create a status item
  with crafted AX frames and is ordered in the Apple group. The capture indicators stay protected
  by the title rule; screencaptureui's recording item does not, if the host already has a known
  bar and screencaptureui does not yet.
- **Residual route 2: a skipped Apple owner.** If the owning Apple app is launching, unresponsive
  or paused, a sole non-Apple claim in a finished scan wins. The title rule still covers the
  capture indicators.
- **Regression risk (macOS 26): an Apple process claims a third-party window** if it exposed
  enabled extras-menu-bar children at third-party positions. Unlikely (Control Center was
  already among the first apps asked); maintainer step 1 checks it.
- **More items may stay unattributed for one read**: non-Apple claims from an unfinished scan
  are not accepted, and a scan with a third-party window pending now asks every app.
- **Contested items** show as "Menu Bar Item", are never auto-placed, and are skipped by the
  spacing relaunch (F-101, separate finding).
- **Signature check cost:** 0.1–0.3 s once after launch, inside the budget. An Apple app whose
  binary was replaced while it runs fails the check until it relaunches.
- **Title rule on all versions:** a third-party item titled exactly "AudioVideoModule" or
  "FaceTime" can no longer be hidden or concealed (also in Concealer27); it can only keep itself
  visible (same class as F-70).
- **Merges:** other `audit-manual/*` branches still carry the old `Shared/CodeSigning` files from
  the base; this branch's content wins. Nothing here touches `ServiceBackend26.swift` or the
  Xcode project. Check `CaptureIndicatorItems` for name clashes with the F-08 chain at merge time.

## Open questions for the maintainer

1. **Apple-signed script hosts (route 1).** Options, not part of this decision:
   (a) treat a window that two Apple-signed apps claim as contested too (needs a full scan for
   every pending window, no early stop); (b) count as "Apple" only processes that are
   Apple-signed **and** have a bundle identifier (`osascript` and `python3` run unbundled);
   (c) combine either with F-44's namespace hardening.
2. **Skipped Apple owner (route 2).** Option: accept non-Apple claims only from scans in which
   no Apple-signed app was skipped; the cost is slower naming of new third-party items while any
   Apple app is unresponsive.
3. **F-44** (namespace spoofing), when decided, can reuse `CodeSignature.isSignedByApple`.

## Self-Check: PASSED

All six created files exist; the nine code and test files equal the prototype; every gate above passed before the commit.
