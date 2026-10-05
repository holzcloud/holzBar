# Remediation: appearance / split-shape (F-39)

Branch `audit-manual/appearance-split`, based on `audit/remediation-2026-10-05`.

## F-39: on macOS 27 the Split menu bar shape always fell back to the full shape

**Maintainer decision:** compute the right half again on macOS 27 ("Rechte Hälfte neu berechnen"). The alternatives, hiding Split on macOS 27 or only showing a note, were rejected.

**Cause:** `MenuBarOverlayPanel.pathForSplitShape` sized the trailing half from the total width of the WindowServer item windows (`MenuBarItem.getMenuBarItemWindows`). macOS 27 has no such windows, so the trailing bounds were always `.zero` and the full-shape branch ran every time.

**Fix:**
- `ItemHitTest27` (package target `HolzBarMacOS27Core`): the edge computation in `isInsideItemsArea` moved into the pure function `itemsAreaLeftEdge(displayBounds:items:concealedPIDs:systemFrames:rememberedLeftEdge:drawnFramesOnDisplay:) -> CGFloat?`. `isInsideItemsArea` now returns `point.x >= edge`, and its behaviour is unchanged.
- `MenuBarBackend` has a new method, `itemsAreaLeftEdge(on:appState:) -> CGFloat?`. `WindowListBackend` returns `nil`, and `ServiceBackend26` forwards to it. `AccessibilityBackend27` builds the edge from the same inputs as its `isInsideItemsArea`: the managed items in the item cache, `concealer27.concealedPIDs`, the system frames including the overflow chevron, `MenuBarItemProvider27.leftEdge(for:)` and `drawnFrames(for:)`. Every input is a cached value behind a lock or on the main actor, so no Accessibility call runs while the view draws.
- `pathForSplitShape`: when the backend returns an edge, `position = edge - screen.frame.minX`, then -7 without the inset, or +4 - `menuBarInsetAmount` with it. Otherwise the existing window-width path runs unchanged (macOS 14, 15 and 26). If the edge is `nil` or the two halves overlap, the full shape is still drawn.
- **Padding note (deliberate adaptation of the implementation note):** the old code got the trailing x as `rect.maxX - totalWidth`. With the inset and a round trailing end cap, `rect.maxX` is already shifted left by the inset amount, which is why the old code subtracted the inset only for the square cap. An absolute edge does not move with `rect`, so the inset is subtracted for both caps. This puts the trailing half where macOS 26 draws it. The constants may still need tuning on macOS 27.
- Redraws: the content view already redraws when `itemCache`, `concealedPIDs` or a section's `isHidden` changes. Concealer27 refreshes the cache 400 ms after it applies a change, so the shape briefly catches up after a reveal or hide. The maintainer accepted this.

**Tests:** a new suite, "Items area left edge" in `Tests/HolzBarMacOS27CoreTests/Plan2Core27Tests.swift`, covers the active display, the inactive display through drawn frames, concealed PIDs being excluded, the overflow button being included, and `nil` when nothing is known (including a remembered edge from another display). The existing ItemHitTest27 and Items zone tests still pass.

## Review fix-ups

- **F39-R1 (redraw after a hide):** concealed items keep their old frames and the visible ones do not move, so the read 400 ms after an apply left the item cache equal and nothing redrew the shape. `MenuBarItemProvider27.items()` now compares the edge's inputs (remembered left edges, drawn frames per display, system and overflow frames) before and after each read and posts `menuBarItemsAreaDidChange27` on the main thread when they changed. The overlay panel redraws its content view on it.
- **F39-R2 (inactive display):** `SplitShape27.leftEdge` (HolzBarMacOS27Core) leaves out the remembered edge once MenuBarAgent's drawn frames for the display are known, so a section concealed again since no longer widens the trailing half there. Hover hit-testing (`isInsideItemsArea`) keeps its behaviour, as the decision requires.
- **F39-R4 (geometry):** `SplitShape27.trailingBounds` computes the macOS 27 position and padding and returns `.zero`, the full-shape fallback, when the half would be narrower than it is high or start left of the shape. Tests cover both trailing end caps with and without the inset.
- **F39-R3 (release notes):** the Fixed line below is still open. This chain may not edit `docs/`; it must go into `docs/release-notes/v0.0.7-beta2.md` when that file is written, before the beta is tagged.

## Gates run (all passed)

- appcheck.sh (label f39): ERRORS: 0
- servicecheck.sh: SERVICE EXIT: 0
- `swift test`: full run, 266 tests in 45 suites passed
- `swiftlint lint --strict --quiet`: no output, exit 0
- privacy-check.py network and logs, strings-check.py: passed (no new strings)
- Former-name check: no matches

## User test steps (macOS 27, partly possible only there)

1. Settings > Menu Bar Appearance > Shape Kind "Split". Check that the right shape sits cleanly around the icons, from the leftmost visible item to the right edge.
2. Repeat with "Inset" on and off on a display with a notch, and with round and square trailing end caps.
3. Reveal and hide the hidden section (click and Show on hover). After a short catch-up (about 0.4 s) the right shape should follow the icons, after a hide as well as after a reveal, without switching apps.
4. With a second display whose menu bar is not active, check the right shape there too. Reveal the hidden section while that display is active, hide it again from the other display, and check that the right shape on the inactive display shrinks back.
5. With enough items that some fold behind the system chevron, check that the chevron is inside the right shape.
6. On macOS 26, check that Split looks exactly as before (regression check).

## Documentation updates needed

- **Open, required before the next beta is tagged:** `docs/release-notes/v0.0.7-beta2.md` does not exist yet. Add a Fixed line, for example "The Split menu bar shape now works on macOS 27 instead of falling back to the full shape."
