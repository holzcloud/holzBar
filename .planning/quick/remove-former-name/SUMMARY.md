---
status: complete
completed: 2026-10-02
---
# Quick task: remove the former app name

Only holzBar remains. Everything about the original Ice by Jordan Baird stays.

- Homebrew:
  - `cask_renames.json` is deleted.
  - `Casks/holzbar.rb` points only at holzBar; version and sha256 are unchanged.
  - `release.yml` only updates version and sha256.
  - `cask.yml` runs `brew style` and `brew audit --cask --strict` from the local tap.
- App:
  - The settings import only reads Ice's settings; its flag key is kept and the file copies are removed.
  - The former app is no longer in `ConflictingApps`.
  - Its URL scheme alias is removed; the `ice-bar` alias stays.
  - An unknown stored image set name now decodes as the default image set.
- Docs:
  - The migration section and the old gallery caption are gone from the README.
  - NOTICE, CLAUDE.md and the Raycast README are updated.
  - Release notes v0.0.1 to v0.0.5 now say holzBar.
- CLAUDE.md forbids the former name. The `former-name` job in `build.yml` enforces this everywhere except `.planning/`, `.claude/` and `.github/cms-version.py`.
- `.github/cms-version.py` is not touched. It is website tooling that still uses the old page slug.

Commits: 397e7e7, 7f00592, 8c342bc. CI is green on 8c342bc (build, test, swiftlint, cask, former-name).
