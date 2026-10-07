# Settings sync redesign: maintainer decisions (2026-10-07)

The maintainer answered after reading the summaries of D1–D3. The judge panel's result (`SYNC-REDESIGN-ANALYSIS.md`) was shown before the final answer. The panel recommended D3's scope on D1's per-Mac files and rejected D2. The maintainer knowingly chose D2's single shared file.

## Decisions

| # | Decision | Chosen | Departs from |
|---|---|---|---|
| S-1 | Architecture | **D2: one shared file, `holzBar/Sync2/Settings.plist`**, written only by the new build. Every write is a merge-then-write under `NSFileCoordinator`. Dots per entry, one version vector per file, multi-value registers, conflict copies joined, and healing by the author's replica (D2 §5.4, §10). | Judge panel (D2 rejected: lost writes are possible and must be healed; one damaged file blocks every Mac). The maintainer accepted this trade-off for one inspectable file. |
| S-2 | Scope by macOS version | **Settings sync on macOS 26 and 27. The menu bar arrangement syncs only between macOS 27 Macs** (`L27/<bundleID>` namespace). On macOS 26, `ItemSections` stays local: no `L26` namespace, and no macOS 26 drag capture (`HIDEventManager`/`SectionRestore` attribution) is needed. | D2 §7 (both namespaces); analysis D-1 (settings only in Phase 1) |
| S-3 | Layout profiles | **Synced together with the arrangement, per profile.** A profile gets a stable ID, so a rename is not a delete plus a create. Only the macOS 27 part (`applicationSections`, `knownApplications`) syncs. Space and display bindings, `CurrentLayoutProfile` and bound applications (automatic) stay local. Profile hotkeys are keyed by profile ID. | Analysis D-4 (export/import only) |
| S-4 | Different settings changed on two Macs | **Merge per unit without a question.** Ask only when the same unit was changed to different values concurrently. | `sync-1` literal (ask for the whole set); matches analysis D-2 (a) |
| S-5 | While a question waits | **Keep publishing**; only the conflicting unit waits, and the other Mac's value is never superseded. | `sync-1`, `modal-alerts-1` (pushes paused) |
| S-6 | Macs on 0.0.6 or 0.0.7-beta1 | **Two groups.** The new build never writes `holzBar/Settings.plist`, reads it only as join input (genesis/legacy base), and shows a status line in Settings → Advanced plus the release notes. | — (analysis D-3 (a)) |

## Defaults adopted (analysis §6.2, D2 §1.3), unless the maintainer objects

- One-time flags (`MacOS27LayoutSeeded`, `hasMigrated*`, `HasImportedIceSettings`) stay local. `KnownItemTags` and `TitleChangingItemOwners` stay local, because the macOS 26 arrangement is local. `KnownApplications27` merges by union among macOS 27 Macs, because the macOS 27 arrangement syncs (D2 M-4).
- `CurrentLayoutProfile` and the device tuning keys stay local; a profile applied by a Space or display binding is automatic (D2 M-5).
- At a join, "no user value" means the key is absent. A fresh install with nothing set adopts the folder silently (D-6, D2 M-6).
- A custom icon over 256 KiB stays on its Mac with a note (D-7).
- Rows with three or more values: a pop-up per row with no default (D-8).
- Files and entries of Macs no longer used are never deleted automatically in this release (D-9).
- Bystander conflicts: a Settings line only (D-10). The sheet names the other Mac by dates only (D-11).
- Founding from the β1 file: compare once when founding, and ignore the file when it is this Mac's own (D-12).
- A shared file that stays unreadable or too large is never overwritten automatically; "Replace…" in Settings writes over it with the user's consent (D2 M-7).

## What carries over from the analysis regardless of S-1

- Simulator first: a deterministic multi-Mac simulator in HolzBarCore tests, with exact β1/β2 peers and provider faults (including D2's write collisions without a surviving copy, conflict copies per provider and last-writer-wins), the A1 catalogue as fixed tests, and a mutation check. No app code before it passes.
- The analysis §4.9 fixes before coding (load-time writers, item re-keys, rollback joins, counter reuse, no join while files are unread).
- Re-enable sync (`SettingsSyncPause.isPaused` and its test) only in the redesign PR, after the simulator and the two-Mac tests pass. Release as 0.0.7-beta3.
