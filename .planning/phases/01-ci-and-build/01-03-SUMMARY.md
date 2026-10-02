---
phase: 01-ci-and-build
plan: 03
subsystem: infra
tags: [github-actions, xcode, release, signing, ci]
status: complete

requires:
  - phase: 01-ci-and-build
    provides: "01-01: .github/actions/select-xcode (Xcode 26.6), build and test on every PR; 01-02: pinned official SwiftLint"
provides:
  - "Ice.xcodeproj: MARKETING_VERSION 0.0.5 and CURRENT_PROJECT_VERSION 1 in all four target configurations, no DEVELOPMENT_TEAM"
  - "Scripts/install.sh signs ad hoc with the CI overrides, so anyone can build it"
  - "README states the real build requirement (Xcode 26.6 on macOS Tahoe 26.2 or later)"
  - "release.yml: validated, env-passed version; notes checked once; pinned Xcode; checkout v7"
affects: [phase-06-release, release.yml, Scripts/install.sh, README.md]

actuals:
  tokens: 6500
  tasks: 2
  commits: 2
plan_head_before: f25bdd05fd3740f48e16be6b08643711904fbd22
plan_head_after: 9594596840c2ce53fc8e2b6ec071a59cfe17b0ce

tech-stack:
  added: []
  removed: ["the 'newest installed Xcode' step in release.yml", "actions/checkout@v4 in release.yml"]
  patterns:
    - "Untrusted workflow input reaches the shell only via env:, is regex-validated, then written to GITHUB_ENV; no expression inside any run block"
    - "Source builds and CI share one set of ad hoc signing overrides"

key-files:
  created: []
  modified:
    - Ice.xcodeproj/project.pbxproj
    - Scripts/install.sh
    - README.md
    - .github/workflows/release.yml

key-decisions:
  - "The project sets no DEVELOPMENT_TEAM at all; install.sh, build.yml and release.yml all sign ad hoc with CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO"
  - "release.yml passes VERSION, ZIP and SHA256 between steps through GITHUB_ENV; the version is written only after it matches ^[0-9]+\\.[0-9]+\\.[0-9]+(-beta[0-9]+)?$"

requirements-completed: [CI-01, CI-05, CI-06, CI-07]

duration: 12min
completed: 2026-10-02
---

# Phase 1 Plan 03: holzIce identity, ad hoc install.sh and a hardened release workflow Summary

**The Xcode project now says holzIce 0.0.5 with no foreign development team, `Scripts/install.sh` signs ad hoc with CI's exact overrides, the README names the Xcode CI pins (26.6), and `release.yml` only sees the version through env after validating it against the 0.0.6 / 0.0.6-beta1 scheme.**

## Performance

- **Duration:** about 12 min
- **Started:** 2026-10-02T10:37Z
- **Completed:** 2026-10-02T10:49Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- `Ice.xcodeproj/project.pbxproj`: all six `DEVELOPMENT_TEAM` lines (K2ATHQPJDP at project level, WMBUU9S842 in both targets) are gone; `MARKETING_VERSION = 0.0.5;` and `CURRENT_PROJECT_VERSION = 1;` in all four target configurations. Signing style, build phases and everything else unchanged. `build` on 45e0e88 compiled the hand-edited project.
- `Scripts/install.sh`: passes `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=` before `ENABLE_HARDENED_RUNTIME=NO`; the comment explains the ad hoc signing first, keeps the hardened-runtime reason and the jordanbaird/Ice#1006 credit to @Theralley.
- `README.md` (line 78): "Requires Xcode 26.6, which runs on macOS Tahoe 26.2 or later. CI builds with the same Xcode (pinned in `.github/actions/select-xcode`); holzIce itself runs on macOS 14 or later." Compared with the current origin/main, that is the only README change.
- `.github/workflows/release.yml`: `actions/checkout@v7`; dispatch example `0.0.6-beta1`; `DISPATCH_VERSION` in `env:`; `VERSION="${DISPATCH_VERSION:-${GITHUB_REF_NAME#v}}"` validated with `[[ =~ ]]` before the `GITHUB_ENV` write; the error does not echo the rejected value; one release-notes check, before the build; `- uses: ./.github/actions/select-xcode`; Package writes `ZIP` and `SHA256` to `GITHUB_ENV`; the second notes check in Publish is removed; the cask sed uses `$VERSION` and `$SHA256` in double quotes; commit message `holzice $VERSION`; comment says "-beta1". No `${{ }}` inside any run block.

