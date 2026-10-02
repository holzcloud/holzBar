---
phase: 01-ci-and-build
plan: 02
subsystem: infra
tags: [github-actions, swiftlint, docker, ci, lint]
status: complete

requires:
  - phase: 01-ci-and-build
    provides: "01-01: actions/checkout@v7 and the build/test checks on every pull request"
provides:
  - "lint.yml: strict lint with the official SwiftLint 0.65.1 image, pinned by sha256 digest, contents: read"
  - "Ice/ passes SwiftLint 0.65.1 --strict with 0 violations"
affects: [01-03, lint.yml, .swiftlint.yml]

actuals:
  tokens: 1200
  tasks: 2
  commits: 3
plan_head_before: 07a9364d0a422984abd65978edc325505f44b70f
plan_head_after: 5e864828cdc29da05c36e8c2fc4697a0b6a29c74

tech-stack:
  added: ["ghcr.io/realm/swiftlint:0.65.1 (digest-pinned)"]
  removed: ["norio-nomura/action-swiftlint@3.2.1", "actions/checkout@v3 in lint.yml"]
  patterns:
    - "Container tools run with plain docker run on the host, the checkout mounted at the same path, image pinned by tag plus digest in job env"
    - "The SwiftLint image's entrypoint is /usr/bin/swiftlint; a shell function swiftlint() forwards arguments to the container"

key-files:
  created: []
  modified:
    - .github/workflows/lint.yml
    - Ice/MenuBar/Search/MenuBarSearchPanel.swift
    - Ice/Permissions/PermissionsView.swift
    - Ice/Settings/SettingsPanes/AboutSettingsPane.swift
    - Ice/Utilities/IconResource.swift

key-decisions:
  - "Lint runs the official SwiftLint 0.65.1 image pinned as ghcr.io/realm/swiftlint:0.65.1@sha256:f47e0832...b057; 0.65.1 is the newest version tag on ghcr.io (checked 2026-10-02)"
  - "No lint rule was switched off for the upgrade; the only new finding (legacy_swiftui_aspect_ratio, 7 places) was fixed in code with scaledToFit()"

requirements-completed: [CI-01, CI-02]

duration: 10min
completed: 2026-10-02
---

# Phase 1 Plan 02: Pinned official SwiftLint with --strict Summary

**lint.yml now runs the official SwiftLint 0.65.1 image (pinned by sha256 digest) with `--strict` via plain `docker run`; the single new rule it reported (`legacy_swiftui_aspect_ratio`, 7 places) is fixed with `scaledToFit()`, and no rule was switched off.**

## Performance

- **Duration:** about 10 min
- **Started:** 2026-10-02T10:23Z
- **Completed:** 2026-10-02T10:32Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- `norio-nomura/action-swiftlint@3.2.1` (built from a 2021 Dockerfile on every run) and `actions/checkout@v3` are gone. lint.yml uses only `actions/checkout@v7` and `ghcr.io/realm/swiftlint:0.65.1@sha256:f47e083201e47a136cda5ae847595bfe00226c444ca226fa74fa5dc648a9b057`.
- Top-level `permissions: contents: read`; the vestigial `if: '!github.event.pull_request.merged'` guard is removed. The job id stays `swiftlint`.
- The log prints `swiftlint version` (`0.65.1`) and then the full violation list from the default reporter.
- SwiftLint 0.65.1 `--strict` passes on the PR head; `build` and `test` stay green.

## Version check

`gh api repos/realm/SwiftLint/releases/latest` is blocked in this session (the session has no access to realm/SwiftLint). Instead the ghcr.io tag list of `realm/swiftlint` was read: the newest version tags are `0.64.0, 0.64.1, 0.65.0, 0.65.1`, so 0.65.1 is the newest release. The index digest of `0.65.1` read from ghcr.io is `sha256:f47e083201e47a136cda5ae847595bfe00226c444ca226fa74fa5dc648a9b057` (linux/amd64 and linux/arm64), the same as in the plan. The CI log confirms the pull: `Digest: sha256:f47e0832...b057`.

## First SwiftLint 0.65.1 report

Run on 5b73115 (job 110801034563): `Done linting! Found 7 violations, 7 serious in 130 files.` No configuration warnings (no unknown or renamed rule identifiers).

