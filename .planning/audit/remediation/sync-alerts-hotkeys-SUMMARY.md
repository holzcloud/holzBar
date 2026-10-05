---
phase: audit-remediation-sync-alerts
plan: hotkeys
subsystem: hotkeys
tags: [hotkeys, settings, ui, l10n]
requirements: [F-30]
status: complete
key-files:
  created: []
  modified:
    - holzBar/UI/Views/HotkeyRecorder.swift
    - holzBar/Settings/Models/HotkeysSettings.swift
    - holzBar/Settings/SettingsPanes/HotkeysSettingsPane.swift
    - holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - holzBar/Core/HotkeyStorage.swift
    - Tests/HolzBarCoreTests/HotkeyStorageTests.swift
    - holzBar/Resources/Localizable.xcstrings
completed: 2026-10-05
plan_head_before: 570b6e5e
actuals:
  tasks: 1
  commits: 1
---

# Chain sync-alerts, part hotkeys: ask before moving a hotkey combination another hotkey already uses (F-30)

The maintainer chose **"Nachfragen und ersetzen"** (decision `hotkey-conflicts-1.md`). If you
type a combination that another holzBar hotkey already uses, the recorder now asks:
"Hotkey already in use: “<name>” already uses this combination. Use it here instead?". Replace
(the default button) moves the combination to this row. Cancel keeps recording, so you can type
another combination. The row always shows the stored combination, and its Clear button clears it
again.

## Commit (branch audit-manual/sync-alerts, base 570b6e5e)

| Commit | Findings | Subject |
|--------|----------|---------|
| (this commit) | F-30 | fix(hotkeys): resolve F-30 — ask before moving a combination another hotkey uses |

## F-30: what was done

Cause: the recorder checked only the system's reserved shortcuts and Option-only combinations.
The system registers a combination only once per app, so `RegisterEventHotKey` refused the
duplicate (-9878). The hotkey stayed unregistered (`isEnabled == false`), but its combination
was still saved. The row's label and Clear button depended on `isEnabled`, so the row showed
"Record Hotkey" and could not clear the combination.

Fix:
- **Holder lookup**: `HotkeysSettings.hotkey(using:except:)` searches the action and dynamic
  hotkeys. It compares stored combinations, not registrations, so it also finds the
  always-hidden section's hotkey while that section is off. It excludes the recording hotkey
  by target. Targets are unique in the list, so this is the same as excluding by identity,
  and it also works for undo, where no `Hotkey` object exists yet.
- **Recorder** (`HotkeyRecorder.swift`): after the system-reserved check, a holder leads to the
  new `.alreadyUsed(holder:holderName:keyCombination:)` problem. `Problem` now has associated
  values, and the alert's buttons depend on the problem: Replace and Cancel for `.alreadyUsed`,
  OK for the others. Replace clears the holder first, then assigns the combination.
- **Revert path**: the combination from the start of recording is saved. If the hotkey is still
  unregistered after an assignment, it gets its old combination back, stays disabled while
  recording continues, and the new `.registrationFailed` alert appears. When this happens during
  Replace, the holder gets its combination back too. It is registered again only if it was
  registered before. The failure alert is set one main-actor turn later, because the Replace
  alert is still closing.
- **Label and Clear button** depend on `hotkey.keyCombination != nil`. The unreachable
  "ERROR" label and its catalog entry are removed.
- **Holder names**: the action titles moved from `HotkeysSettingsPane` into
  `HotkeyAction.title` (same catalog keys, so the existing translations still apply). Profiles
  show their name and items their `displayName`, or their key when the item is not in the menu
  bar (`HotkeysSettings.name(of:)`). The pane's item rows use the same function.
- **Wiring**: `HotkeyRecorder(hotkey:settings:label:)` gets `HotkeysSettings` explicitly from the
  pane and from the item popover (`ItemHotkeyView`). It does not use `@Environment(AppState.self)`,
  because the popover's hosting controller has none.
