---
created: 2026-10-09T00:00:00.000Z
title: Move menu bar icons directly in the menu bar by drag and drop
area: product
severity: minor
files:
  - docs/features.md
---

## Problem

The maintainer wants to move icons directly in the menu bar by drag and drop (not only in the Layout pane of Settings, which already has a drag-and-drop editor, and not only with macOS's Command-drag).

## Decided (2026-10-09, maintainer)

- Scope: all three: drag **without holding Command**, drag an item **across the holzBar divider** into the hidden or always-hidden section, and **reorder visible items** directly in the menu bar.
- Release: **0.0.8** (the features release).

## Open points
- How: on macOS 26 items live in separate windows, on macOS 27 the whole menu bar is one window (Apple's change), so the mechanism differs per version. A plain drag in the menu bar normally does nothing; macOS needs Command. Options are to synthesize the Command-drag for the user, or to draw holzBar's own drag handles/overlay.
- Interaction with Phase 28: the arrangement on macOS 27 syncs between Macs and only user moves count (the engine captures them as intents, plan 28-16). A direct drag must send the same user intent as a Layout-pane move.

## Solution

Decide the exact behaviour with the maintainer, spike it on macOS 26 and 27, then assign a release.
