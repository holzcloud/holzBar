---
phase: 02-bug-fixes
plan: 03
subsystem: xpc-menu-bar-item-service
status: complete
tags: [bug-fix, xpc, code-signing, ad-hoc, macos26, least-privilege, swift-testing]
requires:
  - "02-01: test-only Package.swift layout, draft PR #35"
  - "02-02: complete (wave order)"
provides:
  - "Shared/CodeSigning/CodeSignature.swift: currentTeamIdentifier, currentCodeURL(), signingIdentifier(ofCodeAt:), codeDirectoryHashes(ofCodeAt:) (Security only)"
  - "SharedCodeSigning / SharedCodeSigningTests targets in the test-only package (suite \"CodeSignature\", 6 tests)"
  - "MenuBarItemService.appIdentifier = \"com.holzcloud.holzBar\""
  - "Listener peer requirement: same team plus identifier, or (ad hoc) the signing identifier plus the embedding app's code directory hashes; fail closed"
affects:
  - "Phase 3 (docs/upstream-bugs.md report counts)"
  - "Any future team signing: only the branch taken in peerRequirement() / getOrCreateSession() changes"
tech-stack:
  added: []
  patterns:
    - "LightweightCodeRequirements (macOS 14.4+) only in the service, which runs only on macOS 26; the app and Shared/ use Security only"
    - "A running process is checked through SecCodeCopyGuestWithAttributes with its audit token, the way XPC checks a peer"
key-files:
  created:
    - Shared/CodeSigning/CodeSignature.swift
    - Tests/SharedCodeSigningTests/CodeSignatureTests.swift
  modified:
    - Package.swift
    - MenuBarItemService/Listener.swift
    - holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift
    - Shared/Services/MenuBarItemService.swift
    - docs/upstream-bugs.md
decisions:
  - "Ad hoc builds: the XPC listener requires SigningIdentifier(com.holzcloud.holzBar) and CodeDirectoryHash.in(hashes of the embedding app), so exactly that app's code is accepted (D-02); team builds require the same team plus the identifier"
  - "The listener does not listen when the requirement cannot be built (wrong host bundle, invalid signature, no hashes); the app's in-app lookup takes over (fail closed)"
  - "The app sets its same-team peer requirement only when it has a team; on ad hoc builds launchd already resolves the service only inside the app's own bundle"
  - "codeDirectoryHashes(ofCodeAt:) validates every architecture slice (kSecCSCheckAllArchitectures) before it returns hashes"
metrics:
  duration: 20min
  completed: 2026-10-02
  tasks: 2
  files: 7
estimate:
  tokens: 65000
  tasks: 2
actuals:
  tokens: 5950
  tasks: 2
  commits: 4
plan_head_before: 25e5a8eace0a47b35d5e49ac78f2502b179bcd3e
plan_head_after: 32b5ccdcee9e89ffd2393ab4656ee2cf438f2e0b
---

# Phase 2 Plan 03: XPC peer requirement for ad hoc builds Summary

On macOS 26 the menu bar item service now accepts holzBar's ad hoc builds and still rejects everything else. A build without a team identifier makes the listener require holzBar's signing identifier and one of the code directory hashes (cdhashes) of the app bundle the service is embedded in. A team-signed build requires the same team and the identifier. If the service cannot build its requirement, it does not listen at all. The hashes come from the new `Shared/CodeSigning/CodeSignature.swift`, which uses Security only, so the app still launches on macOS 14.0. The new `CodeSignature` Swift Testing suite proves on the CI runner that these hashes match a running process.

## Phase PR

holzcloud/holzBar#35 (still a draft). Its body now lists BUG-06, plus the BUG-05/BUG-07 work from 02-02 that the body was missing. Head after this plan: `32b5ccd` (the docs commit for this SUMMARY comes after it).

## Why the cdhash requirement (D-02)

Code signed ad hoc has no team identifier, so `isFromSameTeam()` has nothing to compare. For such code, Apple's implicit designated requirement is its code directory hash. Requiring holzBar's signing identifier plus the cdhashes of the embedding app (a list, because each architecture slice has its own code directory) accepts exactly the code of that app. Every other process is rejected, including other ad hoc code that claims `com.holzcloud.holzBar`. This is the safest option that works with ad hoc signing. No entitlement or permission was added (least privilege), and the new log line names only the kind of requirement and the number of hashes (private).

## Tasks

| Task | Name | Commits |
|------|------|---------|
| 1 | Read the code directory hashes that pin a process, proven on the CI runner | `6fb70fd`, `1dc2ed0` |
| 2 | The service accepts holzBar's ad hoc build and still rejects everything else | `e83fa77`, `32b5ccd` |

## What changed

- `Shared/CodeSigning/CodeSignature.swift` (new, Foundation and Security only) adds:
  - `Failure` (the Security call that failed and its `OSStatus`)
  - `currentTeamIdentifier` (read once)
  - `currentCodeURL()`
  - `signingIdentifier(ofCodeAt:)`
  - `codeDirectoryHashes(ofCodeAt:)`. It checks the signature on every slice, then collects `kSecCodeInfoUnique` and `kSecCodeInfoCdHashes` from the default slice and from arm64, arm64e and x86_64. A slice the binary lacks is skipped. Duplicates are removed, and it throws when no hash is found.
- `Package.swift` gains the targets `SharedCodeSigning` (`path: "Shared/CodeSigning"`) and `SharedCodeSigningTests`. Every existing target stays.
- `MenuBarItemService/Listener.swift` imports LightweightCodeRequirements (the only file that does) and adds:
  - `uncheckedActivate(requirement:)`
  - `peerRequirement()`, which uses the team branch or the ad hoc branch with the host-bundle identifier check and the hashes
  - `activate()` logging which requirement is in force; any error leaves the listener inactive
