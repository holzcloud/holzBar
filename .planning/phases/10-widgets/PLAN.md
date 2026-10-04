---
phase: 10-widgets
status: planned, decisions recorded 2026-10-04 (stage 1 = text widgets clock, battery, CPU, memory, uptime plus a Shortcut button) (outline; riskiest and largest phase; run /gsd-plan-phase 10)
requirements: [WIDG-01, WIDG-02, WIDG-03, WIDG-04, WIDG-05]
depends_on: Phase 7 (stage 1); Phase 9 (stage 2, script widgets)
research: .planning/research/COMPETITORS.md (section 2, widget apps)
---

# Phase 10: Widgets

**Riskiest and largest phase of the milestone.** It touches the hiding model on three backends and adds a timer to an app whose promise is "nothing runs when nothing is shown". Ship in stages; stage 1 alone is a complete feature.

## Goal

The user can put a small item of their own in the menu bar (a clock, battery percentage, CPU load, a Shortcut button), without code, and holzBar hides, reveals, orders and remembers it like any other item.

## Why (competitors)

Bartender 6 (Widgets, beta since 6.0.0, "no code required") and 7 ("built-in data sources, or make your own with custom scripts"); Ice's README lists "menu bar widgets" as planned; iStat Menus and Stats do it as whole apps. A user who installs holzBar to hide icons should not need a second app for a clock.

## How it fits holzBar today

- holzBar already creates its own status items: `MenuBarSpacers` makes `NSStatusItem`s with an `autosaveName` ("holzBar.Spacer.N"); groups create status items with icons (`MenuBarItemGroups`). macOS remembers an item's position by its autosave name; a ⌘-drag moves it. A widget is the same, with a `button.title` or image the app updates.
- Section membership: items are assigned to the hidden or always-hidden section by the layout model (`MenuBarItems`, per-backend: windows on macOS 14 to 25, XPC on 26, Accessibility discovery on 27). The first stage-1 task is a spike to confirm that holzBar's own extra items are discovered and assignable like spacers and group icons on each backend, and are not mistaken for "unknown" items (`OwnStatusItemWindows.swift`, "own control items recognised" since 0.0.5).
- On macOS 27 items cannot be reordered on the bar itself, only assigned to sections (README, macOS 27 section): widgets inherit that.

## Data sources: permission and cost

| Source | API | Permission | Refresh | Notes |
|---|---|---|---|---|
| Date and time | `Date`, `Date.FormatStyle` | none | one-shot timer to the next change of the shown text (next minute, or next second if seconds are shown); also `NSSystemClockDidChange`, `NSCalendarDayChanged`, wake | Seconds cost a wake every second: default format has none; seconds are a labelled option |
| Battery % and state | `IOPSCopyPowerSourcesInfo`, `IOPSNotificationCreateRunLoopSource` (already used) | none | event, no timer | |
| CPU load | `host_processor_info` or `host_statistics` (Mach, K) | none | timer, 2 s minimum, only while visible | cost is small but a timer |
| Memory use | `host_statistics64`, `ProcessInfo.physicalMemory` | none | timer, 5 s minimum, only while visible | |
| Uptime | `ProcessInfo.systemUptime` | none | timer per minute while visible | |
| Wi-Fi name | CoreWLAN | Location (Phase 8) | event | Later, only if Phase 8's opt-in exists |
| Network throughput | `getifaddrs` counters | none | timer | Deferred: polling by nature |
| Calendar (Itsycal-like) | EventKit | Calendar | event | Not offered: permission and scope |
| Weather, public IP | network | n/a | n/a | **Never**: holzBar is never online |
| Script output | Phase 9 runner | see Phase 9 | on events and a click to refresh; no interval | Stage 2 |
| Shortcut button | `shortcuts://run-shortcut?name=` opened through `NSWorkspace` (K) or the App Intents/Shortcuts route | none of its own (the Shortcut may ask) | click | Name only; no data back |

Energy rule: **a widget timer exists only while the widget is visible** (its section is shown, the display is awake, the screen is not locked). The existing `SystemActivity` (lock, wake) and the section state decide; when hidden, the timer is cancelled and the item's text is not updated; on reveal it refreshes once and restarts. A `Timer` with a tolerance (10 percent of the interval) lets the system coalesce wakeups. Count widgets: at most 6.

## Staged scope

- **Stage 1 (v1, in 0.0.7)**: text widgets from built-in permission-free sources (date/time, battery, CPU, memory, uptime) and the Shortcut button. Format: a small set of presets plus a text template with tokens (`{time}`, `{battery}`, `{cpu}`), no scripting language. Placement and hiding as for spacers; a "Widgets" section in the new Automation pane (my choice after decision 2; change if the user prefers Menu Bar Layout) to add, edit, remove; export/import/sync of kind and format; VoiceOver label and value.
- **Stage 2 (after Phase 9)**: script widget: first line of a script's output, under the SCRIPT gate (bounded plain text, refreshed on engine events and by a click, no interval timer, matching the no-polling decision for scripts).
- **Later**: more sources (thermal, VPN state, audio device), icons from SF Symbols, click actions.

## Plans (outline)

1. **10-01 Spike and model**: a throwaway widget as a status item on macOS 14, 26 and 27 (checklist for the user's Macs): is it listed in the layout editor, can it sit in the hidden section, does it keep its place after relaunch and after a profile apply. `AutomationWidget` model and `WidgetFormat` (template parser, pure, Swift Testing: tokens, escaping, length limit, unknown tokens), validation for import.
2. **10-02 Sources and refresh policy**: `WidgetSource` protocol and the five sources; the refresh scheduler that owns timers and knows visibility, wake and lock; tests with a fake clock for "no timer while hidden", "one refresh on reveal", "cancelled on lock".
3. **10-03 Pane, placement, Shortcut button, persistence**: UI, five languages, layout editor and search integration, export/import/sync, accessibility.
4. **10-04 Script widget (stage 2, after Phase 9)**.

## Risks

- **Backend differences**: on macOS 27 items are drawn by `MenuBarAgent` and hiding is per-app assertion; an app's extra status items may be treated as one app's items (holzBar's own) and cannot be hidden by holzBar the way other apps' items are. Needs the spike first; if impossible on 27, widgets are macOS 14 to 26 and say so, or the phase stops after the spike.
- **Energy**: every timer is a wakeup. Mitigations above; add a measurement step (Activity Monitor "Energy Impact" idle with 0 and 6 visible widgets) to the user's checklist.
- **Layout churn**: more items change the layout model's assumptions (item identity, per-section counts, notch overflow).
- **Item width changes** (a clock whose text length changes) can push items under the notch; use fixed-width (monospaced digit) formatting.
- **Scope creep** towards iStat Menus. Hold the line: text only, built-in sources, no charts, no network.
- No Mac in the environment: all UI of status items is checked only by CI build and the user's checklist.

## Out of scope

Charts and graphs, popovers, weather, anything online, calendars, user-written widget code, a widget gallery.
