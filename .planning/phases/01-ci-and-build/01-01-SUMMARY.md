---
phase: 01-ci-and-build
plan: 01
subsystem: infra
tags: [github-actions, xcode, swift-test, swift-testing, ci]

requires: []
provides:
  - "Local composite action .github/actions/select-xcode: exact Xcode pin (default 26.6), the single source of the CI Xcode version"
  - "build.yml: build and test jobs on every pull request, actions/checkout@v7, contents: read"
  - "test job running swift test (Tests/IceMacOS27CoreTests)"
  - "build log section '==> N compiler warnings' with the deduplicated warnings"
  - "Draft phase PR #30 (claude/ice-fork-development-hzdl1d -> main)"
affects: [01-02, 01-03, release.yml, README]

actuals:
  tokens: 700
  tasks: 2
  commits: 4
plan_head_before: 2389824d37483157e9d91edffc2497d4f8afe77a
plan_head_after: dcdba1e313676eeea10a1b700a49d44d32402f17

tech-stack:
  added: [actions/checkout@v7]
  patterns:
    - "Toolchain selection lives in one local composite action; workflows call `uses: ./.github/actions/select-xcode`"
    - "Run blocks read inputs only through step env vars, never through expression syntax"

key-files:
  created:
    - .github/actions/select-xcode/action.yml
  modified:
    - .github/workflows/build.yml

key-decisions:
  - "CI pins Xcode 26.6 exactly (the newest Xcode on the macos-26 image; there is no Xcode 27 there) and fails loudly instead of falling back"
  - "build.yml runs on every pull request (no paths filter), so docs-only PRs also prove the app builds"
  - "xcodebuild -version is read in full and split in bash: piping it into head crashes xcodebuild with a broken pipe"

patterns-established:
  - "Verify CI work by pushing claude/ice-fork-development-hzdl1d and reading the check runs of PR #30 through gh api"

requirements-completed: [CI-01, CI-03, CI-04, CI-05]

coverage:
  - id: D1
    description: "Both macOS jobs select exactly Xcode 26.6 through select-xcode; a missing Xcode fails with an ::error::"
    requirement: CI-05
    verification:
      - kind: integration
        ref: "build/test check runs on dcdba1e: log shows 'Xcode 26.6' / 'Build version 17F113'"
        status: pass
      - kind: other
        ref: "Task 1 verify: the action's run script, executed on Linux, exits 1 with '::error::Xcode 26.6 is not installed on this runner'"
        status: pass
    human_judgment: false
  - id: D2
    description: "test job runs swift test on every pull request"
    requirement: CI-03
    verification:
      - kind: unit
        ref: "test check run 110794178497 (ffd3b1d) and the test run on dcdba1e: 'Test run with 114 tests in 22 suites passed'"
        status: pass
    human_judgment: false
  - id: D3
    description: "build log lists the deduplicated compiler warnings under '==> N compiler warnings'"
    requirement: CI-04
    verification:
      - kind: integration
        ref: "build check run on dcdba1e: '==> 9 compiler warnings' followed by the list"
        status: pass
    human_judgment: false
  - id: D4
    description: "build.yml uses actions/checkout@v7; its check runs carry no deprecation annotation"
    requirement: CI-01
    verification:
      - kind: integration
        ref: "Task 2 verify: annotations of build and test on dcdba1e contain no 'deprecat'"
        status: pass
    human_judgment: false

duration: 20min
completed: 2026-10-02
status: complete
---

# Phase 1 Plan 01: Pinned Xcode, swift test and compiler warnings in CI Summary

**Every pull request now builds the app and runs the 114 Core unit tests on macos-26 with Xcode 26.6 selected by exact version through a local composite action. The build log lists the 9 compiler warnings, and build.yml is on actions/checkout@v7 (Node 24).**

## Performance

- **Duration:** about 20 min
- **Started:** 2026-10-02T10:00:46Z
- **Completed:** 2026-10-02T10:20:00Z
- **Tasks:** 2/2
- **Files modified:** 2 (1 created, 1 edited)

## Accomplishments

- Phase PR: **#30**, https://github.com/holzcloud/holzIce/pull/30 (draft, base `main`, head `claude/ice-fork-development-hzdl1d`). The body lists what has landed so far.
- Pinned Xcode: **26.6** (build 17F113), the planned default. No fallback was needed.
- `swift test` ran in CI for the first time: **114 tests in 22 suites pass**. No package or test fix was needed (step 7 of Task 1 did not trigger).
- First green build with the warning list: **`==> 9 compiler warnings`** on `dcdba1e`:
  - 2x appintentsmetadataprocessor "Metadata extraction skipped" (the tool prefixes its lines with a timestamp and PID, so `sort -u` cannot merge the two copies)
  - `Ice/Events/HIDEventManager.swift`: non-Sendable `AXUIElement` capture, plus the `@preconcurrency` hint for ApplicationServices
  - `Ice/MenuBar/MacOS27/ItemClicker27.swift`: the same two Sendable warnings
  - `Ice/Utilities/ScreenCapture.swift:81`: `CGImage(windowListFromArrayScreenBounds:...)` deprecated in macOS 14
  - The "Copy to Applications" run script phase has no outputs
  - "SwiftLint not installed" from the project's own build phase (expected, left as is)
