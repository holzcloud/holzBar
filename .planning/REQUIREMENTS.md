# Requirements: holzIce — Modernize

**Defined:** 2026-10-02
**Core Value:** The menu bar items a user hides stay hidden and come back when asked, on every supported macOS version, without the app ever locking up the Mac.

Source: `.planning/codebase/CONCERNS.md` (file:line references there).

## v1 Requirements

### CI and build

- [ ] **CI-01**: Workflows use current action versions (`actions/checkout` v5 or newer) and no deprecated runtime warnings remain
- [ ] **CI-02**: SwiftLint runs with a maintained setup (official SwiftLint, not `norio-nomura/action-swiftlint@3.2.1`) and still passes `--strict`
- [ ] **CI-03**: The unit tests (`swift test`, `Tests/IceMacOS27CoreTests`) run on every pull request
- [ ] **CI-04**: The build workflow prints compiler warnings (deprecations) so they are visible in the log
- [ ] **CI-05**: Xcode version is pinned explicitly in CI and the README states the real build requirement
- [ ] **CI-06**: The Xcode project carries holzIce's version (not `0.11.13-dev.2a`) and no Development Team of the original project; `Scripts/install.sh` builds for anyone (ad hoc signing)
- [ ] **CI-07**: `release.yml` uses the `0.0.6-beta1` scheme in its examples/comments, checks the release notes once, and passes the version input through an environment variable instead of inline `${{ }}` in shell

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

- [ ] **LEFT-01**: Acknowledgements (RTF and PDF shown in About) no longer list Sparkle and do list the packages actually used
- [ ] **LEFT-02**: NOTICE and the README credits name Barometer and Thaw for the adapted macOS 27 code
- [ ] **LEFT-03**: `FREQUENT_ISSUES.md` describes holzIce (or is removed and its useful parts moved to the README)
- [ ] **LEFT-04**: Unused files and dead code are removed (`Resources/rearranging.mov`, `rearranging.gif`, `Icon.png`, `RunLoopLocalEventMonitor.swift`, `ObjectStorage.swift`, the "Copy to Applications" stub phase, `ENABLE_USER_SELECTED_FILES`, redundant `managedItems(for:)`)
- [ ] **LEFT-05**: The bug report template asks for holzIce version, macOS version and install method with current placeholders
- [ ] **LEFT-06**: README and docs are consistent (Thaw in the conflicting apps list, one bug-report count)
- [ ] **LEFT-07**: The hard-coded logger subsystem uses the shared `Logger(category:)`; the `"SU"` exclusion is commented

### Outdated APIs

- [ ] **API-01**: `URL.appendingPathComponent` and `URL.path` are replaced by `appending(path:)` / `path(percentEncoded:)`
- [ ] **API-02**: `UserDefaults.synchronize()` and the shell relaunch are replaced by `NSWorkspace.openApplication`
- [ ] **API-03**: `Host.current()` is gone; settings sync identifies devices by a stored UUID (display name from `SCDynamicStoreCopyComputerName`)
- [ ] **API-04**: Spacing writes preferences through `CFPreferences` instead of spawning `defaults`
- [ ] **API-05**: `holzice://` URLs arrive through `application(_:open:)` instead of `NSAppleEventManager`
- [ ] **API-06**: The Screen Recording deep link uses the current System Settings identifier
- [ ] **API-07**: AXSwift is replaced by direct AX calls and removed from both targets
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

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 0
- Unmapped: 37 ⚠️

---
*Requirements defined: 2026-10-02*
*Last updated: 2026-10-02 after initial definition*
