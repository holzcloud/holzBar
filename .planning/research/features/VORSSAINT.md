# Vorssaint feature inventory, 2026-10-09

Purpose: which Vorssaint features could fit holzBar (macOS 26 and 27 only, least privilege, never online, zero dependencies, no telemetry), and which holzBar already plans. Web research only; no code changed.

## 1. Sources and what could not be read

Read (via WebFetch, which summarises pages with a small model; re-open before any claim goes public):
- https://vorssaint.com/de/ (German page, full feature list) and https://vorssaint.com/en/ (English page, full feature list). Both pages have exactly four links: https://github.com/vorssaint/vorssaint-utils/releases/latest, https://github.com/vorssaint/vorssaint-utils, https://x.com/vorssaint, https://buymeacoffee.com/vorssaint. **The site has no pricing, changelog, docs or per-feature pages**; the product is a single one-page site.
- https://github.com/vorssaint/vorssaint-utils (README: details, requirements, licence, 24.8k stars).
- https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PERMISSIONS.md and .../docs/PRIVACY.md (permission and network tables).
- https://github.com/vorssaint/vorssaint-utils/releases: only characters 0 to 100000 of 149875 were read (v3.4.0 to v3.4.1 and betas). The tool reported release dates in **2024**, which contradicts the macOS 27 mention in the notes and today's date (2026); treat the dates as unreliable, do not quote them.

Not read: docs/TROUBLESHOOTING.md, CONTRIBUTING.md, SUPPORT.md, SECURITY.md, TRADEMARKS.md, older releases, Discord, X. The README's "no telemetry" claim and the PRIVACY.md table were read once each and not cross-checked in code.

## 2. The product

One product: **Vorssaint** (repo name vorssaint-utils), a "free, open-source, modular menu bar app": every tool can be installed or removed. Swift/SwiftUI with AppKit.
- Plan/tier: **none. Free, no subscription**; donations via Buy Me a Coffee. Licence: GPL-3.0-or-later per README (the site says only "open source"); trademark and visual identity separate.
- Platform: macOS 14 or later, **Apple Silicon only**. Homebrew cask `vorssaint`, Developer ID signed and notarized, optional build from source.
- Privacy as stated: "local-first, no account, analytics or tracking", but PRIVACY.md lists many network hosts (section 4).
- Not a menu bar *icon manager*: it hides nothing and rearranges no one else's icons. It is a bundle of utilities that lives in the menu bar. Overlap with holzBar is therefore small.

## 3. Permissions (PERMISSIONS.md; "all optional, features degrade gracefully")

Accessibility; Screen Recording; System Audio Recording; Microphone; Camera; Calendars; Files and Folders (Downloads); Notifications; Full Disk Access (uninstaller); **Administrator (one-time sudoers rule, for closed-lid mode)**; Automation (Finder, Terminal, music apps); App Management. The table maps permissions to features as in section 5 ("Perm" column). Where the page did not name the permission for a feature, the cell says "(not stated)".

## 4. Network use (PRIVACY.md)

api.github.com (update check, toggleable); speed.cloudflare.com (speed test); Homebrew hosts and formulae.brew.sh; uclient-api.itunes.apple.com and itunes.apple.com (App Store version lookup); developer update feeds; Vorssaint service (temporary screenshot links, temporary recording links, feedback); lrclib.net (lyrics); raw.githubusercontent.com (AI pricing list); OpenAI via Codex (limits); local AirPlay speakers. Most are opt-in, update checks are on by default and toggleable. Public IPs kept up to 24 h for abuse prevention. This alone disqualifies every feature in the "network" rows from holzBar.

## 5. Feature inventory

