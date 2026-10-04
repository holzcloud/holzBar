# Requirements: holzIce — Modernize

**Defined:** 2026-10-02
**Core Value:** The menu bar items a user hides stay hidden and come back when asked, on every supported macOS version, without the app ever locking up the Mac.

Source: `.planning/codebase/CONCERNS.md` (file:line references there).

## v1 Requirements

### CI and build

- [x] **CI-01**: Workflows use current action versions (`actions/checkout` v5 or newer) and no deprecated runtime warnings remain
- [x] **CI-02**: SwiftLint runs with a maintained setup (official SwiftLint, not `norio-nomura/action-swiftlint@3.2.1`) and still passes `--strict`
- [x] **CI-03**: The unit tests (`swift test`, `Tests/IceMacOS27CoreTests`) run on every pull request
- [x] **CI-04**: The build workflow prints compiler warnings (deprecations) so they are visible in the log
- [x] **CI-05**: Xcode version is pinned explicitly in CI and the README states the real build requirement
- [x] **CI-06**: The Xcode project carries holzIce's version (not `0.11.13-dev.2a`) and no Development Team of the original project; `Scripts/install.sh` builds for anyone (ad hoc signing)
- [x] **CI-07**: `release.yml` uses the `0.0.6-beta1` scheme in its examples/comments, checks the release notes once, and passes the version input through an environment variable instead of inline `${{ }}` in shell

### Rename to holzBar

