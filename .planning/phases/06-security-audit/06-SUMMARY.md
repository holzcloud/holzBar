---
phase: 06-security-audit
plan: fixes
subsystem: security (URL scheme, settings import and sync, custom icons, release pipeline, build script)
status: complete
tags: [security, audit-01, url-scheme, zen-mode, settings-validation, settings-sync, code-signing, attestation]
requires: ["06-SECURITY-AUDIT.md"]
provides:
  - "URL commands that cannot end Zen mode silently or during a screen share"
  - "range-checked imported, synced and stored settings; hotkeys without modifiers refused on load"
  - "sync file read without symbolic links, size-limited, off the main actor after launch; no computer name"
  - "custom icons decoded only as bitmaps"
  - "stable self-signed release signature (once the secrets exist) and build provenance attestations"
  - "SECURITY.md with the threat register"
affects: [".github/workflows/release.yml", "README.md", "Integrations/Raycast/README.md", "Scripts/install.sh"]
tech-stack:
  added: ["actions/attest-build-provenance@v4 (release workflow)"]
  patterns:
    - "Core decision types for untrusted input (URLCommand.Decision, SettingsSchema.NumberRule, CustomIconData), unit tested in HolzBarCoreTests"
    - "O_NOFOLLOW | O_NONBLOCK open plus fstat for files in folders other parties can write"
    - "signing key imported only after the build, into a throwaway keychain"
key-files:
  created:
    - holzBar/Core/URLPrompt.swift
    - holzBar/Core/CustomIconData.swift
    - Tests/HolzBarCoreTests/URLPromptTests.swift
    - Tests/HolzBarCoreTests/CustomIconDataTests.swift
    - docs/signing.md
    - SECURITY.md
  modified:
    - holzBar/Core/URLCommand.swift
    - holzBar/Core/ZenMode.swift
    - holzBar/Main/URLCommands.swift
    - holzBar/MenuBar/MenuBarManager.swift
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - holzBar/Core/SettingsSchema.swift
    - holzBar/Core/Defaults.swift
    - holzBar/Core/HotkeyStorage.swift
    - holzBar/Settings/Models/GeneralSettings.swift
    - holzBar/Settings/Models/AdvancedSettings.swift
    - holzBar/Settings/Models/HotkeysSettings.swift
    - holzBar/MenuBar/Spacers/MenuBarSpacers.swift
    - holzBar/MenuBar/Appearance/Configurations/MenuBarAppearanceConfigurationV2.swift
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/Utilities/Migration.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Core/SettingsSyncDevice.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/MenuBar/ControlItem/ControlItemImage.swift
    - holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift
    - holzBar/Resources/Localizable.xcstrings
    - MenuBarItemService/Listener.swift
    - .github/workflows/release.yml
    - Scripts/install.sh
    - README.md
    - Integrations/Raycast/README.md
    - .planning/phases/06-security-audit/06-SECURITY-AUDIT.md
decisions:
  - "M-1: a URL may always turn Zen mode on; turning it off asks (NSAlert, no default button, Escape cancels) and is refused while Zen mode's automatic part (screen sharing) is on; a URL never clears isAutomatic"
  - "M-1/L-1: while Zen mode is on, URL toggles of the Shelf and auto-rehide and URL profiles are refused; outside Zen mode they ask first, because they change settings that last and sync"
  - "L-1: prompts show only stored names, cleaned and cut to 40 characters; one open prompt at a time and a 30 s quiet period after a declined one"
  - "M-2: slider values are clamped to the slider's range, whole-number settings (choices, counts) outside their range are refused, infinity and NaN always refused; the models clamp again on load because any process can write the defaults"
  - "M-2: the prompt before applying a pulled sync file at launch was not added (not part of the chosen fix)"
  - "L-2: the launch-time pull stays synchronous on the main thread (it must finish before any setting is read); the size limit bounds it; checks after launch read with @concurrent"
  - "L-2: files dated more than 1 h ahead are ignored rather than clamped, so a clamped date cannot make the same file apply again and again"
  - "L-5: stored icons are decoded with ImageIO only as PNG, JPEG, TIFF, HEIC/HEIF, GIF, BMP or ICNS (earlier versions stored icons in the chosen format); newly chosen icons are rasterized to PNG at most 256 px"
  - "M-4: sign after an ad hoc build instead of passing the identity to xcodebuild, so the key is never in a keychain while build scripts run, and Xcode's identity validation does not reject an untrusted self-signed certificate"
  - "M-4: the XPC peer requirement stays cdhash-based (a self-signed certificate has no team); pinning the certificate instead was not needed"
metrics:
  duration: "about 3 h"
  completed: 2026-10-03
actuals:
  tokens: 24000
  tasks: 8
  commits: 7
plan_head_before: 717545ac009210a32a7d0c6897cf4e0130372396
---

# Phase 06 Fixes: Security audit findings M-1 to M-4, L-1 to L-5, L-8 Summary

