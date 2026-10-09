---
status: testing
phase: 23-liquid-glass-transparency
source: [23-01-SUMMARY.md, 23-02-SUMMARY.md, 23-03-SUMMARY.md]
started: 2026-10-09T11:22:00Z
updated: 2026-10-09T11:22:00Z
---

## Setup

Nothing in this file has been observed: the Mac it was written on has no Xcode and cannot run macOS 26 or 27 UI. Every result is `[pending]` until the maintainer runs the item.

Install a build of branch `release/0.0.7` with this phase's commits (the CI build of the milestone's pull request, or `Scripts/install.sh` on a Mac with Xcode) on a Mac with macOS 26 and on one with macOS 27. The two options are in System Settings, Accessibility, Display ("Reduce transparency", "Increase contrast"). In holzBar: Settings, Appearance, Tint, System Glass. Run each item on macOS 26 and on macOS 27 unless it says otherwise, and give one result per item: `issue` if either version fails, with the version named. macOS 14 and 15 are not part of this UAT (the Shelf part also runs there; the CI launch legs show that holzBar starts).

## Current Test

number: 1
name: U-01 System Glass, options off
expected: |
  The bar shows the system's glass as in 0.0.7-beta2, with no added line
awaiting: user response

## Tests

### 1. U-01 System Glass, options off
steps: Tint: System Glass, both options off
expected: The bar shows the system's glass as in 0.0.7-beta2, with no added line
result: [pending]

### 2. U-02 Reduce Transparency turns the glass opaque, live
steps: With System Glass chosen, turn Reduce transparency on and watch the menu bar without touching holzBar
expected: Within about a second the glass becomes an opaque bar in the window background colour with a thin visible line along its edge; the application menu and every menu bar item stay visible and clickable; holzBar was not restarted
result: [pending]

### 3. U-03 Reduce Transparency off brings the glass back, live
steps: Turn Reduce transparency off
expected: The glass returns and the added line is gone, without a restart
result: [pending]

### 4. U-04 Increase Contrast
steps: Reduce transparency off, Increase contrast on
expected: The same opaque bar and line as in U-02, the line visibly stronger; the application menu and the items stay visible and clickable
result: [pending]

### 5. U-05 Shapes
steps: An option on; Shape: Full, then Split with rounded ends (on a Mac with a notch also "Use inset shape on screens with notch")
expected: The opaque fill and the line follow the shape's outline and nothing is painted outside it
result: [pending]

### 6. U-06 A border you configured stays
steps: An option on; Border on with a colour, width 2, style Dashed
expected: Your border is drawn as configured and no second line is added; with Border off the thin visible line appears
result: [pending]

### 7. U-07 Dynamic appearance
steps: Dynamic Appearance with System Glass in light and in dark; an option on; switch the Mac between light and dark
expected: The opaque bar follows the mode (light fill in light, dark fill in dark) and keeps its visible line
result: [pending]

### 8. U-08 Other tints are unchanged
steps: An option on; Tint: Solid, Gradient, Follow Wallpaper, None in turn
expected: Each draws as it does with the option off (a translucent tint over the bar) and no line is added
result: [pending]

### 9. U-09 The Shelf, options on and off
steps: An option on; open the holzBar Shelf (hover an empty spot of the bar, or click the holzBar icon); then turn the option off and open it again
expected: On: an opaque background with a visible line and legible items. Off: as before, with a line only if you configured a border
result: [pending]

### 10. U-10 The Shelf follows an option while open
steps: Open the Shelf, then toggle Reduce transparency or Increase contrast without closing it (Option-Command-F5 opens the Accessibility Shortcuts panel; if it does not offer the option, toggle it in System Settings and note whether the Shelf is still open)
expected: The line appears and disappears while the Shelf stays open. If the Shelf closes when the setting changes, note that as an observation; reopening it must then show the right look
result: [pending]

### 11. U-11 The Shelf line on light and dark wallpapers
steps: Increase contrast on; open the Shelf over a light and over a dark wallpaper
expected: The line is clearly visible on both
result: [pending]

### 12. U-12 Idle cost
steps: System Glass chosen, options unchanged, Shelf closed; Activity Monitor, CPU, the holzBar row, for one minute
expected: holzBar stays at 0.0 % CPU when nothing happens; nothing wakes it periodically
result: [pending]

### 13. U-13 The Liquid Glass slider and the probe (macOS 27 only)
steps: `swiftc -O Scripts/macos27/glass-signals.swift -o /tmp/glass-signals`, then `/tmp/glass-signals --all-notifications`; open System Settings, Appearance; move the Liquid Glass slider across its three steps and back; stop with Ctrl-C; paste the output under "Observations" in `23-01-SPIKE.md`; also look at holzBar's System Glass bar while you move it
expected: The observation is recorded in the note and nothing is claimed beyond it. If `reduceTransparency` or `increaseContrast` flips at a step, say which: the docs may then say that step turns the option on. A notification name that appears in no SDK header is recorded and never used
result: [pending]

### 14. U-14 The wording in five languages
steps: Settings, Appearance with System Glass chosen shows one sentence under the tint picker; read it in English and, if you like, in German, French, Italian and Romansh (`open -a holzBar --args -AppleLanguages "(de)"`, then fr, it, rm)
expected: The sentence reads naturally and names the options as System Settings does; report any wording you would change (the Romansh text is a proposal)
result: [pending]

## Summary

total: 14
passed: 0
issues: 0
pending: 14
skipped: 0
blocked: 0

## Gaps

[none yet]
