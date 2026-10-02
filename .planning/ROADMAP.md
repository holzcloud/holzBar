# Roadmap: holzIce

## Overview

The "Modernize" milestone removes everything outdated that the codebase audit (`.planning/codebase/CONCERNS.md`) found, then publishes `0.0.6-beta1`. CI and build come first so every later change is compiled, linted and tested on the macOS runner (there is no local compiler). Then the real bugs, the Ice and Sparkle leftovers, the outdated APIs, and the security and performance findings follow, each as one pull request that must build green. The last phase is the small beta release.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: CI and build** - Current actions, maintained SwiftLint, unit tests on every PR, visible warnings, pinned Xcode, holzIce project metadata
- [ ] **Phase 01.1: Rename to holzBar** (INSERTED) - Name, logo, identifiers, code and links say holzBar; holzIce settings are imported
- [ ] **Phase 2: Bug fixes** - Spacing relaunch, data race, hotkey recorder, XPC ad hoc check, permission continuation, allowlist
- [ ] **Phase 3: Ice and Sparkle leftovers** - Acknowledgements, credits, docs, templates, dead code and files removed
- [ ] **Phase 4: Outdated APIs** - Modern URL, UserDefaults, CFPreferences, URL-open, window and AX APIs; AXSwift removed
- [ ] **Phase 5: Security and performance** - Validated settings import, private logging, Caches storage, no needless tasks or polling
- [ ] **Phase 05.1: Modern, lean and private** (INSERTED) - 2026 code, Swift 6, @Observable, fewer dependencies, no network, least privilege
- [ ] **Phase 6: Security audit** - Full security analysis of the whole app, findings ranked, fixes chosen by the user done before the release
- [ ] **Phase 7: Release 0.0.6-beta1** - Tag, hand-written release notes, cask updated

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

**Plans**: 3/3 plans executed (sequential waves: one PR branch, every task verified by its CI checks)

Plans:
- [x] 01-01-PLAN.md — Tracer: pinned Xcode 26.6 (composite action, fails loudly), `swift test` job on every PR, compiler warnings in the build log, checkout v7, phase PR opened
- [x] 01-02-PLAN.md — Official SwiftLint 0.65.1 (digest-pinned image) with `--strict`; fix or deliberately configure what it reports
- [x] 01-03-PLAN.md — holzIce version and no foreign team in the project, ad hoc `install.sh`, README build requirement, hardened `release.yml`; PR ready for review

### Phase 01.1: Rename to holzBar (INSERTED)

**Goal:** The app is called holzBar everywhere — name, logo, identifiers, code, project, repository links, cask — while the credit to the original Ice stays and existing holzIce users keep their settings
**Requirements**: REN-01, REN-02, REN-03, REN-04, REN-05, REN-06, REN-07, REN-08
**Depends on:** Phase 1
**Success Criteria** (what must be TRUE):
  1. No user-visible "holzIce" or "Ice" remains except the credit to the original Ice (About, README, NOTICE) and the Ice settings import; the Ice Bar is called "holzBar Shelf"
  2. Bundle id, XPC service, product, URL scheme, cask, folders and links use holzBar (`com.holzcloud.holzBar`, `holzBar.app`, `holzbar://`, `holzcloud/holzBar`)
  3. On first launch holzBar imports the settings and data of an installed holzIce; `brew upgrade` moves holzIce users to the holzbar cask
  4. The Xcode project, target, scheme, module, source folder and type names no longer say Ice; build, test and swiftlint are green
  5. The new logo is in the app icon, the settings sidebar, README banner and Resources/Logo

**Plans:** 4/6 plans executed (sequential waves: one PR branch, every task verified by its CI checks)

Plans:
- [x] 01.1-01-PLAN.md — Tracer: holzBar.xcodeproj, target/scheme/module holzBar, folder holzBar/, test package HolzBarMacOS27Core, bundle ids com.holzcloud.holzBar(.MenuBarItemService) with a CI identifier check; phase PR opened
- [x] 01.1-02-PLAN.md — Type, file and folder names: HolzBar<Name> UI components, HolzBarShelf<Name> in MenuBar/Shelf/, shelf/holzBarIcon members; stored key strings unchanged
- [x] 01.1-03-PLAN.md — Every Swift text and comment says holzBar / holzBar Shelf; holzBar data folders, autosave names and links; developer scripts, docs and issue templates
- [x] 01.1-04-PLAN.md — First-launch import of holzIce's settings, item images and iCloud file (before Ice's); ConflictingApps quits holzIce; holzbar:// with holzice:// alias; Raycast scripts
- [ ] 01.1-05-PLAN.md — holzBar logo: app icon in all sizes, vector sidebar logo next to the title, Resources/Logo/holzBar.svg, banner.svg/png
- [ ] 01.1-06-PLAN.md — Casks/holzbar.rb + cask_renames.json proven by a cask CI job, release workflow, README/NOTICE/CLAUDE.md; user renames the repository after the merge

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