- [x] **REN-01**: Every user-visible text says "holzBar" (written exactly so) instead of "holzIce"/"Ice": UI strings, menus, alerts, permissions texts, Info.plist display names, README, docs, CLAUDE.md, NOTICE, issue templates, Raycast scripts. Exceptions: the credit to the original Ice by Jordan Baird (About, README, NOTICE), the Ice settings import, the `jordanbaird-ice` cask conflict, and past release notes (historical)
- [x] **REN-02**: The "Ice Bar"/"holzIce Bar" feature is called "holzBar Shelf" in the UI and docs
- [x] **REN-03**: Identifiers use holzBar: bundle id `com.holzcloud.holzBar`, XPC service `com.holzcloud.holzBar.MenuBarItemService`, product `holzBar.app`, URL scheme `holzbar://` (the old `holzice://` keeps working as an alias), logger subsystems, Application Support / Caches / iCloud Drive folders `holzBar`, release asset `holzBar-<version>.zip`
- [x] **REN-04**: On first launch holzBar imports the settings and data (layout profiles, item images, iCloud sync file) of an installed holzIce (`com.holzcloud.holzIce`) with the same exclusions as the Ice import, before and instead of the Ice import; holzBar offers to quit a running holzIce like the other conflicting apps
- [x] **REN-05**: The Xcode project, target, scheme, Swift module, source folder (`Ice/`), test targets, file names and type names no longer say Ice (e.g. `IceBar` → `HolzBarShelf`, `IceSection` → `HolzBarSection`); `Ice.xcodeproj` → `holzBar.xcodeproj`; CI, scripts, `.swiftlint.yml`, `Package.swift` follow
- [x] **REN-06**: The new logo (`.planning/ideas/holzbar-logo.svg`: light menu bar with chevron and dots on the holzcloud plank) is the app icon in all sizes, the logo in the settings sidebar next to the title (replaces LEFT-08's holzIce logo), the README banner and `Resources/Logo/`
- [x] **REN-07**: The Homebrew cask is `Casks/holzbar.rb` (token `holzbar`, app `holzBar.app`, zap paths for holzBar, `conflicts_with` holzice and jordanbaird-ice); `cask_renames.json` maps `holzice` → `holzbar` so `brew upgrade` migrates; all install guides use `brew tap holzcloud/holzbar https://github.com/holzcloud/holzBar`, `brew trust --cask holzcloud/holzbar/holzbar`, `brew install --cask holzbar`
- [x] **REN-08**: All links point to `https://github.com/holzcloud/holzBar` and the website `https://holzcloud.ch/holzbar` (`Constants`, README, cask homepage, release workflow); the user renames the GitHub repository

### Bugs

- [x] **BUG-01**: Applying menu bar item spacing relaunches every affected app (`continue` instead of `break`)
- [x] **BUG-02**: Spacing relaunch waits long enough for apps to quit, does not force-terminate them after 1 s, and always resumes its continuation
- [x] **BUG-03**: Spacing relaunch collects the owning apps on macOS 27 too
- [x] **BUG-04**: The event source cache in `MenuBarItemManager` is free of data races
- [x] **BUG-05**: The hotkey recorder rejects combinations that macOS 15+ cannot register (Option or Option+Shift only) and tells the user; the hotkey signature stays identical to Ice's
- [x] **BUG-06**: The XPC menu bar item service accepts the app on ad hoc builds (no team identifier) while still rejecting foreign processes
- [x] **BUG-07**: Waiting for a permission twice never leaves a continuation unresumed
- [x] **BUG-08**: Comment and code of the macOS 27 system item allowlist agree

### Leftovers

- [x] **LEFT-01**: (also fixes the "Ice uses …" sentence found in Phase 01.1 verification) Acknowledgements and license information are shown natively inside the app (a SwiftUI view in About, no PDF/RTF), list the packages actually used with their licenses, and no longer mention Sparkle; `Acknowledgements.pdf`/`.rtf` are removed
- [x] **LEFT-02**: NOTICE and the README credits name Barometer and Thaw for the adapted macOS 27 code
- [x] **LEFT-03**: `FREQUENT_ISSUES.md` describes holzIce (or is removed and its useful parts moved to the README)
- [x] **LEFT-04**: Unused files and dead code are removed (`Resources/rearranging.mov`, `rearranging.gif`, `Icon.png`, `RunLoopLocalEventMonitor.swift`, `ObjectStorage.swift`, the "Copy to Applications" stub phase, `ENABLE_USER_SELECTED_FILES`, redundant `managedItems(for:)`)
- [x] **LEFT-05**: The bug report template asks for holzIce version, macOS version and install method with current placeholders
- [x] **LEFT-06**: README and docs are consistent (Thaw in the conflicting apps list, one bug-report count)
- [x] **LEFT-08**: (superseded by REN-06) The settings sidebar shows the colored holzIce logo as on the website (ice cube with chevron on the wooden plank, sparkle, transparent background — the motif from `Resources/Logo/banner.svg` without the dark tile) to the left of the "holzIce" title, as a vector image asset (`Logo.imageset`, SVG with preserved vector data), sized to the title height
- [x] **LEFT-07**: The hard-coded logger subsystem uses the shared `Logger(category:)`; the `"SU"` exclusion is commented

### Outdated APIs

- [x] **API-01**: `URL.appendingPathComponent` and `URL.path` are replaced by `appending(path:)` / `path(percentEncoded:)`
- [x] **API-02**: `UserDefaults.synchronize()` and the shell relaunch are replaced by `NSWorkspace.openApplication`
- [x] **API-03**: `Host.current()` is gone; settings sync identifies devices by a stored UUID (display name from `SCDynamicStoreCopyComputerName`)
- [x] **API-04**: Spacing writes preferences through `CFPreferences` instead of spawning `defaults`
- [x] **API-05**: `holzice://` URLs arrive through `application(_:open:)` instead of `NSAppleEventManager`
- [x] **API-06**: The Screen Recording deep link uses the current System Settings identifier
- [x] **API-07**: AXSwift is replaced by direct AX calls and removed from both targets
- [x] **DEP-01**: Every Swift package (`Package.resolved`) is on its latest stable release (Ifrit is replaced by holzBar's own fuzzy search — user decision 2026-10-02), and the app still builds and behaves the same
- [x] **API-08**: Windows are opened and closed through a captured `OpenWindowAction`/`DismissWindowAction`, not a fresh `EnvironmentValues()`

### Modern, lean and private

- [x] **LEAN-01**: An analysis of the whole code base (written to `.planning/phases/05.1-modern-lean-and-private/05.1-ANALYSIS.md`) lists everything that can be more modern (2026 Swift/SwiftUI/AppKit idioms), more efficient (CPU, energy, memory, wake-ups, polling), smaller (binary and bundle size, dependencies, assets) and faster (launch time, UI), each with location, gain and risk; the user picks what gets done
- [x] **MOD-01**: Swift 6 language mode for all targets (strict concurrency, no `@unchecked Sendable` without a written reason)
- [x] **MOD-02**: Models use `@Observable` instead of `ObservableObject` + `@Published` + Combine
- [x] **MOD-03**: The old Ice migration chain is collapsed into one import step
- [x] **MOD-04**: `MenuBarItemManager` and `HIDEventManager` are split per backend (pre-26, 26, 27)
- [x] **MOD-05**: Tests for migration, settings import/sync, URL commands and hotkeys
- [x] **MOD-06**: Settings sync uses `NSFileCoordinator` / `NSMetadataQuery`
- [x] **LEAN-02**: Every third-party dependency that the system frameworks can replace without losing a feature is removed (candidates: LaunchAtLogin-Modern → `SMAppService`, CompactSlider, Semaphore, Ifrit); the app bundle is measurably smaller (size before/after in the PR)
- [x] **LEAN-03**: No polling or timer runs while nothing can change (event- and notification-driven instead); idle CPU wake-ups are measured before/after where possible
- [x] **PRIV-01**: The app makes no network connection at all: no telemetry, analytics, crash reporting, update checks or remote fetches; a CI check fails if networking APIs (`URLSession`, `NWConnection`, `Network` framework sockets, web views) appear outside an explicit allowlist (opening links in the browser is allowed); entitlements contain no network client/server entitlement; documented in README ("Principles" section and banner, added in Phase 01.1, kept accurate here)
- [x] **PRIV-02**: No personal data leaves the Mac or lands in logs: logs use `privacy: .private` for anything user-specific, item images and settings stay local (iCloud sync only when the user turns it on)
- [x] **PERM-01**: holzBar asks only for the permissions it really needs, only when a feature needs them, and explains why in the permissions window; every permission, entitlement and Info.plist usage string is listed with the feature that needs it, and anything not needed is removed — without removing a feature

### Thaw fixes and speed

- [x] **THAW-01**: see `.planning/research/THAW.md`
- [x] **THAW-02**: see `.planning/research/THAW.md`
- [x] **THAW-03**: see `.planning/research/THAW.md`
- [x] **THAW-04**: see `.planning/research/THAW.md`
- [x] **THAW-05**: see `.planning/research/THAW.md`
- [x] **THAW-06**: see `.planning/research/THAW.md`
- [x] **THAW-07**: see `.planning/research/THAW.md`
- [x] **THAW-08**: see `.planning/research/THAW.md`

- [x] **ICE-01**: see `.planning/research/THAW.md` (Ice upstream scan)
- [x] **ICE-02**: see THAW.md
- [x] **ICE-03**: see THAW.md
- [x] **ICE-04**: see THAW.md
- [x] **ICE-06**: see THAW.md

### Thaw features

- [x] **THAW-10**: see `.planning/research/THAW.md`
- [x] **THAW-11**: see `.planning/research/THAW.md`
- [x] **THAW-12**: see `.planning/research/THAW.md`
- [x] **THAW-13**: see `.planning/research/THAW.md`
- [x] **THAW-14**: see `.planning/research/THAW.md`
- [x] **THAW-15**: see `.planning/research/THAW.md`
- [x] **THAW-16**: see `.planning/research/THAW.md`
- [x] **THAW-17**: see `.planning/research/THAW.md`

- [x] **SYNC-01**: Settings sync works with any synced folder, not only iCloud Drive: the user picks the folder (iCloud Drive as default, or Nextcloud, Dropbox, OneDrive, Syncthing, a network share …) in an open panel; holzBar only reads and writes `holzBar/Settings.plist` there with file coordination and file presentation (no polling, no network code — the folder's own client syncs); the choice is stored as a bookmark and survives renames; the Settings pane shows the folder and lets the user change or turn off sync; README, permissions table and comparison tables updated ("Settings sync: iCloud Drive or any synced folder")
- [x] **ICE-05**: localization (String Catalog: en, de, fr, it, rm) — see THAW.md

### Security and performance

- [x] **SEC-01**: Settings import and sync only apply known keys with the expected types
- [x] **SEC-02**: URL commands log only the command, not the full URL as public
- [x] **SEC-03**: Captured item images are stored in Caches (excluded from backups), not Application Support; old files are moved or deleted
- [x] **PERF-01**: Show on hover keeps one cancellable task instead of starting a task per mouse move
- [x] **PERF-02**: Permission polling stops once all permissions are granted
- [x] **PERF-04**: The menu bar search tolerates 1–2 typos (own code, no dependency) while in-order matches rank first
- [x] **PERF-03**: Reveal rules react to power and network notifications instead of polling every 60 s

### Toolchain and Apple APIs

- [x] **APPLE-01**: Adopt what Swift 6.4 brings where holzBar does worse today (language features, concurrency, Observation, Testing), and promote "built with Swift 6.4" in the README selling points and on the website
- [x] **APPLE-02**: No deprecated or soon-to-be-deprecated API where Apple names a replacement: build with deprecation warnings visible, review every remaining one (CGWindowList capture of off-screen items is the documented exception), replace the rest
- [x] **APPLE-03**: As soon as Xcode 27 is available on the CI runners (beta allowed by user decision 2026-10-03): build with it, adopt the macOS 27 SDK improvements where holzBar is worse today, and promote it in README and on the website
- [x] **APPLE-04**: UI follows the Human Interface Guidelines (settings layout, menu bar extras, permissions prompts, accessibility)

### Compatibility

- [x] **COMPAT-01**: macOS 26 (Tahoe) and macOS 27 are supported without restriction; this is mandatory
- [x] **COMPAT-02**: For macOS 14 and 15 it is measured (CI builds and tests on macos-14 and macos-15 runners, `#available` branches reviewed) what works and what it costs to keep; the user decides whether to keep them or raise the deployment target to macOS 26 (which removes the pre-26 backend code)
- [x] **COMPAT-03**: README, the cask's `depends_on macos:`, the badge and the release notes state exactly the supported versions

### Release

- [x] **FACT-01**: Before the release, every claim in the README, on the website (all languages) and in the comparison tables is checked against the code and sources and corrected
- [x] **REL-01**: `0.0.6-beta1` (published as 0.0.6) is released with hand-written notes (brew trust, update, quarantine) and the cask points at it

### Security audit

- [x] **AUDIT-01**: Before the release, a full security analysis of the whole app (code, XPC service, URL scheme, settings import/sync, permissions, private APIs, CI/release pipeline, cask) is written to `.planning/` with severity-ranked findings, the user decides which to fix, and those fixes ship in `0.0.6-beta1`

## Milestone 0.0.7 "Automation" (planned 2026-10-04, not started)

Source: `.planning/research/COMPETITORS.md` (gaps, API and permission facts). Every requirement below must keep to the principles in `CLAUDE.md`: no network, no polling where an event exists, least privilege (a permission is asked only when the user adds the feature that needs it, with the reason), pure logic in `holzBar/Core` with Swift Testing tests, five languages (`.github/scripts/strings-check.py`), private logs.

### Triggers (Phase 8)

- [ ] **TRIG-01**: An automation rule is `conditions` (match all or any) plus one `action`; the evaluation is a pure function in `holzBar/Core` (facts in, effects out) with Swift Testing tests for all/any, edge detection (acts once when a rule becomes true), what happens when it ends (restore the previous profile, or nothing), conflicts between rules (first rule in the list wins) and no loop when the effect changes a fact
- [ ] **TRIG-02**: Permission-free conditions: power source and battery level, Low Power Mode, an app running or frontmost, time window and weekdays, a display connected (by UUID), network kind (Wi-Fi, Ethernet, offline, expensive connection). Each is fed by a system notification, never by polling; a monitor exists only while an enabled rule needs its kind (measured: no wakeups with no rules)
- [ ] **TRIG-03**: Condition "connected to the Wi-Fi network named X" asks for Location Services only when the user adds that condition, with the reason shown first (macOS 14+ returns no SSID without it); without the permission the condition shows "needs Location Services" and is never true; the Info.plist usage text and README Permissions table are updated
- [ ] **TRIG-04**: A layout profile can be applied by a Focus filter (`SetFocusFilterIntent`) with no permission; shipped only if a spike on macOS 26 and 27 shows the system calls the intent, otherwise recorded as not possible
- [ ] **TRIG-05**: Actions: apply a layout profile, show a section for the usual interval, turn Zen mode on or off; applying a profile never re-applies the one already active
- [ ] **TRIG-06**: The existing "show on low battery" and "show when offline" rules become rules of the engine; existing users' settings carry over unchanged
- [ ] **TRIG-07**: A settings pane lists, adds, edits, reorders, enables and deletes rules (HIG: list with add and remove, forms, plain wording), reachable with VoiceOver and keyboard; all strings exist in English, German, French, Italian and Romansh
- [ ] **TRIG-08**: Rules are exported, imported and synced like other settings, validated (known condition kinds, ranges, at most 50 rules, profile names looked up, unknown ones disable the rule); logs never contain SSIDs or app names in public
- [ ] **TRIG-09**: URL commands and Shortcuts can list, enable and disable rules and tell which are active; they cannot create or edit a rule; lasting changes ask first like the other URL commands

### Scripts (Phase 9)

- [ ] **SCRIPT-01**: A security design and threat-register entries (`SECURITY.md`) exist before any code: privilege escalation through a script runner, same-user malware, settings import/sync/URL as injection paths, quarantine, TCC inheritance (see `.planning/phases/09-scripts/PLAN.md`)
- [ ] **SCRIPT-02**: Scripts run only from a folder the user chose, only regular files owned by the user and not writable by group or others, never through a symbolic link out of the folder, never with a quarantine attribute; run by `Process` (or `NSUserScriptTask` if the spike proves it safer) with a fixed executable, no shell, no arguments, a minimal environment, stdin closed, a timeout, an output size limit and a rate limit
- [ ] **SCRIPT-03**: The first run of a script, and the first run after its content changes (SHA-256), needs the user's confirmation naming the file, its folder and what it will be able to do; approvals are local
- [ ] **SCRIPT-04**: Script bindings, folder, approvals and hashes never leave the Mac: not exported, not imported, not synced, not settable by URL or Shortcuts; an imported or synced rule that names a script is dropped and reported
- [ ] **SCRIPT-05**: A script can be a condition (exit status 0 means true; evaluated on the engine's events and a manual re-check, plus an optional interval of at least 5 minutes that the pane labels as polling) and an action of a rule (run once when the rule becomes true or ends); output is data: shown as plain text, length-limited, never run or opened
- [ ] **SCRIPT-06**: AppleScript files (`.scpt`, `.applescript`) run through the same gate; the pane tells that scripts run with holzBar's permissions and that macOS asks separately before a script controls another app

### Widgets (Phase 10, staged)

- [ ] **WIDG-01**: The user can add a widget: an extra menu bar item (status item) with a text label from a built-in source, placed in a section like any other item and kept there by the holzBar hiding model on macOS 14 to 27; at most 6
- [ ] **WIDG-02**: Built-in sources need no permission: date and time, battery percent and state, CPU load, memory use, uptime; each refreshes on a timer only while the item is visible and the screen is awake (no timer while hidden, asleep or locked), and from notifications where they exist (battery)
- [ ] **WIDG-03**: A widget can be a button that runs a Shortcut chosen by name, with no permission request of its own
- [ ] **WIDG-04**: Widgets are in the layout editor, search and profiles like other items, can be exported, imported and synced (kind, source, format only), and are accessible (VoiceOver label, value)
- [ ] **WIDG-05** (stage 2, after Phase 9): a widget can show the first line of a script's output under the SCRIPT rules

### Competitor gaps (Phases 11 to 13)

- [ ] **LOCK-01**: Showing hidden items can require the Mac's owner (Touch ID or password through `LocalAuthentication`), no permission and no network; Settings says what it protects
- [ ] **ANIM-01**: Showing and hiding can animate, only for the duration of the change, with no timer while idle, and off when Reduce Motion is on
- [ ] **DESK-01**: A spike decides whether desktop icons can be hidden without a private API or a Finder restart; shipped only if yes, otherwise dropped and recorded

### Release 0.0.7

- [ ] **FACT-02**: README, website, comparison tables and Permissions table are re-checked and updated for what shipped (🔜 rows only for what is planned and says so)
- [ ] **REL-02**: `0.0.7-beta1` (and further numbered betas) released with hand-written notes (brew trust, update, quarantine)

## v2 Requirements

(MOD-01 to MOD-06 moved into v1, Phase 05.1)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Changing the hotkey signature | Must stay identical to Ice (user decision) |
| Replacing Carbon hotkeys | Only public API for global hotkeys without Input Monitoring |
| Replacing CGWindowList capture | ScreenCaptureKit cannot capture off-screen item windows |
| Replacing private APIs (CGS, MenuBarClientCore) | No public equivalent |
| Developer ID signing / notarization | Rejected by the user |
| Raising the deployment target | macOS 14 stays supported |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CI-01 | Phase 1 | Complete |
| CI-02 | Phase 1 | Complete |
| CI-03 | Phase 1 | Complete |
| CI-04 | Phase 1 | Complete |
| CI-05 | Phase 1 | Complete |
| CI-06 | Phase 1 | Complete |
| CI-07 | Phase 1 | Complete |
| REN-01 | Phase 01.1 | Complete |
| REN-02 | Phase 01.1 | Complete |
| REN-03 | Phase 01.1 | Complete |
| REN-04 | Phase 01.1 | Complete |
| REN-05 | Phase 01.1 | Complete |
| REN-06 | Phase 01.1 | Complete |
| REN-07 | Phase 01.1 | Complete |
| REN-08 | Phase 01.1 | Complete |
| BUG-01 | Phase 2 | Complete |
| BUG-02 | Phase 2 | Complete |
| BUG-03 | Phase 2 | Complete |
| BUG-04 | Phase 2 | Complete |
| BUG-05 | Phase 2 | Complete |
| BUG-06 | Phase 2 | Complete |
| BUG-07 | Phase 2 | Complete |
| BUG-08 | Phase 2 | Complete |
| LEFT-01 | Phase 3 | Complete |
| LEFT-02 | Phase 3 | Complete |
| LEFT-03 | Phase 3 | Complete |
| LEFT-04 | Phase 3 | Complete |
| LEFT-05 | Phase 3 | Complete |
| LEFT-06 | Phase 3 | Complete |
| LEFT-08 | Phase 3 | Complete |
| LEFT-07 | Phase 3 | Complete |
| API-01 | Phase 4 | Complete |
| API-02 | Phase 4 | Complete |
| API-03 | Phase 4 | Complete |
| API-04 | Phase 4 | Complete |
| API-05 | Phase 4 | Complete |
| API-06 | Phase 4 | Complete |
| API-07 | Phase 4 | Complete |
| DEP-01 | Phase 4 | Complete |
| API-08 | Phase 4 | Complete |
| SEC-01 | Phase 5 | Complete |
| SEC-02 | Phase 5 | Complete |
| SEC-03 | Phase 5 | Complete |
| PERF-01 | Phase 5 | Complete |
| PERF-02 | Phase 5 | Complete |
| PERF-04 | Phase 5 | Complete |
| PERF-03 | Phase 5 | Complete |
| LEAN-01 | Phase 05.1 | Complete |
| MOD-01 | Phase 05.1 | Complete |
| MOD-02 | Phase 05.1 | Complete |
| MOD-03 | Phase 05.1 | Complete |
| MOD-04 | Phase 05.1 | Complete |
| MOD-05 | Phase 05.1 | Complete |
| MOD-06 | Phase 05.1 | Complete |
| LEAN-02 | Phase 05.1 | Complete |
| LEAN-03 | Phase 05.1 | Complete |
| PRIV-01 | Phase 05.1 | Complete |
| PRIV-02 | Phase 05.1 | Complete |
| PERM-01 | Phase 05.1 | Complete |
| THAW-01 | Phase 05.1.1 | Complete |
| THAW-02 | Phase 05.1.1 | Complete |
| THAW-03 | Phase 05.1.1 | Complete |
| THAW-04 | Phase 05.1.1 | Complete |
| THAW-05 | Phase 05.1.1 | Complete |
| THAW-06 | Phase 05.1.1 | Complete |
| THAW-07 | Phase 05.1.1 | Complete |
| THAW-08 | Phase 05.1.1 | Complete |
| THAW-10 | Phase 05.1.1.1 | Complete |
| THAW-11 | Phase 05.1.1.1 | Complete |
| THAW-12 | Phase 05.1.1.1 | Complete |
| THAW-13 | Phase 05.1.1.1 | Complete |
| THAW-14 | Phase 05.1.1.1 | Complete |
| THAW-15 | Phase 05.1.1.1 | Complete |
| THAW-16 | Phase 05.1.1.1 | Complete |
| THAW-17 | Phase 05.1.1.1 | Complete |
| ICE-01 | Phase 05.1.1 | Complete |
| ICE-02 | Phase 05.1.1 | Complete |
| ICE-03 | Phase 05.1.1 | Complete |
| ICE-04 | Phase 05.1.1 | Complete |
| ICE-06 | Phase 05.1.1 | Complete |
| SYNC-01 | Phase 05.1.1.1 | Complete |
| ICE-05 | Phase 05.1.1.1 | Complete |
| AUDIT-01 | Phase 6 | Complete |
| COMPAT-01 | Phase 06.1 | Complete (CI launch on 26 and 27; real-Mac checklist by the user) |
| COMPAT-02 | Phase 06.1 | Complete (decision: keep macOS 14+) |
| COMPAT-03 | Phase 06.1 | Complete |
| APPLE-01 | Phase 05.1.1.1.1 | Complete |
| APPLE-02 | Phase 05.1.1.1.1 | Complete |
| APPLE-03 | Phase 05.1.1.1.1 | Complete |
| APPLE-04 | Phase 05.1.1.1.1 | Complete |
| FACT-01 | Phase 7 | Complete (0.0.6) |
| REL-01 | Phase 7 | Complete (released as 0.0.6, stable) |
| TRIG-01 | Phase 8 | Planned |
| TRIG-02 | Phase 8 | Planned |
| TRIG-03 | Phase 8 | Planned |
| TRIG-04 | Phase 8 | Planned |
| TRIG-05 | Phase 8 | Planned |
| TRIG-06 | Phase 8 | Planned |
| TRIG-07 | Phase 8 | Planned |
| TRIG-08 | Phase 8 | Planned |
| TRIG-09 | Phase 8 | Planned |
| SCRIPT-01 | Phase 9 | Planned |
| SCRIPT-02 | Phase 9 | Planned |
| SCRIPT-03 | Phase 9 | Planned |
| SCRIPT-04 | Phase 9 | Planned |
| SCRIPT-05 | Phase 9 | Planned |
| SCRIPT-06 | Phase 9 | Planned |
| WIDG-01 | Phase 10 | Planned (WIDG-05 stage 2) |
| WIDG-02 | Phase 10 | Planned (WIDG-05 stage 2) |
| WIDG-03 | Phase 10 | Planned (WIDG-05 stage 2) |
| WIDG-04 | Phase 10 | Planned (WIDG-05 stage 2) |
| WIDG-05 | Phase 10 | Planned (WIDG-05 stage 2) |
| LOCK-01 | Phase 11 | Planned |
| ANIM-01 | Phase 12 | Planned |
| DESK-01 | Phase 13 | Planned (spike) |
| FACT-02 | Phase 14 | Planned |
| REL-02 | Phase 14 | Planned |

**Coverage:**
- v1 requirements: 63 total, all mapped
- Milestone 0.0.7 "Automation": 25 requirements, all mapped to phases 8 to 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-02*
*Last updated: 2026-10-04 after planning milestone 0.0.7 "Automation"*