- No deprecation annotation on the `build` and `test` check runs. The only annotation is GitHub's notice about macOS arm64 queue times.

## Task Commits

1. **Task 1 (tracer): pinned-Xcode build and swift test on the phase PR**: `359a575` (ci), plus the fix `ffd3b1d` (fix)
2. **Task 2: compiler warnings listed in the build log**: `dcdba1e` (ci)

`commits: 4` is measured with `git rev-list --count 2389824..dcdba1e`. One of those four, `996ba01` ("docs: always use the latest stable dependencies"), is the coordinator's commit. It landed on the branch mid-plan and was picked up by `git pull --rebase`. This plan made three commits.

## Files Created/Modified

- `.github/actions/select-xcode/action.yml` (new): composite action. Its `version` input (default `"26.6"`) is the single source of the CI Xcode version. It selects `/Applications/Xcode_<version>.app`, checks `xcodebuild -version` against the pin, and fails with `::error::` (listing the installed Xcodes) instead of falling back.
- `.github/workflows/build.yml`: no `paths` filter on `pull_request`; `permissions: contents: read`; `actions/checkout@v7`; both jobs use `./.github/actions/select-xcode`; new job `test` (`swift test`); the Build step prints `==> N compiler warnings` and the deduplicated, repository-relative warning list. The `push` trigger on main did not change.

## Decisions Made

- Kept the planned pin 26.6. It is the newest Xcode on the `macos-26` image, so it also meets the new CLAUDE.md rule "latest stable version of every ... tool (Xcode)". Xcode 27 is not on GitHub's image.
- The warning list is left exactly as specified: `grep warning:` | strip `$GITHUB_WORKSPACE/` | `sort -u`. The timestamped appintents duplicate is noted above and was not filtered further, because the plan asked for this exact pipeline.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The installed-Xcode list aborted the step under pipefail**
- **Found during:** Task 1, local verify
- **Issue:** GitHub runs composite bash steps with `-e -o pipefail`. With no Xcode installed, `ls -d /Applications/Xcode*.app` exits non-zero, so the `INSTALLED=$(ls ... | tr ...)` assignment killed the script before the `::error::` line was printed.
- **Fix:** `... | tr '\n' ' ' || true` inside the command substitution.
- **Files modified:** `.github/actions/select-xcode/action.yml`
- **Verification:** the Task 1 local check now prints `::error::Xcode 26.6 is not installed on this runner (expected /Applications/Xcode_26.6.app). Installed: none` and exits 1.
- **Committed in:** `359a575`

**2. [Rule 1 - Bug] `xcodebuild -version | head -1` crashed xcodebuild**
- **Found during:** Task 1, first CI run on `359a575` (build and test both failed at "Select Xcode")
- **Issue:** `head` closes the pipe after one line, xcodebuild throws `NSFileHandleOperationException ... Broken pipe` (exit 134), and pipefail fails the step.
- **Fix:** capture `VERSION_OUTPUT="$(xcodebuild -version)"`, take the first line with `${VERSION_OUTPUT%%$'\n'*}`, and print the captured output at the end.
- **Files modified:** `.github/actions/select-xcode/action.yml`
- **Verification:** `build` and `test` green on `ffd3b1d`; the log shows `Xcode 26.6` / `Build version 17F113`.
- **Committed in:** `ffd3b1d`

---

**Total deviations:** 2 auto-fixed (both Rule 1)
**Impact on plan:** both fixes were needed for the select step to work at all. No scope creep.

## Issues Encountered

- A push was rejected as non-fast-forward because the coordinator committed `996ba01` to the branch. Resolved with `git pull --rebase origin claude/ice-fork-development-hzdl1d`, then a normal push (no force-push).

## User Setup Required

None.

## Next Phase Readiness

- Plans 01-02 and 01-03 push to the same branch and PR #30. `release.yml` and the README take the Xcode version from `inputs.version.default` in `.github/actions/select-xcode/action.yml`.
- `lint.yml` and `release.yml` are unchanged against `origin/main`, as the plan requires.
- Warnings now visible for later phases: Sendable captures of `AXUIElement` (HIDEventManager, ItemClicker27) and the deprecated CGWindowList screenshot API in ScreenCapture.swift.

---
*Phase: 01-ci-and-build*
*Completed: 2026-10-02*

## Self-Check: PASSED

Files exist (action.yml, build.yml, this SUMMARY); commits 359a575, ffd3b1d and dcdba1e exist; build and test are green on PR #30 head dcdba1e.
