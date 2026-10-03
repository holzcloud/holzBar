# Roadmap: holzIce

## Overview

The "Modernize" milestone removes everything outdated that the codebase audit (`.planning/codebase/CONCERNS.md`) found, then publishes `0.0.6-beta1`. CI and build come first so every later change is compiled, linted and tested on the macOS runner (there is no local compiler). Then the real bugs, the Ice and Sparkle leftovers, the outdated APIs, and the security and performance findings follow, each as one pull request that must build green. The last phase is the small beta release.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: CI and build** - Current actions, maintained SwiftLint, unit tests on every PR, visible warnings, pinned Xcode, holzIce project metadata
- [x] **Phase 01.1: Rename to holzBar** (INSERTED) - Name, logo, identifiers, code and links say holzBar; holzIce settings are imported
- [x] **Phase 2: Bug fixes** - Spacing relaunch, data race, hotkey recorder, XPC ad hoc check, permission continuation, allowlist
- [x] **Phase 3: Ice and Sparkle leftovers** - Acknowledgements, credits, docs, templates, dead code and files removed
- [x] **Phase 4: Outdated APIs** - Modern URL, UserDefaults, CFPreferences, URL-open, window and AX APIs; AXSwift removed
- [x] **Phase 5: Security and performance** - Validated settings import, private logging, Caches storage, no needless tasks or polling
- [ ] **Phase 05.1: Modern, lean and private** (INSERTED) - 2026 code, Swift 6, @Observable, fewer dependencies, no network, least privilege
- [ ] **Phase 6: Security audit** - Full security analysis of the whole app, findings ranked, fixes chosen by the user done before the release
- [ ] **Phase 06.1: Compatibility check** (INSERTED) - Which macOS versions really work; 26 and 27 required, older ones optional
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

**Plans:** 6/6 plans executed (sequential waves: one PR branch, every task verified by its CI checks)

Plans:
- [x] 01.1-01-PLAN.md — Tracer: holzBar.xcodeproj, target/scheme/module holzBar, folder holzBar/, test package HolzBarMacOS27Core, bundle ids com.holzcloud.holzBar(.MenuBarItemService) with a CI identifier check; phase PR opened
- [x] 01.1-02-PLAN.md — Type, file and folder names: HolzBar<Name> UI components, HolzBarShelf<Name> in MenuBar/Shelf/, shelf/holzBarIcon members; stored key strings unchanged
- [x] 01.1-03-PLAN.md — Every Swift text and comment says holzBar / holzBar Shelf; holzBar data folders, autosave names and links; developer scripts, docs and issue templates
- [x] 01.1-04-PLAN.md — First-launch import of holzIce's settings, item images and iCloud file (before Ice's); ConflictingApps quits holzIce; holzbar:// with holzice:// alias; Raycast scripts
- [x] 01.1-05-PLAN.md — holzBar logo: app icon in all sizes, vector sidebar logo next to the title, Resources/Logo/holzBar.svg, banner.svg/png
- [x] 01.1-06-PLAN.md — Casks/holzbar.rb + cask_renames.json proven by a cask CI job, release workflow, README/NOTICE/CLAUDE.md; user renames the repository after the merge

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

**Plans**: 4/4 plans executed (sequential waves: one PR branch, every task verified by its CI checks)

Plans:
- [x] 02-01-PLAN.md — Tracer: tested `holzBar/Core` package target (`HolzBarCore`); spacing relaunch keeps going past skipped processes (MenuBarAgent skipped on macOS 27), 10 s event-driven quit wait, no force-termination; phase PR opened
- [x] 02-02-PLAN.md — Hotkey recorder refuses Option-only combinations on macOS 15+ and says why (signature unchanged); every permission wait returns
- [x] 02-03-PLAN.md — XPC service accepts holzBar's ad hoc build by pinning the embedding app's signing identifier and code directory hashes (proven by a CodeSignature test suite); foreign processes still rejected
- [x] 02-04-PLAN.md — Lock-guarded event source cache; macOS 27 system item allowlist 0 to 127 with matching comment and tests; PR body complete

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
  6. The settings sidebar shows the colored holzIce logo (as on the website) left of the title (superseded by REN-06, done)

**Plans**: 2/2 plans executed (sequential waves; one PR for Phases 3 to 5, pushed once per plan)

Plans:
- [x] 03-01-PLAN.md — Tracer: native, tested acknowledgements sheet in About (Core data checked against Package.resolved, license texts in the app, build check), PDF/RTF removed; Barometer/Thaw credits, README Troubleshooting replaces FREQUENT_ISSUES.md, README/docs agree, modern bug template; LEFT-08 superseded; draft PR opened
- [x] 03-02-PLAN.md — Unused media, dead types, stub build phase and sandbox-only setting removed; item cache read through its subscript; click bridge on Logger(category:), SU exclusion commented

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

**Plans**: 3/3 plans executed (sequential waves; same PR; 04-03 starts with a user decision on Ifrit 4.0.0)

