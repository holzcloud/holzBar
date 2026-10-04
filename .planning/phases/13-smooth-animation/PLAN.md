---
phase: 12-smooth-animation
status: planned, selected by the user 2026-10-04 (outline)
requirements: [ANIM-01]
depends_on: Phase 7
---

# Phase 13: Smooth show and hide

## Goal

Showing and hiding items looks smooth where it can, costs nothing when idle, and never delays the reveal.

## Why

Vanilla is praised for "fluid animations" (MacStories roundup). Ice and holzBar switch the divider control item between a normal and a very large length (K), so items appear at once.

## Design sketch

- Animate only the control item's length (or the Shelf's appearance), in a few steps over about 0.15 to 0.2 s, while a reveal or a hide is in progress. No timer, no display link outside that window. Prefer the system's animation for the Shelf (SwiftUI/AppKit, `NSAnimationContext`) over hand-made timers.
- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and its change notification: no animation when Reduce Motion is on.
- A spike decides whether stepping the length of a status item is smooth on macOS 14, 26 and 27 or looks like flicker (items beside the divider jump); if not smooth, ship only the Shelf's fade and say so. The macOS 27 backend hides through assertions, not lengths, so the animation may not apply there at all: say so in Settings and the README.
- Pure part in Core: the step schedule (`RevealAnimationSchedule`: duration, steps, easing), tested with Swift Testing (monotonic, ends exactly at the target, zero steps when Reduce Motion).
- Setting: "Animate showing and hiding" (default on if the spike is good), exported and synced.

## Plans

1. **13-01 Spike and implementation**: spike on three macOS versions with a checklist for the user; schedule in Core; Reduce Motion; setting; strings; docs; energy measurement (no wakeups when idle).

## Risks

- Several items moving at once can make other apps' items jump or flash; a reveal that animates may feel slower than the instant one the user knows. Keep the duration short and the setting off-able.
- Rapid show/hide sequences (hover in and out) must cancel and not queue.
- Not applicable on macOS 27's assertion-based hiding (to confirm).