**Plans**: 4 plans (sequential waves: one PR branch, every task verified by its CI checks)

Plans:
- [ ] 02-01-PLAN.md — Tracer: tested `Ice/Core` package target; spacing relaunch keeps going past skipped processes (MenuBarAgent skipped on macOS 27), 10 s quit wait, no force-termination; phase PR opened
- [ ] 02-02-PLAN.md — Hotkey recorder refuses Option-only combinations on macOS 15+ and says why (signature unchanged); every permission wait returns
- [ ] 02-03-PLAN.md — XPC service accepts holzIce's ad hoc build by pinning the embedding app's signing identifier and code directory hashes (proven by a CodeSignature test suite); foreign processes still rejected
- [ ] 02-04-PLAN.md — Lock-guarded event source cache; macOS 27 system item allowlist 0 to 127 with matching comment and tests; PR body complete

### Phase 3: Ice and Sparkle leftovers

**Goal**: Nothing of Ice or Sparkle remains unless it is credited, and the repository contains no unused files or dead code
**Depends on**: Phase 2
**Requirements**: LEFT-01, LEFT-02, LEFT-03, LEFT-04, LEFT-05, LEFT-06, LEFT-07, LEFT-08
**Success Criteria** (what must be TRUE):
  1. Acknowledgements and licenses are shown natively in the app (no PDF/RTF), list the packages actually used and no longer mention Sparkle
  2. NOTICE and the README credit Barometer and Thaw for the adapted macOS 27 code, and the README and docs agree (Thaw listed as conflicting app, one bug-report count)
  3. `FREQUENT_ISSUES.md` describes holzIce (or is gone) and the bug report template asks for holzIce version, macOS version and install method
  4. The listed unused files, stub build phase, setting and redundant code are gone and the app still builds
  5. The logger subsystem uses the shared `Logger(category:)` and the `"SU"` exclusion is commented
  6. The settings sidebar shows the colored holzIce logo (as on the website) left of the title
  6. The settings sidebar shows the colored holzIce logo (as on the website) left of the title

**Plans**: TBD

### Phase 4: Outdated APIs

**Goal**: Deprecated and outdated APIs are replaced by their macOS 14 compatible modern equivalents, and AXSwift is removed
**Depends on**: Phase 3
**Requirements**: API-01, API-02, API-03, API-04, API-05, API-06, API-07, API-08, DEP-01
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

### Phase 05.1: Modern, lean and private (INSERTED)

**Goal:** holzBar is written the way a macOS app is written in 2026, uses as little CPU, memory, disk and as few permissions as possible, and never talks to the network — without losing a feature
**Requirements**: LEAN-01, MOD-01, MOD-02, MOD-03, MOD-04, MOD-05, MOD-06, LEAN-02, LEAN-03, PRIV-01, PRIV-02, PERM-01
**Depends on:** Phase 5
**Success Criteria** (what must be TRUE):
  1. An analysis lists every modernisation, efficiency, size and speed improvement with gain and risk, and the user has chosen what to do
  2. All targets build in Swift 6 language mode; models use `@Observable`
  3. Dependencies that the system can replace are gone and the bundle is smaller; no needless polling remains
  4. A CI check proves there is no network code, and the README states it; logs keep personal data private
  5. Every permission and entitlement is justified by a feature, asked for only when needed, and anything unneeded is gone

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 05.1 to break down)

### Phase 6: Security audit

**Goal**: The user knows every security risk of the app, ranked, and has decided which to fix
**Depends on**: Phase 5
**Requirements**: AUDIT-01
**Success Criteria** (what must be TRUE):
  1. A security report covers the app, the XPC service, the URL scheme, settings import/sync, permissions, private APIs, CI/release pipeline and the cask
  2. Every finding has a severity, a location and a proposed fix
  3. The user has chosen which findings to fix, and those fixes are merged before the release

**Plans**: TBD

### Phase 7: Release 0.0.6-beta1

**Goal**: Users can install and update to `0.0.6-beta1` through Homebrew with clear instructions
**Depends on**: Phase 6
**Requirements**: REL-01
**Success Criteria** (what must be TRUE):
  1. The `v0.0.6-beta1` GitHub pre-release exists with hand-written notes from `docs/release-notes/v0.0.6-beta1.md`
  2. The notes' install section covers `brew tap`, `brew trust`, `brew install`, the `brew update && brew upgrade` path and the quarantine command
  3. The cask on `main` points at `0.0.6-beta1`

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CI and build | 3/3 | Complete (human check: install.sh on a Mac) | 2026-10-02 |
| 01.1. Rename to holzBar | 4/6 | In Progress|  |
| 2. Bug fixes | 0/4 | Planned | - |
| 3. Ice and Sparkle leftovers | 0/0 | Not started | - |
| 4. Outdated APIs | 0/0 | Not started | - |
| 5. Security and performance | 0/0 | Not started | - |
| 6. Security audit | 0/0 | Not started | - |
| 7. Release 0.0.6-beta1 | 0/0 | Not started | - |
