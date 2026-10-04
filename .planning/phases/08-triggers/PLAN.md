---
phase: 08-triggers
status: planned (outline; run /gsd-plan-phase 8 to split into executable plans)
requirements: [TRIG-01, TRIG-02, TRIG-03, TRIG-04, TRIG-05, TRIG-06, TRIG-07, TRIG-08, TRIG-09]
depends_on: Phase 7
research: .planning/research/COMPETITORS.md (sections 3 and 4)
---

# Phase 8: Triggers

## Goal

The user can say "when this is true, apply this profile, show these items, or turn Zen mode on" and holzBar does it from system events alone: no polling, no network, and a permission only for the one condition that needs it, asked when the user adds it.

## Why (competitors)

Bartender 5/6/7, Thaw and SaneBar all have triggers; holzBar has only two fixed rules (low battery, offline) and profiles bound to a display or a Space. Thaw has the widest set and AND/OR; SaneBar has it free. holzBar's angle is the same feature with the fewest permissions.

## Trigger inventory: API, permission, event source, decision

Facts marked (V) were read in Apple documentation or an Apple DTS answer on 2026-10-04; (K) are from knowledge and must be confirmed on a Mac in the spike of the plan that uses them.

| Condition | API | Permission | Event-driven? | Decision |
|---|---|---|---|---|
| Power source, battery level | `IOPSNotificationCreateRunLoopSource` (already in `RevealRules.swift`) | none | yes: run loop source fires on change | In v1 |
| Low Power Mode | `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` (K) | none | yes | In v1 |
| App running / frontmost | `NSWorkspace` `didLaunchApplicationNotification`, `didTerminateApplicationNotification`, `didActivateApplicationNotification` (K) | none | yes | In v1; match by bundle identifier chosen from a picker of running apps |
| Time window, weekdays | one `Timer` armed for the next rule boundary, re-armed on `NSCalendarDayChanged`, `NSSystemClockDidChange`, time zone change and wake (K). Not `NSBackgroundActivityScheduler`: Apple documents it for activities of 10 minutes or more, which the system may defer (V) | none | yes: one-shot timer, not polling; nothing runs while the Mac sleeps; re-evaluated on wake | In v1 |
| Display connected | `NSApplication.didChangeScreenParametersNotification`, display UUID (already used by `ProfileBinding`) | none | yes | In v1 |
| Network kind: Wi-Fi, Ethernet, offline, expensive (phone hotspot, Low Data Mode) | `NWPathMonitor`, `usesInterfaceType`, `isExpensive` (already used for "offline"; it never opens a connection) | none | yes | In v1; `isExpensive` as "hotspot" needs a test on a Mac (K) |
| **Wi-Fi network named X** | `CWWiFiClient.shared().interface()?.ssid()` (V: needs Location since macOS 14; nil without it; Stats asks for Location for the same reason). Change events: `CWWiFiClient.startMonitoringEvent(with: .ssidDidChange)` with a `CWEventDelegate` (V: macOS 10.10+; the docs name the `com.apple.wifi.events` entitlement, an Apple forum thread (11307) says non-sandboxed apps work without it: spike). Fallback with no entitlement: use the `NWPathMonitor` update as the wake-up and read `ssid()` once | **Location Services** (When In Use is enough if the spike confirms it works for an accessory app; needs `NSLocationUsageDescription` in Info.plist) | yes, by CoreWLAN event or by NWPath update | In v1 as opt-in: asked when the user first chooses "Wi-Fi network named...", with the reason in the pane first. Never asked at launch or when other conditions are used. Without it the condition is "needs Location Services" and false. No GPS is used and no location is stored |
| **Focus** | `INFocusStatusCenter` (V): macOS 12+, needs authorization and the Communication Notifications capability, and says only "is focused", not which Focus; the capability needs a provisioning profile the self-signed build cannot have: **rejected**. Reading `~/Library/DoNotDisturb/DB/Assertions.json` needs Full Disk Access: **rejected**. `SetFocusFilterIntent` (V: App Intents, macOS 13+): the user adds holzBar as a Focus filter in System Settings; the system calls the intent when the Focus turns on or off; no permission, no data read | none | yes: the system calls us | Spike first: a forum post (V, May 2026) says `perform` is never called on macOS 26.5. Ship "Focus filter applies a profile" only if the spike shows it works on 26 and 27 |
| Location (place) | `CLLocationManager` (V): authorization and usage text | Location Services, continuous | region monitoring | **Not offered** (Wi-Fi name covers "at home / at work" without GPS). Revisit only on request |
| VPN | `NWPathMonitor` interface type `.other` / `SCDynamicStore` (K) | none | yes | After v1, same framework |
| Audio output device | CoreAudio default output device property listener (K) | none | yes | After v1 |
| Thermal state / Energy Mode | `ProcessInfo.thermalState` + notification (K); Energy Mode: no public API known | none | yes | Thermal after v1; Energy Mode not offered |
| Bluetooth device | `IOBluetooth` / CoreBluetooth | Bluetooth permission | yes | Not offered in this milestone (permission) |
| Camera / microphone in use | CoreMediaIO property listener (K) | probably none | yes | Not offered in this milestone (unverified; the macOS 27 privacy indicator is already affected by holzBar, see T-06-M3) |
| Script exit status | Phase 9 | see Phase 9 | on events only | Phase 9 |