Legend. Plan: all features are Free (no tiers). Verdict: **fits** = plausible under holzBar's principles; **maybe** = only in a reduced, permission-free form or after a spike; **no** = breaks a principle or is outside a menu bar manager's job. Planned: holzBar phase (8 to 27 of ROADMAP.md) or "shipped" (0.0.6, per COMPETITORS.md) or "not planned". Descriptions are from the English page (https://vorssaint.com/en/) unless noted. Perm = permission per PERMISSIONS.md.

### Windows and Dock

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| App switcher | Switch apps and windows with previews | Accessibility, Screen Recording (previews) | no | Window management, needs Screen Recording | not planned |
| Dock Preview | Window previews on Dock hover | Accessibility, Screen Recording | no | Same, and Dock is out of scope | not planned |
| Dock clicks | Click Dock icon to minimize or cycle | Accessibility | no | Out of scope (Dock) | not planned |
| Maximize windows | Green button maximizes instead of full screen | Accessibility | no | Window manager job | not planned |
| Window layout | Shortcuts or edge snapping | Accessibility | no | Window manager job | not planned |
| Quit on close | Quit apps when last window closes | Accessibility | no | Not menu bar related | not planned |

### Mouse and keyboard

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Invert mouse scrolling, linear/smooth scrolling, scroll sideways with key | Scroll tweaks | Accessibility | no | Input remapping, event tap, off-topic | not planned |
| Focus follows mouse | Focus window under pointer | Accessibility | no | Off-topic | not planned |
| Disable mouse acceleration, side buttons, mouse button shortcuts, trackpad middle click, extra click filter | Mouse tweaks | Accessibility (middle click stated; rest not stated) | no | Off-topic, event taps | not planned |
| Debounce | Ignore accidental double key presses | (not stated; needs an event tap) | no | Off-topic | not planned |
| Text snippets | Triggers expand into text | (not stated; event tap) | no | Keylogger-like surface, off-topic | not planned |
| Super key | One key acts as a modifier combination | (not stated) | no | Off-topic | not planned |
| Quit and close protection | Guard Cmd-Q and Cmd-W | Accessibility | no | Off-topic | not planned |

### Clipboard and files

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Clipboard history (search, preview, auto-clear) | Local history of copies | (not stated) | no | Privacy liability; COMPETITORS.md item 11 already rejects it | not planned (decided) |
| Paste as plain text | Paste without formatting | Accessibility | no | Off-topic | not planned |
| Cut and paste files in Finder | Finder cut/paste | Accessibility, Automation | no | Off-topic | not planned |
| Rename shortcut | Rename selected file | (not stated) | no | Off-topic | not planned |
| Shelf (menu bar file drop) | Drop files on the menu bar to hold them | (not stated) | no | Different job; name clashes with holzBar Shelf | not planned |
| Clean URL | Strip tracking from copied links | (not stated) | no | Clipboard watching, off-topic | not planned |
| Disk image installer | Install the single app in a DMG | App Management | no | Off-topic | not planned |

### Sound

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Volume mixer, live equalizer | Per-app volume, pin, order | System Audio Recording | no | Heavy permission, off-topic | not planned |
| Output switcher | Cycle outputs with a shortcut | (not stated) | maybe | A hotkey/action over CoreAudio needs no permission; could be one action in the Phase 14 catalog or a Phase 12 text source | not planned |
| Audio device priority | Auto-use preferred devices | (not stated) | no | Off-topic | not planned |
| Mute microphone | Mute from anywhere | (not stated) | maybe | Small action, no permission for muting input volume; only as a Phase 12/25 action, low value | not planned |
| Music app blocker | Block music launches from media keys | (not stated) | no | Off-topic | not planned |

### Energy and display

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Keep awake | Keep Mac awake on demand (timer, triggers) | Notifications; Administrator for closed-lid mode | maybe | Caffeinate-style via IOPMAssertion needs no permission; the closed-lid mode (sudoers) does not fit. Natural as a Phase 8 rule action or Phase 14 action | not planned |
| Displays (brightness, power per display) | Brightness and on/off | (not stated) | no | Private/hardware APIs | not planned |
| Extra brightness (XDR) | Boost XDR brightness | (not stated) | no | Off-topic | not planned |
| Bluetooth on sleep | Bluetooth off while asleep | (not stated; Bluetooth) | no | Permission, off-topic | not planned |

### Tools

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Quick panel | Floating panel of favourite tools | (not stated) | maybe | Same idea as holzBar Shelf plus palette | Phase 14 (palette) covers the intent |
| Quick toggles / Quick actions | One-click dark mode, Trash, ... | (not stated; Automation likely) | maybe | Dark mode toggle etc. need Automation for System Events; only permission-free toggles | Phase 12 (Shortcut button) and 25 (control) partly |
| Color picker | Pick any screen colour | Screen Recording (magnifier) | no | NSColorSampler needs no permission, but off-topic for a bar manager | not planned |
| Copy text from screen (OCR, QR) | Vision OCR of screen | Screen Recording | no | Off-topic, permission | not planned |
| Cleaning mode | Lock keyboard and screen | (not stated; event tap) | no | Off-topic | not planned |
| Media compression, batch image conversion | Compress video/image/GIF | (not stated) | no | Off-topic | not planned |
| Cleaner (caches, scheduled) | Clear caches and junk | (not stated) | no | Off-topic | not planned |
| Uninstaller | Remove apps and leftovers | Full Disk Access, App Management | no | Broad permission | not planned |
| Homebrew integration | Keep packages updated | Automation (Terminal); network | no | Network | not planned |
| App updates | Find and install updates (several sources) | App Management; network | no | Network | not planned |
| Screenshot (annotate, watermark, temp links) | Capture and annotate | Screen Recording; link upload needs network | no | Permission, network | not planned |
| Screen recording | Record area/window/screen, edit | Screen Recording, System Audio, Microphone | no | Off-topic | not planned |
| Camera preview | Floating mirror | Camera | no | Off-topic | not planned |
| Radial menu | Wheel of favourite actions at pointer | Accessibility | maybe | Action launcher; holzBar's palette (Phase 14) covers it without Accessibility | Phase 14 partly |
| Scratchpad | Floating notes with tabs, Markdown | (not stated) | no | Off-topic; stores user text | not planned |
| Command Bar | One field that finds and runs everything, calculator, emoji, apps | (not stated) | fits | A fuzzy action and item search is exactly holzBar's palette; only the scope (holzBar actions, no app launcher, no history) differs | **Phase 14** |
| Wallpaper | Pick still wallpaper | (not stated) | no | Off-topic | not planned |
| Kill Process | Search processes, force quit, kill trees | (not stated) | no | Off-topic | not planned |
| Port Manager | Active listening ports | (not stated) | no | Off-topic | not planned |

### Dynamic Island (notch overlay; floating capsule on notchless and external displays, Lock Screen)

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| Dynamic Island core + gestures | Music, controls, tools at top of screen; scroll/swipe gestures | Accessibility (notch notifications) | no | A second UI surface at the notch; competes with Shelf and notch handling for no gain | not planned |
| Calendar | Month and upcoming events | Calendars | no | Permission; COMPETITORS.md already keeps Calendar out except as inspiration | not planned |
| Notifications | System notifications shown in the island | Accessibility | no | Reads other apps' notifications | not planned |
| Timer | Timers, stopwatch, focus sessions | Notifications | maybe | Local only, no permission for the display; but a timer is not a menu bar manager job. Could be a Phase 12 widget source (countdown) | Phase 12 (possible source) |
| Accessory hints | Connected accessories, 20 % battery warning | Notifications | no | Bluetooth/notification permissions | not planned |
| Lyrics | Follow song lyrics | network (lrclib.net) | no | Network | not planned |
| Next up, Bars follow music | Upcoming songs; audio-reactive bars | System Audio / Automation | no | Permission, energy | not planned |
| Downloads | Files arriving in a folder | Files and Folders | no | Permission | not planned |
| AI Agents | Plan limits, tokens, API value, work in progress (Claude Code, Codex, OpenCode, Copilot) | network (OpenAI, pricing list) | no | Network, off-topic | not planned |
| Watch | Turn part of any window into a live activity | Screen Recording | no | Screen Recording | not planned |
| Companion | A little animated character | none stated | no | Gimmick, energy | not planned |

### System monitor

| Feature | Description | Perm | Verdict | Reason | Planned |
|---|---|---|---|---|---|
| CPU (per-core, temperature) | Usage and temperature | (not stated) | maybe | Load via host_statistics needs no permission; temperature needs private SMC/IOHID APIs, so only load | Phase 12 source "CPU load" (COMPETITORS.md lists CPU load, memory as cheap sources) |
| GPU | Usage and temperature | (not stated) | no | Private IOKit | not planned |
| Memory | Use and pressure | (not stated) | maybe | Public API, no permission | Phase 12 source |
| Network speed and usage | Throughput | (not stated) | maybe | Interface byte counters are local; no connection made. Speed test is network and rejected | not planned |
| Disks | Space and activity | (not stated) | maybe | Free space via URL resource values, no permission | not planned (possible Phase 12 source) |
| Power / battery (health, wattage, charging) | Battery and charging | (not stated) | maybe | IOPS is permission-free; already used for reveal rules | Phase 8 (power condition), Phase 12 source "battery" |
| Connected devices | Count USB peripherals | (not stated) | no | Off-topic | not planned |
| Fan control (beta) | Manual or curve-based fan speed | (not stated; privileged SMC write) | no | Needs privileged helper, unsafe | not planned |
| Alerts for sustained load, temperature, memory pressure, disk, battery | Threshold notifications (README) | Notifications | no | Notification permission; no | not planned |
| History graphs, speed test | Graphs; Cloudflare speed test | network for speed test | no | Network | not planned |

### Other items named only in the README

Space management and window position tracking, layout restoration (window manager, no); Finder drag-move, F2 rename, image paste (no); batch image conversion (no); clipboard auto-clear (no); music app control via Automation (no).

## 6. Summary against holzBar

- Only **Command Bar** (-> Phase 14), and read-only monitor/status text (-> Phase 12 sources), are real overlaps. Everything else is outside a menu bar manager.
- **Maybe list, in order of usefulness:** (1) Keep awake as a Phase 8 rule action and Phase 14 palette action, IOPMAssertion only, never the sudoers closed-lid mode; (2) CPU load, memory, battery, disk free as extra Phase 12 text sources; (3) audio output switch and mic mute as palette actions; (4) countdown as a Phase 12 source. None is required and none should be added without a principle check (energy: refresh only while visible, as Phase 12 already demands).
- **Does not fit and should stay out:** everything that needs Screen Recording, System Audio, Full Disk, Administrator or Automation grants; everything that opens a connection (updates, lyrics, speed test, Homebrew, App Store lookups, upload links, AI limits); clipboard history; event-tap input remappers.
- **Nothing Vorssaint has that holzBar lacks in its own field**: it has no hiding, no profiles, no triggers, no lock, no scripting dictionary; those are all in holzBar's roadmap or shipped.
- Positioning note: Vorssaint claims privacy ("no telemetry") yet lists about 14 network endpoints, mostly opt-in; holzBar's "never connects" claim stays a differentiator. Vorssaint is Apple Silicon only, macOS 14+, GPL-3.0-or-later.
