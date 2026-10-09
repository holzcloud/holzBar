# Module plan: replacing Vorssaint with holzBar modules, 2026-10-09

Purpose: group every Vorssaint feature into candidate opt-in holzBar modules and judge each against holzBar's principles (macOS 26/27 only, never connects, least privilege, no third-party packages, single executable with no helper, no entitlements). Supersedes the fits / maybe / no classification in VORSSAINT.md, which assumed no modules. Web research only; no code changed. Rectangle, AltTab, Flameshot and MonitorControl overlaps are researched separately; only the overlap is noted here.

## 1. Sources and reliability

Read with WebFetch (summarised by a small model, so wording is paraphrase; re-open before quoting publicly):
- README https://github.com/vorssaint/vorssaint-utils (24.9k stars, 1,785 commits; read in full)
- Permissions https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PERMISSIONS.md (full table)
- Privacy https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PRIVACY.md (full endpoint and storage tables)
- Troubleshooting https://github.com/vorssaint/vorssaint-utils/blob/main/docs/TROUBLESHOOTING.md
- Security https://github.com/vorssaint/vorssaint-utils/blob/main/SECURITY.md
- Trademarks https://github.com/vorssaint/vorssaint-utils/blob/main/TRADEMARKS.md, LICENSE, CONTRIBUTING.md
- Releases https://github.com/vorssaint/vorssaint-utils/releases (only the first 100k+ of 149.9k characters; v3.4.1 on Oct 8 down to v3.4.0-beta.4; older history not read). The release dates ("Oct 8", "Sep 27") fit 2026, which corrects the doubt about 2024 in VORSSAINT.md.
- CHANGELOG.md (only first 100k of 251k characters)
- Source tree listing: https://github.com/vorssaint/vorssaint-utils/tree/main/Sources/Vorssaint/Services (folder and file names only)

Not read: any Swift source beyond one file name check, SUPPORT.md, Discord, X, the rest of CHANGELOG and releases. **Every statement about which API a feature uses is inferred from permissions, folder names and general macOS knowledge, not from code, and is marked (inferred).** Before any port, read the actual source file.

## 2. Licence and code reuse (verified)

- README: "GPL 3.0 or later, copyright 2026 Vorssaint"; CONTRIBUTING: "GPL-3.0-or-later applies unless stated otherwise"; TRADEMARKS: "GPL-3.0-or-later license covers only source code"; LICENSE file is the GPLv3 text (29 June 2007) with the standard "any later version" wording. Verified in four places. Caveat: "unless stated otherwise" means individual files could carry another header; check each file's SPDX header before porting (CONTRIBUTING says new files keep project SPDX headers).
- holzBar is a fork of Ice (GPL-3.0). Code under GPL-3.0-or-later may be combined into a GPL-3.0 work; the result is distributed under GPL-3.0. Allowed: copy, adapt, translate. Required: keep copyright and SPDX headers of the copied files, add "Portions adapted from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later" to NOTICE, mark changes. (Not legal advice.)
- Trademark carve-out (TRADEMARKS.md): the name Vorssaint, logo, icon, bundle identity, trade dress and signing identity may not be reused. holzBar must use its own names, icons and UI look for adapted modules; do not copy asset catalogues, the Dynamic Island look, or the island's visual identity (the "look" is explicitly covered separately). Code only.
- Port friction (inferred): Vorssaint targets macOS 14 and Apple Silicon, builds with `build.sh` and Command Line Tools, has a monolithic `Sources/Vorssaint` tree split into App, Core, Services, UI, Support. Services are in per-feature folders (about 45), which makes cherry-picking easier than the README suggests. It localises into many languages (`AppLanguage.allCases`) and requires settings-backup participation; holzBar would need its own strings pipeline.
- holzBar constraints that block direct copying: no network calls (CI check `no-network`), no entitlements, no nested code or helper (Scripts/check-signature.sh), `@Observable`/Swift concurrency style, SwiftLint strict. Vorssaint has a "fan helper", a sudoers rule (SudoersSupport.swift), Process/shell runners (BoundedProcessRunner, ShellSupport, DetachedProcess) and reads `~/.zprofile` and `~/.zshrc`; none of that may come across.

## 3. Network endpoints (PRIVACY.md) and what happens to each

