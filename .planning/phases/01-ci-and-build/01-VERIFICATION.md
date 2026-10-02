---
phase: 01-ci-and-build
verified: 2026-10-02T11:30:00Z
status: human_needed
score: 5/5 must-haves verified
covered_files:
  - ".github/actions/select-xcode/action.yml"
  - ".github/workflows/build.yml"
  - ".github/workflows/lint.yml"
  - ".github/workflows/release.yml"
  - "Ice.xcodeproj/project.pbxproj"
  - "README.md"
  - "Scripts/install.sh"
covered_digest: "v2:sha256:375db6d3b367ad9d7f6a7b4fb3555bef6f33dfa91614717c83fe28036c0d3dc1"
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "On a Mac with Xcode 26.6 (macOS Tahoe 26.2 or later), in a fresh clone of the PR #30 branch, run Scripts/install.sh"
    expected: "** BUILD SUCCEEDED **, 'TeamIdentifier=not set' in the signature output, holzIce launches from ~/Applications, and Settings > About shows version 0.0.5"
    why_human: "install.sh was never executed anywhere (no Mac here; CI builds with xcodebuild directly using the same signing overrides, so the flags are proven but the script itself, the codesign verify, the install and the launch are not). The runtime launch of an ad hoc signed bundle and the About version string cannot be checked on Linux."
---

# Phase 1: CI and build Verification Report

**Phase Goal:** Every pull request is built, linted and tested with current, pinned tooling, and the project carries holzIce's own identity
**Verified:** 2026-10-02
**Status:** human_needed
**Re-verification:** No, initial verification

PR holzcloud/holzIce#30: open, draft, base `main`, head `9413a314d90d` (docs-only commit on top of `9594596`), `mergeable_state: clean`. Check runs were read with `gh api` (REST) on both `9413a31` and `9594596`; the three jobs (`build`, `test`, `swiftlint`) are `completed/success` on both.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A PR run shows no deprecated-runtime warnings; workflows use `actions/checkout` v5 or newer | VERIFIED | `grep checkout@ .github` shows only `actions/checkout@v7` (build x2, lint, release). No `norio-nomura/action-swiftlint`. Annotations on all three check runs of head `9413a31` (via `check-runs/{id}/annotations`) are one `notice` each: the macOS arm64 queue-time notice (build, test) and the ubuntu-latest to Ubuntu 26 migration notice on 2026-10-19 (swiftlint). None mentions a deprecated or Node runtime. The ubuntu-latest migration notice is an unrelated runner-image heads-up, not a deprecated-runtime warning. |
| 2 | The lint job runs official SwiftLint with `--strict` and passes | VERIFIED | `lint.yml` runs `ghcr.io/realm/swiftlint:0.65.1@sha256:f47e0832...b057` (official realm image, digest-pinned) via `swiftlint lint --strict`. Job log on `9413a31` (job 110807381906): `0.65.1` then `Done linting! Found 0 violations, 0 serious in 130 files.`; check conclusion success. `.swiftlint.yml` not weakened (no rule added to `disabled_rules` for this phase; SUMMARY states the 7 new `legacy_swiftui_aspect_ratio` findings were fixed in code, and lint passes). |
| 3 | `swift test` for `Tests/IceMacOS27CoreTests` runs on every PR and passes | VERIFIED | `build.yml` `pull_request:` trigger has no `paths` filter (only `push` has one); job `test` runs `swift test`. `Package.swift` testTarget path is `Tests/IceMacOS27CoreTests`. Job log (110807382018): `Test run with 114 tests in 22 suites passed`. |
| 4 | Build log lists compiler warnings; CI Xcode is pinned and matches the README build requirement | VERIFIED | Build log (job 110807381677) prints `==> 9 compiler warnings` followed by the list (Sendable captures, deprecated `CGImage(windowListFromArrayScreenBounds:)`, etc.) and `** BUILD SUCCEEDED **`. `select-xcode/action.yml` pins `/Applications/Xcode_26.6.app`, verifies `xcodebuild -version` equals `Xcode 26.6`, and emits `::error::` instead of falling back; used by `build`, `test` and `release`. Log shows `Xcode 26.6`. README line 78: "Requires Xcode 26.6 ... CI builds with the same Xcode (pinned in `.github/actions/select-xcode`)". CLAUDE.md "Building" also points at the action. |
| 5 | Xcode project reports holzIce's version with no foreign Development Team; `install.sh` builds with ad hoc signing; `release.yml` uses `0.0.6-beta1` scheme and passes version via env | VERIFIED (with one human item) | `project.pbxproj`: `MARKETING_VERSION = 0.0.5` and `CURRENT_PROJECT_VERSION = 1` in all four target configs; `grep DEVELOPMENT_TEAM` returns nothing; no `0.11.13`; `Ice/Resources/Info.plist` has no hard-coded version keys (generated from build settings), bundle id `com.holzcloud.holzIce`, product `holzIce`. `Scripts/install.sh` passes `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO`, identical to `build.yml`/`release.yml` (CI proves these flags build); `bash -n` passes. `release.yml`: dispatch example `0.0.6-beta1`; `DISPATCH_VERSION` via `env:`; I extracted the `Determine version` step and ran it under `bash -e`: `0.0.6-beta1` and tag `v0.0.6-beta2` accepted; `0.0.6"; echo injected; "`, `1.0`, `v0.0.6-rc1` rejected with rc 1 and nothing written to `GITHUB_ENV`. A YAML scan finds no `${{ }}` expression inside any `run:` block. Release-notes check appears once. Actually running `install.sh` is not verifiable here (see Human Verification). |

**Score:** 5/5 truths verified, 0 behavior-unverified. One human UAT item remains (install.sh on a Mac).

