# Security

holzBar is a menu bar manager that holds the Accessibility permission, so its security matters. This file says how to report a vulnerability, what holzBar promises, and which threats are known and how they are handled.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: on [holzcloud/holzBar](https://github.com/holzcloud/holzBar), open **Security → Report a vulnerability**. Do not open a public issue for a vulnerability.

Only the latest release, and `main`, receive security fixes. holzBar is in beta until 1.0.

## What holzBar promises

- **No network.** holzBar never connects to the network. No networking code, no network entitlement; CI checks the sources and the built binaries.
- **Least privilege.** Accessibility at first launch; Screen Recording only when a feature that needs it is used. No entitlements, the hardened runtime on the app and its XPC service.
- **Private logs.** Personal data (item names, bundle identifiers, profile names, paths) is logged as private or hashed.
- **Settings are input, not code.** Imported and synced settings are decoded only as property lists and JSON, limited to holzBar's own keys with the expected type and range.
- **Releases you can check.** Releases are signed with holzBar's own certificate once it is set up, and carry a build provenance attestation ([docs/signing.md](docs/signing.md)). holzBar has no Apple Developer ID and is not notarized.

## Threat register

From the security audit of 2026-10-03 (`.planning/phases/06-security-audit/06-SECURITY-AUDIT.md`), with its fixes. Severity follows the audit; nothing was rated critical or high.

| ID | Threat | Component | Severity | Disposition | Status |
|---|---|---|---|---|---|
| T-06-M1 | Another app or a web page turns Zen mode off with `holzbar://zen` and reveals hidden items during a screen share (confused deputy) | URL scheme, Zen mode | Medium | Mitigate | **Mitigated**: a URL may turn Zen mode on; turning it off asks first and is refused while the screen is shared; while Zen mode is on, no URL reveals items or changes a setting |
| T-06-M2 | A crafted settings file or sync file crashes holzBar at every launch (`ItemSpacingOffset = 1e300`) or registers a hotkey without modifiers system-wide | Settings import and sync | Medium | Mitigate | **Mitigated**: numbers are range-checked and clamped on import, sync and load; stored hotkeys without a modifier, or with Shift alone, are not loaded |
| T-06-M3 | On macOS 27, Control Centre's camera, microphone and screen-capture indicator is gone while holzBar conceals items | macOS 27 concealment | Medium | Mitigate (disclose) | **Disclosed** in Settings → General (macOS 27) and the README. The indicator itself cannot be kept: macOS removes it while any concealment assertion is live |
| T-06-M4 | A trojanized `holzBar.app` gets Accessibility because users re-grant it after every ad hoc update | Distribution, signing, TCC | Medium | Mitigate | **Mitigated** from 0.0.6-beta1: releases are signed with a stable self-signed certificate from repository secrets (ad hoc, with a warning, until they are set) and carry build provenance attestations |
| T-06-L1 | URL commands show a spoofable prompt, repeat it, or change lasting settings without asking | URL scheme | Low | Mitigate | **Mitigated**: prompts name only stored profiles, cleaned up and shortened; one prompt at a time and none for 30 s after a declined one; the Shelf and auto-rehide toggles ask first |
| T-06-L2 | The sync folder's file is followed through symbolic links, read whole at any size, read on the main thread, or dated far in the future | Sync-folder file handling | Low | Mitigate | **Mitigated**: no symbolic links (`O_NOFOLLOW`, `lstat`), regular files of at most 1 MB, checks after launch read off the main actor, files dated more than an hour ahead are ignored |
| T-06-L3 | An imported settings file turns settings sync on | Settings import | Low | Mitigate | **Mitigated**: `SyncsSettingsWithICloud` is never exported, imported or synced |
| T-06-L4 | The computer name (often the owner's name) is written into the sync file | Settings sync | Low | Mitigate | **Mitigated**: no longer written; still read from files of older builds |
| T-06-L5 | Custom icon data from settings reaches every image and document parser of AppKit | Custom holzBar icon | Low | Mitigate | **Mitigated**: decoded with ImageIO only as a few bitmap formats within byte and pixel limits; new icons are stored as PNG |
| T-06-L6 | The release job's write token is available during the whole build; actions pinned by tag; no binary checks on the published zip | Release workflow | Low | Mitigate | Open. The signing key is imported only after the build and deleted right after |
| T-06-L7 | Minimal repository protections for `main`, `v*` tags and secrets | GitHub settings | Low | Mitigate | Open (repository settings, done by the maintainer) |
| T-06-L8 | Another local account swaps the app in `/tmp/holzbar-build` during `Scripts/install.sh` | Build from source | Low | Mitigate | **Mitigated**: builds in a private `mktemp -d` folder, removed on exit |

The audit's informational findings (I-1 to I-11) are accepted or tracked there.