| # | Endpoint | Vorssaint use | holzBar decision |
|---|---|---|---|
| 1 | api.github.com | update check (on by default) | drop; holzBar updates through Homebrew |
| 2 | speed.cloudflare.com | speed test | drop; the feature is the network |
| 3 | Homebrew hosts (via local `brew`) | Homebrew manager | drop (also needs Terminal Automation and login-shell env) |
| 4 | formulae.brew.sh | app popularity badges | drop |
| 5 | uclient-api.itunes.apple.com | App Store update check | drop |
| 6 | itunes.apple.com | App Store fallback | drop |
| 7 | developer servers | "Online" app update check | drop |
| 8 | lrclib.net | lyrics | drop (lyrics module does not exist offline) |
| 9 | raw.githubusercontent.com | AI price list | drop; ship static pricing or omit cost estimates |
| 10 | Vorssaint service | temporary screenshot links | drop; save/copy only |
| 11 | Vorssaint service | temporary recording links | drop |
| 12 | Vorssaint service | feedback form | drop; link to GitHub issues in the browser (allowed exception) |
| 13 | local network (AirPlay) | per-app AirPlay routing | drop, needs Local Network permission (inferred) and is not a plain local feature |
| 14 | OpenAI via Codex | Codex banked resets | drop |

All 14 are dropped. Whole features that disappear because the network is their purpose: update manager (App updates, Homebrew), speed test, lyrics, share links, feedback, Codex limits, AirPlay routing. holzBar would not need any network permission or entitlement.

## 4. Module catalogue

Effort: S = days, M = 1 to 3 weeks, L = 1 month or more, per module in holzBar quality (tests, strings, settings UI). "Public API only" is (inferred) unless stated. "Port" says whether Vorssaint's GPL code is a useful starting point; code for features with a documented API is usually faster to write fresh in modern Swift.

### M1. Windows (layout and snapping)
- Features: window layout by shortcut or edge snapping, configurable snap areas, multi-display, maximise via green button, layout restore, window position tracking, spaces order preservation.
- Permissions: Accessibility. Space order and restore may need private Spaces APIs (inferred, uncertain).
- Public API only: layout, snap and maximise yes (AXUIElement, CGWindowList). Spaces order and restoring windows per Space: no public API (inferred).
- Network: none. Licence: GPL-3.0-or-later, adaptable (Services/WindowLayout, WindowMaximizer).
- Effort: M for layout and snap; L if Spaces handling is included.
- Overlap: Rectangle (direct, core of that app), partly AltTab (focus). Whatever the Rectangle research decides applies here; this is the same module.

