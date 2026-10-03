# Phase 06: Security audit of holzBar (AUDIT-01)

**Date:** 2026-10-03
**Commit audited:** `729c4c0` (main)
**Scope:** the app (`holzBar/`), the XPC service (`MenuBarItemService/`), `Shared/`, the `holzbar://` URL scheme, App Intents/Shortcuts, settings import, export and sync, permissions and TCC, private API use, event taps, logging, process spawning, hardened runtime and entitlements, ad hoc signing and quarantine removal, the CI and release pipeline (`.github/`), the Homebrew cask, the supply chain.
**Method:** source read of every entry point and trust boundary, plus the two repository checks (`privacy-check.py network` and `logs`, both pass), plus a read-only look at the GitHub repository settings (`gh api`). No code was changed. Nothing was built or run on a Mac (this environment is Linux), so runtime behaviour is taken from the code and from measurements recorded in code comments; those cases are marked.
**Config:** ASVS level 1, `block_on: high`.
**Fix status (2026-10-03, see `06-SUMMARY.md`):** M-1, M-2, L-1 to L-5 and L-8 are fixed; M-3 is disclosed; M-4 is fixed in the release workflow and needs the signing secrets; L-6, L-7 and the Info findings stay open. Each fixed finding below carries a **Status** line.

---

## Executive summary

holzBar's main security promises hold in the code:

- **No network.** No networking API in the sources, no network entitlement, NWPathMonitor only observes; CI checks the sources and the built binaries.
- **Least privilege.** No entitlements at all, hardened runtime on the app and the XPC service, no usage strings, Screen Recording only asked for by the feature that needs it, `tccutil` only for holzBar's own entry.
- **Private logs.** Every log interpolation names its privacy; personal data is `.private` or hashed.
- **XPC.** On macOS 26 and later the service accepts only holzBar's exact code (team + signing identifier, or signing identifier + cdhash for ad hoc builds), and it fails closed.
- **Settings input.** Only holzBar's own keys with the expected plist type are applied; only Codable/JSON decoding, no `NSKeyedUnarchiver`; item icon file names cannot escape their folder.

The audit found **no Critical or High** findings. It found **4 Medium**, **8 Low** and **11 Info** findings. The Medium ones:

1. **M-1:** any app, or a web page once the browser has asked, can switch **Zen mode off through `holzbar://zen`** and then reveal hidden items. Zen mode is meant to keep them hidden during a screen share.
2. **M-2:** **imported or synced settings are only type-checked.** One crafted value (`ItemSpacingOffset = 1e300`) makes holzBar crash at every launch on every Mac that syncs the file. A hotkey without modifiers (for example Space) is registered system-wide.
3. **M-3:** on macOS 27, while holzBar conceals items, **Control Centre's camera, microphone and screen-capture indicator is gone** (measured by the project, written in the code). Users are not told.
4. **M-4:** release trust rests on an **ad hoc signature with quarantine removed**. Every update makes users grant Accessibility again, so a trojanized `holzBar.app` would get the grant just as easily. Developer ID is out of scope by user decision, but a stable self-signed certificate would remove most of this risk.

The CI and release pipeline is above average: the version input is validated, the swift.org toolchain is pinned by SHA-256 and its signature is checked, the SwiftLint image is pinned by digest, and the workflows have no `pull_request_target`. What remains: the release job's write token is available during the whole build, actions are pinned by tag, and the repository protections on `main` and the `v*` tags are minimal (L-6, L-7).

**threats_open (severity >= high): 0.** Every finding is below the `block_on: high` threshold. The user decides which ones ship in `0.0.6-beta1` (AUDIT-01).

| Severity | Count | IDs |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 4 | M-1, M-2, M-3, M-4 |
| Low | 8 | L-1 to L-8 |
| Info | 11 | I-1 to I-11 |

---

## Attack surface: what another party can trigger