### Plan must-haves (merged)

| Plan truth | Status | Evidence |
|------------|--------|----------|
| PR from `claude/ice-fork-development-hzdl1d` to `main` exists with green checks | VERIFIED | PR #30 open (draft), checks green on head. Draft flag is not a roadmap criterion; the orchestrator was to mark it ready. |
| Both macOS jobs use `select-xcode`, fail loudly on a missing Xcode | VERIFIED | `uses: ./.github/actions/select-xcode` in both jobs; action has `::error::` branch. |
| Build job log lists deduplicated warnings under `==> N compiler warnings` | VERIFIED | Log line present (9 warnings). Two `appintentsmetadataprocessor` duplicates remain because of timestamp prefixes (cosmetic, known). |
| `build.yml` uses `checkout@v7`, no deprecation annotation | VERIFIED | See SC1. |
| lint.yml and release.yml free of old actions | VERIFIED | `checkout@v7` only; `action-swiftlint` gone; `permissions: contents: read` in build/lint. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/actions/select-xcode/action.yml` | Pinned Xcode, fails loudly | VERIFIED | 37 lines, substantive, used by 3 jobs |
| `.github/workflows/build.yml` | build + test on every PR | VERIFIED | `swift test`, warnings list, no PR paths filter |
| `.github/workflows/lint.yml` | Official SwiftLint --strict | VERIFIED | digest-pinned image, passes |
| `.github/workflows/release.yml` | validated env version, 0.0.6-beta1 scheme | VERIFIED | see SC5 |
| `Ice.xcodeproj/project.pbxproj` | holzIce version, no team | VERIFIED | see SC5; compiled green in CI |
| `Scripts/install.sh` | ad hoc signing overrides | VERIFIED (static) | not executed |
| `README.md` | build requirement | VERIFIED | line 78 |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| build.yml (build, test) | select-xcode action | `uses: ./.github/actions/select-xcode` | WIRED |
| release.yml | select-xcode action | same | WIRED |
| build.yml test job | Package.swift / Tests | `swift test` at repo root; 114 tests ran | WIRED |
| README requirement | action default `26.6` | text matches the pin, CI log shows `Xcode 26.6` | WIRED |
| release.yml version step | later steps | `GITHUB_ENV` -> `$VERSION`, `$ZIP`, `$SHA256` in shell | WIRED |

### Data-Flow Trace (Level 4)

Not applicable (CI configuration and project metadata; no dynamic rendered data).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| install.sh parses | `bash -n Scripts/install.sh` | ok | PASS |
| release version validation and injection rejection | extracted step run under `bash -e`, 5 inputs | accept/accept/reject/reject/reject as specified | PASS |
| No expression syntax in release run blocks | YAML scan | none found | PASS |
| CI jobs on head | `gh api .../commits/9413a31/check-runs` | build, test, swiftlint success | PASS |

### Probe Execution

No probe scripts declared or present (`scripts/*/tests/probe-*.sh` absent). SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| CI-01 | 01-01/02/03 | SATISFIED | checkout@v7 everywhere, no deprecation annotations |
| CI-02 | 01-02 | SATISFIED | official SwiftLint image, `--strict`, 0 violations |
| CI-03 | 01-01 | SATISFIED | `test` job on every PR, 114 tests pass |
| CI-04 | 01-01 | SATISFIED | `==> 9 compiler warnings` in the build log |
| CI-05 | 01-01/03 | SATISFIED | Xcode 26.6 pinned, README matches |
| CI-06 | 01-03 | SATISFIED in code; `install.sh` run on a Mac pending (human item) | pbxproj, install.sh |
| CI-07 | 01-03 | SATISFIED | release.yml checks above |

No orphaned requirements: REQUIREMENTS.md maps exactly CI-01..CI-07 to Phase 1, all claimed by the plans.

### Anti-Patterns Found

None. No `TBD`/`FIXME`/`XXX` in the phase's workflow, script or README changes (the files touched are YAML/shell/Markdown/pbxproj plus four Swift files with a one-line `scaledToFit()` change). No stubs.

### Deferred Items

None needed. The Sendable and `CGImage(windowListFromArrayScreenBounds:)` warnings that CI now surfaces belong to Phase 4 (Outdated APIs); they are not Phase 1 gaps.

### Human Verification Required

#### 1. Run Scripts/install.sh on a Mac

**Test:** On macOS Tahoe 26.2 or later with Xcode 26.6, clone the PR #30 branch fresh and run `Scripts/install.sh`.
**Expected:** `** BUILD SUCCEEDED **`; the signature output shows `TeamIdentifier=not set`; holzIce launches from `~/Applications`; Settings > About shows 0.0.5.
**Why human:** No Mac in this environment; the script has never been executed. CI compiles with the same signing overrides, so the flags are proven, but the script's verify, install and launch steps are not.

### Advisory notes (non-blocking)

- PR #30 is still a draft (REST cannot flip it; not a roadmap criterion). Mark ready before merge.
- The README claim that Xcode 26.6 runs on macOS Tahoe 26.2 or later is an external fact not checkable from the repository.
- `ubuntu-latest` migrates to Ubuntu 26 on 2026-10-19; lint.yml uses the Docker image and should be unaffected, but watch the first run after that date.
- ROADMAP progress table still shows Phase 1 "In Progress" and the phase checkbox unchecked; update on completion.

### Gaps Summary

No gaps. All five roadmap success criteria and all CI-01..CI-07 are backed by repository files and by green CI check runs on the PR head. The only open item is a human run of `Scripts/install.sh` on a Mac, which makes the status `human_needed` rather than `passed`.

---

_Verified: 2026-10-02_
_Verifier: Claude (gsd-verifier)_
