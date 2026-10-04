---
phase: 13-applescript-dictionary
status: planned, selected by the user 2026-10-04 (outline; run /gsd-plan-phase 13)
requirements: [ASDICT-01, ASDICT-02, ASDICT-03]
depends_on: Phase 8 (rules), Phase 12 (final feature set); every reveal command goes through Phase 18's gate
research: .planning/research/COMPETITORS.md (gap 7)
---

# Phase 13: AppleScript dictionary

## Goal

holzBar can be driven from AppleScript, JXA, Script Editor and `osascript` with a small command set, and the dictionary is no way to create or change scripts, rules, profiles or settings.

## Why (competitors)

Bartender 7 lists AppleScript integration (macbartender.com/Bartender7/); SaneBar lists "AppleScript Automation: full scripting integration" (github.com/sane-apps/SaneBar). holzBar already has `holzbar://` URL commands, Shortcuts actions and Raycast commands; AppleScript reaches users of Script Editor, Keyboard Maestro, BetterTouchTool and scripts that already use `tell application`.

## Design

### Mechanism (K: confirm in the plan)

Cocoa scripting: a `holzBar.sdef` in the app bundle, `OSAScriptingDefinition` = `holzBar.sdef` and `NSAppleScriptEnabled` = YES in Info.plist, command classes (`NSScriptCommand` subclasses) and a few scripting properties on the application object (`NSApplication` scripting category or `NSScriptKeyValueCoding`). The app is an accessory (LSUIElement) app; verify that it receives Apple events and that Script Editor resolves the dictionary. Everything runs on the main actor and calls the same services the URL commands call (`URLCommands.swift`), not new code paths.

### Commands (v1)

| Command / property | Does | Notes |
|---|---|---|
| `show section "hidden"` / `hide section` / `toggle section` | Shows, hides or toggles the hidden or always-hidden section | Goes through the Phase 18 gate; refused while Zen mode is on, like URL `show` |
| `apply profile "Work"` | Applies a stored layout profile by name | Same prompt/clean-up rules as URL (`URLPrompt`); unknown name is an error, never creates |
| `set zen mode to true/false` | Turns Zen mode on; off asks first and is refused while the screen is shared | Same as T-06-M1 |
| `enable rule "Name"` / `disable rule "Name"` | Switches an existing automation rule | Cannot create or edit rules; script-bound rules cannot be enabled by it until approved locally |
| Properties (read only): `profile names`, `current profile`, `rule names`, `active rule names`, `zen mode`, `hidden section is shown` | State for scripts | Names are the user's own; no paths, no SSIDs, no app lists, no script names |

Not in the dictionary, on purpose: creating, editing or deleting profiles, rules, widgets, hotkeys or any setting; anything about scripts (list, approve, run); reading item lists (they contain other apps' names); the settings export; quit/relaunch.

## Security analysis (to go into SECURITY.md as T-13-*)

| ID | Threat | Mitigation |
|---|---|---|
| T-13-M1 | Another app or script uses holzBar's dictionary to reveal hidden items, switch profiles or end Zen mode during a screen share (confused deputy, same as the URL scheme) | Same decision logic as the URL commands: ask before lasting changes, Zen-off refused while the screen is shared, no reveal while Zen mode is on; reveals pass the Phase 18 lock. Pure logic shared with the URL path and unit-tested |
| T-13-H1 | The dictionary becomes a path to create rules or scripts, and so to run code as the Accessibility holder (privilege escalation through Phase 11) | No command creates or edits a rule, profile or setting, and none touches scripts at all; enabling a rule that uses a script still needs the local approval of SCRIPT-03; a test asserts the sdef lists exactly the allowed commands |
| T-13-M2 | Floods of Apple events (a script in a loop) flicker the bar or burn energy | Rate limit shared with URL commands; repeated identical reveals are coalesced |
| T-13-L1 | Replies leak personal data | Replies only contain profile and rule names the user chose, Booleans and counts |
| T-13-L2 | A script that Phase 11 runs sends Apple events back to holzBar (loop) | Rate limit and the engine's hold-off; script runs are rate-limited too |

### Apple events permission analysis (K: to verify on a Mac)

- Apple events arriving at holzBar: macOS asks the **sender** (Script Editor, a Shortcut, a script run by another app) for Automation permission to control holzBar, the first time, in System Settings > Privacy & Security > Automation. holzBar itself asks for nothing and needs no entitlement to receive them.
- holzBar **sends** no Apple events in this phase, so it needs neither `NSAppleEventsUsageDescription` nor the `com.apple.security.automation.apple-events` entitlement (that one is for apps that send Apple events under the hardened runtime). README rule "Entitlements: none" stays true. A check in CI should confirm the built app has no such entitlement.
- Scripts that Phase 11 runs are separate processes; if one talks to holzBar, macOS applies the Automation prompt to that process or its responsible app (see the TCC spike in Phase 11).

## Plans (outline)

1. **13-01 Dictionary and command handling**: spike (does Script Editor show the dictionary and run a command in an accessory app on macOS 14, 26, 27); `holzBar.sdef`; command classes; the shared decision logic with the URL commands extracted to Core with Swift Testing; the sdef-lists-only-allowed-commands test; no entitlement check.
2. **13-02 Docs, Permissions, SECURITY**: README (feature, Permissions table note that macOS asks the caller for Automation), SECURITY.md T-13-*, example scripts in `Integrations/AppleScript/` (read-only samples), the 🔜 row to ✅ when the milestone ships.

## Risks

- Cocoa scripting in a Swift 6, main-actor-by-default app has sharp edges (`NSScriptCommand` runs on the main thread, bridged to Objective-C selectors); keep the glue tiny.
- Another input path into the app: that is why the command set is small and read-mostly.
- No Mac in the environment: the user checks Script Editor on 26 and 27.

## Out of scope

Creating or editing anything, scripts, item lists, JXA-only features, an Automator action (Shortcuts covers it).
