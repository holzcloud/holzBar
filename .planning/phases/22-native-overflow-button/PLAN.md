---
phase: 22-native-overflow-button
status: planned (outline; macOS 27 only; run /gsd-plan-phase 22)
requirements: [M27-01, M27-02]
depends_on: Phase 7 (the macOS 27 backend); independent of the Automation phases
---

# Phase 22: macOS 27 native overflow button

## Goal

holzBar knows whether macOS 27's own overflow control is collapsed or expanded, and does not show the same items twice (once expanded by macOS, once in the holzBar Shelf), without ever leaving an item unreachable.

## What is known

- Source (not Apple): macOS 27 has "a native expand/collapse button for overflow icons"; "click it and the hidden items expand to the left of the notch; click again and they collapse back"; it appears when menu bar space runs out. The article names no API and says apps cannot detect or control it (badgeify.app/macos-27-golden-gate-menu-bar-changes). Treated as the only public description; everything below that goes beyond it comes from holzBar's own measurements.
- holzBar already knows the control. `MenuBarItemProvider27.readItems` reads `AXExtrasMenuBar` of every app and, in `MenuBarAgent`'s extras bar, takes the child with role `AXButton` as "the system overflow control ("<<" / ">>")" and keeps its frame (`overflowButtonFrame()`). `OverflowDetection27.isInOverflow` says an item is folded when its frame overlaps that button ("measured on macOS 27.0: while the overflow is collapsed, every folded item reports a frame stacked against the overflow button; while it is expanded, folded items are drawn and report their real frames"). `StuckOverflow27` recognises the state where macOS fails to re-lay out items after holzBar concealed apps (no button, items under the notch). `NotchCover27` keeps holzBar's own icon out from under the notch. The setting **Show items covered by the notch** (`showsNotchOverflowInShelf`, default on) lists folded items in the Shelf. `docs/macos27.md`: hiding is turned off on purpose where macOS folds items.
- So detection of *presence* exists. New is the *expanded or collapsed state* and the Shelf's reaction to it.

## Design

- **State** (pure, `holzBar/MenuBar/MacOS27/Core`, Swift Testing next to `OverflowDetection27`): `NativeOverflowState` = `.none` (no control), `.collapsed`, `.expanded`, `.unknown`. Derived from facts already read: control frame present or not; whether any item frame overlaps it (collapsed) or items that were folded now report real frames to the left of the notch (expanded); optionally the control's `AXTitle`/`AXDescription`/`AXValue` ("<<" versus ">>", K, spike to dump with `Scripts/macos27/ax-items.swift`). `.unknown` whenever the facts disagree.
- **Event-driven**: the existing `ItemChangeObserver27` and scans already follow layout changes (AX notifications and the settle logic); the state is recomputed in those passes, no new timer or observer. If the AX tree has no notification for the toggle, re-read once after a click on the control (holzBar already sees clicks in the menu bar strip) and after the bar settles.
- **Shelf** (M27-02): while `.expanded`, the Shelf omits the items that macOS shows expanded (they are on screen, so listing them again duplicates them); while `.collapsed`, `.none` or `.unknown` it lists covered items exactly as today. **Fail safe**: any doubt means today's behaviour (show them), because hiding an item that is not on screen would make it unreachable, the worse failure.
- **Concealer coordination**: when macOS has the overflow expanded, holzBar must not start concealing or revealing in a way that changes the layout under the user's click; the existing settle debounce and `StuckOverflow27` re-flow logic stay in charge. The phase adds a rule: never re-conceal while `.expanded` until the user collapses it or a short timeout (spike).
- **Setting** (question 31): keep the one existing switch (**Show items covered by the notch**), add automatic de-duplication under it; no new control unless the user prefers a three-way picker.
- **Guards**: everything lives in the macOS 27 backend files, which only run on macOS 27 (`MenuBarBackendKind`); macOS 14 to 26 code paths are not touched. Testing is on macOS 27 only (the user, and the CI launch leg); the pure state logic has unit tests on every runner.

## What breaks if detection is wrong

| Wrong result | Effect | Handling |
|---|---|---|
| `.expanded` reported while collapsed | Items vanish from the Shelf although macOS shows no overflow: covered items unreachable | Worst case; the state needs two agreeing facts, any single signal gives `.unknown`; the Shelf never drops items on `.unknown`; user can turn the de-duplication off |
| `.collapsed` reported while expanded | Items listed twice (today's behaviour) | Cosmetic; acceptable |
| `.none` while the control exists (frame read times out) | As today | Acceptable |
| A future macOS 27.x changes the control (role, position) | State becomes `.unknown` everywhere | Fail safe; a probe script (`Scripts/macos27/`) and a CI-independent checklist re-measure |

## Privacy and permission analysis

No new permission: Accessibility is already held and the control is read through the same calls. No new data. Logs: the state enum only.

## Plans (outline)

1. **22-01 Spike and measurement on macOS 27**: extend `Scripts/macos27/ax-items.swift` or add `overflow-state-probe.swift`: dump the control's AX attributes collapsed and expanded, the notifications it posts, and the frames of folded items in both states; record in `22-01-SPIKE.md` (go/no-go: if the state cannot be told reliably with two agreeing facts, stop and keep today's behaviour).
2. **22-02 State logic (pure) and tests**: `NativeOverflowState`, fixtures from the spike, `.unknown` rules.
3. **22-03 Shelf de-duplication and concealer rule**: wire the state, fail-safe, setting wording, strings in five languages, `docs/macos27.md` and README (only what the user verified).

## Risks

- macOS 27 is young; the control's behaviour may change in point releases (the repo already carries 27.0 measurements).
- Accessibility keeps frames of items that are no longer drawn (`StuckOverflow27` notes this), so frames alone can lie: hence two facts.
- Interplay with `StuckOverflow27` and `NotchCover27`: the new state must not undo their fixes.
- Needs a notched Mac on macOS 27 for every check.

## Open design question

31. **How does the Shelf react to the native overflow?** A. Keep the single switch "Show items covered by the notch" and de-duplicate automatically when macOS has the overflow expanded (**recommended**); B. A new three-way choice: always list, automatic, never list; C. Keep today's behaviour and do nothing (drop the phase after the spike).