### M2. App switcher and Dock
- Features: app and window switcher with previews and search; Dock Preview on hover; Dock click minimise/hide/cycle; quit on last window close; Dock window drag-move.
- Permissions: Accessibility; Screen Recording for thumbnails and window titles (falls back to icons without it, per PERMISSIONS.md).
- Public API only: switcher with icons yes. Window enumeration yes (CGWindowListCopyWindowInfo, which Vorssaint's WindowServerSupport uses publicly). Thumbnails: ScreenCaptureKit (public), but Screen Recording permission. Per-window raise needs `_AXUIElementGetWindow` in most known apps (inferred, uncertain; not in the file checked). Dock hover detection needs an Accessibility observer on Dock (public, fragile).
- Network: none. Licence: adaptable (Services/Switcher, DockPreview, DockClick, AutoQuit).
- Effort: L (switcher M, Dock preview M, Dock clicks S).
- Overlap: AltTab (direct); Dock features have no overlap.
- Build note: make Screen Recording strictly optional and requested on first use of previews.

### M3. Mouse and trackpad
- Features: per-device scroll inversion, linear/smooth scrolling, scroll sideways with a key, focus follows mouse, disable acceleration, side-button remap and mouse button shortcuts, middle click on trackpad, click debounce, button-drag gestures, per-app exceptions.
- Permissions: Accessibility (event taps) and, for tap on input devices, Input Monitoring (inferred, PERMISSIONS.md lists only Accessibility).
- Public API only: CGEventTap yes; acceleration change via IOHIDSystem parameters or `defaults` (inferred; partly undocumented). Trackpad multitouch middle click uses the private MultitouchSupport framework in most tools (inferred, uncertain).
- Network: none. Licence: adaptable (Services/ScrollInverter, SmoothScroll*, FocusFollowsMouse, MouseAcceleration, MouseButtons, MouseClickDebounce, MiddleClick, MouseNavigation, MouseExceptions).
- Effort: M (inversion, focus follows, debounce, side buttons) to L (smooth scrolling, middle click).
- Overlap: none of the four reference apps.
- Risk: event taps run in a hot path; a tap must stay off unless a sub-feature is enabled (principle "lean and fast"), and each sub-feature should be separately switchable.

### M4. Keyboard
- Features: text snippets with variables, key debounce, super key, assistive keyboard, quit and close protection (guard Cmd-Q/Cmd-W), shortcut recorder, system shortcut takeover, cleaning mode (lock keyboard and screen).
- Permissions: Accessibility plus Input Monitoring (inferred).
- Public API only: yes with CGEventTap. Snippet expansion reads every keystroke; that is a keylogger-like surface and must be in-memory only, never logged, switch-off by default, with password-field exclusion (secure input is skipped by the OS anyway).
- Network: none. Licence: adaptable (Snippets, KeyboardDebounce, SuperKey, QuitProtection, CleaningMode, SystemShortcutTakeover).
- Effort: M (quit protection S, debounce S, super key S/M, snippets M, cleaning mode S).
- Overlap: none.

### M5. Clipboard and files
- Features: clipboard history (search, preview, card shelf or list, auto-clear after delay, sleep or lock, excluded apps, concealed-content skipping), paste as plain text, URL tracking cleaner, Finder cut and paste (Cmd-X/V), F2 rename, image paste, file shelf (drop files to park them), downloads monitoring, messaging download organiser, disk image installer, Command Bar learning data.
- Permissions: clipboard history: none on macOS 26 beyond pasteboard-access prompts (macOS 15.4+ introduces a pasteboard-privacy prompt, behaviour on 26/27 to be verified, uncertain); paste as plain text and Finder cut/paste: Accessibility + Automation (Finder); downloads watch: Files and Folders (bookmark); disk image installer: App Management.
- Public API only: yes (NSPasteboard polling of `changeCount`, a timer; no notification exists, which conflicts with "no polling when an event exists", mitigate with long interval and only while enabled). Finder cut/paste needs Automation of Finder.
- Network: none. Licence: adaptable (Clipboard, Shelf, URLCleanerService, GeneralPasteboardAccess, TransientPaste, Finder, ManagedDownloads, DiskImageInstaller).
- Effort: M for history + clean URL + plain paste; M for Finder; S for shelf.
- Privacy: clipboard history is the biggest data liability in the plan; previously rejected (COMPETITORS.md item 11). As an opt-in module it is allowed if: off by default, in-memory or encrypted store, skip concealed/transient types (`org.nspasteboard.ConcealedType`), excluded apps, auto-clear, no logging. Vorssaint stores history in app local storage until cleared (PRIVACY.md), which holzBar should improve upon.
- Overlap: none of the four. Split into sub-modules (history, files) because their permissions differ.

### M6. Sound
- Features: volume mixer with per-app volume and boost, live equalizer, per-app output routing, output switcher and device priority, microphone input selection and level, mute microphone, music-app launch blocker, microphone faders.
- Permissions: per-app mixer and equaliser: System Audio Recording (process taps, CoreAudio public from macOS 14.2, per PERMISSIONS.md); output switch and mic mute: none (inferred); music control: Automation.
- Public API only: yes. CoreAudio process taps (`AudioHardwareCreateProcessTap`) are public since macOS 14.2; device selection and volume yes. Per-app AirPlay needs local network, drop.
- Network: AirPlay local routing only (dropped). Licence: adaptable (Services/Audio, Media).
- Effort: S for output switcher + mic mute + device priority; L for mixer and equaliser (audio-thread code, CPU, energy).
- Overlap: none. System Audio Recording is a heavy permission; ship output/mic first.

### M7. Energy and display
- Features: keep awake (timer, triggers such as helper apps, closed-lid mode), battery protection alerts, per-display brightness with half and quarter steps, external monitor dimming, extra brightness (XDR), lid dimming, Bluetooth off on sleep, Bluetooth accessory hints, fan control.
- Permissions: Notifications (timer, alerts); closed-lid keep awake needs Administrator (sudoers for `pmset disablesleep`); Bluetooth (inferred).
- Public API only: keep awake with IOPMAssertion yes; closed lid: no (privileged pmset). Brightness of built-in display: DisplayServices private framework (inferred); external monitors via DDC over IOAVService is private (inferred); MonitorControl uses these. XDR extra brightness uses undocumented EDR tricks (inferred, uncertain). Fan control: AppleSMC write needs root helper (SMCClient.swift exists; "fan helper" in the changelog); excluded by the no-helper rule.
- Network: none. Licence: adaptable (KeepAwakeManager, Display/*, Bluetooth, FanControl, SudoersSupport).
- Effort: S for keep awake (assertions only), S for battery notification; L for brightness/DDC; XL and excluded for fan control.
- Overlap: MonitorControl (brightness, dimming; same module as MonitorControl research). Closed-lid mode and sudoers: do not build.

### M8. System monitor
- Features: CPU per core, GPU, memory and pressure, temperature, battery health and wattage, network throughput, disks, per-process usage, history graphs, menu bar readout, alerts for load, temperature, memory pressure, disk and battery, connected devices.
- Permissions: Notifications for alerts; none otherwise.
- Public API only: CPU load (host_statistics), memory, disk free, network byte counters, battery (IOPS) yes. Temperature, GPU load, fan RPM and wattage: SMC/IOHID/IOReport, undocumented (inferred; SMCClient.swift confirms SMC access). Per-process usage via libproc is public.
- Network: none (speed test dropped). Licence: adaptable (SystemMonitor, ProcessUsageService); SMCClient excluded.
- Effort: M for the public subset (load, memory, disk, network, battery, process list); +M for private sensors, not recommended.
- Overlap: none of the four. Fits holzBar as live text items (planned Phase 12 sources). Refresh only while visible.

### M9. Tools
- Features: quick panel, quick toggles (dark mode, Trash, etc.), radial menu, scratchpad (Markdown notes), color picker (HEX/RGB/HSL/SwiftUI formats), OCR and QR from screen, screenshot (annotate, crop, redact, watermark), screen recording (system audio and microphone, export), camera preview, video compression, batch image conversion, wallpaper picker, cache cleaner, uninstaller, port manager, kill process, app update manager, Homebrew.
- Split into sub-modules because permissions differ:
  - **Command Bar and Quick panel**: no permission for own actions; Automation if running others' scripts; no app launcher requires Spotlight (inferred). Effort M. Overlap none. Port: CommandBar, QuickTools.
  - **Color picker**: NSColorSampler needs no permission (public); S.
  - **Capture (screenshot, OCR, QR, recording, camera)**: Screen Recording, Microphone, System Audio, Camera; ScreenCaptureKit (public, macOS has `SCScreenshotManager` and `SCContentSharingPicker`), Vision for OCR/QR (public, offline). Effort L. Overlap: Flameshot (screenshots, annotation). Drop temporary share links.
  - **Process tools (port manager, kill process)**: libproc and `kill` (public); S. Port manager uses `lsof`-like data; use libproc, not shelling out.
  - **Media (compress video, convert images)**: AVFoundation and ImageIO (public); M. Cleaner and uninstaller: Full Disk Access and App Management; high risk (deletion of user data); recommend skip or last.
  - **Scratchpad, wallpaper, radial menu, quick toggles**: S each; scratchpad stores user text locally.
  - **App updates, Homebrew**: dropped (network).
- Licence: adaptable per folder (Recorder, Switcher, Wallpaper, QuickTools, RadialMenu, KillProcess, PortManager, Cleaner, Uninstall).

### M10. Dynamic Island (notch overlay)
- Features: island at the notch or floating capsule on notchless and external displays and Lock Screen; music, controls, calendar and event countdowns, notifications mirroring, timers, stopwatch and focus sessions, downloads, accessory hints, lyrics, next up, music-reactive bars, AI agent usage (Claude Code, Codex, OpenCode, Copilot), Watch (live activity from any window), companion character, camera mirror, audio controls and microphone faders, Command Bar drop-down.
- Permissions: Accessibility (reads notifications, inferred as private/fragile), Calendars (full access), Files and Folders, Notifications, Screen Recording (Watch), System Audio (bars), Camera, local network.
- Public API only, per sub-feature: now-playing needs the private MediaRemote framework (inferred; Vorssaint also uses Automation for music apps; macOS 15.4 restricted MediaRemote, uncertain); notification mirroring has no public API (inferred; Vorssaint says Accessibility); calendar via EventKit yes; Lock Screen overlay is probably a high window level and works only partly (uncertain); AI agent usage reads local log files of other tools (needs Files and Folders access, and it is those tools' private data).
- Network: lyrics (lrclib.net), AI price list, Codex (all dropped).
- Licence: adaptable but hard to separate (Services/Notch, Media, AgentUsage); the look is trademark-protected, so a holzBar island needs its own design.
- Effort: L to XL. This is the largest part of Vorssaint (v3.4.0 and 3.4.1 were mostly Island) and the most private-API-dependent.
- Overlap: none of the four; it overlaps holzBar's own Shelf and notch handling (it is a second UI surface). Recommend building a reduced version: timers, calendar, music via Automation, downloads, no notification mirroring, no AI agents, no companion.

## 5. Everything-at-a-glance table

| Module | Permissions | Public API only | Network dropped | Effort | Overlap |
|---|---|---|---|---|---|
| M1 Windows | Accessibility | layout yes, Spaces no | none | M/L | Rectangle |
| M2 Switcher and Dock | Accessibility, Screen Recording (opt.) | mostly (window id risk) | none | L | AltTab |
| M3 Mouse | Accessibility (+Input Monitoring?) | mostly; middle click private | none | M/L | none |
| M4 Keyboard | Accessibility (+Input Monitoring?) | yes | none | M | none |
| M5 Clipboard and files | Pasteboard, Accessibility, Automation, Files, App Mgmt | yes | none | M | none |
| M6 Sound | System Audio Recording (mixer) | yes | AirPlay | S (switch) / L (mixer) | none |
| M7 Energy and display | Notifications; Admin for lid | keep awake yes; brightness/fan no | none | S / L / excluded | MonitorControl |
| M8 System monitor | Notifications | public subset yes; sensors no | speed test | M | none |
| M9 Tools | varies | mostly yes | links, updates, Homebrew, feedback | S to L each | Flameshot |
| M10 Dynamic Island | many | partial; MediaRemote/notifications no | lyrics, AI price, Codex | L/XL | holzBar Shelf |

## 6. Cross-cutting findings

- Principle conflicts that need a decision, not just work: (a) Accessibility, Screen Recording, System Audio, Camera, Calendars, Full Disk, Automation and App Management are requested by modules, which is allowed only if each module asks on first enable and says why; (b) clipboard history and snippets store or see sensitive data; (c) closed-lid keep awake, fan control and any root helper break "no helper, no entitlement" and should be declared out of scope permanently.
- "Replace Vorssaint completely" cannot be honoured literally: fan control (privileged helper), closed-lid mode (sudoers), update manager and Homebrew (network), lyrics, speed test, share links, feedback, Codex limits, per-app AirPlay, notification mirroring and the companion are not buildable under the principles. Suggested statement: holzBar replaces everything that works offline with public APIs.
- The modules hub exists upstream: v3.4.1 notes say "New features wait on the Features page instead of installing themselves on update", i.e. the same opt-in idea; copy the idea, not the code.
- Every event tap and timer must be created only when its sub-feature is enabled; users who enable only the Shelf should pay nothing.
- Permissions are tied to the signing identity; holzBar's own certificate (see CLAUDE.md) keeps grants stable across updates.

## 7. Recommended build order

1. **Foundation**: module registry and switch hub, per-module permission explainer, per-module settings, NOTICE entry for adapted code (effort M, prerequisite for all).
2. **M7a Keep awake + M8 System monitor (public subset)**: lowest permission, no private API, fit the Phase 12 text sources (S + M).
3. **M6a Output switcher, mic mute, device priority**, **M9 colour picker, port manager and kill process**, **M5 file shelf and clean URL**: small, permission-free or nearly so (S each).
4. **M1 Windows (layout and snapping)**: highest daily value, Accessibility only; reconcile with the Rectangle research (M).
5. **M5b Clipboard history** with the privacy rules above (M), then **M4 Keyboard** (quit protection, debounce, snippets) and **M3 Mouse** (inversion, focus follows, side buttons) (M each).
6. **M9 Command Bar and Quick panel**, with a holzBar-only scope (M).
7. **M2 App switcher and Dock** (L; reconcile with AltTab research).
8. **M9 Capture** (screenshot, OCR, QR, recording) (L; reconcile with Flameshot research), **M6b Volume mixer**, **M7b Brightness** (reconcile with MonitorControl research; private API risk).
9. **M10 Dynamic Island, reduced version** (timers, calendar, downloads, music via Automation) (L, last because it depends on many others and has the most uncertain APIs).
10. **Excluded**: fan control, closed-lid mode, update manager, Homebrew, uninstaller and cleaner (recommend skip), lyrics, speed test, share links, feedback, AI agent tracking, companion, notification mirroring.

## 8. Uncertain claims to verify before planning

- Which private APIs Vorssaint actually uses (only WindowServerSupport.swift was inspected and uses public CoreGraphics only; SMCClient.swift confirms SMC access).
- Whether Input Monitoring is needed for the event-tap modules on macOS 26/27 (not in PERMISSIONS.md).
- MediaRemote availability for now-playing on macOS 26/27 and the pasteboard privacy prompt behaviour.
- Per-file SPDX headers (CONTRIBUTING says "unless stated otherwise").
- Release history before v3.4.0-beta.4 and CHANGELOG beyond the first 100k characters.
- The effort sizes are estimates from feature size, not from reading code.
