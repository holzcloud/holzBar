# Phase 28: Settings sync redesign — Context

**Gathered:** 2026-10-07 (maintainer decisions taken in the resume session; this file replaces discuss-phase)
**Status:** Ready for planning
**Target:** 0.0.7-beta3

<domain>
## Phase Boundary

Re-enable settings sync on a redesigned engine that cannot lose, revert or silently overwrite a user's change. The design is the judge panel's recommended architecture (`.planning/research/sync-redesign/SYNC-REDESIGN-ANALYSIS.md` §4, §5, §7: one file per Mac, causal dots, lattice join, multi-value registers, Σ), **extended by the maintainer's scope decision**: in addition to the settings of analysis §4.2, the **macOS 27 menu bar arrangement (`MacOS27Layout`) and the layout profiles' macOS 27 part sync between macOS 27 Macs** in this phase. The macOS 26 arrangement (`ItemSections`) stays local.

In scope: Core engine, deterministic multi-Mac simulator and catalogue tests (gate G1 before any app glue), app glue, UI (hint, status lines, sheet), migration/β1 boundary, companion fixes (analysis §4.9), docs and release notes for 0.0.7-beta3, flipping `SettingsSyncPause.isPaused` to false with its test.

Not in scope: macOS 26 arrangement sync and Command-drag attribution on macOS 26; D2's shared file, healing and "Replace…"; writing `holzBar/Settings.plist`; automatic cleanup of departed Macs; publishing the release tag (admin, after the maintainer's two-Mac UAT).
</domain>

<decisions>
## Implementation Decisions (locked — see `.planning/research/sync-redesign/DECISIONS.md`)

### Architecture
- **D-01:** One file per Mac, `<folder>/holzBar/Macs/<MacID>.plist`, written only by that Mac; every Mac reads every file and joins. Format, Σ, identity, counters, collision rules exactly as analysis §4.3–§4.5. Pass-through of unknown units/families from day 1.
- **D-02:** Never write or delete `holzBar/Settings.plist`. Read it only as join input when founding a group (analysis §4.8, D-12). Macs on 0.0.6/0.0.7-beta1 form a separate group; Settings → Advanced shows "A Mac with an older holzBar still uses this folder", and the release notes say "update all Macs".

### Scope of what syncs
- **D-03:** Settings: unit table v1 of analysis §4.2 (General, Advanced, holzBar icon ≤256 KiB, appearance, groups, hotkeys split per action/item, item icons, reveal rules, reveal-on-change marks). Syncs on macOS 26 and 27.
- **D-04 (maintainer, departs from analysis D-1):** The macOS 27 arrangement syncs between macOS 27 Macs as the family `l27/<bundleID>` (one split unit per app, value = section; explicit "visible" value, absence never means visible). Only a Mac running macOS 27 creates dots there; macOS 26 Macs relay it untouched and never apply it. Design reference: D1 §7 and D2 §7 restricted to the L27 namespace. Intent capture on macOS 27 only from user actions: a Layout-pane move (`Concealer27.setSection(_:for:)` is exactly one user move), applying a profile by the user (menu, hotkey, Shortcuts, `holzbar://`; only entries whose value changes), Import. Seeding (`seedLayoutIfNeeded`), `placeNewApplications`, reconciliation, displacement and profile application by a Space/display binding are automatic and never create dots. Automatic stores must not overwrite an entry backed by applied intent; seeding fills only apps without an entry (D2 §7.3 rules restricted to 27). The planner must verify in code whether macOS 27 offers any other user arrangement path (e.g. a Command-drag on the bar handled by `AccessibilityBackend27`/`Concealer27`) and capture it the same way, or record that none exists.
- **D-05 (maintainer):** Layout profiles sync per profile with a stable profile ID (rename ≠ delete+create), family `prof/<profileID>`. Only the macOS 27 part (`applicationSections`, `knownApplications`) and the name sync; `itemSections` (macOS 26 part), Space/display bindings, `CurrentLayoutProfile` stay local. Profile hotkeys (`ApplyProfile:…`) are keyed by profile ID; whether they sync follows the hotkey units (sync with the profile ID key). `saveCurrentLayout` records only the running generation's part and keeps the other part (D3 §4.5). A profile saved on macOS 26 changes only its local 26 part and creates no `prof` dot for the 27 part.
- **D-06:** `KnownApplications27` merges by union among macOS 27 Macs (it decides new-app placement together with the synced arrangement). `KnownItemTags`, `TitleChangingItemOwners`, one-time flags, `CurrentLayoutProfile`, device tuning and every `SettingsSync…` key stay local.

### Conflicts and questions
- **D-07:** Per-unit merge: different units changed on two Macs merge without a question; the same unit changed to different values concurrently is a conflict (siblings). Answers supersede exactly the dots the sheet showed (applied-context rule).
- **D-08:** Publishing continues while a question waits; only the conflicting unit waits.
- **D-09:** The question UI follows `modal-alerts-1`: a quiet hint, a sheet only when clicked; buttons Use Settings from Sync Folder / Keep This Mac's Settings / Later (Cancel when joining). Rows list the conflicting units with both values. Rows with three or more values: a pop-up per row with no default. Bystander conflicts: a Settings line only. The sheet names the other Mac by dates only.
- **D-10:** Defaults of analysis §6.2: "no user value" at a join = key absent; oversize icon stays local with a note; no automatic deletion of departed Macs' files.

