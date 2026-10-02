# Roadmap: holzIce

## Overview

The "Modernize" milestone removes everything outdated that the codebase audit (`.planning/codebase/CONCERNS.md`) found, then publishes `0.0.6-beta1`. CI and build come first so every later change is compiled, linted and tested on the macOS runner (there is no local compiler). Then the real bugs, the Ice and Sparkle leftovers, the outdated APIs, and the security and performance findings follow, each as one pull request that must build green. The last phase is the small beta release.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: CI and build** - Current actions, maintained SwiftLint, unit tests on every PR, visible warnings, pinned Xcode, holzIce project metadata
- [ ] **Phase 2: Bug fixes** - Spacing relaunch, data race, hotkey recorder, XPC ad hoc check, permission continuation, allowlist
- [ ] **Phase 3: Ice and Sparkle leftovers** - Acknowledgements, credits, docs, templates, dead code and files removed
- [ ] **Phase 4: Outdated APIs** - Modern URL, UserDefaults, CFPreferences, URL-open, window and AX APIs; AXSwift removed
- [ ] **Phase 5: Security and performance** - Validated settings import, private logging, Caches storage, no needless tasks or polling
- [ ] **Phase 6: Release 0.0.6-beta1** - Tag, hand-written release notes, cask updated
- [ ] **Phase 7: Security audit** - Full security analysis of the whole app, findings ranked, user decides fixes

Each phase is one pull request and must build green on the macOS CI runner before merge.

## Phase Details

### Phase 1: CI and build
**Goal**: Every pull request is built, linted and tested with current, pinned tooling, and the project carries holzIce's own identity
**Depends on**: Nothing (first phase)
**Requirements**: CI-01, CI-02, CI-03, CI-04, CI-05, CI-06, CI-07
**Success Criteria** (what must be TRUE):
  1. A pull request run shows no deprecated-runtime warnings from the workflows, which use `actions/checkout` v5 or newer
  2. The lint job runs official SwiftLint with `--strict` and passes
  3. The `swift test` job for `Tests/IceMacOS27CoreTests` runs on every pull request and passes
  4. The build log lists compiler warnings, and the CI Xcode version is pinned and matches the README's stated build requirement
  5. The Xcode project reports holzIce's version with no foreign Development Team, and `Scripts/install.sh` builds with ad hoc signing; `release.yml` uses the `0.0.6-beta1` scheme and passes the version through an environment variable
**Plans**: TBD

### Phase 2: Bug fixes
**Goal**: The real bugs found by the audit are fixed so spacing, hotkeys, XPC and permissions behave correctly on every supported macOS version
**Depends on**: Phase 1
**Requirements**: BUG-01, BUG-02, BUG-03, BUG-04, BUG-05, BUG-06, BUG-07, BUG-08
**Success Criteria** (what must be TRUE):
  1. Applying menu bar item spacing relaunches every affected app, waits for them to quit without force-terminating after 1 s, and works on macOS 27 too
  2. The hotkey recorder rejects combinations macOS 15+ cannot register (only Option or Option+Shift are allowed) and tells the user, while the hotkey signature stays identical to Ice's
  3. An ad hoc build is accepted by the XPC menu bar item service, and foreign processes are still rejected
  4. Waiting for a permission twice never hangs, and the event source cache has no data race
  5. The macOS 27 system item allowlist comment and code agree
**Plans**: TBD

### Phase 3: Ice and Sparkle leftovers
**Goal**: Nothing of Ice or Sparkle remains unless it is credited, and the repository contains no unused files or dead code
**Depends on**: Phase 2
**Requirements**: LEFT-01, LEFT-02, LEFT-03, LEFT-04, LEFT-05, LEFT-06, LEFT-07
**Success Criteria** (what must be TRUE):
  1. Acknowledgements and licenses are shown natively in the app (no PDF/RTF), list the packages actually used and no longer mention Sparkle
  2. NOTICE and the README credit Barometer and Thaw for the adapted macOS 27 code, and the README and docs agree (Thaw listed as conflicting app, one bug-report count)
  3. `FREQUENT_ISSUES.md` describes holzIce (or is gone) and the bug report template asks for holzIce version, macOS version and install method
  4. The listed unused files, stub build phase, setting and redundant code are gone and the app still builds
  5. The logger subsystem uses the shared `Logger(category:)` and the `"SU"` exclusion is commented
**Plans**: TBD

### Phase 4: Outdated APIs
**Goal**: Deprecated and outdated APIs are replaced by their macOS 14 compatible modern equivalents, and AXSwift is removed
**Depends on**: Phase 3
**Requirements**: API-01, API-02, API-03, API-04, API-05, API-06, API-07, API-08
**Success Criteria** (what must be TRUE):
  1. The app relaunches through `NSWorkspace.openApplication`, spacing writes use `CFPreferences`, and no `defaults` process or shell relaunch is spawned
  2. `holzice://` URL commands still work, arriving through `application(_:open:)`
  3. Settings sync identifies devices by a stored UUID with the computer name as display name, and `Host.current()` is gone
  4. The Screen Recording link opens the correct System Settings pane, and windows open and close through a captured `OpenWindowAction`/`DismissWindowAction`
  5. AXSwift is no longer a dependency of either target, and the menu bar items are still discovered through direct AX calls
**Plans**: TBD
**UI hint**: yes

### Phase 5: Security and performance
**Goal**: Imported data is validated, private data stays private, and the app does no needless background work
**Depends on**: Phase 4
**Requirements**: SEC-01, SEC-02, SEC-03, PERF-01, PERF-02, PERF-03
**Success Criteria** (what must be TRUE):
  1. Importing or syncing settings applies only known keys with the expected types and ignores the rest
  2. The log shows only the command of a URL command, not the full URL
  3. Captured item images are stored in Caches, and old files in Application Support are moved or deleted
  4. Moving the mouse over show-on-hover keeps one cancellable task, and permission polling stops once all permissions are granted
  5. Reveal rules react to power and network notifications instead of polling every 60 s
**Plans**: TBD

### Phase 6: Release 0.0.6-beta1
**Goal**: Users can install and update to `0.0.6-beta1` through Homebrew with clear instructions
**Depends on**: Phase 5
**Requirements**: REL-01
**Success Criteria** (what must be TRUE):
  1. The `v0.0.6-beta1` GitHub pre-release exists with hand-written notes from `docs/release-notes/v0.0.6-beta1.md`
  2. The notes' install section covers `brew tap`, `brew trust`, `brew install`, the `brew update && brew upgrade` path and the quarantine command
  3. The cask on `main` points at `0.0.6-beta1`
**Plans**: TBD

### Phase 7: Security audit
**Goal**: The user knows every security risk of the app, ranked, and has decided which to fix
**Depends on**: Phase 6
**Requirements**: AUDIT-01
**Success Criteria** (what must be TRUE):
  1. A security report covers the app, the XPC service, the URL scheme, settings import/sync, permissions, private APIs, CI/release pipeline and the cask
  2. Every finding has a severity, a location and a proposed fix
  3. The user has chosen which findings become follow-up work
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CI and build | 0/0 | Not started | - |
| 2. Bug fixes | 0/0 | Not started | - |
| 3. Ice and Sparkle leftovers | 0/0 | Not started | - |
| 4. Outdated APIs | 0/0 | Not started | - |
| 5. Security and performance | 0/0 | Not started | - |
| 6. Release 0.0.6-beta1 | 0/0 | Not started | - |
| 7. Security audit | 0/0 | Not started | - |
