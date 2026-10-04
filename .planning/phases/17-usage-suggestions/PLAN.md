---
phase: 17-usage-suggestions
status: planned (outline; run /gsd-plan-phase 17)
requirements: [USAGE-01, USAGE-02, USAGE-03, USAGE-04]
depends_on: Phase 16 (which items are informational and never suggested), Phase 9 (snapshot before accepting a suggestion)
---

# Phase 17: Local usage suggestions

## Goal

holzBar can notice which visible items the user has not clicked for a long time and suggest hiding them. The user opts in; only counters are kept; they stay on the Mac and can be forgotten with one click.

## Why

It answers "what should I hide?" with the user's own behaviour instead of guesses (Phase 16 covers the first launch without behaviour). It is also the feature most likely to look like tracking, so the design is built around being visibly small: what is stored is shown to the user in full.

## Strict privacy design

| Rule | Decision |
|---|---|
| Opt-in | **Off by default.** Offered on the last page of the Phase 16 assistant and in Settings; never as a pop-up or notification (question 20). Turning it off deletes the data. |
| What is stored | Per item identity (`ItemIdentity` key) a count per **calendar day** (an integer for each of the last 30 days). No timestamps within a day, no sequences, no durations, no window titles, no menu contents, no screen content. Plus a per-item "dismissed suggestion" flag. |
| Where | `~/Library/Application Support/holzBar/Usage.json`, mode 0600, written at most once per minute and on quit. **Excluded from backups** (`isExcludedFromBackup`, documented for support files "not needed in a backup", V; question 22) so Time Machine does not archive behaviour data. |
| Never | Exported, imported, synced, put in snapshots (Phase 9), in diagnostics (Phase 20 reports only "usage suggestions: on/off" and the number of items), in logs, or in the shared-profile file (Phase 15). `SettingsSchema` gets no key for it (it is not a setting). |
| See and erase | The Settings row shows exactly what is held ("42 items, 30 days, 1,204 clicks") with a **View Data** list (item, last 30 daily counts) and **Forget Everything**, one click, no confirmation maze. |
| Retention | Days older than 30 are dropped on every write. |

## How clicks are seen without extra cost

- No new event tap and no additional permission: holzBar already has a passive global mouse-down monitor in `HIDEventManager` (`mouseDownMonitor`, used for show-on-click and smart rehide) and `MenuBarHitTesting.swift` for locating the item under the cursor. When the feature is on, a mouse-down **inside the menu bar strip** is resolved to an item with the existing hit testing and counted; mouse moves are never involved, and the work is a dictionary increment. When the feature is off, the code path does not exist (no monitor is kept alive for it).
- Opens that pass through holzBar itself (the Shelf, the search, "open by letter", the Phase 14 palette) already know the item (`ItemOpener`) and count there with no hit test.
- On macOS 27 clicks go through the bridges (`SystemItemClickBridge27`, `ItemClicker27`); counting hooks the same resolved-item point, spike on a Mac to confirm.
- Cost budget (measured in Phase 17's check): no wake-ups with no clicks; one hit test per click in the menu bar.

## Suggestion logic (pure, `holzBar/Core`, Swift Testing)

`UsageSuggester`: an item is suggested for Hidden when the feature has observed at least **14 days** (since opt-in), the item was in the visible section for those days, has **zero clicks in the last 14 days**, is not informational (live-value or Apple essentials, from Phase 16's classifier), was not dismissed, and is not controlled by an item rule (Phase 10). Constants are named and tested at their edges. Items already hidden are never "suggested to show": hidden items are used when revealed, and a revealed click counts as a use.

## UI

A "Suggestions" section in the Menu Bar Layout pane (non-modal, quiet): "You haven't clicked these in 14 days: <icon> Name  [Move to Hidden] [Keep]". Accepting takes a snapshot first (Phase 9). No badge, no notification, no menu bar blinking.

## Permission analysis

None new. Reuses Accessibility-based event monitoring that already exists. No network.

## Plans (outline)

1. **17-01 Counters store and suggester (Core)**: day-bucket model, 30-day rolling window, forget, `UsageSuggester` with tests (window edges, dismissal, informational exclusion, opt-in start date, clock changes and time zones: buckets use a fixed calendar day count so travel does not corrupt them).
2. **17-02 Capture and storage**: hook into the existing click handling and `ItemOpener`, atomic 0600 file, backup exclusion, off = no monitor and no file; a test that nothing is written while off.
3. **17-03 Settings, data viewer, suggestions UI, strings, privacy docs**: five languages, README privacy section, `privacy-check.py` additions to prove no usage data reaches logs.

## Risks

- Looks like tracking to users and reviewers: the viewer, forget button and opt-in default are the answer; the README must say what is and is not stored.
- Hit-test errors (multi-display, notch, macOS 27) could count the wrong item: count only when the hit test is unambiguous.
- Behaviour data is sensitive even locally: backup exclusion and 0600, and never in any export path (a CI test lists every writer of exported data).
- Misleading suggestions for items that are used by looking (monitors) or via hotkey: the informational list and the dismiss flag.

## Open design questions

20. **How is the feature offered?** A. Off by default; offered on the assistant's last page and in Settings (**recommended**); B. Settings only; C. Ask once after two weeks of use (a prompt about tracking, not recommended).
21. **Observation window?** A. At least 14 days observed, no click in the last 14, keep 30 days (**recommended**); B. 30 days of silence; C. 7 days.
22. **Backups?** A. Exclude the counters file from backups (**recommended**); B. Include it.
