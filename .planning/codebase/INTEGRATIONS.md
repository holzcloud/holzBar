---
last_mapped_commit: 213805b84bc1e41e6026202b2b4e829dbaca7b03
last_mapped_at: 2026-10-02
---
# External Integrations

**Analysis Date:** 2026-10-02

## APIs & External Services

**Network calls from the app:**
- None detected. `grep` for `URLSession`/HTTP clients in `Ice/`, `Shared/`, `MenuBarItemService/` finds none; the only `https://` literals are link constants in `Ice/Utilities/Constants.swift` (`repositoryURL` = github.com/holzcloud/holzIce, `websiteURL` = holzcloud.ch/holzice, `originalIceURL` = github.com/jordanbaird/Ice, plus issues URL), opened in the browser by the user. The `Network` framework import in `Ice/MenuBar/RevealRules/RevealRules.swift` is for local state, not a remote API.
- No auto-updater: Sparkle was removed; updates come from Homebrew (`brew update && brew upgrade --cask holzice`).

**System frameworks / OS services used as integrations:**
- Accessibility API (`ApplicationServices`, `AXSwift` package) - reads menu bar items on macOS 27 (`Ice/MenuBar/MacOS27/`, `Shared/Utilities/AXHelpers.swift`)
- Screen Recording / ScreenCaptureKit and CoreGraphics window list - item images and window info (`Shared/Utilities/WindowInfo.swift`)
- Carbon hotkeys (`Ice/Hotkeys/`)
- XPC - helper `MenuBarItemService` (`MenuBarItemService/main.swift`, `MenuBarItemService/Listener.swift`, `Shared/Services/MenuBarItemService.swift`); bundle id `com.holzcloud.holzIce.MenuBarItemService`
- Private/undocumented macOS APIs via bridging: `Shared/Bridging/Bridging.swift`, `Shared/Bridging/Shims.swift`
- macOS 27 `MenuBarAgent` (system process drawing all items), handled by `Ice/MenuBar/MacOS27/`; see `docs/macos27.md`
- Launch at login via `LaunchAtLogin-Modern` (SMAppService)

**Raycast / shell integration:**
- `Integrations/Raycast/*.sh` (script commands: `holzice-toggle-hidden.sh`, `holzice-search.sh`, ...) drive the app via the `holzice://` URL scheme registered in `Ice/Resources/Info.plist`. Documented in `Integrations/Raycast/README.md`.

**Upstream compatibility:**
- Imports settings from the original app's domain `com.jordanbaird.Ice`; cask `conflicts_with cask: "jordanbaird-ice"` in `Casks/holzice.rb`.

## Data Storage

**Databases:**
- None

**File Storage:**
- Local filesystem only: `UserDefaults` (`com.holzcloud.holzIce` plist), `~/Library/Application Support/holzIce`, caches in `~/Library/Caches/com.holzcloud.holzIce` (cleanup list in cask `zap`)

**Caching:**
- In-process only (e.g. `Shared/Services/SourcePIDCache.swift`)

## Authentication & Identity

**Auth Provider:**
- None. macOS TCC permissions (Accessibility, Screen Recording) managed in `Ice/Permissions/`.
- Code signing: ad hoc (`CODE_SIGN_IDENTITY=-`); no Developer ID, no notarization; Gatekeeper bypass through cask `postflight_steps` removing `com.apple.quarantine`.

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry/Crashlytics)

**Logs:**
- Apple unified logging (`OSLog`) via `Shared/Utilities/Logging.swift`; CI builds log to `build.log` (`.github/workflows/build.yml`)

## CI/CD & Deployment

**Hosting:**
- GitHub repo `holzcloud/holzIce`; releases as GitHub Release assets; this repository doubles as the Homebrew tap (`Casks/holzice.rb`, tap `holzcloud/holzice`). Website https://holzcloud.ch/holzice (not in this repo).

**CI Pipeline:**
- GitHub Actions, three workflows:
  - `.github/workflows/build.yml` - Release build on `macos-26` for PRs and pushes to `main` (path filtered)
  - `.github/workflows/lint.yml` - SwiftLint `--strict` on `ubuntu-latest` via `norio-nomura/action-swiftlint@3.2.1` (**[OUTDATED]**, with `actions/checkout@v3`, **[OUTDATED]**)
  - `.github/workflows/release.yml` - on `v*` tag or manual dispatch: verifies `docs/release-notes/v<version>.md`, builds with `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION=${{ github.run_number }}`, packages with `ditto`, publishes via `gh release create` (pre-release if tag starts `v0.` or contains `-`), then commits the new `version`/`sha256` to `Casks/holzice.rb` on `main` with a direct push as `github-actions[bot]`
- Action versions: `actions/checkout@v4` (build, release; Node 20 runtime **[OUTDATED]**), `actions/checkout@v3` (lint **[OUTDATED]**). Version pinning is by tag, not commit SHA.
- Release workflow notes: top-level `permissions: contents: write`; interpolates `${{ github.event.inputs.version }}` directly into shell (script-injection risk limited to users with dispatch rights, but should go through `env:`).
- Not present: SwiftPM/DerivedData caching, `swift test` job, Dependabot (`.github/` has only `FUNDING.yml`, `ISSUE_TEMPLATE/`, `workflows/`), notarization.
- Homebrew cask (`Casks/holzice.rb`): `livecheck` with `strategy :git` (because pre-releases are skipped by `:github_latest`), `depends_on macos: :sonoma`, structured `postflight_steps`, `uninstall quit: "com.holzcloud.holzIce"`. Cask `version` is `0.0.5`.

## Environment Configuration

**Required env vars:**
- None for the app. CI uses `GH_TOKEN: ${{ github.token }}` (release publish). `Scripts/install.sh` optionally reads `DEST` and `DERIVED`.

**Secrets location:**
- No repository secrets referenced in any workflow beyond the built-in `github.token`. No `.env*` files present.

## Webhooks & Callbacks

**Incoming:**
- None (the `holzice://` URL scheme is a local app callback, `Ice/Resources/Info.plist`)

**Outgoing:**
- None

---

*Integration audit: 2026-10-02*
