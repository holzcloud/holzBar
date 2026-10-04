---
phase: 09-layout-snapshots
status: planned (outline; run /gsd-plan-phase 9)
requirements: [SNAP-01, SNAP-02, SNAP-03, SNAP-04]
depends_on: Phase 7 (needs Phase 8's rule and profile hooks only for the "before a rule applies" trigger; the rest stands alone)
placed_early_because: Phases 10 to 17 and 18 change layouts (item rules, assistant, suggestions, restore); a snapshot taken before each of them makes every one undoable
---

# Phase 9: Layout snapshots ("your layout never gets lost")

## Goal

holzBar keeps automatic, versioned snapshots of the arrangement (sections, order, profiles, groups, spacers) on the Mac, and the user can see what changed and restore one with a click, including after macOS or an app has scrambled the bar.

## Why

Menu bar layouts are fragile: apps relaunch and lose their place, macOS updates reset positions, a display change moves items. `SectionRestore.swift` already puts items back from the one saved layout, but there is only one saved state and no way back from a bad arrangement, a wrong profile, a bad rule or the Phase 16 assistant. Snapshots give the milestone's riskiest changes an undo. Competitors: none of the sources read for `COMPETITORS.md` mentions snapshots or history (Thaw: export/import of profiles "for backup"); not claimed as a lead beyond "no source says they have it".

## What a snapshot holds

Everything needed to rebuild the arrangement, nothing else: per-item section by `ItemIdentity` key (macOS 14 to 26), per-application section by bundle identifier (macOS 27), order within each section where the backend knows it, the profile list (names, per-profile sections and bindings), groups and spacers settings, the macOS and holzBar versions and the backend. No images, no hotkeys, no other settings, no usage data (Phase 17), no script data (Phase 11). A snapshot is typically a few KB.

## Design

- **Pure logic in `holzBar/Core`, Swift Testing** (`Tests/HolzBarCoreTests`): `LayoutSnapshot` (Codable, versioned `format`), `SnapshotPolicy.shouldTake(trigger:current:latest:now:)` (debounce, dedupe by a content hash so an unchanged layout never makes a new file), `SnapshotRetention.prune(_:)`, `SnapshotDiff` (what moves where, what is missing, what is new), `LayoutLossDetector` (decides "the layout looks reset": many items are in the default/new-items section now that the latest snapshot had elsewhere), `SnapshotReason` (`arrangement`, `daily`, `beforeProfile`, `beforeRule`, `beforeRestore`, `beforeAssistant`, `afterSystemUpdate`, `manual`).
- **When** (decision question 12): after the user's arrangement settles (30 s after the last change, only if the content differs), once per day at first launch or wake when the layout changed, and **before** anything that rearranges many items: profile apply, an automation rule's profile action (Phase 8), a restore, the Phase 16 assistant, an item-rule move (Phase 10) burst. macOS offers no "before update" hook; holzBar detects at launch that the macOS version changed and labels the newest earlier snapshot "Before macOS X.Y" (retroactive, and exempt from pruning).
- **How many** (question 13): newest 10, then the newest of each of the previous 20 days, at most 30, plus labelled "before macOS update" and manually starred ones; a hard size cap of 2 MB for the folder.
- **Where**: `~/Library/Application Support/holzBar/Snapshots/<UTC timestamp>.json`, mode 0600, written atomically. Whether to exclude from backups: question 14; recommended not excluded (small user data worth restoring from Time Machine; `isExcludedFromBackup` is documented for "cache and other application support files which are not needed in a backup", Apple, `URLResourceValues.isExcludedFromBackup`).
- **Not synced, not exported, not imported**: item identities and per-app sections are specific to one Mac's apps. Kept out of `SettingsSchema`'s allowlist (nothing to add) and out of the sync file.
- **Restore UI** in the Menu Bar Layout pane, "Layout History…": a list (date, reason, counts: "3 sections, 41 items, 4 profiles"), a preview of the difference to now ("5 items will move to Hidden, 2 to Visible, 3 apps are not running and will be placed when they launch") with app icons and names (shown in the UI only), a **Restore** button and **Delete**/**Star**; restoring first takes a `beforeRestore` snapshot, so "Undo restore" is the top entry. Full keyboard and VoiceOver use (Phase 21).
- **Reset notice** (SNAP-04, question 15): at launch and after the bar settles, if `LayoutLossDetector` says the layout looks reset, a non-modal banner in the Layout pane and a menu bar item menu entry: "Your layout looks reset. Restore from <date>?" with Restore / Not now / Don't ask again for this snapshot. Never restores silently by default. `SectionRestore` keeps handling the ordinary relaunch case first.
- **Crash resilience**: the file is written only after the arrangement settles, so a crash mid-move leaves the last good snapshot; a corrupt file (decode error) is skipped and logged without content.
- **Logs**: counts and reasons only; no item titles, bundle ids or profile names in public.

## Privacy and permission analysis

No permission, no network. Data: the user's own arrangement (bundle identifiers and titles of the apps in their menu bar), which is already stored today in Defaults for profiles and sections; snapshots add history of it. Mitigations: local files only, 0600, a "Delete all snapshots" button and an off switch (default on, question 12 covers whether on by default), nothing in logs, not in diagnostics (Phase 20 reports the number of snapshots only), not synced.

## Plans (outline)

1. **09-01 Model, policy, retention, diff, loss detector (Core)**: tests for dedupe, debounce, pruning at the edges (exactly 30, older than 20 days, starred), diff of moved/missing/new items, loss detector thresholds, format versioning (unknown `format` is skipped, never crashes).
2. **09-02 Store and triggers**: file store (atomic write, 0600, size cap, corrupt-file skip), the take points (settle, daily, before profile/restore), retroactive "Before macOS" labelling; the Phase 8 hook for "before rule" added when Phase 8 exists; strings for reasons.
3. **09-03 Layout History UI and restore**: sheet in the Menu Bar Layout pane, preview, restore with undo, delete, star, delete-all, off switch; five languages.
4. **09-04 Reset notice and docs**: banner and menu entry, "Don't ask again", README feature line (not a row before it works), SECURITY.md note (local files, not synced).

## Risks

- Restoring on macOS 27 only sets per-app sections, not order (README: items cannot be reordered on the bar itself): the preview must say what a restore can and cannot do on that backend.
- Item identity drift (titles with live values) can make an old snapshot match poorly: use `ItemIdentity.storedKey` and report "n items not found".
- Interplay with `SectionRestore` and profiles: a restore must not fight a profile bound to a display; restore applies sections only, then lets the normal reconcile run once.
- A burst of snapshots from rapid changes: debounce and dedupe by hash.
- No Mac in the environment: the restore path is checked by the user (26.7.1, 27) with a checklist: arrange, snapshot, scramble (quit apps, change display), restore.

## Open design questions (multiple choice; answers recorded in `.planning/research/AUTOMATION-QUESTIONS.md`)

12. **When are snapshots taken?** A. After the arrangement settles, once a day if changed, and before profile/rule/restore/assistant applies (**recommended**); B. Only once a day; C. Only before applies.
13. **How many are kept?** A. Newest 10 plus one per day for 20 days, at most 30, plus starred and "before macOS" ones (**recommended**); B. Newest 10 only; C. As many as fit in 2 MB.
14. **Backups?** A. Not excluded, so Time Machine can bring them back (**recommended**); B. Excluded from backups.
15. **When the layout looks reset?** A. Ask with a banner and a Restore button (**recommended**); B. Restore automatically and tell the user afterwards; C. Do nothing, History only.