Plans:
- [x] 04-01-PLAN.md — Tracer: spacing through CFPreferences; sync device UUID with SCDynamicStoreCopyComputerName; relaunch through NSWorkspace with a bounded wait for the old instance; modern URL path APIs
- [x] 04-02-PLAN.md — holzbar:// through application(_:open:) with a tested URLCommand parse; captured OpenWindowAction/DismissWindowAction; current Screen Recording pane; direct AX calls instead of AXSwift
- [x] 04-03-PLAN.md — Decision on search ranking for Ifrit 4.0.0; AXSwift removed from both targets; every package on its latest stable release; resolved packages in the build log; acknowledgements follow

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

**Plans**: 2/2 plans executed (sequential waves; same PR, completed by 05-02)

Plans:
- [x] 05-01-PLAN.md — Tracer: imported, synced and Ice settings validated against Defaults.Key kinds (Defaults moved to Core, tested); URL logs name only the command; item images in Caches with a tested one-time move
- [x] 05-02-PLAN.md — One cancellable hover task (tested HoverSchedule); permission checks stop once granted; reveal rules on IOPSNotificationCreateRunLoopSource and NWPathMonitor (tested RevealTrigger); final PR body

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

**Plans:** 3/3 plans executed (sequential waves; one PR "Modern, lean and private", pushed once per plan; 05.1-03 starts with one strict-concurrency measurement build)

Plans:
- [x] 05.1-01-PLAN.md — Tracer: no-network CI job and binary check, private logs, "How to Update…"; LaunchAtLogin-Modern, Semaphore and CompactSlider replaced (SMAppService, own AsyncLock and slider), -Osize; taps and timers only while needed; draft PR with size and wake-up figures
- [x] 05.1-02-PLAN.md — Tracer: Screen Recording asked in context with the why; one-step Ice migration, no swizzling or preview/app-group leftovers, lazy panels, hardened runtime everywhere; settings sync through NSFilePresenter; tests for migration, sync, hotkeys and URL commands
- [x] 05.1-03-PLAN.md — Tracer: strict-concurrency measurement build; explicit isolation and no unprotected globals; @Observable without Combine (macOS 14); Swift 6 mode for app and XPC; managers split per backend; macOS 26/27 checklist in the PR

### Phase 05.1.1: Thaw fixes and speed (INSERTED)

**Goal:** The bugs Thaw fixed that holzBar shares are fixed, and revealing is fast and never freezes input
**Requirements**: THAW-01, THAW-02, THAW-03, THAW-04, THAW-05, THAW-06, THAW-07, THAW-08, ICE-01, ICE-02, ICE-03, ICE-04, ICE-06
**Depends on:** Phase 05.1
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 05.1.1 to break down)

### Phase 05.1.1.1: Thaw features (INSERTED)

**Goal:** holzBar gains Thaw's best features within its principles (no network, least privilege, lean)
**Requirements**: THAW-10, THAW-11, THAW-12, THAW-13, THAW-14, THAW-15, THAW-16, THAW-17, ICE-05
**Depends on:** Phase 05.1.1
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 05.1.1.1 to break down)

### Phase 6: Security audit

**Goal**: The user knows every security risk of the app, ranked, and has decided which to fix
**Depends on**: Phase 5
**Requirements**: AUDIT-01
**Success Criteria** (what must be TRUE):
  1. A security report covers the app, the XPC service, the URL scheme, settings import/sync, permissions, private APIs, CI/release pipeline and the cask
  2. Every finding has a severity, a location and a proposed fix
  3. The user has chosen which findings to fix, and those fixes are merged before the release

**Plans**: TBD

### Phase 06.1: Compatibility check (INSERTED)

**Goal:** It is known and documented which macOS versions holzBar really runs on; macOS 26 and 27 are guaranteed, older versions are kept only where they cost little
**Requirements**: COMPAT-01, COMPAT-02, COMPAT-03
**Depends on:** Phase 6
**Success Criteria** (what must be TRUE):
  1. CI builds and runs the unit tests on every macOS runner GitHub offers (macos-14, macos-15, macos-26), and the deployment target matches the oldest version that really works
  2. macOS 26 and 27 are verified on real Macs by the user with a short checklist (hiding, Shelf, layout editor, hotkeys, settings import)
  3. README, cask `depends_on macos:` and release notes state the supported versions truthfully; if the user decides to drop 14/15, the old backend code is removed (lean)

**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 06.1 to break down)

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
| 01.1. Rename to holzBar | 6/6 | In Progress|  |
| 2. Bug fixes | 4/4 | In Progress|  |
| 3. Ice and Sparkle leftovers | 2/2 | In Progress|  |
| 4. Outdated APIs | 3/3 | In Progress|  |
| 5. Security and performance | 2/2 | In Progress|  |
| 6. Security audit | 0/0 | Not started | - |
| 7. Release 0.0.6-beta1 | 0/0 | Not started | - |