| Entry point | Who can use it | What it can do | Guard today |
|---|---|---|---|
| `holzbar://` URLs (`AppDelegate.application(_:open:)`) | Any process of the user, with no permission (`open`, `NSWorkspace`). A web page after the browser's "Open holzBar?" consent; Chrome can remember "always allow" per site | Show, hide or toggle the hidden and always-hidden sections; open the search; open Settings; toggle the Shelf, auto-rehide, application menus and **Zen mode**; apply a layout profile | Zen mode refuses show and toggle, but it can be switched off by URL (M-1). Applying a profile asks first (L-1) |
| App Intents / Shortcuts (`HolzBarIntents.swift`) | Shortcuts the user built, Siri, Spotlight. Other apps only through shortcuts the user made | The same actions, plus opening (clicking) any menu bar item by fuzzy name | None, by design: the user builds the shortcut (I-7) |
| Sync folder `holzBar/Settings.plist` | Anyone who can write the chosen folder: a shared Dropbox or Nextcloud folder, a network share, a Syncthing peer, malware on another synced Mac | Every holzBar setting (hotkeys, layout, profiles, appearance, rules), applied **silently at launch** | Key and plist-type check only (M-2, L-2) |
| Settings import (`SettingsBackup.importFromFile`) | A file the user picks | Every holzBar setting, including turning sync on (L-3) | Confirmation alert, key and type check |
| XPC service `com.holzcloud.holzBar.MenuBarItemService` | Only the containing app (launchd scope); on macOS 26+ also a peer code requirement | Window-to-PID lookups | Requirement on 26+ (I-1, I-2) |
| Distributed notifications (`com.apple.screenIsLocked`/`Unlocked`) | Any process | Pause or resume menu bar captures | None needed (I-4) |
| Defaults domain `com.holzcloud.holzBar` and Ice's domain | Any process of the same user | The same as an import | Same-user trust boundary: out of scope, except that it is the same input path as M-2 |

---

## Findings

### Medium

#### M-1: Any app or web page can turn Zen mode off and reveal hidden items

- **Location:**
  - `holzBar/Main/URLCommands.swift:93-94` (`holzbar://zen` calls `manager.toggleZenMode()` without asking)
  - `holzBar/Core/URLCommand.swift:41-47` (`needsConfirmation` is `false` for `.toggleZenMode`)
  - `holzBar/Core/ZenMode.swift:68-70` (toggling an active Zen mode clears **both** `isManual` and `isAutomatic`)
  - `holzBar/MenuBar/MenuBarManager.swift:444-445`
  - The guard that this bypasses: `URLCommands.swift:59-66` ("Zen mode keeps hidden items hidden; another app cannot reveal them.")
- **Impact:** Zen mode is a privacy control: it turns on automatically while the screen is mirrored or shared, and it refuses URL commands that would reveal items. But the URL scheme can switch Zen mode itself off, automatic part included, with no confirmation and no permission. After that, `show/hidden` works. With `auto-rehide/toggle` the items also stay revealed, and that setting persists and syncs.
- **Exploit scenario:** During a Zoom or Teams screen share, auto-Zen is on. Any process of the user, or a page the browser may open `holzbar://` links for, opens `holzbar://zen`, then `holzbar://auto-rehide/toggle`, then `holzbar://show/hidden`. The hidden items appear on the shared screen and stay there.
- **Proposed fix:**
  - A URL may only turn Zen mode **on** (`holzbar://zen/on`); `zen/toggle` while Zen is active is refused or asks like `profile`.
  - Never clear `isAutomatic` from a URL.
  - While Zen is active, refuse `auto-rehide` and `shelf` toggles from URLs.
  - Add tests in `URLCommandTests`/`ZenModeTests`.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). `holzbar://zen` takes `on`, `off` and `toggle`; a URL may turn Zen mode on, turning it off asks first, and while the screen is shared it is refused (`URLCommand.Action.decision(zenMode:)`, `ZenMode.requested(byURL:)`, which never clears `isAutomatic`). While Zen mode is on, the Shelf and auto-rehide toggles and profiles from URLs are refused. Tests in `URLCommandTests` and `ZenModeTests`.

#### M-2: Imported or synced settings can crash holzBar at every launch and register bare-key global hotkeys

