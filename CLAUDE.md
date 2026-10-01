# holzIce

holzIce is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, a menu bar manager for macOS, with macOS 27 support and Homebrew distribution.

## Rules

- **Everything in this repository is written in English**: code, comments, commit messages, pull requests, issues, README and other docs. This applies even when the conversation is in another language.
- Always credit Ice and Jordan Baird as the original project (README, NOTICE). Keep the GPL-3.0 license.

## Layout

- `Ice/` – the app. `Ice/MenuBar/MacOS27/` is the macOS 27 backend.
- `Casks/holzice.rb` – the Homebrew cask; this repository is also the tap.
- `.github/workflows/release.yml` – a `v*` tag builds the app on a macOS runner, publishes the release and updates the cask on `main`.
- `Resources/Logo/` – logo and README banner sources (SVG).

## Building

macOS only (Xcode 27): `Scripts/install.sh`. There is no Linux build; CI runs SwiftLint (`.swiftlint.yml`, `--strict`).