### Verification gates
- **D-11:** Simulator first (analysis §5): a deterministic seeded multi-Mac simulator in the Core test package drives the real engine with exact β1/β2 peers, provider faults (deletion, restore, dataless, partial/damaged files, conflict copies, per-device iCloud winners), ground-truth oracles for the A2 invariants (amended per analysis §2.3) plus the L27/profile invariants (INV-L1–L6 restricted to 27, union of KnownApplications27), control engines it must catch, a mutation gate and fixed catalogue tests (A1 scenarios incl. the macOS 27 layout ones previously "SCOPE"). **No app sync glue before G1 passes.**
- **D-12:** Sync stays paused in every commit until the engine, simulator, glue and docs are complete; the flip to `isPaused = false` and its test is the last code change of the phase, in the same PR.

### Claude's Discretion
- Exact Swift type names, file split inside `holzBar/Core/Sync/…`, simulator internals, budgets of the exploration runs (must finish in CI time).
- Strings wording in English (de, fr, it, rm translations machine-written as today; strings CI must pass).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Decisions and design
- `.planning/research/sync-redesign/DECISIONS.md` — the maintainer's decisions for this phase (authoritative over the analysis where they differ)
- `.planning/research/sync-redesign/SYNC-REDESIGN-ANALYSIS.md` — recommended architecture (§4), verification strategy (§5), phase outline and two-Mac script (§7), code facts (Appendix A)
- `.planning/research/sync-redesign/D1-per-device-files.md` — per-Mac files incl. layout namespaces (§7) and profiles
- `.planning/research/sync-redesign/D2-single-file-version-vectors.md` §7 — macOS-specific layout capture/apply rules (use the L27 parts only; the shared-file mechanism is rejected)
- `.planning/research/sync-redesign/D3-settings-only.md` — unit table, profile `saveCurrentLayout` companion change (§4.5)
- `.planning/research/sync-redesign/A1-failure-taxonomy.md` §6 — regression catalogue (70 scenarios)
- `.planning/research/sync-redesign/A2-requirements-invariants.md` — reference model, invariants, fault model, simulator notes
- `.planning/research/sync-redesign/A3-research.md` — techniques and provider behaviour

### Existing code
- `holzBar/Core/SettingsSyncPause.swift`, `holzBar/Settings/…/SettingsSync*.swift`, `SettingsSyncPolicy.swift` (to be replaced), `SettingsBackup.swift`
- `holzBar/MenuBar/MacOS27/Concealer27.swift`, `holzBar/MenuBar/Profiles/LayoutProfiles.swift`, `holzBar/MenuBar/MenuBarItems/SectionRestore.swift`
- Branch `audit-manual/sync-fix`: history of the six failed rounds — reference only, never merge

### Project rules
- `CLAUDE.md` — English in the repo, GSD, one PR and push once, multiple-choice questions in German, no network, lean, Apple's way
- Local checks without Xcode: `swift test`, `swiftc -emit-sil` type check, SwiftLint with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` (memory: holzbar-local-checks-without-xcode). CI is the only full compiler.
</canonical_refs>

<code_context>
## Existing Code Insights

- The Core test package (`Package.swift`) compiles `holzBar/Core` as `HolzBarCore` with `Tests/HolzBarCoreTests`, Swift 6, main-actor default isolation: new engine types are `nonisolated` Foundation-only value types.
- Load-time writers that must stop writing back or be marked automatic (analysis Appendix A items 1–4, §4.9): `HotkeysSettings.loadInitialState`, `GeneralSettings` didSet/clamps, `MenuBarSpacers.performSetup`, appearance and groups re-encode.
- Re-keys of item-keyed settings (`ItemIconStore.setChoice`, `ItemChangeWatcher.setRevealedOnChange`) follow the alias rule (analysis §4.6.2).
- `LayoutProfiles.saveCurrentLayout` copies `MacOS27Layout` into every profile on every OS (Appendix A item 8) — must change (D-05).
</code_context>

<specifics>
## Specific Ideas

- Requirement IDs for this phase: **SYNC-R01** engine and format; **SYNC-R02** identity, counters, collisions; **SYNC-R03** simulator and oracles (G1); **SYNC-R04** catalogue and mutation gate; **SYNC-R05** settings units and capture (only user changes); **SYNC-R06** macOS 27 arrangement sync; **SYNC-R07** profile sync; **SYNC-R08** questions, hint, status lines, strings; **SYNC-R09** β1 boundary and migration from the pause; **SYNC-R10** docs, release notes v0.0.7-beta3, re-enable.
- The maintainer's two-Mac UAT (analysis §7.5, extended with macOS 27 arrangement and profile tests between two macOS 27 Macs if available) is gate G3 and happens after the PR is green; the phase ends with the PR ready and the UAT script handed over.
</specifics>

<deferred>
## Deferred Ideas

- macOS 26 arrangement sync (needs Command-drag attribution traces on real Macs; analysis §4.13, §7.6)
- Automatic cleanup of departed Macs' files
- One-way import of β1 changes into the new group
</deferred>

---

*Phase: 28-settings-sync-redesign*
*Context gathered: 2026-10-07*
