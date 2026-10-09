---
created: 2026-10-09T00:00:00.000Z
title: Grow holzBar into an all-in-one with optional, switchable modules
area: product
severity: major
files:
  - .planning/research/features/DECISIONS.md
  - .planning/research/features/VORSSAINT.md
---

## Problem

The maintainer wants one app instead of several: holzBar should take over the jobs of these tools, as modules that are all optional and can be switched off:

- **Vorssaint** (modular menu bar toolbox: windows/Dock, mouse and keyboard, clipboard and files, sound, energy and display, system monitor, Dynamic Island)
- **AltTab** (window switcher with previews)
- **Flameshot** (screenshots and annotation)
- **Rectangle** (window snapping and tiling)
- **MonitorControl** (brightness and volume of external displays)

This supersedes the "Later" and "No" entries of `research/features/DECISIONS.md` for vorssaint's other tools (window management, input remapping, screenshots, cleaner, Dynamic Island): they are now wanted, as opt-in modules.

## Constraints to keep (CLAUDE.md principles)

- Every module is off by default and can be switched off completely; a module that is off costs no CPU, memory or permission, and its code does not run.
- Least privilege: a module asks for its permission (Accessibility, Screen Recording, ...) only when the user turns it on, and says why. Nothing is requested at first launch for modules the user never enables.
- Private: no network, no telemetry, no update check, in any module.
- Lean and modern: no third-party packages, current Apple APIs. Display brightness over DDC may need private or unstable APIs: decide per module whether it fits.
- Licences: holzBar is GPL-3.0. To verify before adapting any code: Rectangle (MIT), MonitorControl (MIT), AltTab (GPL-3.0), Flameshot (GPL-3.0), Vorssaint (GPL-3.0 or later per its README). Credit each in NOTICE and Settings → About, as done for Ice.

## Solution

1. Research per tool (current features, permissions, macOS 26/27 behaviour, licence, what to take and what not), one report each in `.planning/research/features/`.
2. Decide the module architecture first (a module registry, one Settings pane "Modules" with a switch per module, shared permission handling, README and comparison table updates).
3. Choose the order and release (candidate: a milestone "Modules" after 0.0.9; Rectangle and MonitorControl first, as they are the smallest and need the fewest permissions).
