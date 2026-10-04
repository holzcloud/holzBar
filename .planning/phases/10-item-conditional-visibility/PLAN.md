---
phase: 10-item-conditional-visibility
status: planned (outline; run /gsd-plan-phase 10)
requirements: [VIS-01, VIS-02, VIS-03, VIS-04]
depends_on: Phase 8 (engine and conditions), Phase 9 (snapshots protect the moves)
---

# Phase 10: Item conditional visibility

## Goal

A menu bar item can have its own rule: "show this item only while <condition>". The VPN item appears only while a VPN is connected; an app's item only while that app runs; a meeting app's item only during work hours.

## Why

Thaw's README: "Item triggers move a menu bar item when something happens" and "Reveal an item when a condition is met, or hide it instead" (github.com/thaw-app/Thaw); Bartender 6/7 triggers show items "exactly when they matter" (macbartender.com/Bartender7/). Phase 8's rules act on whole profiles or sections; this phase is the per-item form and reuses the same engine and conditions.

## Design

- **Model**: `ItemRule { itemKey (ItemIdentity key, or bundle id on macOS 27), match (all/any), conditions: [AutomationCondition], hiddenSection }` in `holzBar/Core`, next to `AutomationRule`. Evaluated by the Phase 8 `AutomationEngine` (facts in, effects out); new effect `.setItemSection(key, section)`. Pure, Swift Testing: edge detection, restore of the "visible" section, unknown facts keep the item where it is (never hide because a fact is unavailable), no loop.
- **Conditions**: all of Phase 8's, plus two this phase adds to the engine: `.vpnConnected` (`NWPathMonitor` interface kinds or `SCDynamicStore`, K, spike on a Mac; no permission) and `.itemsAppRunning` (the item's own app is running, via `NSWorkspace` notifications; no permission). Phase 8's provider lifecycle (a provider runs only while an enabled rule needs it) applies unchanged.
- **Mechanism**: no new hiding technology. A rule moves the item between its normal ("visible") section and a hidden section with the existing per-item move machinery that profiles use. When the condition holds the item goes to the section the user had it in (stored as `visibleSection` when the rule is created and updated when the user moves it while the condition holds); when it does not hold it goes to `hiddenSection`. On macOS 27 sections are per application, so the rule applies to the app (the UI says "all items of <App>").
- **When the item's app is not running**: there is no item to move. The rule is stored by identity and shows as "app not running" in the pane. When the app launches, `SectionRestore` reconciles with the **rule's current state** (state wins over the saved section), so the item appears directly in the right place and never flashes into the visible bar. For "app running" conditions that is the intended behavior.
- **Conflicts with profiles** (question 16): recommended **item rules win**: applying a profile leaves items that have an item rule where the rule says; the Profiles UI says "N items are controlled by rules". Conflicts with Phase 8 rules that apply a profile: same, rules win over the profile's section for those items. Conflicts between two item rules cannot happen (one rule per item). A manual move of a controlled item: while the condition holds it changes the visible section; while it does not, the move is reverted at the next evaluation with a hint in the pane, never silently.
- **Hidden target** (question 17): the Hidden section by default, chooseable per item (Always-hidden).
- **UI** (VIS-03): in the Menu Bar Layout pane, an item's context menu (and VoiceOver action) "Show Only When…" opens a popover with the Phase 8 condition editor (reused view), "Hide into: Hidden / Always hidden", Remove rule. Controlled items get a small badge and tooltip ("Shown while VPN is connected"). A list of all item rules also sits in the Automation pane ("Item rules"), for review and disabling.
- **Settings**: stored with the Phase 8 rules under their key; exported, imported and synced with the same validation (known conditions, ranges, at most 100 item rules, item keys of limited length; unknown ones dropped); Wi-Fi names and app choices included as decided for rules. Logs private.
- **Snapshots**: a burst of rule moves takes one `beforeRule` snapshot first (Phase 9).

## Privacy and permission analysis

No new permission. VPN and running-app conditions need none. Wi-Fi-name conditions keep Phase 8's Location opt-in. No new data beyond item identities the app already stores. Logs: counts and rule ids only.

## Plans (outline)

1. **10-01 Model and engine extension (Core)**: `ItemRule`, `.setItemSection` effect, `.vpnConnected` and `.itemsAppRunning` conditions, Swift Testing (state wins on app launch, unknown fact keeps place, no loop, profile apply skips controlled items).
2. **10-02 Move execution and conflicts**: wire effects to the existing section-move code on macOS 14 to 26 and the per-app path on 27; `SectionRestore` honors rule state; profile apply skips controlled items; hold-off and debounce so a flapping VPN does not move the item every second.
3. **10-03 Layout pane UI, Automation pane list, strings, settings**: context menu, popover, badge, list, five languages, export/import/sync validation.

## Risks

- Moves are expensive (event posting, Accessibility) and visible: a flapping condition (VPN reconnect, Wi-Fi roaming) must be debounced (minimum hold of 3 s) and the move must never run while the user drags.
- macOS 27: per-app sections mean "this item" is "all of this app's items"; say so in the UI.
- Items that exist only while their app runs (most of them) plus "app running" conditions are a tautology; the UI should prefer helpful presets (VPN, work hours, Wi-Fi) over that one.
- The visible section stored at rule creation can go stale if the user rearranges while the rule hides the item: handled by the manual-move rule above.

## Open design questions

16. **When an item rule and a layout profile disagree?** A. The item rule wins; profiles skip controlled items (**recommended**); B. The profile wins until the next condition change; C. Ask the user each time (rejected for interruptions, listed for completeness).
17. **Where does a hidden-by-rule item go?** A. The Hidden section by default, selectable per item (**recommended**); B. Always the Always-hidden section; C. Always the Hidden section, no choice.