| Rule | Count | Files |
|------|-------|-------|
| legacy_swiftui_aspect_ratio (new default rule) | 7 | Ice/MenuBar/Search/MenuBarSearchPanel.swift (4: lines 396, 423, 552, 561), Ice/Permissions/PermissionsView.swift (1: line 55), Ice/Settings/SettingsPanes/AboutSettingsPane.swift (1: line 60), Ice/Utilities/IconResource.swift (1: line 21) |

The very first run (261fe12, job 110800522753) reported 14 violations in 260 files because of the entrypoint bug below; every file was linted twice. The corrected run above is the authoritative report.

## Fixed in code

- `legacy_swiftui_aspect_ratio`, 7 places: `.aspectRatio(contentMode: .fit)` became `.scaledToFit()`. SwiftUI defines `scaledToFit()` as `aspectRatio(nil, contentMode: .fit)`, so the layout is unchanged. Every site is a SwiftUI `Image(...).resizable()` chain; there are no custom `aspectRatio`/`scaledToFit` overloads in `Ice/`. The `.aspectRatio(1, contentMode: .fit)` calls in HotkeyRecorder.swift pass a ratio and are not flagged.

## Switched off

None. `.swiftlint.yml` is unchanged: `included: [Ice]`, `file_header`, `custom_rules`, `modifier_order` and `trailing_comma` as before.

## Final result

PR head 5e86482 (job 110801348940):

```
0.65.1
Done linting! Found 0 violations, 0 serious in 130 files.
```

Check runs on 5e86482: `swiftlint` success, `build` success, `test` success. The only annotation on the swiftlint run is GitHub's notice that `ubuntu-latest` migrates to Ubuntu 26 from 2026-10-19; there is no deprecation annotation.

## Task Commits

1. **Task 1: lint every PR with the pinned official SwiftLint** - `261fe12` (ci), fixed by `5b73115` (fix)
2. **Task 2: make --strict pass with SwiftLint 0.65.1** - `5e86482` (style)

## Files Created/Modified

- `.github/workflows/lint.yml` - official digest-pinned SwiftLint image via docker run, `--strict`, `contents: read`
- `Ice/MenuBar/Search/MenuBarSearchPanel.swift`, `Ice/Permissions/PermissionsView.swift`, `Ice/Settings/SettingsPanes/AboutSettingsPane.swift`, `Ice/Utilities/IconResource.swift` - `scaledToFit()`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The container command repeated the image's entrypoint**
- **Found during:** Task 1
- **Issue:** The image's entrypoint is `/usr/bin/swiftlint`, so `docker run ... "$SWIFTLINT_IMAGE" swiftlint version` ran `swiftlint swiftlint version`: a lint of the missing paths `swiftlint` and `version`. It never printed the version and linted every file twice (260 files, every violation doubled). The same applied to the `lint --strict` run.
- **Fix:** The run block defines a shell function `swiftlint() { docker run --rm -v ... -w ... "$SWIFTLINT_IMAGE" "$@"; }` and calls `swiftlint version` and `swiftlint lint --strict`, so the container gets SwiftLint's arguments directly.
- **Files modified:** .github/workflows/lint.yml
- **Commit:** 5b73115

### Other notes

- The latest-release check used ghcr.io instead of `gh api repos/realm/SwiftLint/releases/latest`, which is blocked in this session (see Version check).
- Plan verification "`git diff origin/main -- .github/workflows/release.yml Ice.xcodeproj Scripts README.md` is empty" is not empty because of README.md, which commit 996ba01 ("docs: always use the latest stable dependencies") changed before this plan. This plan touched none of those files.

## Issues Encountered

None beyond the entrypoint bug above.

## Next Phase Readiness

- Plan 01-03 (release.yml, Xcode project, Scripts, README) can start; lint, build and test are green on the phase PR.

## Self-Check: PASSED

- FOUND: .github/workflows/lint.yml, the four Swift files
- FOUND commits: 261fe12, 5b73115, 5e86482 (git rev-list --count 07a9364..5e86482 = 3)
- Task 1 and Task 2 verify conditions confirmed against CI on 5e86482
