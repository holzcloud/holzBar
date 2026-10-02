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

- [ ] **REN-01**: Every user-visible text says "holzBar" (written exactly so) instead of "holzIce"/"Ice": UI strings, menus, alerts, permissions texts, Info.plist display names, README, docs, CLAUDE.md, NOTICE, issue templates, Raycast scripts. Exceptions: the credit to the original Ice by Jordan Baird (About, README, NOTICE), the Ice settings import, the `jordanbaird-ice` cask conflict, and past release notes (historical)
- [ ] **REN-02**: The "Ice Bar"/"holzIce Bar" feature is called "holzBar Shelf" in the UI and docs
- [x] **REN-03**: Identifiers use holzBar: bundle id `com.holzcloud.holzBar`, XPC service `com.holzcloud.holzBar.MenuBarItemService`, product `holzBar.app`, URL scheme `holzbar://` (the old `holzice://` keeps working as an alias), logger subsystems, Application Support / Caches / iCloud Drive folders `holzBar`, release asset `holzBar-<version>.zip`
- [ ] **REN-04**: On first launch holzBar imports the settings and data (layout profiles, item images, iCloud sync file) of an installed holzIce (`com.holzcloud.holzIce`) with the same exclusions as the Ice import, before and instead of the Ice import; holzBar offers to quit a running holzIce like the other conflicting apps
- [x] **REN-05**: The Xcode project, target, scheme, Swift module, source folder (`Ice/`), test targets, file names and type names no longer say Ice (e.g. `IceBar` → `HolzBarShelf`, `IceSection` → `HolzBarSection`); `Ice.xcodeproj` → `holzBar.xcodeproj`; CI, scripts, `.swiftlint.yml`, `Package.swift` follow
- [ ] **REN-06**: The new logo (`.planning/ideas/holzbar-logo.svg`: light menu bar with chevron and dots on the holzcloud plank) is the app icon in all sizes, the logo in the settings sidebar next to the title (replaces LEFT-08's holzIce logo), the README banner and `Resources/Logo/`
- [ ] **REN-07**: The Homebrew cask is `Casks/holzbar.rb` (token `holzbar`, app `holzBar.app`, zap paths for holzBar, `conflicts_with` holzice and jordanbaird-ice); `cask_renames.json` maps `holzice` → `holzbar` so `brew upgrade` migrates; all install guides use `brew tap holzcloud/holzbar https://github.com/holzcloud/holzBar`, `brew trust --cask holzcloud/holzbar/holzbar`, `brew install --cask holzbar`
- [ ] **REN-08**: All links point to `https://github.com/holzcloud/holzBar` and the website `https://holzcloud.ch/holzbar` (`Constants`, README, cask homepage, release workflow); the user renames the GitHub repository

### Bugs

- [ ] **BUG-01**: Applying menu bar item spacing relaunches every affected app (`continue` instead of `break`)
- [ ] **BUG-02**: Spacing relaunch waits long enough for apps to quit, does not force-terminate them after 1 s, and always resumes its continuation
- [ ] **BUG-03**: Spacing relaunch collects the owning apps on macOS 27 too
- [ ] **BUG-04**: The event source cache in `MenuBarItemManager` is free of data races
- [ ] **BUG-05**: The hotkey recorder rejects combinations that macOS 15+ cannot register (Option or Option+Shift only) and tells the user; the hotkey signature stays identical to Ice's
- [ ] **BUG-06**: The XPC menu bar item service accepts the app on ad hoc builds (no team identifier) while still rejecting foreign processes
- [ ] **BUG-07**: Waiting for a permission twice never leaves a continuation unresumed
- [ ] **BUG-08**: Comment and code of the macOS 27 system item allowlist agree

### Leftovers

- [ ] **LEFT-01**: Acknowledgements and license information are shown natively inside the app (a SwiftUI view in About, no PDF/RTF), list the packages actually used with their licenses, and no longer mention Sparkle; `Acknowledgements.pdf`/`.rtf` are removed
- [ ] **LEFT-02**: NOTICE and the README credits name Barometer and Thaw for the adapted macOS 27 code
- [ ] **LEFT-03**: `FREQUENT_ISSUES.md` describes holzIce (or is removed and its useful parts moved to the README)
- [ ] **LEFT-04**: Unused files and dead code are removed (`Resources/rearranging.mov`, `rearranging.gif`, `Icon.png`, `RunLoopLocalEventMonitor.swift`, `ObjectStorage.swift`, the "Copy to Applications" stub phase, `ENABLE_USER_SELECTED_FILES`, redundant `managedItems(for:)`)
- [ ] **LEFT-05**: The bug report template asks for holzIce version, macOS version and install method with current placeholders
- [ ] **LEFT-06**: README and docs are consistent (Thaw in the conflicting apps list, one bug-report count)
- [ ] **LEFT-08**: (superseded by REN-06) The settings sidebar shows the colored holzIce logo as on the website (ice cube with chevron on the wooden plank, sparkle, transparent background — the motif from `Resources/Logo/banner.svg` without the dark tile) to the left of the "holzIce" title, as a vector image asset (`Logo.imageset`, SVG with preserved vector data), sized to the title height
- [ ] **LEFT-07**: The hard-coded logger subsystem uses the shared `Logger(category:)`; the `"SU"` exclusion is commented

### Outdated APIs

- [ ] **API-01**: `URL.appendingPathComponent` and `URL.path` are replaced by `appending(path:)` / `path(percentEncoded:)`
- [ ] **API-02**: `UserDefaults.synchronize()` and the shell relaunch are replaced by `NSWorkspace.openApplication`
- [ ] **API-03**: `Host.current()` is gone; settings sync identifies devices by a stored UUID (display name from `SCDynamicStoreCopyComputerName`)
- [ ] **API-04**: Spacing writes preferences through `CFPreferences` instead of spawning `defaults`
- [ ] **API-05**: `holzice://` URLs arrive through `application(_:open:)` instead of `NSAppleEventManager`
- [ ] **API-06**: The Screen Recording deep link uses the current System Settings identifier
- [ ] **API-07**: AXSwift is replaced by direct AX calls and removed from both targets
- [ ] **DEP-01**: Every Swift package (`Package.resolved`) is on its latest stable release (e.g. Ifrit 2.0.6 → latest), and the app still builds and behaves the same
- [ ] **API-08**: Windows are opened and closed through a captured `OpenWindowAction`/`DismissWindowAction`, not a fresh `EnvironmentValues()`

### Security and performance

- [ ] **SEC-01**: Settings import and sync only apply known keys with the expected types
- [ ] **SEC-02**: URL commands log only the command, not the full URL as public
- [ ] **SEC-03**: Captured item images are stored in Caches (excluded from backups), not Application Support; old files are moved or deleted
- [ ] **PERF-01**: Show on hover keeps one cancellable task instead of starting a task per mouse move
- [ ] **PERF-02**: Permission polling stops once all permissions are granted
- [ ] **PERF-03**: Reveal rules react to power and network notifications instead of polling every 60 s

### Release

- [ ] **REL-01**: `0.0.6-beta1` is released with hand-written notes (brew trust, update, quarantine) and the cask points at it

### Security audit

- [ ] **AUDIT-01**: Before the release, a full security analysis of the whole app (code, XPC service, URL scheme, settings import/sync, permissions, private APIs, CI/release pipeline, cask) is written to `.planning/` with severity-ranked findings, the user decides which to fix, and those fixes ship in `0.0.6-beta1`

## v2 Requirements

- **MOD-01**: Swift 6 language mode for all targets
- **MOD-02**: Models use `@Observable` instead of `ObservableObject` + Combine
- **MOD-03**: Ice migration chain collapsed into one import step
- **MOD-04**: `MenuBarItemManager` and `HIDEventManager` split per backend
- **MOD-05**: Tests for migration, settings import/sync, URL commands, hotkeys
- **MOD-06**: Settings sync with `NSFileCoordinator` / `NSMetadataQuery`

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
| REN-01 | Phase 01.1 | Pending |
| REN-02 | Phase 01.1 | Pending |
| REN-03 | Phase 01.1 | Complete |
| REN-04 | Phase 01.1 | Pending |
| REN-05 | Phase 01.1 | Complete |
| REN-06 | Phase 01.1 | Pending |
| REN-07 | Phase 01.1 | Pending |
| REN-08 | Phase 01.1 | Pending |
| BUG-01 | Phase 2 | Pending |
| BUG-02 | Phase 2 | Pending |
| BUG-03 | Phase 2 | Pending |
| BUG-04 | Phase 2 | Pending |
| BUG-05 | Phase 2 | Pending |
| BUG-06 | Phase 2 | Pending |
| BUG-07 | Phase 2 | Pending |
| BUG-08 | Phase 2 | Pending |
| LEFT-01 | Phase 3 | Pending |
| LEFT-02 | Phase 3 | Pending |
| LEFT-03 | Phase 3 | Pending |
| LEFT-04 | Phase 3 | Pending |
| LEFT-05 | Phase 3 | Pending |
| LEFT-06 | Phase 3 | Pending |
| LEFT-08 | Phase 3 | Pending |
| LEFT-07 | Phase 3 | Pending |
| API-01 | Phase 4 | Pending |
| API-02 | Phase 4 | Pending |
| API-03 | Phase 4 | Pending |
| API-04 | Phase 4 | Pending |
| API-05 | Phase 4 | Pending |
| API-06 | Phase 4 | Pending |
| API-07 | Phase 4 | Pending |
| DEP-01 | Phase 4 | Pending |
| API-08 | Phase 4 | Pending |
| SEC-01 | Phase 5 | Pending |
| SEC-02 | Phase 5 | Pending |
| SEC-03 | Phase 5 | Pending |
| PERF-01 | Phase 5 | Pending |
| PERF-02 | Phase 5 | Pending |
| PERF-03 | Phase 5 | Pending |
| AUDIT-01 | Phase 6 | Pending |
| REL-01 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 48 total
- Mapped to phases: 48
- Unmapped: 0 ✓

---
*Requirements defined: 2026-10-02*
*Last updated: 2026-10-02 after initial definition*