Least-privilege decisions in one sentence each: nothing is asked at install or launch; Location is asked once, when and only when the user picks a Wi-Fi network name; every monitor is created when an enabled rule needs that condition kind and cancelled when the last such rule is disabled; the Focus filter and the other conditions need no permission at all.

## Design

### Model (pure, `holzBar/Core`, Swift Testing in `Tests/HolzBarCoreTests`)

- `AutomationCondition` (enum, Codable, Sendable, Equatable): `.power(onBattery/ac)`, `.batteryBelow(Int)`, `.lowPowerMode`, `.appRunning(bundleID)`, `.appFrontmost(bundleID)`, `.time(start, end, weekdays)`, `.displayConnected(uuid)`, `.network(kind)`, `.wifiNetwork(ssid)`; later cases are added without changing the others. Any condition can be negated (`not`).
- `AutomationAction`: `.applyProfile(name)`, `.showSection(section)`, `.zen(on/off)`; optional `restoresPrevious` for `applyProfile` and `zen`.
- `AutomationRule`: `id` (UUID), `name`, `isEnabled`, `match` (`.all`/`.any`), `conditions`, `action`, `restoresWhenEnded`.
- `AutomationFacts`: a value holding the current answer for every kind (`Optional` when unknown or unavailable, e.g. Wi-Fi name without permission). Providers fill it; the engine only reads it.
- `AutomationEngine.evaluate(rules:facts:previous:) -> (effects: [Effect], state: State)`: edge detection per rule (reuses the idea of `RevealTrigger`), the first enabled rule in list order wins when two want to apply a profile, the active profile is never re-applied (as `ProfileBinding` does), unknown fact = condition false, and applying an effect never re-enters evaluation in the same pass (no loop).
- Migration: `RevealRules` (low battery, offline) become two built-in rules generated from the old Defaults keys; the old keys keep working and are written back so downgrade is not harmed.

### Providers (main actor, `holzBar/MenuBar/Automation/`)

One small observer per fact kind behind a protocol `AutomationFactProvider { start() / stop() / facts stream }`, owned by `AutomationMonitors`, which starts a provider only when an enabled rule uses its kind and stops it when none does. Reuse `ObservationLoop`/`Debouncer` where present; coalesce bursts (display and network changes arrive in groups) with the existing `Debouncer`. Time provider = one-shot timer. No provider polls.

### Settings UI