- **Location:**
  - `holzBar/Core/SettingsSchema.swift:42-43` (`.number` accepts any `NSNumber`: NaN, ±inf, 1e300)
  - `holzBar/Settings/Models/GeneralSettings.swift:116-120`, `:161`, `:172` (`Int(itemSpacingOffset)` traps when the value is out of `Int` range or not finite)
  - `holzBar/Utilities/SettingsSync.swift:376-387` (`pullIfNeeded` applies a newer sync file before `AppState` exists, without asking; `AppDelegate.swift:17-18`)
  - `holzBar/Settings/Models/HotkeysSettings.swift:90-105` (`decodeKeyCombination` checks the key range, the modifier bits and the system's symbolic hotkeys only, while the recorder also refuses no modifiers and Shift-only at `holzBar/UI/Views/HotkeyRecorder.swift:210`; `KeyCombination.swift:78` accepts modifiers `0`)
  - The same class of bug: `showOnHoverDelay` reaches `Task.sleep(for: .seconds(delay))` at `holzBar/Events/HIDEventManager.swift:579/603`. `tempShowInterval` reaches `holzBar/Hotkeys/HotkeyActionPerform.swift:68-70`; its clamp at `AdvancedSettings.swift:130` does not catch NaN. Converting a non-finite or huge `Double` to a `Duration` is expected to trap too; not verified on a Mac.
- **Impact:**
  - **Denial of service:** holzBar crashes during setup at every launch, on **every Mac that pulls the file**. Recovery needs `defaults delete com.holzcloud.holzBar ItemSpacingOffset`, which a user will not find.
  - **Input interception:** a stored hotkey without modifiers (Space, Return, a letter) or with Command+V is passed to `RegisterEventHotKey` and swallows that key system-wide.
  - No code execution was found: the readers decode only JSON and plist types.
- **Exploit scenario:** Someone who can write the sync folder writes `holzBar/Settings.plist` with:
  - a newer `modified` date and a random `deviceID`;
  - `<key>ItemSpacingOffset</key><real>1e300</real>` in `settings`;
  - optionally a `Hotkeys` entry with modifiers 0.

  At the next launch each syncing Mac applies it silently and crashes. The same works with a "my holzBar settings" file a user downloads and imports.
- **Proposed fix:**
  - Extend `SettingsSchema` from types to **values**: finite numbers clamped to each setting's range (the slider bounds), enum raw values checked, `spacerWidth` bounded.
  - Run stored hotkeys through `Modifiers.rejection(refusesOptionOnly:)` and the system-reserved check, exactly like the recorder.
  - Replace `Int(x)` on settings with `Int(exactly:)` or clamping.
  - Ask before applying a pulled file at launch when it changes hotkeys. Better: apply pulled settings only after launch, with the existing "Restart" prompt.
  - Add fuzz cases (NaN, inf, 1e300, negative) to `SettingsSchemaTests` and `HotkeyStorageTests`.
- **Effort:** M
- **Status: fixed** (phase 06 fixes). `SettingsSchema.NumberRule` and `Defaults.Key.numberRule`: imported and synced numbers must be finite, slider values are clamped to the slider's range, whole numbers (choices, counts) outside their range are refused; the models clamp what they read from the defaults (`Defaults.Key.clamped(_:fallback:)`), and `itemSpacingOffset` reaches `Int` only clamped. The appearance's border width and screen corner radius are clamped when decoded. Stored hotkeys without a modifier, or with Shift alone (and Option-only on macOS 15 and later), are not loaded (`HotkeyStorage.loadRejection`). Not done: asking before a pulled file changes hotkeys at launch. Tests in `SettingsSchemaTests` and `HotkeyStorageTests`.

#### M-3: On macOS 27, concealment hides Control Centre's camera, microphone and screen-capture indicator

- **Location:**
  - `holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:59-64`. The project measured this on macOS 27.0 and wrote it down there: the capture indicator "is drawn while no assertion is live and gone while one is, whatever the allowlist holds". Only "the small green dot beside the clock … stays".
  - `holzBar/MenuBar/MacOS27/Concealer27.swift` holds the assertion whenever an application is concealed, which is holzBar's normal state.
- **Impact:** macOS's menu bar privacy indicator (green for the camera, orange for the microphone, indigo for screen sharing or recording) disappears while holzBar hides anything.
  - Screen capture by another app then has no menu bar indicator at all; the clock dot is documented only as the camera dot.
  - The README, the permissions table and the release notes do not mention it.
- **Exploit scenario:** A remote-support tool or spyware that already holds Screen Recording records the screen. The user relies on the menu bar indicator, sees nothing while holzBar's sections are collapsed, and never learns that the screen is being captured.
- **Proposed fix:**
  1. Disclose it now: README "Known issues", the permissions section and the `0.0.6-beta1` release notes.
  2. Release the assertion (show everything) while a capture runs:
     - microphone in use: CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`;
     - camera in use: CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere`;
     - both are public and need no permission, and listeners avoid polling.
  3. Screen capture has no public signal. Offer a setting such as "Keep the privacy indicator visible" (do not conceal on macOS 27), and file Feedback with Apple.
- **Effort:** M
- **Status: disclosed** (phase 06 fixes). A note in Settings → General on macOS 27 (`PrivacyIndicatorNote`), the README's Permissions section and its macOS 27 known limitations. The `0.0.6-beta1` release notes still need it. Not done: releasing the assertion while the camera or microphone is in use, and a setting to keep the indicator.

#### M-4: Release trust rests on an ad hoc signature, quarantine removal and an Accessibility re-grant after every update

- **Location:**
  - `.github/workflows/release.yml:52-59` (`CODE_SIGN_IDENTITY=-`)
  - `Casks/holzbar.rb:23-31` (`xattr -dr com.apple.quarantine`)
  - `holzBar/Permissions/Permission.swift:173-191` and `README.md:209`, `:310` (users are told to "Reset and Grant Again" after updates)
  - `Scripts/install.sh:61-70` (resets TCC for every ad hoc build)
- **Impact:**
  - TCC pins an ad hoc app to its cdhash, so every update drops Accessibility and users learn to grant it again.
  - Gatekeeper never assesses holzBar: Homebrew installs lose the quarantine flag, and manual downloaders are told to strip it.
  - `/Applications/holzBar.app` belongs to the user, so any process of the user can replace it.
  - A trojanized build with the same name and bundle identifier is therefore indistinguishable: the user sees holzBar's familiar permissions window and grants Accessibility. That means synthetic input, reading UI and keystroke monitoring for the attacker.
- **Exploit scenario:** Malware running as the user (no admin rights) replaces `holzBar.app/Contents/MacOS/holzBar` with its own ad hoc-signed binary and waits for the next login. holzBar "asks for Accessibility again, as after every update", and the user grants it.
- **Note:** Developer ID signing and notarization are out of scope by user decision (REQUIREMENTS "Out of Scope"). This finding records the residual risk and a mitigation that needs no Apple account.
- **Proposed fix:**
  - Sign releases with a **stable self-signed code-signing certificate**, kept as an encrypted CI secret. The designated requirement becomes `identifier "com.holzcloud.holzBar" and certificate leaf = H"…"`:
    - TCC keeps the grant across updates, so the re-grant habit and the "Reset and Grant Again" step after updates go away;
    - a replaced binary signed with another key loses the grant;
    - the XPC service can pin the certificate instead of cdhashes.
  - Publish the certificate's SHA-256 in the README.
  - Add GitHub artifact attestations (`actions/attest-build-provenance`), so `gh attestation verify holzBar-<v>.zip -R holzcloud/holzBar` proves that a zip came from the workflow.
- **Effort:** M
- **Status: fixed in the workflow** (phase 06 fixes). `release.yml` signs with a stable self-signed certificate from the `SIGNING_CERTIFICATE_P12` and `SIGNING_CERTIFICATE_PASSWORD` secrets, imported after the build into a temporary keychain that is deleted afterwards; without them it stays ad hoc with a warning. Every release zip gets a build provenance attestation (`actions/attest-build-provenance@v4`; `id-token` and `attestations` write only on the release job). The XPC peer requirement needs no change: a self-signed certificate has no team, so the service keeps pinning the containing app's cdhashes. How to create the certificate and verify a release: `docs/signing.md`. The maintainer still has to create the certificate, add the secrets and publish its fingerprint.

### Low

#### L-1: URL commands show a spoofable prompt, can repeat it, and change persistent settings without asking

- **Location:**
  - `holzBar/Main/URLCommands.swift:96-100`, `:114-125`. The alert text is built from the URL **before** `LayoutProfiles.apply(named:)` checks at `holzBar/MenuBar/Profiles/LayoutProfiles.swift:150-154` that the profile exists.
  - `URLCommands.swift:87-90`: `useShelf` and `autoRehide` are toggled; both persist and are pushed to every synced Mac.
- **Impact:** Any app or page can:
  - show a holzBar-branded modal whose message carries arbitrary text, newlines included;
  - repeat the modal;
  - flip settings that then sync to all of the user's Macs.
- **Exploit scenario:** An app opens `holzbar://profile/x%E2%80%9D%3F%0A%0AholzBar%20must%20verify%20your%20Apple%20Account…`, and holzBar shows a phishing-style question. A loop of such URLs nags the user with modal alerts.
- **Proposed fix:**
  - Look the profile up first and ignore unknown names (log only).
  - Show the stored profile's name, strip control characters and newlines, and truncate it.
  - Allow at most one pending prompt.
  - Make the `shelf` and `auto-rehide` URL toggles temporary, or ask.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). The profile is looked up first, unknown names are ignored, and the prompt shows the stored name cleaned of control and formatting characters and cut to 40 characters (`URLPrompt.displayName`); one prompt at a time and none for 30 s after a declined one (`URLPrompt.Gate`); the Shelf and auto-rehide toggles ask first. Tests in `URLPromptTests`.