## Local version-step test (release.yml)

Run with the plan's harness (the step's `run` under `bash -e`, fresh GITHUB_ENV per case):

| Input | Result |
|-------|--------|
| dispatch `0.0.6-beta1` | rc 0, `VERSION=0.0.6-beta1` |
| tag `v0.0.6-beta2` | rc 0, `VERSION=0.0.6-beta2` |
| tag `v0.0.5` | rc 0, `VERSION=0.0.5` |
| `0.0.6"; echo injected; "`, `0.0.6\nEVIL=1`, `0.0.6-beta.1`, `1.0`, `v0.0.6`, `0.0.6-rc1` | rc 1, GITHUB_ENV empty |

The cask sed expressions, expanded with `0.0.6-beta1` and a test hash, changed exactly the `version` and `sha256` lines of a copy of `Casks/holzice.rb` (GNU sed locally; the workflow keeps BSD `sed -i ''` for macOS).

## CI result

PR #30, final head **9594596840c2ce53fc8e2b6ec071a59cfe17b0ce**:

- `build` success (job 110805896540): `Xcode 26.6` / `Build version 17F113`, `==> 9 compiler warnings`, `** BUILD SUCCEEDED **`
- `test` success (job 110805896693): `Test run with 114 tests in 22 suites passed`
- `swiftlint` success (job 110805895919): `Done linting! Found 0 violations, 0 serious in 130 files.`
- Annotations: only GitHub's macOS arm64 queue-time notice and the ubuntu-latest to Ubuntu 26 migration notice; no deprecation annotation.
- PR mergeable, `mergeable_state` clean. PR body updated (CI-01 to CI-07, Verified by, Phase 6 note, attribution).

**PR status: ready to mark ready.** It is still a draft: the REST API cannot change the draft flag and GraphQL is blocked here. The orchestrator marks it ready (GitHub MCP `update_pull_request`, `draft=false`) and does the `.draft == false` check of the Task 2 verify.

## Task Commits

1. **Task 1: holzIce version, no foreign team, ad hoc install.sh, README requirement** - `45e0e88` (build); build, test, swiftlint green on it
2. **Task 2: release.yml takes a validated version through env** - `9594596` (ci); build, test, swiftlint green on it

## Files Created/Modified

- `Ice.xcodeproj/project.pbxproj` - holzIce version 0.0.5 / build 1, no DEVELOPMENT_TEAM
- `Scripts/install.sh` - ad hoc signing overrides identical to CI, rewritten comment
- `README.md` - real build requirement
- `.github/workflows/release.yml` - env-passed, validated version; single notes check; pinned Xcode; checkout v7

## Decisions Made

- None beyond the plan. The cask step keeps its direct push to main (outside this phase).

## Deviations from Plan

None - plan executed exactly as written.

### Other notes

- origin/main moved on while this plan ran (PR #31, README banner: `Resources/Logo/banner.png`, `banner.svg`). The branch does not contain it yet, so a two-dot `git diff origin/main --stat` also lists those two files (and `.gitignore`/`CLAUDE.md` from the coordinator's earlier commits). The three-dot diff and the README diff show only this phase's changes; GitHub reports the PR as mergeable and clean.
- The Task 2 verify's last condition (`.draft == false`) cannot hold until the orchestrator marks the PR ready; every other condition holds on 9594596.

## Issues Encountered

None.

## Open human check

On the Mac (macOS Tahoe 26.2 or later with Xcode 26.6), in a fresh clone of the branch: run `Scripts/install.sh`. Expect `** BUILD SUCCEEDED **`, `TeamIdentifier=not set` under the signature lines, holzIce launching from `~/Applications`, and holzIce > About showing version 0.0.5.

## Next Phase Readiness

- Phase 1 is complete once PR #30 is marked ready and merged. `release.yml` first runs for real at the `v0.0.6-beta1` tag in Phase 6.

## Self-Check: PASSED

- FOUND: Ice.xcodeproj/project.pbxproj, Scripts/install.sh, README.md, .github/workflows/release.yml, this SUMMARY
- FOUND commits: 45e0e88, 9594596 (git rev-list --count f25bdd0..9594596 = 2)
- Task 1 verify passes in full; Task 2 verify passes except the draft flag, which the orchestrator sets
