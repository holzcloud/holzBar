# holzIce

## What This Is

holzIce is a menu bar manager for macOS (14 to 27), a community fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird. It hides, reveals and styles menu bar items, has a dedicated backend for macOS 27's redesigned menu bar, and is installed and updated through Homebrew (this repository is also the tap). It is in public beta (0.0.x pre-releases).

## Core Value

The menu bar items a user hides stay hidden and come back when asked, on every supported macOS version, without the app ever locking up the Mac.

## Requirements

### Validated

- ✓ Hidden and always-hidden sections, show on hover/click/scroll, auto-rehide — existing (Ice)
- ✓ Drag-and-drop layout editor, search, item spacing — existing (Ice)
- ✓ holzIce Bar, appearance (tint, shadow, border, shapes) — existing (Ice)
- ✓ macOS 27 backend (assessment-mode assertions, Accessibility discovery) — 0.0.1
- ✓ Homebrew cask and release workflow — 0.0.1
- ✓ Layout profiles, groups, spacers, new-item placement, reveal rules, URL commands, Raycast, settings export/import/iCloud sync, black menu bar, rounded corners, notch overflow — 0.0.2
- ✓ Ice settings import, conflicting-app detection — 0.0.4
- ✓ Own control items recognised and in-app source PID fallback on macOS 26 — 0.0.5
- ✓ Modernize: current CI, bug fixes, Swift 6.4 and Xcode 27, no dependencies, security audit, macOS 14 to 27 checked in CI, signed with a stable certificate — 0.0.6

### Active

Milestone "Automation" (0.0.7, planned and decided 2026-10-04, extended the same day; one beta `0.0.7-beta1` when the whole milestone is done). Research: `.planning/research/COMPETITORS.md`; decisions: `.planning/research/AUTOMATION-QUESTIONS.md` (the first 11 answered, the rest per phase open).

- [ ] Triggers: rules (conditions all/any -> apply profile, show items, Zen mode) fed by system events, a permission only when the user adds the condition that needs it (Phase 8; the Focus-filter spike on macOS 26 and 27 comes first and the milestone is held if it fails)
- [ ] Layout snapshots with one-click restore (Phase 9) and item conditional visibility (Phase 10)
- [ ] Scripts under a security design for an unsandboxed app with Accessibility (Phase 11), widgets (Phase 12, riskiest), an AppleScript dictionary (Phase 13)
- [ ] Command palette (14), share profiles (15), first-launch clean-up assistant (16), opt-in local usage suggestions (17)
- [ ] Lock hidden items (18), smooth show and hide (19), copy diagnostics (20), accessibility showcase (21)
- [ ] macOS 27 and Xcode 27 items: native overflow button (22), Liquid Glass follows transparency (23), SwiftUI reorder spike (24), Control Center control (25, optional, go/no-go), Swift 6.4 adoption (26)
- [ ] `0.0.7-beta1` released once, with hand-written notes, when the whole milestone is done (Phase 27)

### Out of Scope

- Changing the Carbon hotkey signature — must stay identical to Ice's (`OSType(1231250720)`); holzIce and Ice never run in parallel (holzIce quits Ice), and the user wants it unchanged
- Swift 6 language mode, `@Observable` migration, migration-chain cleanup, splitting god objects — large refactors, later milestone
- Replacing Carbon hotkeys, CGWindowList capture of off-screen items, private APIs — no public replacement
- Developer ID signing and notarization — rejected by the user earlier
- Raising the deployment target above macOS 14

## Context

- Brownfield Swift/SwiftUI/AppKit app; codebase map in `.planning/codebase/` (2026-10-02).
- There is no Mac in the development environment. The only compiler is the macOS GitHub Actions runner (`.github/workflows/build.yml`); every change must get a green build there. SwiftLint `--strict` runs in `lint.yml`.
- The user tests on a MacBook with macOS 26.7.1 and later on macOS 27.
- Three backends: macOS 14–25 (window based), macOS 26 (XPC `MenuBarItemService` + in-app fallback), macOS 27 (`Ice/MenuBar/MacOS27/`).
- Project rules in `CLAUDE.md`: everything in English, credit Ice, beta numbering (`0.0.6-beta1`), release notes per release, brew trust and quarantine in install guides.

## Constraints

- **Compatibility**: macOS 14 deployment target — replacements must work on 14 or be guarded with `#available`.
- **Build**: no local compiler — validate through CI before merging; keep each PR small.
- **Naming**: Xcode target/module and internal type names stay `Ice`; user-visible name is holzIce.
- **License**: GPL-3.0; credit adapted code (Ice, Barometer, Thaw) in NOTICE.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep the hotkey signature identical to Ice | Both apps never run in parallel | — Pending |
| Release only at the end of the milestone as `0.0.6-beta1` | User's choice | ✓ Released as 0.0.6 |
| One pull request per phase, merged after a green build | No local compiler | — Pending |
| No per-phase research; the codebase audit is the research | Findings already have file:line and replacements | ✓ Good |
| Automation: permission-free triggers first; Wi-Fi name (Location) opt-in; no GPS location trigger; Focus only through a Focus filter; no Full Disk Access | Least privilege; INFocusStatusCenter needs a capability a self-signed app cannot have (see COMPETITORS.md section 4) | ✓ Decided 2026-10-04: Wi-Fi name optional (opt-in, spike first); Focus filter required, milestone held without it |
| Scripts only from a folder the user chose, hash-pinned and confirmed, local-only, never from import, sync, URL or Shortcuts | holzBar is unsandboxed and holds Accessibility, so a script runner is a privilege-escalation surface | ✓ Decided 2026-10-04: hash plus confirmation sheet is the minimum; conditions re-evaluated on events and "Check now", no polling; Phase 11 security design still first |
| Widgets: text from built-in sources (clock, battery, CPU, memory, uptime) plus a Shortcut button, timers only while visible, never online | Lean and private | ✓ Decided 2026-10-04 (Phase 12 spike first) |
| One beta `0.0.7-beta1` at the end of the milestone, no beta per phase; one push | User's choice; saves CI runs | ✓ Decided 2026-10-04 |
| Rules screen is a new "Automation" pane; rules restore the previous profile by default; rules carry Wi-Fi names and chosen apps in export and sync (logs private) | User's choices | ✓ Decided 2026-10-04 |
| AppleScript dictionary for holzBar is a phase; hide desktop icons is not | User's choice | ✓ Decided 2026-10-04 |
| Eight more feature phases (snapshots, item rules, palette, share profiles, assistant, usage suggestions, diagnostics, accessibility) and five macOS 27 / Swift 6.4 phases; "Verify this build", panic hotkey, CI budget and `.xcproj` stay backlog | User's choice | ✓ Selected 2026-10-04 |
| Usage suggestions: opt-in counters per item and day, local, excluded from backup, never exported or synced; palette keeps no history; diagnostics are allowlist-based and shown before copying | Private principle | ✓ Design in the phase outlines; open questions listed |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-04 after planning milestone 0.0.7 Automation*