#### L-2: Sync-folder file handling follows symlinks, has no size or type limit and reads at launch on the main thread

- **Location:**
  - `holzBar/Utilities/SettingsSync.swift:201-218` and `:305-318` (`createDirectory` and the coordinated write follow a symlinked `holzBar` directory)
  - `:355-372` (`Data(contentsOf:)` with no size or regular-file check)
  - `:376-387` (`pullIfNeeded` runs on the main thread in `AppDelegate.init`)
  - `holzBar/Core/SettingsSyncFile.swift:41` (any future `modified` date is accepted)
- **Impact:** A writer to the folder can:
  - turn `holzBar` into a symlink, so holzBar creates and replaces `Settings.plist` in another folder of the user. The content stays limited to holzBar's schema; no way to code execution was found;
  - place a multi-GB file that is read whole into memory on the main thread at launch (hang, memory pressure);
  - date the file in the far future, so this Mac ignores legitimate updates from the other Macs until it pushes itself.
- **Proposed fix:**
  - Refuse symlinks and non-regular files (`URLResourceValues.isSymbolicLink`, `isRegularFile`).
  - Cap the file at 1 MB.
  - Read off the main thread with a deadline.
  - Clamp `modified` to `now` plus a small skew.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). The file is opened with `O_NOFOLLOW | O_NONBLOCK`, checked with `fstat` to be a regular file of at most 1 MB and read up to that limit (`SettingsSyncFile.readContents`); the `holzBar` folder must be a real folder or not exist yet (`isUsableFolder`, `lstat`) before holzBar watches, creates or writes it; checks after launch read the file off the main actor; files dated more than an hour ahead are ignored. The launch-time pull still reads on the main thread, as it must finish before the settings are read; the size limit bounds it. Tests in `SettingsSyncFileTests`.