- `MenuBarItemServiceConnection.swift`: `.isFromSameTeam(andMatchesSigningIdentifier: MenuBarItemService.name)` only when `CodeSignature.currentTeamIdentifier != nil`. Otherwise no requirement is set, and a comment explains why.
- `Shared/Services/MenuBarItemService.swift`: `static let appIdentifier = "com.holzcloud.holzBar"`. The `static let name` line is unchanged, so the build's "Check the identifiers" step still reads it.
- `docs/upstream-bugs.md`: the macOS 26 "Loading menu bar items…" row's Fix cell records the ad hoc acceptance. Nothing else in the file changed.

## Tests that ran (CI, suite "CodeSignature")

All passed on `1dc2ed0`, `e83fa77` and `32b5ccd` (`Test run with 137 tests in 25 suites passed`):

- The hashes of this process's code are distinct 20-byte hashes
- This process's code has a signing identifier
- A requirement on identifier and hashes matches this process (macOS 15+)
- Another signing identifier does not match (macOS 15+)
- Another program's hashes do not match (`/usr/bin/true`; also checks that the two hash sets are disjoint) (macOS 15+)
- Code that does not exist has no hashes

The test process is `swiftpm-testing-helper`, with identifier `swiftpm-testing-helper-<hash>`. Identifiers of that form are what the linker gives code it signs ad hoc, so this is probably the same signing kind as holzBar's builds. `CodeSignature` read **2 hashes** for it (from the first, failing run's log).

## TDD Gate Compliance

As the plan's Task 1 step 4 prescribes, the test and the implementation went into one commit (`6fb70fd`). There was no separate RED commit with a missing implementation. That commit failed CI, but in the test's harness, not in `CodeSignature` (see below). The fix (`1dc2ed0`) changed only the test's way of getting the running process's code and made the suite green. No test was loosened, skipped or deleted.

## CI fixes needed

1. **`SecCodeCopySelf` cannot be used with `SecCodeCheckValidityWithProcessRequirement`** (found in Task 1's first CI run, `6fb70fd`). The call returned `ValidationResult(signatureIsValid: false, requirementMatched: false, failureReason: -50)`, which is errSecParam. The test now looks up its own process with `SecCodeCopyGuestWithAttributes` and its audit token (`task_info(TASK_AUDIT_TOKEN)`), the way XPC identifies a peer. Then the requirement matched. On failure, the expectation comments now also log the compared hashes in hex, the running process's cdhash (`kSecCSDynamicInformation`) and `SecTaskValidateForRequirement`'s verdict. `CodeSignature.swift` itself needed no change.
2. Commit `32b5ccd` reworded a comment in `MenuBarItemServiceConnection.swift` so that the phase verification `git grep LightweightCodeRequirements -- holzBar Shared MenuBarItemService` lists only `MenuBarItemService/Listener.swift`. The Task 2 action had asked for a comment naming the module there.

There were no compiler warnings in the changed files. The build reported 9 warnings, all of them already present in other files.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test validated the process through a SecCode that the lightweight check rejects with errSecParam**
- **Found during:** Task 1 (first CI run)
- **Fix:** the process is now looked up by its audit token, and the failure comment carries more detail
- **Files modified:** Tests/SharedCodeSigningTests/CodeSignatureTests.swift
- **Commit:** 1dc2ed0

**2. [Rule 1 - Consistency] Comment in the app named the framework, which conflicts with the plan's own verification grep**
- **Found during:** Task 2 verification
- **Fix:** the comment now says "the framework for lightweight code requirements"
- **Files modified:** holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift
- **Commit:** 32b5ccd

**3. [Addition] `codeDirectoryHashes(ofCodeAt:)` validates with `kSecCSCheckAllArchitectures`**
- Without this flag, the default check covers only one slice, while hashes are collected from all slices. Now every pinned hash belongs to a slice that was validated.

The former-name rule (added after planning) was respected: the former name does not appear in any changed file outside `.planning/`. The `former-name` job passed on every head.

## Open human checks

On the Mac (macOS 26.7.1), with holzBar built by CI or `Scripts/install.sh` (ad hoc; `codesign -dv` shows `TeamIdentifier=not set`):

1. Run `log stream --level info --predicate 'process == "MenuBarItemService" OR subsystem BEGINSWITH "com.holzcloud.holzBar"'`.
2. Launch holzBar and open Settings, Menu Bar Layout.

Expected:
- The service logs "Listener requires the app's exact code (N code directory hashes)" with N ≥ 1.
- The layout shows the menu bar items instead of "Loading menu bar items…".
- No "looking up source processes in the app instead" line appears.

## Known Stubs

None.

## Threat Flags

None beyond the plan's threat model (T-02-07 to T-02-10 mitigated or accepted as planned; T-02-SC: only local targets were added, with no package dependency).

## Self-Check: PASSED

- FOUND: Shared/CodeSigning/CodeSignature.swift, Tests/SharedCodeSigningTests/CodeSignatureTests.swift
- FOUND commits: 6fb70fd, 1dc2ed0, e83fa77, 32b5ccd (on origin/claude/ice-fork-development-hzdl1d)
- PR #35 head = 32b5ccd: build, test, swiftlint and former-name passed. Logs show `BUILD SUCCEEDED`, `Test run with 137 tests in 25 suites passed`, `Suite "CodeSignature" passed` and `Done linting! Found 0 violations`.