New sidebar pane **Automation** (decision question 2), between Menu Bar Layout and Hotkeys: a list of rules (name, summary sentence, switch), add and remove buttons, a sheet to edit: name; "When **all/any** of these are true" with a condition list and an add menu; "Then" with the action; "When it stops being true: restore the previous profile". The Wi-Fi network condition shows, before the system prompt, a plain explanation ("macOS shares the Wi-Fi network name only with apps that may use Location Services. holzBar uses it only to read that name. It does not read your location.") and a button that asks. HIG: grouped form, system controls, destructive delete confirmed by undo rather than a dialog where possible, VoiceOver labels, full keyboard use. All strings in `Localizable.xcstrings`, five languages, checked by `strings-check.py`.

### Settings, sync, URL, Shortcuts

- Rules are stored as one JSON string under a new `Defaults.Key` (`AutomationRules`), added to `SettingsSchema` with an allowlist of condition and action kinds, max 50 rules, max lengths (names 80, SSID 32 bytes, bundle id 255), ranges for battery and time; unknown kinds drop the rule; unknown profile names disable it; exported, imported and synced like other settings (open question 5 covers SSID values).
- URL: `holzbar://automation?list`, `?enable=<name>`, `?disable=<name>`, `?status`; no create or edit; enabling or disabling is a lasting change and asks first like other URL commands (reuse `URLPrompt`); disabled while Zen mode is on, like the rest. Shortcuts: "Enable/Disable automation rule" and "Get active automation rules" in `HolzBarIntents.swift`, rule chosen from an `AppEntity` list.
- Logs: rule ids only; SSIDs, app names and profile names are `.private`.
- `privacy-check.py`: `NWPathMonitor` is already allowlisted; check that CoreWLAN does not match a network pattern, and add `CoreWLAN` to the allowlist with the reason if it does.

## Plans (outline)

1. **08-01 Engine and migration (tracer)**: `AutomationCondition/Action/Rule/Facts/Engine` in Core with Swift Testing (all/any, edges, restore, conflict, no loop, unknown facts, Codable round trip, validation); the two old reveal rules run through the engine with unchanged behaviour. No UI yet.
2. **08-02 Permission-free providers and actions**: power, Low Power Mode, app, time, display, network kind; the monitor lifecycle (started only when needed, with a test that counts started providers); actions apply profile (existing `LayoutProfiles`), show section, Zen. A temporary developer-only toggle to create a rule by `defaults` for the first on-Mac check.
3. **08-03 Automation pane, strings, settings, URL, Shortcuts**: the UI, five languages, export/import/sync with validation, URL commands, App Intents, README and docs text, SECURITY.md note that rules are data.
4. **08-04 Wi-Fi network condition**: spike (does `ssid()` return with Location "When In Use" for an accessory app signed with holzBar's certificate; does `ssidDidChange` arrive without the entitlement; is the prompt shown to a non-notarized app), then the opt-in flow, Info.plist usage text (the README claim "Info.plist usage strings: none" changes), Permissions table row, and the "needs Location Services" state.
5. **08-05 Focus filter**: spike on macOS 26.x and 27 (does the system call `perform` when the Focus changes; how to show it in System Settings); ship the Focus-filter profile binding if yes, else document "not possible on macOS X" in the pane's help and drop. Independent of 08-04.

## Risks

- The Wi-Fi name may not be readable by an accessory app without more setup (Location "Always"?), or the system may not show the prompt for a self-signed app: spike before promising it in the README; the fallback is "any Wi-Fi / Ethernet / offline" only.
- `SetFocusFilterIntent` is reported broken on macOS 26.5 (V, unanswered): may have to wait for a fix.
- Rule loops: a profile apply changes facts (display, app names in the bar) which flip a rule back: covered by "never re-apply the active profile" and a minimum 2 s hold-off after an effect.
- Time rules and sleep: a timer does not fire while asleep; evaluate on wake and on day, clock and time-zone changes.
- Migration of the two old rules must be lossless (the user keeps their settings).
- No Mac in the development environment: every provider needs a CI build and a checklist for the user's Macs (26.7.1 and 27).

## Out of scope

Location (GPS) condition, Bluetooth, camera/microphone, Energy Mode; scripts (Phase 9); widgets (Phase 10).