- **Load-time cleanup**: `HotkeysSettings.loadInitialState` collects the stored hotkeys in load
  order (actions first, then profiles and items by storage key). It skips any hotkey whose
  combination an earlier one already uses and removes that hotkey's stored key. The log names
  only `target.logDescription`. The pure rule is
  `HotkeyStorage.duplicateStorageKeys(inLoadOrder:)` in Core, with two new tests.
- **Undo** (`LayoutProfiles.restore`): a profile's hotkey is not restored if another hotkey took
  its combination in the meantime. Renaming is safe as it was, because `moveHotkey` removes the
  old key first.
- **Alert convention** (from the alerts part): the prompt is a SwiftUI `.alert`, which AppKit
  shows as a sheet on the window that hosts the recorder. For the Hotkeys pane, that is the
  Settings window. Nothing runs `runModal()`, so no Task blocks. In the item hotkey popover
  (Menu Bar Layout > item menu > Set Hotkey…), the alert attaches to the popover, as the
  existing recorder problems already do.
- F-29, F-93 and F-94 were already on the base branch (`.onDisappear` stops recording, only one
  recorder records at a time, the monitor passes key presses through while an alert is shown).
  F-94's guard also covers the new alerts.

New strings (en, de, fr, it, rm): "Hotkey already in use", "“%@” already uses this combination.
Use it here instead?", "Replace", "Hotkey could not be registered", "macOS did not accept this
combination. Choose another one.". "Cancel" and "OK" already existed. "ERROR" was removed.

## Gates run (all passed before the commit)

- `appcheck.sh … hotkeys`: ERRORS: 0 (whole app module, Swift 6, macOS 26.5 SDK). No warnings
  in the changed files.
- `servicecheck.sh`: SERVICE EXIT: 0.
- `swift test`: 315 tests in 47 suites passed, including the 2 new HotkeyStorage tests.
- `swiftlint lint --strict --quiet`: no output, exit 0.
- `privacy-check.py network`, `privacy-check.py logs`, `strings-check.py`: passed (377 strings
  in 5 languages).
- Former-name check: no match.

## User test steps

1. Settings > Hotkeys: give "Search menu bar items" ⌃⌥⌘K. Then record ⌃⌥⌘K for "Zen mode".
   A sheet "Hotkey already in use" names "Search menu bar items". Press Return (Replace).
   "Zen mode" now shows ⌃⌥⌘K, "Search menu bar items" shows "Record Hotkey", and ⌃⌥⌘K toggles
   Zen mode.
2. Repeat, but choose Cancel. The row keeps recording ("Type Hotkey"). Type another combination
   or press Escape. "Search menu bar items" keeps ⌃⌥⌘K.
3. Save a layout profile, give it the combination of an action in Settings > Hotkeys, and choose
   Replace. The profile's hotkey applies the profile, and the action row is empty.
4. In Menu Bar Layout, open an item's menu > Set Hotkey…, and type a combination another hotkey
   uses. The same question appears in the popover. After Replace, the item hotkey opens the item
   and appears in Settings > Hotkeys.
5. Turn on the always-hidden section and give its toggle a hotkey. Turn the section off, then
   type that combination for another row. The question names "Toggle the always-hidden section".
   After Replace, turn the section back on: its toggle row is empty and the other row works.
6. Every row with a combination shows it, and its x button clears it.
7. Optional, to test the load cleanup (a test Mac only): write two hotkeys with the same
   combination into the `Hotkeys` setting, for example with an imported settings file, and
   relaunch. Only the first one in load order keeps the combination; the other row is empty.
8. Switch the system language to German, French, Italian or Romansh and repeat step 1. The texts
   are translated.

## Deviations from Plan

- The decision suggested excluding the recording hotkey by identity (`!==`). The lookup excludes
  it by target instead (`except: HotkeyTarget`), which is equivalent because targets are unique.
  Undo can then use the same lookup.
- The "ERROR" catalog entry was removed, because its only use went away.

## Scope note

The relayed user message ("Können wir das mit dem signieren nicht doch anders lösen?") is about
release signing. This part touches no signing, release workflow or secret. The question belongs
to the release chain and should be answered for the maintainer there.

## Self-Check: PASSED
