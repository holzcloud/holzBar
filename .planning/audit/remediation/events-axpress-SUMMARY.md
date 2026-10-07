---
chain: events
part: axpress
findings: [F-36]
decision: decisions/axpress-1.md — "Zeitablauf als Erfolg werten (Recommended)"
status: complete
---

# events / axpress: F-36 Summary

A hidden item's Accessibility press that runs into the 0.25 s messaging timeout now counts as taken, so holzBar no longer shows the item and clicks it again while its menu is open. The press also no longer leaves the short timeout on the macOS 27 provider's shared element.

## F-36: a menu-opening AXPress was treated as a failure

**Maintainer's decision:** treat the timeout as success (the window-based option was rejected).

**Cause.** With "Open hidden items in the menu bar" off, `pressWithoutShowing` accepted only `.success`. A status item's press blocks while its menu is open, so a press that opened a menu came back `.cannotComplete` after 0.25 s. `openItem` then fell back to showing the item and clicking it (`ItemClicker27.click` on macOS 27, `temporarilyShow` on macOS 26), which closed the menu again or made it jump. On macOS 27 the 0.25 s timeout also stayed on the provider's stored element (`MenuBarItemProvider27.element(forWindowID:)`), against the rule at `MenuBarItemProvider27.swift:126-128`.

**Fix.**
- New pure rule `holzBar/Core/HiddenItemPress.swift`. `HiddenItemPress.isTaken(_:elapsed:timeout:)` counts `.success` as taken. It also counts a `.cannotComplete` that came back after at least 80 % of the timeout (0.2 s of 0.25 s) as taken. An immediate `.cannotComplete`, any other error (`.failure`, `.actionUnsupported`, `.invalidUIElement`) and a missing element are not taken, so those keep today's fallback. The timeout is the one named constant `HiddenItemPress.timeout` (250 ms). HolzBarCore needs no AX import: the app maps `AXError` to a small `Result` enum.
- `ItemOpener.pressWithoutShowing` times `AXUIElementPerformAction` with `ContinuousClock`. Right after the press returns, in the same dispatch block, it resets the element's messaging timeout to 0 (the global default). That restores the macOS 27 shared element to the state the provider left it in. This is the convention F-57 proposes. A press that ran into the timeout is logged at debug level. The extras-menu-bar lookup on macOS 26 uses the same constant instead of literal `0.25`s.
- Doc comments of `openItem`, `pressWithoutShowing` and `AdvancedSettings.openHiddenItemsInMenuBar` now say that a press blocked by the open menu counts as taken.
- Regression tests: `Tests/HolzBarCoreTests/HiddenItemPressTests.swift` (5 tests). They cover success, a timed-out cannotComplete, an immediate cannotComplete, other errors (actionUnsupported/failure) and a threshold that follows the timeout.

**Known trade-off (accepted by the maintainer).** When an app hangs, nothing visible happens. Today's fallback click does not open a hung app's menu either. A press that returns `.success` but opens nothing (possible for concealed items on macOS 27) is still not covered. That is a separate follow-up.

**Files:** `holzBar/Core/HiddenItemPress.swift` (new), `Tests/HolzBarCoreTests/HiddenItemPressTests.swift` (new), `holzBar/MenuBar/MenuBarItems/ItemOpener.swift`, `holzBar/Settings/Models/AdvancedSettings.swift`.

## Gates

| Gate | Result |
| ---- | ------ |
| `appcheck.sh` (whole app, Swift 6, macOS 26.5 SDK) | ERRORS: 0 |
| `servicecheck.sh` | SERVICE EXIT: 0 |
| `swift test` (full) | 300 + 136 + 6 tests passed (baseline 295 + 136 + 6). The first three runs hit the known "TestingMacros plugin not found" transient; the fourth passed. |
| `swiftlint lint --strict --quiet` | no output, exit 0 |
| `privacy-check.py network`, `privacy-check.py logs`, `strings-check.py` | pass (no new strings) |
| Former name check | no matches |

## User test steps

1. In Settings > Advanced, turn off "Open hidden items in the menu bar".
2. Hide an item that opens a menu (for example a third-party app's status item) in the hidden section.
3. Open the item from the holzBar Shelf. Its menu opens and stays open, and the item does not appear in the menu bar.
4. Close the menu, then open the same item with its hotkey. The result is the same.
5. Right-click the item in the Shelf. Its secondary menu stays open and the item does not appear.
6. Repeat steps 3 to 5 on macOS 27 (the maintainer has to do this; this Mac runs macOS 26).
7. Check an item whose app does not support the press (an item that does not open from the Shelf without showing it). It is still shown and clicked as before.

## Doc updates needed

- `docs/release-notes/v0.0.7-beta2.md` (to be written, with the F-01 and F-13 lines), under Fixed: add a line. v0.0.7-beta1 is tagged and released, so its notes stay as they are. Suggested text: "With "Open hidden items in the menu bar" off, a hidden item's menu now stays open, and the item no longer appears in the menu bar and gets clicked again."
