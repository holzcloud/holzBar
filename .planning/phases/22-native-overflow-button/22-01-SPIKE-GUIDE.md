---
phase: 22-native-overflow-button
plan: 22-01
type: spike-guide
status: ready for the maintainer (needs a notched MacBook on macOS 27)
---

# 22-01 Spike guide: measuring macOS 27's native overflow control

This is the checklist for the one measurement Phase 22 cannot do without a real notched Mac. You run one read-only script twice (overflow collapsed, then expanded) and send back the two outputs. About 15 minutes, most of it making the overflow appear.

The script is `Scripts/macos27/overflow-state-probe.swift`. It only reads: public Accessibility and CoreGraphics calls, no network, no private API. It never clicks, moves or changes anything; you do the one click on the overflow control yourself.

## What you need

- A MacBook with a notch (built-in display) on macOS 27. The external-display-only case is not interesting here.
- Xcode or the Command Line Tools (the `swift` command works in Terminal).
- This repository on branch `chore/phase22-probe` (or any checkout that has the script).
- **holzBar quit** for both runs, and Ice, Thaw, Bartender and similar menu bar managers quit too. holzBar conceals apps and changes the layout; this spike measures what macOS does on its own.

## Step 1: give the terminal Accessibility

The probe reads the menu bar through Accessibility, and macOS grants that to the app you start it from.

1. Open System Settings > Privacy & Security > Accessibility.
2. Click the `+` button (or find your terminal in the list), add the terminal app you use (Terminal, iTerm, Ghostty, Warp, ...) and switch it on.
3. Quit the terminal completely (Cmd-Q) and open it again; the permission is only picked up by a new process.
4. Check: `cd` to the repository and run `swift Scripts/macos27/overflow-state-probe.swift --seconds 0`. You should see a report ending in `=== end of report ===`. If you see "This terminal has no Accessibility permission", step 1 to 3 did not take: check the switch and restart the terminal.

If `swift ...` itself fails (the interpreter is picky on some setups), build it once and run the binary instead; everything below works the same:

```sh
swiftc -O Scripts/macos27/overflow-state-probe.swift -o /tmp/overflow-probe
/tmp/overflow-probe --label collapsed 2>&1 | tee ~/Desktop/overflow-collapsed.txt
```

(Accessibility then has to be granted to the terminal that runs it, as before.)

## Step 2: make the native overflow appear

macOS 27 shows its own expand/collapse button only when the menu bar runs out of room beside the notch (see PLAN.md, "What is known"). To run out of room:

