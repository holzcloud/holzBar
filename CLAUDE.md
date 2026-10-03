# holzBar

holzBar is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, a menu bar manager for macOS, with macOS 27 support and Homebrew distribution.

## Rules

- **Everything in this repository is written in English**: code, comments, commit messages, pull requests, issues, README and other docs. This applies even when the conversation is in another language.
- Always credit Ice and Jordan Baird as the original project (README, NOTICE). Keep the GPL-3.0 license.

## Workflow

- Work with **GSD** ([OpenGSD gsd-core](https://github.com/open-gsd/gsd-core)) whenever possible. It is installed locally in `.claude/` (commands `/gsd-*`, agents, hooks in `.claude/settings.json`), so every session has it. Planning state lives in `.planning/`. Start with `/gsd-help`; for this existing codebase, `/gsd-map-codebase` maps it and `/gsd-new-project` / `/gsd-plan-phase` / `/gsd-execute-phase` drive the work.
- Save CI runs and credits: group several phases into one pull request where they fit together, and push once per plan (not after every task); wait for CI only after that push.
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

## Naming

- The app is called **holzBar** (exactly so) everywhere a user can see it (UI strings, menus, README). The bundle identifier is `com.holzcloud.holzBar`, the product is `holzBar.app`, the XPC service is `com.holzcloud.holzBar.MenuBarItemService`, and the URL scheme is `holzbar://`. Ice's bar is the **holzBar Shelf**.
- Internal names say holzBar too: the Xcode project `holzBar.xcodeproj`, target, scheme and Swift module `holzBar`, the source folder `holzBar/`, the test package `HolzBarMacOS27Core`. Types that carry the app's name are `HolzBar<Name>` (`HolzBarSection`, `HolzBarForm`, …), the Shelf's are `HolzBarShelf<Name>` with members `shelf<Name>`, and the holzBar icon's are `holzBarIcon<Name>`.
- Persisted strings keep their old names: `Defaults.Key` and `HotkeyAction` raw values (such as `HasImportedIceSettings`) and the hotkey signature `OSType(1231250720)`. Renaming them would lose every user's settings and hotkeys, and the import of Ice settings relies on them.
- Links in the app and the repository lead to holzBar (`Constants.repositoryURL`, `Constants.issuesURL`, `Constants.websiteURL`). The only exception is the credit to the original: "Based on Ice by Jordan Baird" in the About pane (`Constants.originalIceURL`), the README and NOTICE. The website is https://holzcloud.ch/holzbar (`Constants.websiteURL`, README, cask `homepage`).
- Keep `com.jordanbaird.Ice` (and the name Ice) only where it refers to the original app: importing its settings, the conflicting-app check and the `jordanbaird-ice` cask conflict.
- The app's former name (`holz` followed by `Ice`, in any capitalization or spelling) must not appear anywhere in the repository. The `former-name` job in `.github/workflows/build.yml` fails when it does; only `.planning/`, `.claude/` and `.github/cms-version.py` are exempt.

## Releases

- Every release gets clean, hand-written release notes in `docs/release-notes/v<version>.md` (English; sections such as Highlights, New, Fixed, Changed, Known issues, Install). The release workflow publishes that file as the release body and fails without it. Write it in the same pull request as the version's last change.
- Releases before 1.0 are pre-releases (beta).
- During the beta, don't bump the version for every release. Publish numbered betas of the next version instead: `0.0.6-beta1`, `0.0.6-beta2`, … (tag `v0.0.6-beta1`, notes `docs/release-notes/v0.0.6-beta1.md`). Publish a version without the `-betaN` suffix (a stable release) only when the user says there is a new stable release.
- Every install guide (README, release notes) runs `brew trust --cask holzcloud/holzbar/holzbar` between `brew tap` and `brew install`; Homebrew refuses casks from untrusted third-party taps.
- Updating is `brew update && brew upgrade --cask holzbar`: without `brew update` Homebrew may not have fetched the tap and reports the old version as the latest.
- The cask uses Homebrew's structured steps (`postflight_steps`), not Ruby `postflight` blocks, and `depends_on macos: :sonoma` (a symbol, not a comparison string).
- Every release note's install section includes how to take the app out of quarantine (`xattr -dr com.apple.quarantine /Applications/holzBar.app`).
- Keep the comparison table "holzBar vs. Ice and Thaw" (right below "Why holzBar?", whose table lists the main selling points) (README and the website https://holzcloud.ch/holzbar) up to date with every relevant change: features, compatibility, privacy and permissions, code and resources (Swift version, dependencies, CPU/energy, size), distribution. Add a row when holzBar gains something Ice lacks, update a row when a 🔜 item lands, and never claim what is not true yet. Keep the README's feature list current too. Promote what makes holzBar modern (current Swift and Xcode, no dependencies, privacy) in the README selling points and on the website. Before every release, re-check every claim in the README, the website and the comparison tables against the code and the sources, and fix anything that is not true.

## Layout

- `holzBar/` – the app. `holzBar/MenuBar/MacOS27/` is the macOS 27 backend (its core is the Swift package `HolzBarMacOS27Core`, tested by `swift test`).
- `Casks/holzbar.rb` – the Homebrew cask; this repository is also the tap.
- `.github/workflows/build.yml` – builds every pull request on a macOS runner (the only way to compile without a Mac), runs `swift test` and checks that the former name appears nowhere.
- `.github/workflows/release.yml` – a `v*` tag builds the app on a macOS runner, publishes the release and updates the cask on `main`; a second job writes the version into the app's pages on holzcloud.ch (`.github/cms-version.py`, skipped for betas and without the `CMS_TOKEN` secret).
- `.github/workflows/cask.yml` – for every pull request that touches the cask: `brew style` and `brew audit` of the cask from this repository as the tap, on a macOS runner.
- `Resources/Logo/` – logo and README banner sources (SVG).
- `Resources/Screenshots/` – real screenshots of the app, used by the README gallery (and on https://holzcloud.ch/holzbar). Replace any that do not show holzBar as it is now, and the one of the original Ice, with new screenshots of holzBar when they exist.
- `docs/upstream-bugs.md` – the open bug reports of the original Ice, grouped, and which of them holzBar has fixed. Update it when fixing one.

## Building

macOS only (the Xcode pinned in `.github/actions/select-xcode/action.yml`, currently 26.6): `Scripts/install.sh` builds `holzBar.xcodeproj` (scheme `holzBar`) and installs `holzBar.app` to `~/Applications`. There is no Linux build; CI builds, runs `swift test` and runs SwiftLint (official image pinned in `lint.yml`, `.swiftlint.yml`, `--strict`).