#### L-3: An imported settings file can turn settings sync on

- **Location:**
  - `holzBar/Core/Defaults.swift:186`, `:266`: `SyncsSettingsWithICloud` is an importable `.bool`.
  - `holzBar/Utilities/SettingsBackup.swift:24-35`: not in `excludedKeyPrefixes`, so it is exported (`:44-52`) and applied (`:62-81`).
  - `holzBar/Utilities/SettingsSync.swift:37-40`: the key is excluded from sync only.
  - Enabling sync without a chosen folder falls back to iCloud Drive and stores it (`SettingsSync.swift:79-106`, `:174-177`).
- **Impact:** Importing a file exported on a Mac with sync on, or a crafted file, turns sync on after the restart. holzBar then writes the settings and the computer name (L-4) to iCloud Drive although the user never turned sync on. This contradicts PRIV-02 ("iCloud sync only when the user turns it on").
- **Proposed fix:** Never export or import `SyncsSettingsWithICloud`: add it to `excludedKeyPrefixes`, or keep a set of local-only keys that `SettingsBackup` honors.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). `Defaults.Key.localOnlyKeys` holds `SyncsSettingsWithICloud`; it is not in `importableKinds`, so it is never exported, imported or synced.

#### L-4: The computer name is written into the sync file

- **Location:** `holzBar/Utilities/SettingsSync.swift:298-303`. The name is only a fallback in `holzBar/Core/SettingsSyncDevice.swift:30-38`, for files without a `deviceID`, and is never shown.
- **Impact:** Computer names usually contain the owner's name ("Anna's MacBook Pro"). The name goes to iCloud Drive or a shared folder although the UUID alone decides which Mac wrote the file. This goes against "Personal data stays on the Mac".
- **Proposed fix:** Stop writing `device`; keep reading it for files from older builds. Or write a salted hash.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). The sync file no longer carries `device`; it is still read from files of older builds.

#### L-5: Custom icon data from untrusted settings is decoded with `NSImage(data:)`

- **Location:** `holzBar/MenuBar/ControlItem/ControlItemImage.swift:41-42`, reached from `holzBar/Settings/Models/GeneralSettings.swift:193-196` (`IceIcon`, an importable and synced `.data` key).
- **Impact:** `NSImage(data:)` accepts many formats (PDF, TIFF, …). Bytes from a sync folder or an imported file reach these parsers at every launch, in an unsandboxed process that holds Accessibility. No bug is known; this widens the parser attack surface of the most privileged process.
- **Proposed fix:** Decode with `CGImageSource`, only when `CGImageSourceGetType` is `public.png`, with a byte and pixel cap. Or store custom icons as files the way `ItemIconStore` does (re-encoded PNG, validated name).
- **Effort:** S
- **Status: fixed** (phase 06 fixes). Stored icons are decoded with ImageIO only as PNG, JPEG, TIFF, HEIC/HEIF, GIF, BMP or ICNS, up to 8 MB and 4096 pixels (`CustomIconData`, `ControlItemImage.bitmapImage(from:)`); a newly chosen icon is scaled and stored as PNG.

#### L-6: Release job holds a write token during the whole build, runs an unpinned tool and skips the post-build checks

- **Location:**
  - `.github/workflows/release.yml:11-12` (`contents: write` for the whole job)
  - `:22-24` (`actions/checkout` persists the token in `.git/config`; no `persist-credentials: false`)
  - `:52-59`: the build runs the project's SwiftLint run-script phase (`holzBar.xcodeproj/project.pbxproj:232`) with whatever `swiftlint` is on `PATH`, unsandboxed (`ENABLE_USER_SCRIPT_SANDBOXING = NO`, `:399`, `:434`)
  - every `uses: actions/checkout@v7` is pinned by tag, not commit SHA
  - the hardened-runtime, network-symbol and entitlement checks of `build.yml:58-136` are not run on the binary that is published
- **Impact:**
  - Any code that runs during the release build can use a token that pushes to `main` and edits releases and the cask: the run-script, the toolchain package's install scripts, or a moved action tag.
  - The published zip is never checked for the hardened runtime or network symbols, although README:124 says "every build checks the app's binaries and entitlements for network access".
