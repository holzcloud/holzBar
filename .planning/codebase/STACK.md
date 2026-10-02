---
last_mapped_commit: 213805b84bc1e41e6026202b2b4e829dbaca7b03
last_mapped_at: 2026-10-02
---
# Technology Stack

**Analysis Date:** 2026-10-02

Legend: **[OUTDATED]** = known older than current practice; **[CHECK]** = could not be verified against upstream (no network access to package registries during analysis); **[MISMATCH]** = two sources disagree.

## Languages

**Primary:**
- Swift (language mode 5.0, toolchain Swift 6 via Xcode 27) - whole app in `Ice/`, helper XPC service in `MenuBarItemService/`, shared code in `Shared/`
  - **Language mode 5.0** everywhere: `SWIFT_VERSION = 5.0` in all four build configs of `Ice.xcodeproj/project.pbxproj` (app Debug/Release, MenuBarItemService Debug/Release) and `.swiftLanguageMode(.v5)` in `Package.swift`. Swift 6 strict concurrency is NOT enabled. **[OUTDATED]** relative to the Swift 6 default.
  - `MenuBarItemService` target additionally sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` (`Ice.xcodeproj/project.pbxproj`).
  - Swift Testing (`import Testing`) is used in `Tests/IceMacOS27CoreTests/*.swift`.

**Secondary:**
- Bash - `Scripts/install.sh`, `Scripts/macos27/verify-*.sh`, `Integrations/Raycast/*.sh`
- Swift scripts (probes, run as scripts on a real Mac) - `Scripts/check-panels.swift`, `Scripts/macos27/*.swift`
- Ruby (Homebrew cask DSL) - `Casks/holzice.rb`
- YAML - `.github/workflows/*.yml`, `.swiftlint.yml`

## Runtime

**Environment:**
- macOS native app (AppKit + SwiftUI), no sandbox (`ENABLE_APP_SANDBOX = NO`), `LSUIElement`-style menu bar agent
- Deployment target: macOS 14.0 (`MACOSX_DEPLOYMENT_TARGET = 14.0` in `Ice.xcodeproj/project.pbxproj`; `.macOS(.v14)` in `Package.swift`; cask `depends_on macos: :sonoma` in `Casks/holzice.rb`). All three agree.
- macOS 27 has a dedicated backend in `Ice/MenuBar/MacOS27/`; macOS 14-26 use the legacy window-based path.
- URL scheme `holzice://` registered in `Ice/Resources/Info.plist`.

**Package Manager:**
- Swift Package Manager (Xcode-integrated); `Package.swift` (tools 6.0, name `IceMacOS27Core`) is a test-only package compiling `Ice/MenuBar/MacOS27/Core`
- Lockfile: present - `Ice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (version 3). No root `Package.resolved` for `Package.swift` (it has no dependencies).
- Xcode project format `objectVersion = 70` (Xcode 16+ synchronized folder groups; the `Ice` folder is a synchronized group)

## Frameworks

**Core:**
- SwiftUI (57 imports) - settings UI, Ice Bar, layout editor
- AppKit/Cocoa - status items, panels, windows
- Combine (41 imports) - observation/state flow
- OSLog / os - logging (`Shared/Utilities/Logging.swift`)
- CoreGraphics, ApplicationServices (Accessibility), Carbon (hotkeys, `Ice/Hotkeys/`), ScreenCaptureKit (screen capture permission/capture), IOKit, XPC, Network (`Ice/MenuBar/RevealRules/RevealRules.swift`), UniformTypeIdentifiers

**Testing:**
- Swift Testing (`Testing` module) - `Tests/IceMacOS27CoreTests/` (7 files), run with `swift test` via `Package.swift`
- **No CI job runs `swift test`** (`.github/workflows/` has only build, lint, release). Tests are local-only.

**Build/Dev:**
- Xcode 27 (README: "Requires Xcode 27 on macOS 14 or later") - `Ice.xcodeproj`, scheme `Ice`, targets `Ice` and `MenuBarItemService`
- SwiftLint (`--strict`) configured in `.swiftlint.yml`, scanning `Ice/` only (not `Shared/`, `MenuBarItemService/`, `Tests/`)
- `Scripts/install.sh` - local signed build+install to `~/Applications`

## Key Dependencies

SwiftPM remote packages (declared `upToNextMajorVersion` in `Ice.xcodeproj/project.pbxproj`, resolved in `Package.resolved`):

| Package | Declared min | Resolved | Used for |
|---------|-------------|----------|----------|
| `tmandry/AXSwift` | 0.3.2 | 0.3.2 | Accessibility API wrapper (`import AXSwift`) |
| `buh/CompactSlider` | 2.1.0 | 2.1.0 | SwiftUI slider control |
| `ukushu/Ifrit` | 2.0.3 | 2.0.6 | Fuzzy search (menu bar item search) |
| `sindresorhus/LaunchAtLogin-Modern` | 1.0.0 | 1.1.0 | Launch-at-login toggle (`import LaunchAtLogin`) |
| `groue/Semaphore` | 0.1.0 | 0.1.0 | Async semaphore (`import Semaphore`) |

- **[CHECK]** Latest upstream versions could not be fetched (GitHub API access denied in this session). All five are pinned at or near their declared minimum; `AXSwift` 0.3.2 and `Semaphore` 0.1.0 are early-version pins (0.x, no stability guarantee under `upToNextMajor`). Re-check with `xcodebuild -resolvePackageDependencies` / `gh api repos/<owner>/<repo>/releases/latest`.
- Sparkle was removed (see comment in `Scripts/install.sh`); updates are Homebrew-only.

## Configuration

**Environment:**
- No `.env` files, no runtime environment variables. User settings in `UserDefaults` under bundle id `com.holzcloud.holzIce`.
- Version: `MARKETING_VERSION = "0.11.13-dev.2a"`, `CURRENT_PROJECT_VERSION = 1121` in `Ice.xcodeproj/project.pbxproj` for the app. **[MISMATCH]** Last released version is 0.0.5 (`Casks/holzice.rb`, `docs/release-notes/v0.0.5.md`); the project file still carries the inherited upstream-style `0.11.13-dev.2a`, which is overridden at release time by `MARKETING_VERSION=` in `.github/workflows/release.yml`. The helper service has `MARKETING_VERSION = 1.0`.
- Bundle ids: `com.holzcloud.holzIce` (app), `com.holzcloud.holzIce.MenuBarItemService` (XPC service).

**Build:**
- `Ice.xcodeproj/project.pbxproj`, `Ice/Resources/Info.plist` (only URL types; rest generated via `GENERATE_INFOPLIST_FILE = YES`), `MenuBarItemService/Resources/Info.plist`
- `Package.swift`, `.swiftlint.yml`
- Signing: Debug/Release use `CODE_SIGN_STYLE = Automatic` with "Apple Development"; CI and release override to ad hoc (`CODE_SIGN_IDENTITY=-`, `ENABLE_HARDENED_RUNTIME=NO`). No Developer ID, no notarization.

## CI Tool Versions (GitHub Actions)

| Workflow | Runner | Actions / tools | Status |
|----------|--------|-----------------|--------|
| `.github/workflows/build.yml` | `macos-26` | `actions/checkout@v4`; Xcode = newest `/Applications/Xcode*.app` (`sort -V | tail -1`) | `checkout@v4` runs on Node 20 **[OUTDATED]** (Node 20 runner deprecation; v5+ uses Node 24) **[CHECK]** |
| `.github/workflows/release.yml` | `macos-26` | `actions/checkout@v4` (`fetch-depth: 0`); same Xcode selection; `gh` CLI | same `checkout@v4` note |
| `.github/workflows/lint.yml` | `ubuntu-latest` | `actions/checkout@v3` **[OUTDATED]** (Node 16 era, Node 20 at best; two majors behind); `norio-nomura/action-swiftlint@3.2.1` **[OUTDATED]** (Docker action, pins an old SwiftLint image; unmaintained-looking) | needs update |

- **[MISMATCH] Xcode version:** docs/README say "Xcode 27", but CI does not pin Xcode; it selects whichever Xcode is newest on the `macos-26` runner image. `macos-26` images ship Xcode 26.x, so CI likely builds with Xcode 26, not 27, and cannot compile anything needing the macOS 27 SDK. Pin explicitly (`xcode-select` to a named version or `maxim-lobanov/setup-xcode`) or move to a macOS 27 runner when available. **[CHECK]** which Xcode versions are on the runner image.
- No dependency caching (SwiftPM, DerivedData) in any workflow; no `swift test` step; no Dependabot config in `.github/` (only `FUNDING.yml`, `ISSUE_TEMPLATE/`, `workflows/`).
- Lint workflow `if: '!github.event.pull_request.merged'` guard is vestigial (merged PRs do not trigger `pull_request`).

## Platform Requirements

**Development:**
- macOS 14+ with Xcode 27 (README) for building; Linux has no build (CLAUDE.md); CI on macOS runner is the only compile path without a Mac
- SwiftLint (CI only, via Docker action on ubuntu)

**Production:**
- macOS 14 Sonoma or later; distributed as ad hoc signed `holzIce-<version>.zip` through GitHub Releases and Homebrew tap (`Casks/holzice.rb`, tap = this repo `holzcloud/holzIce`). Requires Accessibility and Screen Recording permissions (`Ice/Permissions/`).

---

*Stack analysis: 2026-10-02*