The findings the user chose from `06-SECURITY-AUDIT.md` are fixed: URL commands can no longer end Zen mode silently or during a screen share; imported, synced and stored settings are range-checked; the sync file and custom icons are read defensively; macOS 27's hidden privacy indicator is disclosed; releases get a stable self-signed signature (once the secrets exist) and build provenance attestations; `install.sh` builds in a private folder.

Nothing was compiled or run: this environment is Linux. The Swift was written for Swift 6 language mode with main actor default isolation and reviewed by hand; the new logic lives in `holzBar/Core` with unit tests (`swift test` runs them in CI).

## Per finding

| Finding | Status | What changed |
|---|---|---|
| M-1 Zen mode off by URL | Fixed | `holzbar://zen/on`, `/off`, `/toggle`. `URLCommand.Action.decision(zenMode:)`: turning Zen mode on runs at once, turning it off asks, and is refused while it is on for a screen share. `ZenMode.requested(byURL:)` never clears `isAutomatic`. While Zen mode is on, Shelf, auto-rehide and profile URLs are refused. |
| M-2 Unchecked settings values | Fixed | `SettingsSchema.NumberRule`, `Defaults.Key.numberRule` and `validatedSettings` on import, sync and the Ice import; `Defaults.Key.clamped(_:fallback:)` on load in the models; item spacing to `Int` only clamped; border width and screen corner radius clamped when decoded; stored hotkeys without a modifier (or Shift alone, Option alone on macOS 15+) not loaded. |
| M-3 Privacy indicator hidden on macOS 27 | Disclosed | Note in Settings → General on macOS 27, README Permissions warning and macOS 27 known limitation. |
| M-4 Ad hoc release trust | Fixed in the workflow | `release.yml` re-signs with a self-signed certificate from secrets in a temporary keychain (ad hoc with a warning without them), checks the hardened runtime, prints the certificate's SHA-256; `actions/attest-build-provenance@v4`; job-level permissions. `docs/signing.md`. |
| L-1 Spoofable, repeatable prompts | Fixed | Profile looked up first; stored name cleaned and shortened (`URLPrompt.displayName`); one prompt at a time, 30 s quiet after a decline (`URLPrompt.Gate`); Shelf and auto-rehide toggles ask. |
| L-2 Sync file handling | Fixed | `O_NOFOLLOW`/`O_NONBLOCK` open, `fstat` regular file ≤ 1 MB; `holzBar` folder must not be a link; checks after launch off the main actor; far-future files ignored. |
| L-3 Import turns sync on | Fixed | `SyncsSettingsWithICloud` is local only (`Defaults.Key.localOnlyKeys`). |
| L-4 Computer name in sync file | Fixed | No longer written; still read from older files. |
| L-5 Icon parser surface | Fixed | ImageIO with a bitmap allowlist and size limits; new icons stored as PNG. |
| L-8 Fixed `/tmp` build path | Fixed | `mktemp -d`, removed on exit. |
| L-6, L-7 | Open | Not part of the chosen fixes. |

`SECURITY.md` now holds the reporting policy and the threat register; the audit report marks each fixed finding.

## Deviations from Plan

- **[Rule 2] Appearance values clamped too.** The screen corner radius reached `Int(_:)` in the appearance editor and the border width is drawn; both come from the imported or synced appearance data, so they are clamped when decoded (M-2's "any Int(...) conversion of an untrusted Double").
- **[Rule 2] Profiles from URLs are refused while Zen mode is on.** Applying a profile can move items out of the hidden sections, which Zen mode is meant to prevent.
- **[Rule 1] `install.sh` checks `Signature=adhoc`** instead of a missing team, which a self-signed signature also lacks.
- **README test count** updated from 338 to 371.

## Threat Flags

None beyond the audit: no new network, entitlement or permission. The release workflow gains `id-token: write` and `attestations: write` on the release job, as required by the attestation.

## For the user

- Create the signing certificate and add `SIGNING_CERTIFICATE_P12` and `SIGNING_CERTIFICATE_PASSWORD` (docs/signing.md); after the first signed release, publish the certificate's SHA-256 in the README. The first signed release asks for Accessibility once more.
- Enable GitHub's private vulnerability reporting, which `SECURITY.md` points to.
- Write `docs/release-notes/v0.0.6-beta1.md` with the M-3 disclosure, the new URL behaviour (Shelf and auto-rehide URLs ask; `zen/on` and `zen/off`), the first-signed-release re-grant and how to verify the attestation.
- On a Mac: check that the URL prompts, the macOS 27 note and the icon picker look right, and that the privacy indicator really returns while nothing is concealed.

## Self-Check: PASSED

- Files exist: `holzBar/Core/URLPrompt.swift`, `holzBar/Core/CustomIconData.swift`, `docs/signing.md`, `SECURITY.md`, the two new test files.
- Commits exist: 44eab14, 7763fd5, 373485e, c1eedfa, a7f1f26, 458d824, plus the docs commit with this summary.
- `python3 .github/scripts/strings-check.py`, `privacy-check.py network` and `privacy-check.py logs` pass.
