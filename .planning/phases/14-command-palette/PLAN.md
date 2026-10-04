---
phase: 14-command-palette
status: planned (outline; run /gsd-plan-phase 14)
requirements: [PALETTE-01, PALETTE-02, PALETTE-03]
depends_on: Phase 8 (rules to enable), Phase 13 (the AppleScript dictionary and the palette share one action catalog); every reveal action goes through Phase 18's gate
---

# Phase 14: Command palette

## Goal

A hotkey opens a Spotlight-like panel where the user types to run any holzBar action: toggle Zen mode, apply a profile, show a section, open a Settings pane, open a menu bar item, enable or disable a rule.

## Why

Bartender 7 has a Command Bar ("search and trigger any menu bar item from your keyboard", macbartender.com/Bartender7/); Thaw and holzBar have item search. holzBar's own actions are today spread over hotkeys, the menu, URL commands, Shortcuts and (Phase 13) AppleScript. One keyboard entry point makes the many small features reachable without remembering a hotkey for each. Bartender 7's clipboard history in its Command Bar is deliberately not copied (privacy, see `COMPETITORS.md`).

## Design

- **One action catalog** (`holzBar/Core`, pure, Swift Testing): `ActionCatalog` lists `HolzBarAction` values (stable id, localized title key, keywords, parameter kind: none / profile name / rule name / section / settings pane / item) and which are available now (a rule action only if rules exist; Zen-off only while Zen mode is on). The palette, the Phase 13 dictionary and the existing App Intents read the same catalog, so a new action is defined once. Execution goes through the same services as hotkeys (`HotkeyActionPerform`), not new code paths.
- **Panel**: extend `MenuBarSearchPanel`'s approach (an `NSPanel` with a SwiftUI list, closes on outside click, space or screen change) with a second model `CommandPaletteModel`. Results mix actions and menu bar items; typing filters with `FuzzyMatch` (abbreviations and typos, as in the item search). Return runs, Escape closes, arrows move, Tab completes a parameter ("apply profile" then a profile name). The first result is selected and announced.
- **Hotkey**: a new `HotkeyAction.openCommandPalette` (new raw value `"OpenCommandPalette"`; existing raw values never change), no default key, set in Settings > Hotkeys; also a menu item and an App Intent "Open command palette".
- **Ranking** (question 23-24): fuzzy score then a fixed order by category. No learning, no recent-actions list, so nothing is stored about what the user runs.
- **Gates**: actions behave exactly like their hotkeys: Zen mode and the Phase 18 lock apply to reveals; lasting changes made from the palette need no extra prompt because the user is at the keyboard (URL commands ask because another app can send them). Scripts are not run from the palette in v1, and nothing in the palette can create or edit a rule, script or setting except what the matching hotkey already does.
- **Accessibility** (full pass in Phase 21): the list is a SwiftUI `List` with real rows (VoiceOver reads title and kind), a labelled search field, the result count announced as it changes, usable with Full Keyboard Access and Voice Control, Reduce Motion respected for the open animation, high contrast borders.

## Privacy and permission analysis

No new permission: the panel is holzBar's own window, and the global hotkey uses the same Carbon registration as the others (no Input Monitoring). No network. No history. Item names are shown in the panel only, never logged.

## Plans (outline)

1. **14-01 Action catalog (Core)**: `HolzBarAction`, availability rules, parameter matching, ranking with `FuzzyMatch`; tests (abbreviations, typos, availability, deterministic order, no learning state).
2. **14-02 Panel, hotkey, intents**: `CommandPaletteModel`, panel, hotkey action and Settings row, menu item, App Intent; the dictionary of Phase 13 re-pointed at the catalog if not already.
3. **14-03 Accessibility, strings, docs**: VoiceOver and keyboard checks, five languages, README feature line, URL/Shortcuts docs.

## Risks

- A catalog that grows into a second command system: keep it a thin list over existing services.
- Global hotkey conflicts (Spotlight, Raycast use ⌘Space-like keys): none by default.
- Mixing actions and items can bury a wanted item: group headings and a prefix (">" for actions only) as a fallback.
- The panel must not take focus from a full-screen presentation unexpectedly: same panel rules as the search panel.

## Open design questions

23. **How does the palette relate to the existing item search?** A. A separate palette hotkey and panel sharing the search panel's code, results mix actions and items (**recommended**); B. Merge into the existing search panel (one hotkey); C. The palette replaces the search.
24. **Ranking?** A. Fuzzy score and a fixed order, no history (**recommended**); B. Recently used actions first (a local history of what the user ran, which is behaviour data).
