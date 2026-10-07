---
created: 2026-10-07T06:00:00.000Z
title: Redesign settings sync (paused in 0.0.7-beta2)
area: sync
severity: major
files:
  - holzBar/Core/SettingsSyncPause.swift
  - holzBar/Utilities/SettingsSync.swift
  - holzBar/Core/SettingsSync*.swift
  - .planning/audit/REMEDIATION-2026-10-05.md
---

## Problem

Settings sync is paused in 0.0.7-beta2. `SettingsSyncPause.isPaused = true`: holzBar never touches the sync folder, the stored configuration is kept, and Settings > Advanced shows a note.

Why it is paused:
- The audit fixes F-02, F-15, F-38 and F-60, and the review finding SA-05, made sync ask on conflicts and leave automatic placements alone.
- Six review rounds on branch `audit-manual/sync-fix` (pushed to origin; 58 commits, summaries in its `.planning/audit/remediation/sync-fix-SUMMARY.md`) kept finding new blockers, some caused by the previous round's fixes.
- Every remaining case involves the menu bar arrangement (ItemSections and MacOS27Layout) shared between macOS 26 and 27 Macs, Macs still on 0.0.7-beta1, layout copies kept in the file, and missing or restored files.

## Solution

Plan the redesign as its own GSD phase (discuss, plan, execute, verify), not with more patches. Starting points:
- **Record each version's parent.** Every written version records the version it was based on, per Mac (the `seen` record from round 5 on audit-manual/sync-fix).
- **Possibly stop syncing the arrangement.** Syncing only settings, not the menu bar arrangement, removes most of the hard cases. The maintainer was offered this on 2026-10-06 and chose to pause first.
- **Handle layout edits made during the pause.** userChangedLayout and the state migration do not run while sync is paused; see "Next beta" in the remediation log.
- **Keep the maintainer's policy.** Ask on conflicts, never overwrite silently, and never count holzBar's own placements as the user's change.
- **Re-enable and test.** Change SettingsSyncPause and its test, then run two-Mac tests: same macOS, 26 with 27, and one Mac still on beta 1.

## Update 2026-10-07

Analysis finished and decided: see `.planning/research/sync-redesign/DECISIONS.md` (D2 single shared file; settings on macOS 26 and 27; arrangement and profiles only between macOS 27 Macs). Next: add the phase with `/gsd-phase`.
