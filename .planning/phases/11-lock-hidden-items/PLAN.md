---
phase: 11-lock-hidden-items
status: planned (outline)
requirements: [LOCK-01]
depends_on: Phase 7
---

# Phase 11: Lock hidden items

## Goal

Revealing hidden items can require the Mac's owner: Touch ID or the login password.

## Why

SaneBar offers "Touch ID/Password Lock: biometric protection for hidden icons" (github.com/sane-apps/SaneBar). Fits the principles: `LocalAuthentication` (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`) needs no permission and no network (K; confirm in the plan).

## What it protects (to say in Settings, honestly)

It keeps a bystander at an unlocked Mac from seeing what the hidden items show (VPN, messaging, work apps). It does not stop someone who can open System Settings or holzBar's settings: the user can state whether turning the lock off needs authentication too (recommended: yes). It is not a security boundary against the owner or malware.

## Design sketch

- Setting `lockHiddenItems` (Defaults, exported and synced as a plain Boolean, never imported on): `SyncsSettingsWithICloud` precedent: an imported file must not turn the lock off or on silently; keep it out of import and sync (like T-06-L3).
- Every path that reveals goes through one gate: click, hover, scroll, hotkeys, Shelf, search, URL `show`, Shortcuts, trigger rule action. A rule or URL that would reveal while locked asks for authentication or does nothing; automatic reveals (battery low, offline) stay allowed because they are the user's own safety rules (open question: confirm).
- A successful authentication opens a grace period (default 1 minute, choose 0 to 15) so the user is not asked for every hover; Zen mode and screen lock end it.
- Pure part in Core: `RevealGate` (locked, grace deadline, source of the request) with Swift Testing.

## Plans

1. **11-01 Gate and setting**: `RevealGate` in Core with tests; wiring of every reveal path; the setting and pane row; strings in five languages; docs.

## Success criteria

See `.planning/ROADMAP.md`, Phase 11.

## Risks

- A path that reveals without the gate (there are many: hover, scroll, click, hotkeys, Shelf, search, URL, Shortcuts, rules): inventory them first and test each.
- Authentication UI from an accessory app must come to the front (the system sheet).
- Looks like security; the wording must not overclaim.
