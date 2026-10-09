# MODULE-ALTTAB: research on AltTab (window switcher)

Researched 2026-10-09, web only. Source reading was via raw.githubusercontent.com on branch `master` (no clone). Items marked (UNCERTAIN) are inferred or not confirmed from a primary source.

## 1. Facts

- Current version: v11.9.0, released 2026-10-06 (GitHub releases API: https://api.github.com/repos/lwouis/alt-tab-macos/releases/latest). Earlier: 11.8.0 (09-26), 11.7.1 (09-20), 11.7.0 (09-17), 11.6.x (09-05/11). Source: https://github.com/lwouis/alt-tab-macos/releases
- Minimum macOS raised to 12 in 11.7.0. Apple Silicon and Intel.
- Author: single maintainer (lwouis); about 16k stars, 74 open issues. Sponsor: JetBrains. Last push 2026-10-06. Cadence: a release every 1-2 weeks. Maintenance: very active.
- Website moved: alt-tab-macos.netlify.app 301-redirects to https://alt-tab.app/ (branded "AltTab Pro").
- Licence: repo is GPL-3.0 (GitHub API licence key `gpl-3.0`; `LICENCE.md` is the verbatim GPLv3 text). Confirmed. Caveat: AltTab now has a paid "Pro" tier, and its Pro code, licence manager and trial nagging live in the same GPL repo (`src/pro/...`). The code is GPL, but taking Pro-gating code over makes no sense.
- Contributing/AGENTS docs exist in the repo (the repo has a CLAUDE.md and AGENTS.md, so it is AI-assisted). Not relevant to the licence, but note it if code is ever copied.

## 2. Feature list

Source: https://alt-tab.app/features and the repo tree (https://github.com/lwouis/alt-tab-macos/tree/master/src).

Free (per alt-tab.app/features):
- Window switcher on a hold-modifier+Tab style shortcut, with window thumbnails/previews.
- Minimized, hidden and other-Space windows are included, with a badge.
- Close, minimize or fullscreen a window from the switcher without switching.
- Light/dark mode; instant or persistent switcher mode; VoiceOver support.
- Custom shortcuts, filterable by app, Space or screen.
- Three-finger trackpad gestures; command-line integration; 21 languages; no telemetry (claim by the site, not verified in code; see section 5).
- Exception rules (per-app ignore, e.g. VMs and remote desktops): `ExceptionsTab`, `ExceptionMatcher`.
- Settings tabs in source: General, Appearance (customize-style sheet, animations sheet), Controls (shortcut editor, additional controls, shortcuts-when-active), Exceptions, Upgrade, About.
- Source also shows: preview panel for the selected window, tab-group handling, drag and drop onto tiles, Mission Control overlay handling, input-source events, window-attention badges, screen/Space ordering ("Space Order").

Pro (paid) per the site: multiple display styles (thumbnails, icons, compact list), window search by title/app name, auto-sizing previews, up to 9 shortcuts. A trial/reminder schedule (Day 1/4/12/15/21/35 popovers) is in `src/pro/scheduling`. UNCERTAIN: exact free-versus-Pro split of the appearance themes; the site text is marketing copy.

## 3. Permissions

- Accessibility: required. Used for window enumeration (AXUIElement), raising and focusing windows, close/minimize/fullscreen actions, and the event tap for shortcuts.
- Screen Recording: used for thumbnails and for the titles of other apps' windows. The source has a `screenRecordingPermissionSkipped` preference and a `.skipped` state (`src/macos/SystemPermissions.swift`), so AltTab runs without it, with reduced content (no live thumbnails, titles likely missing; UNCERTAIN exact fallback UI, likely app icons only). The code comment notes that on macOS 27 window titles of other apps appear or vanish immediately with the grant, and SCShareableContent works without a relaunch (measured on macOS 27, per the code comment).
- Entitlements: sandbox off (`com.apple.security.app-sandbox` = false) and `disable-library-validation`. So AltTab is not sandboxed and could not be sandboxed given its private API use. Source: https://raw.githubusercontent.com/lwouis/alt-tab-macos/master/alt_tab_macos.entitlements
- Input Monitoring is not named in the files I read. It is possible the event tap triggers it on some setups (UNCERTAIN).

## 4. Technical approach and private APIs (important)

AltTab depends heavily on private/undocumented APIs. From `src/macos/api-wrappers/` (SkyLight.framework.swift, ApplicationServices.HIServices.framework.swift, CGSSymbolicHotKey.swift) via `@_silgen_name`:
- Window server (SkyLight/CGS): `CGSMainConnectionID`, `CGSHWCaptureWindowList` (thumbnails), `CGSCopyManagedDisplaySpaces`, `CGSCopyWindowsWithOptionsAndTags`, `CGSManagedDisplayGetCurrentSpace`, `CGSCopySpacesForWindows`, `CGSCopyWindowProperty`, `CGSGetWindowLevel`, `CGSCopyActiveMenuBarDisplayIdentifier`, `_SLPSSetFrontProcessWithOptions`, `SLSSpaceSetFrontPSN`, `SLPSPostEventRecordTo` (a synthetic key-window event record, reverse-engineered, with a note about a macOS 14.7.4+ change), `SLSWindowIteratorGetBounds` (via dlsym).
- Hotkeys: `CGSSetSymbolicHotKeyEnabled` to disable the native Cmd+Tab.
- Accessibility: `_AXUIElementGetWindow`, `_AXUIElementCreateWithRemoteToken` (brute-force discovery of windows on other Spaces), plus legacy Carbon process APIs (`GetProcessForPID`, `GetProcessInformation`).
- Public APIs used too: AXUIElement, CGWindowListCopyWindowInfo, NSWorkspace, `CGPreflightScreenCaptureAccess`, ScreenCaptureKit (`SCShareableContent` only for permission detection as far as I saw).
- Private APIs are essential for: windows on other Spaces, focusing a specific window across Spaces, hardware thumbnails, and disabling native Cmd+Tab. None of that has a public equivalent.

## 5. Network use

- Sparkle auto-update: Info.plist sets `SUEnableAutomaticChecks` = true, `SUScheduledCheckInterval` = 604800 (weekly), `SUPublicEDKey`, and the appcast URL is `https://<domain>/appcast.xml` (`src/api/Endpoints.swift`). The `disable-library-validation` entitlement is there for Sparkle.
- Crash reporting: Info.plist contains AppCenter keys (`AppCenterSecret`; a crash reporter). Microsoft AppCenter was retired in 2025, so this may be dead or replaced in code (UNCERTAIN). The "no telemetry" claim should be treated as unverified.
- Pro licensing and feedback: `licenseApiBaseUrl` (`/v1/license`), `feedbackUrl` (`/v1/feedback`), checkout/account URLs, `RemoteLicenseClient`, `MachineFingerprint`, Keychain. All of this must be dropped.
- To fit holzBar: take none of it. No Sparkle, no AppCenter, no licence/feedback, no URL opening for upgrades. Updates come via holzBar's own channel.

## 6. macOS 26 and 27 behaviour and known problems

- 11.7.0 notes: "Fixes Mission Control compatibility on macOS 27"; 11.8.0: "fixes switcher visibility issues on macOS 27". So AltTab is actively tracking macOS 27 betas and had real breakage there (https://github.com/lwouis/alt-tab-macos/releases).
- Open issue #5490: previews broken (empty/misaligned) with Stage Manager enabled on macOS 26.3.1, AltTab 10.9.0, unowned (https://github.com/lwouis/alt-tab-macos/issues/5490). Whether still open in 11.9.0: UNCERTAIN.
- 11.9.0 fixes: permission changes missed until restart (#5739), fullscreen-window and tab-group glitches, phantom windows, invisible windows, empty thumbnails on new windows. Window tracking via AX plus private APIs is a perpetual source of edge cases (phantom windows, fullscreen duplicates, native tabs).
- macOS 26.1 changed how plain executables appear in the Screen Recording list (https://developer.apple.com/forums/thread/807898); irrelevant to a bundled app such as holzBar, but note that holzBar would inherit holzBar's TCC identity.
- The code comment shows CGPreflightScreenCaptureAccess stays "denied" after a mid-session grant, so the permission state has to be detected by other means (titles visible or SCShareableContent).

## 7. What a minimal holzBar module could take

Feasible with public APIs only (Accessibility + optional Screen Recording):
- Window list of the current Space via `CGWindowListCopyWindowInfo` (titles only with Screen Recording) plus AXUIElement for raising/focusing, minimize, close, fullscreen. Without `_AXUIElementGetWindow` mapping AX windows to CGWindowIDs needs heuristics (title/frame matching; AltTab's own `BruteForceWindowMatch` shows the pain), or a simple AX-only list per app.
- Own hotkey: public API only. Options: `CGEventTap` (needs Input Monitoring or Accessibility) or Carbon `RegisterEventHotKey` (no permission, but cannot see modifier release, so a hold-to-select switcher is not possible; use toggle-style).
- Previews: ScreenCaptureKit `SCScreenshotManager`/`SCContentFilter` per window (public, needs Screen Recording, only on demand). Without permission fall back to app icon + title tiles, matching AltTab's skip mode.
- Appearance: one theme set (system material, light/dark), grid or list, icon size. Per-app exceptions: simple bundle-ID ignore list. Multi-display filter: "current screen only" via NSScreen frame intersection. Spaces: only windows on the current Space (public `CGWindowListOption.optionOnScreenOnly`) is the honest scope.

Do not take:
- Anything from SkyLight/CGS/`_SLPS*`/`_AX*` private symbols, `CGSSetSymbolicHotKeyEnabled` (disabling native Cmd+Tab), the other-Space window brute force, `CGSHWCaptureWindowList`. These are exactly the fragile parts (macOS 27 breakages, no sandbox, no App Store).
- Sparkle, AppCenter, Pro licence/trial/feedback code, any URL access, the `disable-library-validation` entitlement.
- Copying GPL-3.0 source verbatim is licence-compatible with holzBar (GPL-3.0) if attribution and notices are kept, but the useful parts are the private-API parts, so reimplementation is cleaner. Use AltTab only as a behavioural reference.

Consequence for the product promise: a public-API-only version cannot show windows from other Spaces or reliably focus a specific window across Spaces. State this clearly in the module's UI and docs.

## 8. Risks / open questions
- Whether a hold-modifier switcher is possible without an event tap (needs Accessibility/Input Monitoring; it adds permissions to holzBar's baseline). Make the module's permission requests lazy and per module.
- Stage Manager and native tab windows are sources of confusing behaviour even in AltTab.
- Verify on macOS 27 hardware; the user cannot test older versions per project scope.
- Not checked: the full README permissions/privacy text (fetch returned only a summary), the exact Pro-gated appearance options, the exact fallback UI without Screen Recording.

## Sources
- https://github.com/lwouis/alt-tab-macos
- https://github.com/lwouis/alt-tab-macos/releases
- https://api.github.com/repos/lwouis/alt-tab-macos (licence, push date)
- https://alt-tab.app/features
- https://raw.githubusercontent.com/lwouis/alt-tab-macos/master/ : Info.plist, alt_tab_macos.entitlements, src/api/Endpoints.swift, src/macos/SystemPermissions.swift, src/macos/api-wrappers/*.swift, changelog.md, LICENCE.md
- https://github.com/lwouis/alt-tab-macos/issues/5490
- https://developer.apple.com/forums/thread/807898
