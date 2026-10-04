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

Milestone "Automation" (0.0.7, planned 2026-10-04): the user gets rules that react to the Mac's state, and a few things competitors have. Research: `.planning/research/COMPETITORS.md`; decisions pending: `.planning/research/AUTOMATION-QUESTIONS.md`.

- [ ] Triggers: rules (conditions all/any -> apply profile, show items, Zen mode) fed by system events, a permission only when the user adds the condition that needs it (Phase 8)
- [ ] Scripts: a user script or AppleScript as a condition or action, under a security design for an unsandboxed app with Accessibility (Phase 9)
- [ ] Widgets: custom text items without code, built-in sources first (Phase 10, riskiest)
- [ ] Competitor gaps: lock hidden items, smooth show and hide, desktop icons spike (Phases 11 to 13)
- [ ] `0.0.7-beta1` and later betas released with hand-written notes (Phase 14)

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
| Automation: permission-free triggers first; Wi-Fi name (Location) opt-in; no GPS location trigger; Focus only through a Focus filter; no Full Disk Access | Least privilege; INFocusStatusCenter needs a capability a self-signed app cannot have (see COMPETITORS.md section 4) | — Pending the user's answers |
| Scripts only from a folder the user chose, hash-pinned and confirmed, local-only, never from import, sync, URL or Shortcuts | holzBar is unsandboxed and holds Accessibility, so a script runner is a privilege-escalation surface | — Pending (Phase 9 security design) |
| Widgets: text from built-in sources, timers only while visible, never online | Lean and private | — Pending (Phase 10 spike) |

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