1. Put the Mac on its built-in display with the notch, and leave the menu bar always visible (System Settings > Control Center > "Automatically hide and show the menu bar": Never).
2. Open many menu bar apps. Start everything you have that lives in the menu bar (clipboard managers, VPN, cloud sync, password manager, system monitor, a timer that shows text, ...).
3. Make the system items wide: System Settings > Control Center, set every item that offers it to "Show in Menu Bar" / "Always" (Bluetooth, Sound, Focus, Display, Now Playing, Battery with percentage, Keyboard Brightness, ...).
4. Make the frontmost app's menu long: an app with many menus (Xcode, a browser) leaves less room than Finder. Pick one app and keep it frontmost for both runs.
5. Keep adding until a button appears at the left edge of the notch (the article calls it an expand/collapse button; holzBar's code calls it "<<" / ">>"), and icons are missing from the bar.

If the button never appears, run Step 3 once anyway with `--label none` and send that output: it is the no-overflow baseline and still tells us what MenuBarAgent reports. Then say so in your message.

## Step 3: run 1, overflow collapsed

1. Get the overflow into the **collapsed** state: the folded icons are hidden and the button is in its "closed" look. Click the button until that is so. Do not touch anything else afterwards.
2. In the terminal, in the repository:

   ```sh
   swift Scripts/macos27/overflow-state-probe.swift --label collapsed 2>&1 | tee ~/Desktop/overflow-collapsed.txt
   ```

3. The script prints a BEFORE report (about a second), then a line `>>> NOW: click the overflow control ONCE <<<` and listens for 20 seconds. Click the overflow button **once** (it should expand), then leave the pointer alone: no other click, no menu, no app switch. The script ends with an AFTER report and a diff.
4. Leave the overflow **expanded** when it finishes.

## Step 4: run 2, overflow expanded

1. The overflow is expanded from run 1. Same frontmost app, same menu bar apps running, same displays.
2. Run:

   ```sh
   swift Scripts/macos27/overflow-state-probe.swift --label expanded 2>&1 | tee ~/Desktop/overflow-expanded.txt
   ```

3. When the `>>> NOW` line appears, click the button **once** (it should collapse) and leave the pointer alone.

Optional, if you have time: run 3 with holzBar running and its overflow-related settings at default (`--label collapsed-holzbar`, no click needed: add `--seconds 0`). It shows how holzBar's own concealment changes what Accessibility reports.

## Step 5: send the outputs

- The files are `~/Desktop/overflow-collapsed.txt` and `~/Desktop/overflow-expanded.txt`. Paste both into the chat (or `pbcopy < ~/Desktop/overflow-collapsed.txt`, paste, then the same for the other file). Each is a few hundred lines; the start (header with the macOS build) and the end (diff, event counts, FACTS lines) matter most, but send all of it.
- Optional but useful: a screenshot of the menu bar around the notch in each state (Cmd-Shift-4 and drag), and the macOS build shown in the report header (`build=...`), which you do not have to type.
- The report contains the bundle identifiers and the titles of your menu bar apps. If you would rather not share them, add `--redact` to both commands; non-Apple apps then show as `app1`, `app2`, ... and their titles and descriptions as `<redacted>` (the numbering is consistent inside one run only). The Apple items, which are what matters, stay readable.
- Nothing leaves the Mac by itself. The script has no network access.

## What the report contains

| Section | Meaning |
|---|---|
| Header | macOS version and build, Mac model, each display with its notch span |
| `CONTROL found ...` and `attr ...` lines | Every Accessibility attribute of the overflow control (role, subrole, title, description, identifier, value, frame, enabled, ...), its actions and which of them are settable |
| `MenuBarAgent extras bar`, `AX windows`, window list | What MenuBarAgent exposes around the control, including its windows' bounds |
| `ITEMS` table | Every extras-bar item: frame, display, flags `C` (overlaps the control, holzBar's folded test), `N` (under the notch), `L`/`R` (left or right of it), `Z` (zero size), `O` (at the origin), `hit=` (does a hit test at its centre find that very item) |
| `FACTS` line | Counts of the above, one line per snapshot, to compare quickly |
| `OBSERVING ...` | Which notifications the control and MenuBarAgent accept, so which ones they can post |
| `EVENT` and `POLL` lines | The notifications that actually arrived during your click, with times, and when the control or the item frames changed |
| `DIFF` | What changed between BEFORE and AFTER in the control's attributes and the items' frames |

## What each result decides

The plan's go/no-go (22-01) is: can the expanded and collapsed state be told apart reliably with **two agreeing facts**? If not, stop and keep today's behaviour (open question 31, option C).

| What the two runs show | Decision |
|---|---|
| The control is found (role `AXButton` in MenuBarAgent's extras bar) in both states | The way holzBar already finds the control stays; `NativeOverflowState` can use its presence and frame |
| `title`, `description`, `value` or `identifier` of the control differs between collapsed and expanded | That attribute is fact 1 (the "<<" versus ">>" idea in the plan); its exact strings become fixtures in 22-02. If they are localised, we only compare "changed", never the text |
| Those attributes are identical in both states, only the frame (or nothing) differs | No attribute fact; the state has to come from frames and hit tests alone. Go only if two of those agree |
| The control disappears when expanded (or when collapsed) | Presence is part of the state, and `.none` (no overflow at all) must then be told apart from `.expanded` by something else, for example the frames of the formerly folded items |
| No control found at all (`CONTROL not found`) | Look at the printed tree and candidates list: if the control sits elsewhere (another role, a window child), the query in `MenuBarItemProvider27` changes; if Accessibility does not expose it, **no-go** |
| Collapsed: several items have flag `C` and the `FACTS` line has `stackedPairs` above 0; expanded: `overlapControl=0` and those items have real frames (flags `L`) | `OverflowDetection27`'s measured rule holds, and "folded items report real, separated frames" is fact 2: **go** |
| Folded items report no frame, a zero size or the origin (`noFrame`, `zeroSize`, `atOrigin` above 0 while collapsed) | The overlap test cannot see them; the state must use their absence, which is a weaker fact; treat it as one signal only |
| Folded items keep their old frames in both states | Frames alone lie (the plan's risk); only the `hit=` result can separate them. Go only if `hitConfirms` clearly differs between the states, otherwise **no-go** |
| `hit=self` for the items that are on screen and `hit=other(...)` for folded ones, in collapsed | The hit test is a usable independent fact 2 (it costs one Accessibility call per item; the plan then uses it on the few items near the control only) |
| `EVENT` lines (`AXMoved`, `AXResized`, `AXValueChanged`, `AXLayoutChanged`, `AXCreated`, `AXUIElementDestroyed`, ...) arrive from MenuBarAgent or the control when you click | Event-driven: 22-02/22-03 add an observer for MenuBarAgent next to `ItemChangeObserver27` and recompute the state on those notifications, no timer |
| No `EVENT` line at all, but `POLL ... changed` lines appear | No notification exists for the toggle: the fallback in the plan applies (re-read once after a click on the control and after the bar settles); the time of the last `POLL` change after your click sets the settle delay |
| Last `EVENT` or `POLL ... changed` comes more than about 1 s after the click | The layout animates; the state must only be read after a settle debounce of that length, and the Shelf must keep today's behaviour meanwhile |
| The control lists an `AXPress` action | Not used in this phase (holzBar does not toggle the control), but recorded: a later phase could offer to toggle it |
| Items with flag `N` (under the notch) in either state | The overlap with `StuckOverflow27` and `NotchCover27` is real on this build; 22-03 must not undo their fixes |
| `FACTS` or the control differ between the two builds if you test on more than one macOS 27.x | The probe is the re-measure tool the plan names for point releases; keep both outputs as fixtures with their `build=` |

What happens next: I turn the two outputs into `22-01-SPIKE.md` (the record, with the go/no-go), then plan 22-02 builds `NativeOverflowState` and its tests from the measured values, or the phase is dropped.

## If something looks wrong

- "This terminal has no Accessibility permission": see Step 1; the terminal must be restarted after switching the permission on.
- `CONTROL not found` in both runs, but you can see the button: the report then prints MenuBarAgent's Accessibility tree and a candidates list; send it as it is, that is exactly what is needed.
- The click did not toggle the overflow: run the same command again and click once more; each run only needs one toggle.
- The run takes long: apps that do not answer Accessibility cost up to 0.4 s each; that is expected with many menu bar apps.
- The script prints at most 300 notifications individually; the counts below them are complete.