- **Proposed fix:**
  - Split the release into a read-only build job (upload artifact) and a publish job with `contents: write`.
  - Set `persist-credentials: false`.
  - Pin actions by SHA, kept current by Dependabot for `github-actions`.
  - Skip the SwiftLint phase in CI (`[ -n "$CI" ] && exit 0`); the lint workflow already runs SwiftLint.
  - Move the `build.yml` binary checks into a script that both workflows run.
- **Effort:** M

#### L-7: Minimal repository protections for `main`, the `v*` tags and secrets

- **Location:** GitHub settings, read on 2026-10-03 with `gh api`:
  - `main` has no branch protection (`404 Branch not protected`);
  - the only ruleset is "No force push" (`deletion`, `non_fast_forward`) on branches;
  - there is no ruleset for tags;
  - secret scanning and push protection are disabled.

  `CMS_TOKEN` is a repository secret used at `.github/workflows/release.yml:116`, with no environment.
- **Impact:** One leaked maintainer token, or a tag pushed on an unreviewed commit, publishes a release, updates the cask on `main` (which every `brew upgrade` installs) and runs `cms-version.py` with `CMS_TOKEN`. Secrets committed by mistake are not caught.
- **Proposed fix:**
  - Add a tag ruleset for `refs/tags/v*` so only maintainers create tags.
  - Require a pull request and the Build and test checks on `main`, with a bypass for the release bot (or let the bot open a pull request).
  - Enable secret scanning and push protection (free for public repositories).
  - Move `CMS_TOKEN` into an environment `release` limited to `v*` tags.
- **Effort:** S

#### L-8: `Scripts/install.sh` builds into a fixed path in `/tmp`

- **Location:** `Scripts/install.sh:17` (`DERIVED` defaults to `/tmp/holzbar-build`), `:30-56`
- **Impact:** On a Mac with several accounts, another local user can create `/tmp/holzbar-build` first and swap the built app between `xcodebuild` and `ditto`. An ad hoc-signed replacement passes `codesign --verify`, is installed and launched, and the script has just reset TCC, so the victim grants it Accessibility.
- **Proposed fix:** Use `DERIVED="${DERIVED:-$(mktemp -d "${TMPDIR:-/tmp}/holzbar-build.XXXXXX")}"`. `TMPDIR` is per-user and `0700`. The `Scripts/macos27/verify-*.sh` scripts already use `mktemp`.
- **Effort:** S
- **Status: fixed** (phase 06 fixes). `DERIVED` defaults to a new `mktemp -d` folder in `TMPDIR`, removed on exit.

### Info

