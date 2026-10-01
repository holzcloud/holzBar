# holzIce

holzIce is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, a menu bar manager for macOS, with macOS 27 support and Homebrew distribution.

## Rules

- **Everything in this repository is written in English**: code, comments, commit messages, pull requests, issues, README and other docs. This applies even when the conversation is in another language.
- Always credit Ice and Jordan Baird as the original project (README, NOTICE). Keep the GPL-3.0 license.

## Naming

- The app is called **holzIce** everywhere a user can see it (UI strings, menus, README). The bundle identifier is `com.holzcloud.holzIce`, the product is `holzIce.app`.
- The Xcode project, target, scheme and Swift module are still called `Ice`, and so are internal type names (`IceBar`, `IceSection`, …). Leave them; renaming them would only churn the code.
- Links in the app and the repository lead to holzIce (`Constants.repositoryURL`, `Constants.issuesURL`, `Constants.websiteURL`). The only exception is the credit to the original: "Based on Ice by Jordan Baird" in the About pane (`Constants.originalIceURL`), the README and NOTICE. `websiteURL` points to the repository until holzIce has a website.
- Keep `com.jordanbaird.Ice` only where it refers to the original app (importing its settings, the `jordanbaird-ice` cask conflict).

## Layout

- `Ice/` – the app. `Ice/MenuBar/MacOS27/` is the macOS 27 backend.
- `Casks/holzice.rb` – the Homebrew cask; this repository is also the tap.
- `.github/workflows/release.yml` – a `v*` tag builds the app on a macOS runner, publishes the release and updates the cask on `main`.
- `Resources/Logo/` – logo and README banner sources (SVG).

## Building

macOS only (Xcode 27): `Scripts/install.sh`. There is no Linux build; CI runs SwiftLint (`.swiftlint.yml`, `--strict`).
