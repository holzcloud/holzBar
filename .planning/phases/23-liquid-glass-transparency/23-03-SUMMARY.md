---
phase: 23-liquid-glass-transparency
plan: 03
subsystem: docs
tags: [docs, uat, reduce-transparency, increase-contrast, liquid-glass]
requires: [23-01, 23-02]
provides:
  - README, feature list and macOS 27 notes state the Phase 23 claim, scoped to what was verified
  - M27-04 closed as not applicable
  - 23-UAT.md, fourteen pending items for macOS 26 and 27
affects: [27-release-0.0.7]
key-files:
  created:
    - .planning/phases/23-liquid-glass-transparency/23-UAT.md
  modified:
    - README.md
    - docs/features.md
    - docs/macos27.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/27-release-0.0.7/PLAN.md
key-decisions:
  - "The docs say what 0.0.7-beta3 contains and that it is not yet checked on real macOS 26 and 27 systems, instead of 'planned, not available', because the beta ships the code; the claim about the slider stays 'no public API'"
status: complete
actuals:
  tokens: 9000
  tasks: 3
  commits: 3
plan_head_before: 067ad07b1169b4f14ef5207c3a0e4e02af466840
plan_head_after: 702ea4f9
requirements-completed: [M27-04]
completed: 2026-10-09
---

# Phase 23 Plan 03: Docs, closure and UAT script Summary

**README, feature list and macOS 27 notes say exactly what Phase 23 does (System Glass and the Shelf follow Reduce Transparency and Increase Contrast) and that the Liquid Glass slider has no public API; M27-04 is closed as not applicable; the UAT script has 14 pending items.**

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | Tracer: README and feature list state the claim | 16d7a421 |
| 2 | macOS 27 notes section, M27-04 closed, Phase 27 hand-off | 1066d2b1 |
| 3 | 23-UAT.md, every item pending | 702ea4f9 |

The Decision line of 23-01-SPIKE.md reads `M27-04: not-applicable` (checked before Tasks 1 and 2).

## Deviations from Plan

**1. [Rule 2 - honesty] Wording adapted to the release.** The plan kept the lines under "planned, not available yet". The same session writes the release notes of 0.0.7-beta3, which contain this work, so README and docs/features.md now say "in 0.0.7-beta3" and "not yet checked on real macOS 26 and 27 systems"; the heading text "None of this is available yet" was narrowed to "Apart from the 0.0.7 parts marked as in 0.0.7-beta3". Phase 27 still flips the lines after the UAT (hand-off sentence says so). No comparison row was added.

**2. [Gate over-match] The slider grep gate fails on an unrelated line.** `docs/features.md` line 157 (a screenshot caption for the spacing slider, pre-existing) matches "slider" without the allowed phrases. Every line about the Liquid Glass slider passes; that one line is not about it.

**3. Ledger file.** The per-plan head ledger could not be written (sandbox); the base commit is recorded above from the known HEAD before the first task.

## Verification

- Spike decision line: 1 match. Slider grep gate: only the unrelated caption above.
- UAT: 14 `### ` items, 14 `result: [pending]`, 0 other results, `pending: 14`.
- REQUIREMENTS.md: M27-04 ticked with "Complete (not applicable...)", M27-03 still open and "Planned".
- `strings-check.py`, `privacy-check.py logs`, `privacy-check.py network`, `workflow-check.py`: all print their success line. Former-name grep: no match. No Swift file touched, so no typecheck.
- Nothing visual was observed; M27-03 stays open until the maintainer's UAT.

## Known Stubs

None.

## Self-Check: PASSED

Files exist (23-UAT.md, edited docs) and the three commits are ancestors of HEAD.
