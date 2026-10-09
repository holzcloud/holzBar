# holzBar

holzBar is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, a menu bar manager for macOS, with macOS 27 support and Homebrew distribution.

## Rules

- **Everything in this repository is written in English**: code, comments, commit messages, pull requests, issues, README and other docs. This applies even when the conversation is in another language.
- Always credit Ice and Jordan Baird as the original project (README, NOTICE). Keep the GPL-3.0 license.

## Workflow

- Work with **GSD** ([OpenGSD gsd-core](https://github.com/open-gsd/gsd-core)) whenever possible. It is installed locally in `.claude/` (commands `/gsd-*`, agents, hooks in `.claude/settings.json`), so every session has it. Planning state lives in `.planning/`. Start with `/gsd-help`; for this existing codebase, `/gsd-map-codebase` maps it and `/gsd-new-project` / `/gsd-plan-phase` / `/gsd-execute-phase` drive the work.
- Documentation-only changes (`*.md`, `docs/`, `.planning/`, screenshots, logos) run no CI: `build.yml` ignores those paths. Check by hand that the former name does not appear in them.
- Save CI runs and credits: run CI as rarely as possible. Group several phases into one pull request, commit locally and push only once at the end of the work (then fix until green); never push after every task or plan.
- Ask the user every question as a multiple choice (the AskUserQuestion tool), never as free text.
- Update GSD with `npx -y @opengsd/gsd-core@latest --claude --local` and commit the result.

## Principles

These hold for every change, always, without taking a feature away:

- **Modern**: write code the way a macOS app is written today (current Swift language mode, Swift concurrency, `@Observable`, current SwiftUI/AppKit APIs); replace outdated APIs when touching code.
- **Lean and fast**: as little CPU, energy, memory and disk as possible; no polling when an event or notification exists; small bundle, fast launch.
- **Private**: the app never connects to the network — no telemetry, analytics, crash reporting, update checks or remote content. Opening a link in the browser is the only exception. Personal data stays on the Mac and out of logs.
- **Apple's way**: follow Apple's guidance — Human Interface Guidelines, API documentation and deprecation notices, Swift API Design Guidelines. Use the API Apple recommends for the job; never build on deprecated or soon-to-be-deprecated API when a replacement exists; adopt improvements a new Xcode, Swift or SDK brings.
- **Least privilege**: request only the permissions and entitlements a feature really needs, only when it needs them, and say why.

## Dependencies

- Always use the latest stable version of every library, package, tool and GitHub Action (Swift packages, SwiftLint, Xcode, actions). No pre-releases. When touching a dependency, update it to the latest stable release.
- Swift is the latest stable release toolchain from swift.org (currently 6.4.0), pinned with its SHA-256 next to Xcode in `.github/actions/select-xcode/action.yml` (`swift-version`, `swift-sha256`); bump both together. The language mode stays `SWIFT_VERSION = 6.2` (Swift 6 mode): Swift 6.4 offers no newer language mode (`swiftc` accepts 4, 4.2, 5 and 6), and Xcode compiles 6.2 and 6.4 alike as `-swift-version 6`.
- GitHub Actions are pinned by full commit SHA with a `# vX.Y.Z` comment; Dependabot (`.github/dependabot.yml`) bumps them in one grouped pull request a week. The only tag reference is the SLSA generator, which checks its own ref. The actionlint image (`build.yml`) and the SwiftLint image (`lint.yml`) are pinned by digest and bumped by hand. `.github/scripts/workflow-check.py` enforces the pins.

## Naming

- The app is called **holzBar** (exactly so) everywhere a user can see it (UI strings, menus, README). The bundle identifier is `com.holzcloud.holzBar`, the product is `holzBar.app`, and the URL scheme is `holzbar://`. Ice's bar is the **holzBar Shelf**.
- Internal names say holzBar too: the Xcode project `holzBar.xcodeproj`, target, scheme and Swift module `holzBar`, the source folder `holzBar/`, the test package `HolzBarMacOS27Core`. Types that carry the app's name are `HolzBar<Name>` (`HolzBarSection`, `HolzBarForm`, …), the Shelf's are `HolzBarShelf<Name>` with members `shelf<Name>`, and the holzBar icon's are `holzBarIcon<Name>`.
- Persisted strings keep their old names: `Defaults.Key` and `HotkeyAction` raw values (such as `HasImportedIceSettings`) and the hotkey signature `OSType(1231250720)`. Renaming them would lose every user's settings and hotkeys, and the import of Ice settings relies on them.
- Links in the app and the repository lead to holzBar (`Constants.repositoryURL`, `Constants.issuesURL`, `Constants.websiteURL`). The only exception is the credit to the original: "Based on Ice by Jordan Baird" in the About pane (`Constants.originalIceURL`), the README and NOTICE. The website is https://holzcloud.ch/holzbar (`Constants.websiteURL`, README, cask `homepage`).
- Keep `com.jordanbaird.Ice` (and the name Ice) only where it refers to the original app: importing its settings, the conflicting-app check and the `jordanbaird-ice` cask conflict.
- The app's former name (`holz` followed by `Ice`, in any capitalization or spelling) must not appear anywhere in the repository. The `former-name` job in `.github/workflows/build.yml` fails when it does; only `.planning/`, `.claude/` and `.github/cms-version.py` are exempt.

## Releases

- Every release gets clean, hand-written release notes in `docs/release-notes/v<version>.md` (English; sections such as Highlights, New, Fixed, Changed, Known issues, Install). The release workflow publishes that file as the release body and fails without it. Write it in the same pull request as the version's last change.
- Releases before 1.0 are pre-releases (beta).
- `main` takes only pull requests with green checks (build, test, former-name, no-network, strings, workflows, compat (macos-26), compat (xcode-27)); never push to it directly.
- A release starts with an annotated `v*` tag pushed on `main` after its release-notes pull request is merged; there is no Run workflow button. Never create a release or tag in the web UI, and never push a `v*` tag to test: every one publishes. After a failed run use "Re-run failed jobs", never "Re-run all jobs" (a rebuild makes a different zip, which publish refuses); a defect in the workflow needs a fix pull request and a new tag.
- Releases are signed with holzBar's own certificate (SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`), so permissions survive updates. The release fails without the signing secrets or with any other certificate; never change it. The secrets are still repository secrets (todo: move them into the environment `release`); the sign and cask jobs run in `release`, which only `v*` tags may use, and the cask job pushes the cask to `main` with the deploy key `CASK_DEPLOY_KEY`.
- During the beta, don't bump the version for every release. Publish numbered betas of the next version instead: `0.0.6-beta1`, `0.0.6-beta2`, … (tag `v0.0.6-beta1`, notes `docs/release-notes/v0.0.6-beta1.md`). Publish a version without the `-betaN` suffix (a stable release) only when the user says there is a new stable release.
- Every install guide (README, release notes) runs `brew trust --cask holzcloud/holzbar/holzbar` between `brew tap` and `brew install`; Homebrew refuses casks from untrusted third-party taps.
- Updating is `brew update && brew upgrade --cask holzbar`: without `brew update` Homebrew may not have fetched the tap and reports the old version as the latest.
- The cask uses Homebrew's structured steps (`postflight_steps`), not Ruby `postflight` blocks, and `depends_on macos: :sonoma` (a symbol, not a comparison string).
- Every release note's install section includes how to take the app out of quarantine (`xattr -dr com.apple.quarantine /Applications/holzBar.app`).
- Keep the comparison table "holzBar vs. Ice and Thaw" (right below "Why holzBar?", whose table lists the main selling points) (README and the website https://holzcloud.ch/holzbar) up to date with every relevant change: features, compatibility, privacy and permissions, code and resources (Swift version, dependencies, CPU/energy, size), distribution. Add a row when holzBar gains something Ice lacks, update a row when a 🔜 item lands, and never claim what is not true yet. Keep the README's feature list current too. Promote what makes holzBar modern (current Swift and Xcode, no dependencies, privacy) in the README selling points and on the website. Before every release, re-check every claim in the README, the website and the comparison tables against the code and the sources, and fix anything that is not true.

## Layout

- `holzBar/` – the app. `holzBar/MenuBar/MacOS27/` is the macOS 27 backend (its core is the Swift package `HolzBarMacOS27Core`, tested by `swift test`).
- `Casks/holzbar.rb` – the Homebrew cask; this repository is also the tap.
- `.github/workflows/build.yml` – builds every pull request on a macOS runner (the only way to compile without a Mac), checks the signature (`Scripts/check-signature.sh`), runs `swift test`, checks that the former name appears nowhere, and lints the workflows (`workflows` job: actionlint and `.github/scripts/workflow-check.py`, configured in `.github/actionlint.yaml`).
- `.github/workflows/release.yml` – runs only for a `v*` tag whose commit is on `main`, in separate jobs: build (ad hoc, no secrets, no write token), sign (the only job with the signing secrets; pins the certificate, no entitlements), publish (GitHub attestation and release), provenance (SLSA Build Level 3, `holzBar-<version>.intoto.jsonl`), cask (moves `Casks/holzbar.rb` on `main` forward only) and holzcloud-ch (writes the version into the app's pages on holzcloud.ch through `.github/cms-version.py`, skipped for betas and without the `CMS_TOKEN` secret).
- `.github/workflows/cask.yml` – for every pull request that touches the cask: `brew style` and `brew audit` of the cask from this repository as the tap, on a macOS runner.
- `.github/workflows/codeql.yml` – CodeQL for the Swift sources and the workflows, weekly and on demand; not a required check. `.github/workflows/scorecard.yml` – OpenSSF Scorecard on every push to `main` and weekly. `.github/dependabot.yml` – weekly action updates.
- `Scripts/check-signature.sh` – fails unless a built `holzBar.app` is validly signed with the hardened runtime, carries no entitlement (not even `get-task-allow`) and has no code besides `Contents/MacOS/holzBar`: holzBar ships a single executable, with no XPC service or other nested code. Used by `build.yml`, `release.yml` and `Scripts/install.sh`.
- `Resources/Logo/` – logo and README banner sources (SVG).
- `Resources/Screenshots/` – real screenshots of the app, used by the README gallery (and on https://holzcloud.ch/holzbar). Replace any that do not show holzBar as it is now, and the one of the original Ice, with new screenshots of holzBar when they exist.
- `docs/upstream-bugs.md` – the open bug reports of the original Ice, grouped, and which of them holzBar has fixed. Update it when fixing one.

## Building

macOS only (the Xcode pinned in `.github/actions/select-xcode/action.yml`, currently 27.0 on GitHub's `xcode-27` runner image, a public preview that the user approved on 2026-10-03): `Scripts/install.sh` builds `holzBar.xcodeproj` (scheme `holzBar`) without `get-task-allow`, runs `Scripts/check-signature.sh` and installs `holzBar.app` to `~/Applications`. There is no Linux build; CI builds, runs `swift test` and runs SwiftLint (official image pinned in `lint.yml`, `.swiftlint.yml`, `--strict`).

CI compiles with Swift 6.4 from swift.org, not with Xcode's own Swift: the select-xcode action selects Xcode 27.0 (SDK and build system; build, test and release run on the `xcode-27` runner), downloads `swift-6.4.0-RELEASE-osx.pkg`, checks its SHA-256 and Developer ID signature, installs it for the runner user and exports `TOOLCHAINS`, which `xcodebuild`, `swift test` and `xcrun` honor. The build job fails if xcodebuild did not use that toolchain. To do the same on a Mac (optional): `installer -pkg swift-6.4.0-RELEASE-osx.pkg -target CurrentUserHomeDirectory`, then `TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw -o - ~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/Info.plist) Scripts/install.sh`.

Without Xcode (only the Command Line Tools), the app module still type-checks with `swiftc -emit-sil -wmo` over `holzBar/` and `Shared/` with the app's Swift flags (`-module-name holzBar -parse-as-library -swift-version 6 -default-isolation MainActor`, the upcoming features `NonisolatedNonsendingByDefault` and `InferIsolatedConformances`, `-target arm64-apple-macos14.0`) against the Command Line Tools' default macOS 27.0 SDK (`MacOSX.sdk`); it needs stubs for the asset symbols Xcode generates (`ImageResource.appLogo`, `.logoStroke`, `ColorResource.defaultLayoutBar`, …). SwiftLint runs from its portable binary with `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint --strict`.
