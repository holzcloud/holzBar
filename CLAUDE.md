# holzIce

holzIce is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, a menu bar manager for macOS, with macOS 27 support and Homebrew distribution.

## Rules

- **Everything in this repository is written in English**: code, comments, commit messages, pull requests, issues, README and other docs. This applies even when the conversation is in another language.
- Always credit Ice and Jordan Baird as the original project (README, NOTICE). Keep the GPL-3.0 license.

## Workflow

- Work with **GSD** ([OpenGSD gsd-core](https://github.com/open-gsd/gsd-core)) whenever possible. It is installed locally in `.claude/` (commands `/gsd-*`, agents, hooks in `.claude/settings.json`), so every session has it. Planning state lives in `.planning/`. Start with `/gsd-help`; for this existing codebase, `/gsd-map-codebase` maps it and `/gsd-new-project` / `/gsd-plan-phase` / `/gsd-execute-phase` drive the work.
- Ask the user every question as a multiple choice (the AskUserQuestion tool), never as free text.
- Update GSD with `npx -y @opengsd/gsd-core@latest --claude --local` and commit the result.

## Dependencies

- Always use the latest stable version of every library, package, tool and GitHub Action (Swift packages, SwiftLint, Xcode, actions). No pre-releases. When touching a dependency, update it to the latest stable release.

## Naming

- The app is called **holzIce** everywhere a user can see it (UI strings, menus, README). The bundle identifier is `com.holzcloud.holzIce`, the product is `holzIce.app`.
- The Xcode project, target, scheme and Swift module are still called `Ice`, and so are internal type names (`IceBar`, `IceSection`, …). Leave them; renaming them would only churn the code.
- Links in the app and the repository lead to holzIce (`Constants.repositoryURL`, `Constants.issuesURL`, `Constants.websiteURL`). The only exception is the credit to the original: "Based on Ice by Jordan Baird" in the About pane (`Constants.originalIceURL`), the README and NOTICE. The website is https://holzcloud.ch/holzice (`Constants.websiteURL`, README, cask `homepage`).
- Keep `com.jordanbaird.Ice` only where it refers to the original app (importing its settings, the `jordanbaird-ice` cask conflict).

## Releases

- Every release gets clean, hand-written release notes in `docs/release-notes/v<version>.md` (English; sections such as Highlights, New, Fixed, Changed, Known issues, Install). The release workflow publishes that file as the release body and fails without it. Write it in the same pull request as the version's last change.
- Releases before 1.0 are pre-releases (beta).
- During the beta, don't bump the version for every release. Publish numbered betas of the next version instead: `0.0.6-beta1`, `0.0.6-beta2`, … (tag `v0.0.6-beta1`, notes `docs/release-notes/v0.0.6-beta1.md`). Publish a version without the `-betaN` suffix (a stable release) only when the user says there is a new stable release.
- Every install guide (README, release notes) runs `brew trust --cask holzcloud/holzice/holzice` between `brew tap` and `brew install`; Homebrew refuses casks from untrusted third-party taps.
- Updating is `brew update && brew upgrade --cask holzice`: without `brew update` Homebrew may not have fetched the tap and reports the old version as the latest.
- The cask uses Homebrew's structured steps (`postflight_steps`), not Ruby `postflight` blocks, and `depends_on macos: :sonoma` (a symbol, not a comparison string).
- Every release note's install section includes how to take the app out of quarantine (`xattr -dr com.apple.quarantine /Applications/holzIce.app`).
- Keep the README's feature list and the comparison with Ice up to date when adding a feature.

## Layout

- `Ice/` – the app. `Ice/MenuBar/MacOS27/` is the macOS 27 backend.
- `Casks/holzice.rb` – the Homebrew cask; this repository is also the tap.
- `.github/workflows/build.yml` – builds every pull request on a macOS runner; the only way to compile without a Mac.
- `.github/workflows/release.yml` – a `v*` tag builds the app on a macOS runner, publishes the release and updates the cask on `main`; a second job writes the version into the holzIce pages of holzcloud.ch (`.github/cms-version.py`, skipped for betas and without the `CMS_TOKEN` secret).
- `Resources/Logo/` – logo and README banner sources (SVG).
- `Resources/Screenshots/` – real screenshots of holzIce, used by the README gallery (and on https://holzcloud.ch/holzice). Replace a screenshot of the original Ice there with one of holzIce when one exists.
- `docs/upstream-bugs.md` – the open bug reports of the original Ice, grouped, and which of them holzIce has fixed. Update it when fixing one.

## Building

macOS only (the Xcode pinned in `.github/actions/select-xcode/action.yml`, currently 26.6): `Scripts/install.sh`. There is no Linux build; CI builds, runs `swift test` and runs SwiftLint (official image pinned in `lint.yml`, `.swiftlint.yml`, `--strict`).
