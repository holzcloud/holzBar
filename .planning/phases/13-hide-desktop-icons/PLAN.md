---
phase: 13-hide-desktop-icons
status: planned (spike; may end with no feature)
requirements: [DESK-01]
depends_on: Phase 7
---

# Phase 13: Hide desktop icons (spike)

## Goal

Know whether desktop icons can be hidden cleanly; ship the feature only if they can.

## Why

Vanilla offers it as a bonus ("desktop icon hiding", MacStories). It is cheap to want and easy to do badly.

## What is known and unknown

- The usual way is `defaults write com.apple.finder CreateDesktop false` followed by a Finder restart (K, `(u)`: no source read today). That changes a system preference of another app, flashes the desktop, relaunches Finder (which can lose Finder windows' state) and needs Automation or a `killall`: against "least privilege" and "Apple's way". Not acceptable without the user's explicit decision.
- macOS 15 and later has a built-in "Show Items on Desktop" switch (System Settings, Desktop and Dock) and Stage Manager can hide icons (K): the spike must find whether there is a public, supported way to toggle it, or whether the best answer is a Shortcut action or a link that opens the right System Settings pane.
- A full-screen window covering the desktop (what some apps do) draws over the wallpaper and icons; it is a hack with Screen Recording and cost implications: rejected unless the spike finds it clean.

## Plans

1. **13-01 Spike**: write `13-SPIKE.md` with the mechanism, permission, side effects, macOS versions, and a recommendation. If a clean mechanism exists: implement as one hotkey, menu item, URL command and Shortcut action ("Toggle desktop icons"), off by default, restore on quit (decision with the user). If not: close the phase with the finding, and add a line to the competitor table that says holzBar deliberately does not do it and why.

## Risks

Leaving the user's desktop hidden after a crash (a restore on launch is mandatory); changing a system preference outside holzBar's own domain.