| ID | Location | Observation | Suggestion |
|---|---|---|---|
| I-1 | `MenuBarItemService/Listener.swift:121-125` | Before macOS 26 the listener has no peer requirement | Accept. Bundled XPC services are only reachable from the containing app's launchd domain, the app connects only on 26+ (`MenuBarItemServiceConnection.swift:12`), and the service only maps windows to PIDs |
| I-2 | `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:149-158` | Ad hoc builds do not pin the service (documented: launchd scoping) | Accept. Or pin with `LightweightCodeRequirements` behind `#available(macOS 14.4, *)`; M-4's certificate makes this simple |
| I-3 | `holzBar/MenuBar/Search/MenuBarSearchPanel.swift:41-49`, `holzBar/Events/EventMonitor.swift:77` | While the search panel is open, a **global** keyDown monitor sees keys typed in other apps. Only Escape is inspected and nothing is stored or logged | A local monitor is enough while the panel is key (least privilege) |
| I-4 | `holzBar/Events/SystemActivityMonitor.swift:59-66` | Any process can post the screen-lock distributed notifications | No impact: they only pause or resume captures |
| I-5 | `.github/scripts/privacy-check.py:37-55`, `.github/workflows/build.yml:112` | The network check is a denylist. `Data(contentsOf:)`, `String(contentsOf:)`, `NSImage(contentsOf:)` and `CGImageSourceCreateWithURL` fetch remote URLs through Foundation-internal URLSession and would pass both the source and the binary check. Today's call sites use file URLs (`SettingsBackup.swift:114` guards) | Flag `contentsOf:` and `CreateWithURL` calls that lack an `isFileURL` guard or an allowlist entry |
| I-6 | `Casks/holzbar.rb:38` | `zap` lists `~/Library/HTTPStorages/com.holzcloud.holzBar`, a path from the Sparkle era | Remove unless the folder is observed. It suggests networking to readers of the cask |
| I-7 | `holzBar/Main/HolzBarIntents.swift:98-118` | Shortcuts actions ignore Zen mode, by design (the user built the shortcut) | Say so in the `ZenMode` doc comment |
| I-8 | `holzBar/Main/ConflictingApps.swift` | Apps are matched by display name ("Ice", "Thaw", …) as well as bundle ID, and force-terminated 3 s after the user confirms | Match bundle IDs only, so an unrelated app named "Ice" is never killed |
| I-9 | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:44-45` | Captured menu bar images (screen content) persist in `~/Library/Caches/com.holzcloud.holzBar/ItemImages` | Fine: per-user, not backed up, discarded on appearance change. Optionally clear them when Screen Recording is revoked |
| I-10 | `.github/workflows/release.yml:17` | Releases are built on the `xcode-27` image, a public preview | Accepted by user decision (2026-10-03) |
| I-11 | `CLAUDE.md` (GSD update), `.claude/settings.json` hooks | Developer machines run `npx -y @opengsd/gsd-core@latest` (unpinned npm code), and its hooks run every session | Not shipped in the app. Pin a version when updating |

---

## Verified as safe

Each item was checked in the code at the cited location.

- **No network code.**
  - `privacy-check.py network` passes; the only allowlisted use is `NWPathMonitor` in `RevealRules.swift`.
  - `build.yml:108-136` checks both binaries for URLSession, NSURLConnection, WKWebView, Network connections and sockets, and both bundles for network entitlements.
  - `Package.swift` has no dependencies; no `Package.resolved`; `.github/allowed-packages.txt` is empty.
  - External links are hard-coded HTTPS constants (`Constants.swift:27-39`).
- **Entitlements and hardening.**
  - `CODE_SIGN_ENTITLEMENTS = ""` and `ENABLE_HARDENED_RUNTIME = YES` for the app and the XPC service (`project.pbxproj:390-498`); no `.entitlements` files.
  - CI checks the runtime flag on both (`build.yml:60-74`).
  - No usage strings in Info.plist or `InfoPlist.xcstrings`; no Apple Events; no sandbox (justified in README:139).
- **XPC peer check (macOS 26+).**
  - Team builds: `.isFromSameTeam(andMatchesSigningIdentifier:)`.
  - Ad hoc builds: signing identifier plus the cdhashes of the containing app, after `SecStaticCodeCheckValidity` over all architectures (`Listener.swift:73-94`, `CodeSignature.swift:85-123`).
  - Fails closed (`Listener.swift:112-129`).
  - The client side checks the team when one exists (`MenuBarItemServiceConnection.swift:156-158`).
  - CI checks that the identifiers match (`build.yml:78-101`).
- **Process spawning.** The only one is `/usr/bin/tccutil reset <service> <own bundle id>`: absolute path, argument array, no shell, user-initiated (`Permission.swift:173-191`). No `system`, `popen`, `NSAppleScript` or `osascript` in the app.
- **Settings import, export and sync.**
  - Only `Defaults.Key` keys with the declared plist kind are applied (`SettingsSchema.swift:64-75`, `SettingsBackup.swift:62-81`, `Migration.swift:28-67`).
  - Readers decode JSON with Codable only; no `NSKeyedUnarchiver` anywhere.
  - `SettingsSync*` keys (device ID, last-sync date, folder bookmark) are never exported, imported or synced (`SettingsBackup.swift:31-34`).
  - Import refuses non-file URLs (`SettingsBackup.swift:114`).
  - Writes are atomic and coordinated (`SettingsSync.swift:312-322`).
  - Window frames and status item positions are never imported.
- **No path traversal in item icons.** `ItemIconChoice.isValidFileName` allows only `[A-Za-z0-9_-]{1,64}.png` and is enforced on read and on delete (`ItemIconStore.swift:173-202`). Chosen images are re-encoded as PNG under a UUID name (`ItemIconStore.swift:118-170`). Group images use the same checks.
- **Hotkeys.** Stored combinations are range-checked (key 0-127, known modifier bits: the Ice#985 fix) and checked against system symbolic hotkeys. Registration uses `UInt32(exactly:)` (`HotkeyRegistry.swift:143-148`). The missing check is the modifier rule (M-2).
- **Event taps never touch the keyboard.**
  - Taps cover mouse moved (listen-only), mouse down/up and posted mouse events (`HIDEventManager.swift:125`, `SystemItemClickBridge27.swift:45`, `MenuBarItemEventPoster.swift:199-370`).
  - Keyboard input arrives only through Carbon hotkeys and local monitors in holzBar's own windows, plus the search panel's monitor (I-3).
  - No key is ever logged or stored.
- **Logging.**
  - `privacy-check.py logs` passes; every interpolation names its privacy.
  - Item names, bundle IDs, profile names, paths and errors are `.private` or `.private(mask: .hash)`.
  - URL commands log only the command name, never the URL (`URLCommands.swift:44-50`).
  - No `print`, `NSLog` or `os_log` calls.
- **URL scheme.**
  - Only `holzbar` is registered (Info.plist); parsing is strict, and unknown commands are ignored.
  - SwiftUI scenes ignore external events (`HolzBarWindow.swift:76`, `:90`).
  - The profile prompt has no Return default and Escape cancels (`URLCommands.swift:121-124`).
  - Non-`holzbar` URLs and file URLs are ignored.
- **Private APIs.**
  - CGS functions are bound with `@_silgen_name`, not looked up at runtime.
  - `MenuBarClientCore` is `dlopen`ed from a fixed system path on the sealed system volume; every selector is checked with `instancesRespond(to:)` before use (`MenuBarAssessmentAssertion27.swift:67-79`).
  - Library validation stays on.
- **Screen Recording** is never asked for at launch, only by `ScreenRecordingFeature` (`Permission.swift:264-282`).
- **Relaunch handoff.** The PID passed in the environment is used only if that process has holzBar's bundle identifier (`AppDelegate.swift:57-60`).
- **Release workflow input.** The tag or dispatch version reaches the shell only through `env` and is validated by a regex before use, and the rejected value is not echoed (`release.yml:29-41`). Release notes are required. `sed` gets only the validated version and a hex SHA-256.
- **Toolchain supply chain.**
  - The swift.org package is checked against a pinned SHA-256 and a Developer ID Installer signature ("Swift Open Source").
  - The toolchain path and the Swift version are verified, and CI fails if xcodebuild did not use that toolchain (`select-xcode/action.yml:58-118`, `build.yml:48-55`).
  - The SwiftLint image is pinned by digest (`lint.yml:17`).
- **Workflow privileges.**
  - Build, lint and cask jobs have `contents: read`; there is no `pull_request_target` or `workflow_run`.
  - Fork pull requests run without secrets on ephemeral GitHub-hosted runners (`xcode-27` is a GitHub image, not self-hosted).
  - `CMS_TOKEN` is used only in a `contents: read` job.
  - `cms-version.py` validates the version, skips betas, never prints the token, and refuses to write when a page's layout is unexpected.
- **Cask.**
  - HTTPS URL to the GitHub release, `sha256` pinned.
  - Quarantine is removed only from `{{appdir}}/holzBar.app`, through structured `postflight_steps` with `writable_paths`.
  - `uninstall quit`; `zap` limited to holzBar's own paths.
- **Raycast scripts.** The profile name is passed to Python as `argv` for URL quoting; no shell injection (`Integrations/Raycast/holzbar-profile.sh`).
- **No committed secrets.** No keys, tokens or certificates in the repository (pattern search over all tracked files outside `.git`, `.claude`, `.planning`).

## Not verifiable from here

- GitHub Actions settings (default workflow token permissions, fork pull request approval, allowed actions) could not be read: the proxy blocks those API paths. Check them in Settings → Actions → General: the default workflow permissions should be "Read repository contents", and "Require approval for all outside collaborators" should be on.
- Runtime claims taken from code comments (M-3's indicator behavior, the Carbon behavior of bare-key hotkeys in M-2) should be confirmed on a Mac when the fixes are made.

---

## Threat register (for SECURITY.md)

| Threat ID | Category | Component | Severity | Disposition | Status |
|---|---|---|---|---|---|
| T-06-M1 | Elevation of privilege (confused deputy) | URL scheme / Zen mode | medium | mitigate | mitigated |
| T-06-M2 | Denial of service / tampering | Settings import and sync | medium | mitigate | mitigated |
| T-06-M3 | Information disclosure (privacy indicator hidden) | macOS 27 concealment | medium | mitigate | disclosed (residual: macOS behaviour) |
| T-06-M4 | Spoofing (publisher identity) | Distribution, signing, TCC | medium | mitigate (or accept per user decision) | mitigated in the workflow (needs the signing secrets) |
| T-06-L1 | Spoofing / tampering | URL scheme | low | mitigate | mitigated |
| T-06-L2 | Tampering / DoS | Sync-folder file handling | low | mitigate | mitigated |
| T-06-L3 | Information disclosure | Settings import enables sync | low | mitigate | mitigated |
| T-06-L4 | Information disclosure | Computer name in sync file | low | mitigate | mitigated |
| T-06-L5 | Tampering (parser surface) | Custom icon data | low | mitigate | mitigated |
| T-06-L6 | Elevation of privilege (CI) | Release workflow | low | mitigate | OPEN (non-blocking) |
| T-06-L7 | Tampering (supply chain) | Repository protections | low | mitigate | OPEN (non-blocking) |
| T-06-L8 | Tampering (local) | `Scripts/install.sh` | low | mitigate | mitigated |

`block_on: high`, so **threats_open: 0**. After the phase 06 fixes, L-6 and L-7 stay open; the register is kept in `SECURITY.md`.
