---
last_mapped_commit: 213805b84bc1e41e6026202b2b4e829dbaca7b03
last_mapped_at: 2026-10-02
---
# Codebase Concerns

**Analysis Date:** 2026-10-02

Scope: the whole repository except `.claude/` (tooling). Deployment target is macOS 14.0 (`Ice.xcodeproj/project.pbxproj`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `Package.swift` `.macOS(.v14)`); the app supports up to macOS 27. "Available on macOS 14" below means the replacement can be adopted without raising the deployment target.

---

## Outdated Items

This section lists everything outdated: APIs, idioms, build settings, scripts, docs, CI and dependencies. Each entry gives the location, the replacement, and whether the replacement works on macOS 14.

### A. Deprecated or legacy Apple APIs

| API in use | Location | Status | Replacement | Works on macOS 14? |
|---|---|---|---|---|
| `CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:)` (`CGWindowListCreateImageFromArray`) | `Ice/Utilities/ScreenCapture.swift:76-82`, used by `Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift` (pre-27 backend) | Deprecated since macOS 14.0; Apple says to use ScreenCaptureKit. Could become unavailable in a future SDK, which would stop the build | `SCScreenshotManager.captureImage(contentFilter:configuration:)`, which the macOS 27 backend already uses (`Ice/MenuBar/MacOS27/ItemImageStore27.swift:273-284`). The comment says ScreenCaptureKit cannot capture off-screen menu bar item windows. Keep the CGWindowList path as a guarded fallback and move on-screen captures to SCK | Yes (SCScreenshotManager is 14.0+) |
| `CGWindowListCopyWindowInfo` (window enumeration) | `Ice/Events/HIDEventManager.swift:506,528`, `Ice/MenuBar/MacOS27/ItemClicker27.swift:82`, `Shared/Utilities/WindowInfo.swift:91` (`CGWindowListCreateDescriptionFromArray`), `Scripts/check-panels.swift:17`, `Scripts/macos27/new-windows.swift:7`, `Scripts/macos27/clock-restore.swift:33` | Not deprecated, but it is the legacy window list API and is called on every click in the macOS 27 click bridge | `SCShareableContent` for on-screen windows where a snapshot is enough; otherwise keep it and cache the result per event | Yes |
| `GetProcessForPID` + `ProcessSerialNumber` (Carbon Process Manager, deprecated since 10.9) | `Shared/Bridging/Shims.swift:159-165`, `Shared/Bridging/Bridging.swift:137-145` (feeds private `CGSEventIsAppUnresponsive`) | Deprecated for more than ten years and bound via `@_silgen_name`, so the compiler cannot warn when it disappears | No public equivalent for "app is unresponsive". Options: treat AX messaging timeouts (`AXUIElementSetMessagingTimeout` + `kAXErrorCannotComplete`) as unresponsive, or keep it behind a `dlsym` check that degrades to `false` | Yes (AX approach) |
| Carbon hotkeys: `RegisterEventHotKey`, `InstallEventHandler`, `GetEventKind`, `import Carbon.HIToolbox` | `Ice/Hotkeys/HotkeyRegistry.swift:6,154,227`, `Ice/Hotkeys/KeyCode.swift:6`, `Ice/Hotkeys/KeyCombination.swift:6`, `Ice/Hotkeys/Modifiers.swift:6` | Legacy, but still the only public API for global hotkeys without the Input Monitoring permission. Since macOS 15, `RegisterEventHotKey` rejects combinations whose only modifiers are Option or Option+Shift; holzIce only logs the failure (`HotkeyRegistry.swift:163-165,237-241`) and the recorder accepts such combinations | Keep Carbon. Add validation in `Ice/UI/Views/HotkeyRecorder.swift` / `Ice/Hotkeys/KeyCombination.swift` that refuses Option-only combinations on macOS 15+ and shows the error in the UI. `KeyCode`/`Modifiers` only need the `kVK_*` constants, which can stay | n/a |
| `NSAppleEventManager.setEventHandler(_:andSelector:forEventClass:andEventID:)` for `holzice://` URLs, plus `MainActor.assumeIsolated` in the handler | `Ice/Main/URLCommands.swift:25-32,85-99` | Legacy Apple Event route; needs an `@objc` selector target and an isolation assumption | `NSApplicationDelegate.application(_:open:)` in `Ice/Main/AppDelegate.swift` (it is `@MainActor` already), or SwiftUI `.onOpenURL` / `.handlesExternalEvents` | Yes (10.13+) |
| `UserDefaults.standard.synchronize()` | `Ice/Utilities/SettingsBackup.swift:106` | Documented as unnecessary and slated for deprecation | Delete it; defaults are flushed when the process exits. If the relaunch race matters, use `CFPreferencesAppSynchronize` | Yes |
| `URL.appendingPathComponent(_:)` / `appendingPathComponent(_:isDirectory:)` | `Ice/Utilities/Constants.swift:30,33`; `Ice/MenuBar/MacOS27/ItemImageStore27.swift:46,66,72,109,413,425,426` | Soft-deprecated since macOS 13 | `appending(path:directoryHint:)` (already used in `Ice/Utilities/SettingsSync.swift:31,38`) | Yes (13+) |
| `URL.path` | `Ice/Utilities/SettingsSync.swift:33`, `Ice/Utilities/SettingsBackup.swift:67,97` | Soft-deprecated since macOS 13 | `path(percentEncoded: false)` | Yes |
| `Host.current().localizedName` | `Ice/Utilities/SettingsSync.swift:98,121` | `Host` is a legacy Foundation class; `current()` can block for seconds on name resolution and runs on the main thread here | `SCDynamicStoreCopyComputerName(nil, nil)` or `ProcessInfo.processInfo.hostName`; better, a per-device UUID stored in local defaults | Yes |
| `defaults -currentHost write/delete -globalDomain` through `/usr/bin/env` | `Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:51-73` | Spawns a shell tool and resolves `defaults` through `PATH` | `CFPreferencesSetValue(key, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)` + `CFPreferencesSynchronize` | Yes |
| Relaunch with `/bin/sh -c "sleep 1; /usr/bin/open \"$0\""` | `Ice/Utilities/SettingsBackup.swift:105-112` | Shell- and timing-based | `NSWorkspace.shared.openApplication(at:configuration:)` with `createsNewApplicationInstance = true`, then `NSApp.terminate(nil)` | Yes |
| `tccutil reset` through `Process` | `Ice/Permissions/Permission.swift:110-127`, `Scripts/install.sh` | Works, but uses an undocumented-for-apps CLI | No public API; keep it and document it as best effort | n/a |
| Screen recording request hack: `SCShareableContent.getWithCompletionHandler { _, _ in }` instead of `CGRequestScreenCaptureAccess()` on macOS 15+ | `Ice/Utilities/ScreenCapture.swift:49-60` (`TODO: Find out if we still need this as of macOS 26`) | Workaround for a macOS 15 bug; unverified on 26 and 27 | Test `CGRequestScreenCaptureAccess()` on 26/27 and drop the hack if it works. Permission detection by reading window titles (`ScreenCapture.swift:16-29`) also needs re-checking on 27, where items are no longer windows | n/a |
| Old System Settings deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` | `Ice/Permissions/Permission.swift:192` | Pre-Ventura pane identifier; still redirects, but it is the legacy form | `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture` | Yes (13+) |
| `EnvironmentValues().openWindow(id:)` / `EnvironmentValues().dismissWindow(id:)` on a freshly built environment | `Ice/Main/AppState.swift:270-285` | Unsupported use; works only because SwiftUI's actions happen to be global | Capture the real `OpenWindowAction` from a view (`@Environment(\.openWindow)`, as `Ice/UI/IceUI/IceWindow.swift:12` does) and store it on `AppState`, or use `NSApp.sendAction` to the window | Yes |
| `NSSplitViewItem.canCollapse` swizzling | `Ice/Utilities/Swizzling.swift`, installed in `Ice/Main/AppDelegate.swift:25` | Runtime method exchange on an AppKit class | On macOS 15+: `NavigationSplitView` + `.toolbar(removing: .sidebarToggle)` and `.navigationSplitViewColumnWidth`; keep the swizzle only for macOS 14 | Partly (15+) |
| Toolbar KVO hack instead of `.windowToolbarLabelStyle(fixed: .iconOnly)` | `Ice/Settings/SettingsWindow.swift:48-70` (`TODO: Switch to the SwiftUI equivalent once we're targeting macOS 15`) | Waits for macOS 15 as the minimum | Keep until the deployment target is 15; then delete `SettingsWindowModel` | No (15+) |
| Status item constraint removal + `statusItem.length = 10_000` to hide items | `Ice/MenuBar/ControlItem/ControlItem.swift:76-94` (`FIXME: Find a replacement for this.`), `:452,460` | Relies on the private layout of `NSStatusBarButton`'s window | No public replacement; on macOS 27 the backend uses assessment-mode assertions instead (`Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift`) | n/a |
| Private CoreGraphics Services via `@_silgen_name` (`CGSMainConnectionID`, `CGSGetWindowList`, `CGSGetProcessMenuBarWindowList`, `CGSCopySpacesForWindows`, `CGSSetConnectionProperty("SetsCursorInBackground")`, …) | `Shared/Bridging/Shims.swift:37-157`, `Shared/Bridging/Bridging.swift`, `Ice/Main/AppDelegate.swift:38` | Private SPI; a missing symbol crashes at launch (no weak linking with `@_silgen_name`) | Resolve through `dlsym` with a fallback, so that a removed symbol disables a feature instead of crashing | n/a |
| Private `MenuBarClientCore.framework` (`MBAssessmentModeConfiguration`, `MBAssessmentModeAssertion`) via `dlopen` + `NSSelectorFromString` + `perform(_:with:with:)` | `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:57-120` | Private SPI; `alloc()` + `perform(init…)` + `takeUnretainedValue()` gets ownership wrong (the `init` result is +1 and is never released) | Keep (no public API), but wrap the calls in a small Objective-C shim or use `unsafeBitCast` to typed IMPs so ARC handles ownership | n/a |

**Modern SwiftUI/AppKit idioms already in place (not outdated):** no `onChange(of:perform:)` (all use the two-parameter or `initial:` form), no `foregroundColor`, no `NavigationView`, no `cornerRadius`, no `activate(ignoringOtherApps:)` (uses `NSApp.activate()` and `NSRunningApplication.activate(from:)`, `Ice/Main/AppState.swift:287-299`), no `NSUserNotification`, no `SMLoginItemSetEnabled` (login item through LaunchAtLogin-Modern, i.e. `SMAppService`), no `allowedFileTypes` (uses `allowedContentTypes`), no `kUTType*`, no `CGWindowListCreateImage` (single-window form), no `NSKeyedArchiver` legacy calls.

### B. Availability checks and dead code below the deployment target

- No `#available` check is lower than macOS 15, so no branch is dead at the macOS 14 target. Every check is `macOS 15.0`, `15.3.2`, `26.0` or `27.0` (75 `#available`, 5 `#unavailable`, 32 `@available`).
- The **macOS 14 branches are live code that is never built or tested on macOS 14**: CI runs on `macos-26` only (`.github/workflows/build.yml:18`). The legacy branches are `Ice/UI/IceUI/IceWindow.swift:51-75` (`windowSceneLegacy`, which closes the window with `.once` at launch), `Ice/UI/Views/SectionedList.swift:53-61`, `Ice/Settings/SettingsWindow.swift:48`, `Ice/Utilities/ScreenCapture.swift:51-59`.
- `MenuBarItemTag.nonHideableItems` guesses the macOS version for MusicRecognition (`Ice/MenuBar/MenuBarItems/MenuBarItemTag.swift:117-131`, `#unavailable(macOS 15.3.2)`, "could be earlier").
- `MenuBarItemTag.immovableItems` keeps the Siri item for macOS < 26 (`MenuBarItemTag.swift:111`). This is correct while macOS 14/15 are supported.
- Three backends live side by side: macOS 14-25 (window-based), macOS 26 (XPC `MenuBarItemService`, `@available(macOS 26.0, *)` in `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:12,121`, `MenuBarItemService/Listener.swift:48`) and macOS 27 (`Ice/MenuBar/MacOS27/`). Raising the deployment target would remove a lot of branching in `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` (2047 lines; `#available` at `:80,377,415,420,436`).

### C. Concurrency idioms that block Swift 6 language mode

- **Language mode:** the app target compiles in Swift 5 (`SWIFT_VERSION = 5.0`, `Ice.xcodeproj/project.pbxproj:458,494`) with no `SWIFT_STRICT_CONCURRENCY`. The XPC service target has `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`:518,544`) and the app target does not, so the targets are inconsistent. `Package.swift` uses tools 6.0 but forces `.swiftLanguageMode(.v5)` on both targets.
- **Global or static mutable state** (an error in Swift 6):
  - `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift:735-737`: `static var cache` inside a **`nonisolated`** function (`getEventSource`). This is a real data race today, not only a Swift 6 diagnostic.
  - `Ice/MenuBar/MenuBarItems/MenuBarItem.swift:340`: `private static var uuidCache` on `MenuBarItemTag.Namespace`, not actor-isolated.
  - `Ice/Utilities/ScreenCapture.swift:38-40`: `static var cachedResult`, not isolated, read from the 1-second permission timer.
  - `Ice/Hotkeys/HotkeyRegistry.swift:125-127`: `static var currentID` (inside a `@MainActor` method; needs `@MainActor` on the enum).
  - `Ice/MenuBar/ControlItem/OwnStatusItemWindows.swift:19-20`: lock-protected `static var windowIDs` (needs `nonisolated(unsafe)` or `OSAllocatedUnfairLock<[ObjectIdentifier: CGWindowID]>`).
- **`@unchecked Sendable` (8):** `Ice/Events/EventMonitor.swift:11,48,85,154`, `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:45`, `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:126`, `Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:38`. Each one needs a review or a move to `OSAllocatedUnfairLock`/`Mutex`. `Mutex` (Synchronization) needs macOS 15, so for the macOS 14 target use `OSAllocatedUnfairLock`, which is already used in `EventMonitor.swift:191`, `SourcePIDCache.swift:164` and `MenuBarItemServiceConnection.swift:36,175`.
- **Mixed locking primitives:** `NSLock` in `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:46`, `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift:44`, `Ice/MenuBar/ControlItem/OwnStatusItemWindows.swift:19`; `OSAllocatedUnfairLock` elsewhere. Standardise on `OSAllocatedUnfairLock` (macOS 13+).
- **`MainActor.assumeIsolated` in callbacks (6):** `Ice/Main/URLCommands.swift:94`, `Ice/MenuBar/MacOS27/ItemImageStore27.swift:84`, `Ice/MenuBar/MacOS27/Concealer27.swift:59,69,83,94`. These crash if a callback ever arrives off the main thread. Prefer `Task { @MainActor in … }` or the async `NotificationCenter.notifications(named:)` sequence.
- **`ObservableObject` + `@Published` + Combine everywhere:** 25 `ObservableObject` classes, 78 `@Published`, 31 `@ObservedObject`, 17 `@EnvironmentObject`, 3 `@StateObject`, 56 `AnyCancellable`, 109 `sink`. `@Observable` (Observation framework) **is available on macOS 14** and fits Swift 6 better. Migrate model by model, starting with leaf models (`Ice/Settings/Models/*.swift`, `Ice/MenuBar/Profiles/LayoutProfiles.swift`, `Ice/MenuBar/Spacers/MenuBarSpacers.swift`). `Ice/Main/AppState.swift` is the root and should go last. Two `ObservableObject`s are not `@MainActor`: `Ice/Permissions/Permission.swift:14` and `Ice/UI/Views/HotkeyRecorder.swift:122`.
- **GCD idioms:** 102 `DispatchQueue` uses, mostly `.receive(on: DispatchQueue.main)` in Combine pipelines (`Ice/Settings/Models/GeneralSettings.swift` x14, `Ice/MenuBar/ControlItem/ControlItem.swift` x12, `Ice/Settings/Models/AdvancedSettings.swift` x9) and `DispatchQueue.main.async`/`asyncAfter` as "SwiftUI conflict" workarounds (`Ice/Main/AppState.swift:272,281`, `Ice/Main/AppDelegate.swift:97`).
- **Non-Sendable captures in detached tasks:** `Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:57-60` captures a `Process` in `Task.detached`.
- **Unstructured tasks without cancellation:** 70 `Task {}` / `Task.detached`. See "Performance": `HIDEventManager.handleShowOnHover` creates a new task on every mouse move.

### D. Dead code and unused files

- `Ice/Events/RunLoopLocalEventMonitor.swift`: `RunLoopLocalEventMonitor` and its publisher are never referenced outside the file. Delete it.
- `Ice/Utilities/ObjectStorage.swift`: `ObjectStorage` is never referenced outside the file. Delete it.
- `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift:170-174`: `managedItems(for:)` is marked `TODO: This is redundant now, so remove it.` and has 7 call sites to switch to the subscript.
- Copy to Applications build phase stub: `Ice.xcodeproj/project.pbxproj:256-271`, a script phase that only echoes "Copy to Applications is disabled". Remove the phase.
- Unreferenced repository assets: `Resources/rearranging.mov` (12.7 MB) and `Resources/rearranging.gif` (3.0 MB) come from the original Ice README and are referenced nowhere; `Resources/Icon.png` is also unreferenced. Delete them, or move them out of the repository.
- **Migration chain for Ice versions** (`Ice/Utilities/Migration.swift`, 532 lines, `FIXME: Migration has gotten extremely messy…`, `TODO: Decide what needs to stay…`): `migrate0_8_0`, `migrate0_10_0`, `migrate0_10_1`, `migrate0_11_10`, `migrate0_11_13`, `migrate0_11_13_1` migrate Ice's own pre-0.11.13 formats. holzIce starts with an empty `com.holzcloud.holzIce` domain and imports Ice settings that Ice has already migrated, so these only matter for users coming from very old Ice builds. The same applies to the legacy keys in `Ice/Utilities/Defaults.swift:197-215` (`Deprecated (Appearance Settings)`, `Deprecated (Advanced Settings)`, `Deprecated (Other)`) and to `Ice/MenuBar/Appearance/Configurations/MenuBarAppearanceConfigurationV1.swift`. Collapse them into one "import from Ice" step that runs the old migrations on the imported dictionary, or drop the versions older than 0.11.10.

### E. Leftovers from Sparkle and the original Ice

- **Acknowledgements still list Sparkle:** `Ice/Resources/Acknowledgements.rtf` (Sparkle mentioned 3 times) and the shipped `Ice/Resources/Acknowledgements.pdf` (TextEdit export, 2025-09-03). Shown from `Ice/Settings/SettingsPanes/AboutSettingsPane.swift:14,127`. Regenerate both without Sparkle, and add Barometer and Thaw (see NOTICE below).
- **Version and build number from Ice:** `MARKETING_VERSION = "0.11.13-dev.2a"` and `CURRENT_PROJECT_VERSION = 1121` (`Ice.xcodeproj/project.pbxproj:435,453,471,489`). Release builds override both (`.github/workflows/release.yml:47-48`), but `Scripts/install.sh` does not, so a source build shows "0.11.13-dev.2a" in the About pane. Set them to the current holzIce version (`0.0.5`).
- **Development teams from Ice:** `DEVELOPMENT_TEAM = WMBUU9S842` (app and service targets, `project.pbxproj:438,474,504,531`) and `K2ATHQPJDP` (project level, `:337,403`) belong to the original project. With `CODE_SIGN_STYLE = Automatic`, `Scripts/install.sh` (which does not pass `DEVELOPMENT_TEAM=`/`CODE_SIGN_IDENTITY=-`, unlike the CI workflows) fails for anyone outside those teams. Clear the team in the project, or pass the same overrides in `install.sh`.
- `ENABLE_USER_SELECTED_FILES = readonly` (`project.pbxproj`, app target) is a sandbox entitlement setting in a target with `ENABLE_APP_SANDBOX = NO`. It does nothing; remove it.
- `SettingsBackup.excludedKeyPrefixes` includes `"SU"` (Sparkle keys) (`Ice/Utilities/SettingsBackup.swift:23-28`). Keep it, because it stops Ice's Sparkle keys from being imported; add a comment explaining why.
- `FREQUENT_ISSUES.md` is the original Ice page. It talks about "Ice", says Ice "cannot" move items or remember their order and links Ice issues #6/#26, all of which holzIce now does. Rewrite it for holzIce or delete it.
- Hotkey signature `OSType(1231250720) // OSType for Ice` (`Ice/Hotkeys/HotkeyRegistry.swift:56`) is the same as the original Ice's, so if both apps run, their hotkey IDs collide in the Carbon event namespace. Use a holzIce-specific code such as `'hIce'`.
- Logger subsystem is hard-coded in one place: `Logger(subsystem: "com.holzcloud.holzIce", …)` (`Ice/Events/HIDEventManager.swift:374`), while everything else uses `Logger(category:)` (`Shared/Utilities/Logging.swift`). Use `Logger(category: "ClickBridge27")`.
- Internal `Ice.ControlItem.*` autosave names (`Ice/MenuBar/ControlItem/ControlItem.swift:17-21`) and `IceBar`/`IceSection` type names stay, as `CLAUDE.md` requires. Not a concern.
- The `jordanbaird/Ice#N` references in comments are intentional issue references. Not a concern.
- `NOTICE` does not credit **Barometer** (mackid1993) and **Thaw** (thaw-app), although `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:5-8` is adapted from them under GPLv3. Add them to `NOTICE` and the README credits.

### F. Outdated scripts, docs and CI

- `.github/workflows/lint.yml`:
  - `actions/checkout@v3` is outdated (other workflows use v4; v5 is current).
  - `norio-nomura/action-swiftlint@3.2.1` is unmaintained, from 2021, and runs an old SwiftLint in a Linux container. It may not parse modern Swift (`if` expressions such as `let r: CGFloat = if #available…` in `Ice/UI/Views/HotkeyRecorder.swift:211`, `#unavailable`). Replace it with `ghcr.io/realm/swiftlint:latest` in a container job, or with `brew install swiftlint` on a macOS runner.
  - `if: '!github.event.pull_request.merged'` is a no-op on `pull_request` events and skips nothing useful.
- `.swiftlint.yml` lints only `Ice/` (`included: [Ice]`). `Shared/`, `MenuBarItemService/`, `Tests/` and `Scripts/` are never linted. The `file_header` rule requires `//  Ice`, but `Shared/` files say `//  Shared`, which is why `Shared/` cannot simply be added.
- `.github/workflows/build.yml` never runs `swift test`, so the only unit tests (`Tests/IceMacOS27CoreTests`, about 114 tests) are not run in CI. Add a `swift test` step. There is no SwiftPM or DerivedData cache.
- `.github/workflows/release.yml`:
  - The `workflow_dispatch` example `"e.g. 0.11.13-holz.1"` (`:7`) is an obsolete version scheme. Use `0.0.6-beta1`.
  - The comment "every tag with a suffix such as -beta.1" (`:69`) does not match the `-betaN` scheme in `CLAUDE.md` (`0.0.6-beta1`). The regex still works.
  - The release-notes check runs twice (`:28-29` and `:74-77`).
  - The cask is updated with a direct `git push origin main` from the bot. This fails if `main` gets branch protection, and the push does not trigger other workflows.
  - The `codesign --verify` step validates an ad hoc signature only. There is no notarization (see Security).
- `README.md:78` says "Requires Xcode 27 on macOS 14 or later", but Xcode 26/27 do not run on macOS 14. State the real host requirement (the macOS version Xcode 27 needs). CI selects "the newest Xcode" on `macos-26` and does not pin Xcode 27.
- `README.md:73` lists "Ice, Bartender or Hidden Bar", but `Ice/Main/ConflictingApps.swift:28` also quits Thaw (as the v0.0.5 notes say). `README.md:174` says "280 open bug reports" and `docs/upstream-bugs.md:3` says 282.
- `Integrations/Raycast/holzice-profile.sh` URL-encodes with `python3`, which is not installed on a clean macOS (it needs the Command Line Tools). Use `osascript -l JavaScript -e 'encodeURIComponent(...)'` or pure Bash.
- `Scripts/macos27/*.sh` and `*.swift` are probes for one particular setup: they hard-code coordinates (`EMPTY_X=900`, `REGION=700,0,1220,34` in `verify-conceal.sh`), assume an external display at the origin, refer to "plan 1" and to the "Thaw not running" setup, write to `/tmp`, and use `try!` (`new-windows.swift:12`). Mark them as development probes in a README, or move them under `docs/`. `Tests/IceMacOS27CoreTests/Plan2Core27Tests.swift` is also named after a development plan.
- `.github/ISSUE_TEMPLATE/bug_report.yml` has placeholders `1.2.3` / `15.3.2`, which predate holzIce's `0.0.x` versioning and macOS 27. It also has no field for "installed via Homebrew / built from source".

### G. Dependencies

| Package | Pinned | Concern | Action |
|---|---|---|---|
| AXSwift (`tmandry/AXSwift`) | 0.3.2 (`Package.resolved`) | Old and rarely maintained; not Swift 6 ready. Used only in `Shared/Services/SourcePIDCache.swift` and `Shared/Utilities/AXHelpers.swift`, while the macOS 27 backend calls the AX C API directly (`Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift`) | Replace it with the direct AX calls already used in `MenuBarItemProvider27.swift`, and drop the dependency from both targets |
| LaunchAtLogin-Modern | 1.1.0 | Thin wrapper over `SMAppService.mainApp` (macOS 13+) | Optional: call `SMAppService` directly in `Ice/Settings/SettingsPanes/GeneralSettingsPane.swift` and drop the package |
| Semaphore (`groue/Semaphore`) | 0.1.0 | Pre-1.0; one use (`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift:21`) | Fine; review for Swift 6 when the language mode changes |
| Ifrit | 2.0.6 (min 2.0.3) | Small fuzzy-search package; uses the `IfritStatic` product | Check for updates |
| CompactSlider | 2.1.0 | One use (`Ice/UI/IceUI/IceSlider.swift`) | Check for updates; SwiftUI `Slider` could replace it |

---

## Tech Debt

**God objects:**
- Issue: `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` (2047 lines) mixes item caching, the event-based move engine, timeouts and three OS-version backends. `Ice/Events/HIDEventManager.swift` (924 lines) mixes event taps, hover, scroll, smart rehide and the macOS 27 click bridge.
- Files: `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`, `Ice/Events/HIDEventManager.swift`, `Ice/MenuBar/Appearance/MenuBarOverlayPanel.swift` (781), `Ice/MenuBar/ControlItem/ControlItem.swift` (734), `Ice/Utilities/Extensions.swift` (694)
- Impact: Hard to change one backend without touching another; SwiftLint's `file_length`/`type_body_length`/`function_body_length`/`cyclomatic_complexity` are disabled (`.swiftlint.yml`) to tolerate this.
- Fix approach: Extract per-backend strategies (pre-26, 26, 27) behind a protocol, as `Ice/MenuBar/MacOS27/` already does for 27.

**Timing by sleep:**
- Issue: Behaviour is tuned with fixed `Task.sleep` delays measured on one machine: 300/600/400/250 ms clicks (`Ice/MenuBar/MacOS27/ItemClicker27.swift:37,43,64,67`), 120 ms click restore (`Ice/Events/HIDEventManager.swift:494-502`), a 100 ms "delay makes this more reliable" (`Ice/Main/AppDelegate.swift:95-100`), a 25 ms layout sleep (`Ice/MenuBar/Groups/MenuBarItemGroups.swift:229`, `Ice/MenuBar/LayoutBar/LayoutBarPaddingView.swift:121`) and a 1 s force-terminate (`Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:44`).
- Impact: Flaky on slower or loaded Macs; behaviour differs between machines.
- Fix approach: Wait for observable conditions (AX notifications, window-list changes, `NSRunningApplication.isTerminated` KVO) with timeouts, and keep the sleeps only as upper bounds.

**Polling timers:**
- Issue: Permissions are polled every 1 s (`Ice/Permissions/Permission.swift:77`, which enumerates menu bar windows each time through `ScreenCapture.checkPermissions`), iCloud settings every 300 s (`Ice/Utilities/SettingsSync.swift:67`), the overlay every 5 s and 10 s (`Ice/MenuBar/Appearance/MenuBarOverlayPanel.swift:196,203`) and reveal rules every 60 s (`Ice/MenuBar/RevealRules/RevealRules.swift:47`).
- Fix approach: Make sure `stopCheck()` runs once permissions are granted. Use `NSMetadataQuery`/`NSFilePresenter` for the iCloud file and `IOPSNotificationCreateRunLoopSource` / `NWPathMonitor` for the reveal rules (power and network).

**Outstanding TODO/FIXME/HACK markers:**
- `Ice/Utilities/Migration.swift:9-10` (FIXME/TODO, rewrite migrations)
- `Ice/MenuBar/ControlItem/ControlItem.swift:84` (FIXME, constraint hack)
- `Ice/Utilities/Extensions.swift:570` (FIXME, AX returns the main screen's menu bar only; notch workaround)
- `Ice/Settings/SettingsWindow.swift:49` (TODO, macOS 15 toolbar API)
- `Ice/Utilities/ScreenCapture.swift:55` (TODO, macOS 26 permission request)
- `Ice/MenuBar/MenuBarItems/MenuBarItemTag.swift:117` (TODO, MusicRecognition version)
- `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift:170` (TODO, redundant method)
- `Ice/MenuBar/MenuBarItems/MenuBarItem.swift:80` (TODO, generate once during init)
- `Ice/MenuBar/MenuBarSection.swift:158` (TODO, use `isEnabled`)
- `Ice/MenuBar/Appearance/MenuBarOverlayPanel.swift:770` (HACK, inset path for inside stroke)

## Known Bugs

**Spacing change skips apps at random (`break` instead of `continue`):**
- Symptoms: After "Menu bar item spacing" is applied, some apps are not relaunched and keep the old spacing. Which apps are skipped changes from run to run.
- Files: `Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:166-174`
- Trigger: The loop iterates a `Set<pid_t>`; when the first PID visited is Control Center or holzIce itself, `guard … else { break }` leaves the whole loop, so no app is relaunched.
- Workaround: Apply the spacing again. Fix: replace `break` with `continue`.

**Spacing relaunch force-terminates apps after 1 second:**
- Symptoms: Apps with menu bar items that take longer than 1 s to quit (unsaved documents, sync clients) are killed with `forceTerminate()`.
- Files: `Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:44,75-110`
- Trigger: Applying a spacing offset.
- Workaround: None. Fix: lengthen the timeout, skip apps that refuse to quit and list them, and resume the continuation when `self` is gone (it currently never resumes in that case, `:100-106`).

**Spacing relaunch on macOS 27 probably does nothing:**
- Symptoms: `MenuBarItem.getMenuBarItems(option: .activeSpace)` is window-based; on macOS 27 items are not windows, so the PID set is likely empty.
- Files: `Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:159-160`
- Fix: Use `MenuBarItemProvider27` to collect the owning PIDs on macOS 27. Verify on a Mac.

**Data race in the event source cache:**
- Symptoms: Possible crash or corrupt dictionary when two item moves or clicks run at the same time.
- Files: `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift:731-745` (`nonisolated func getEventSource`, `static var cache`)
- Fix: Guard the cache with `OSAllocatedUnfairLock`, or create the source per call.

**Comment and code disagree on the system item allowlist:**
- Symptoms: The doc comment says numbers "up to 127" are accepted and that the range matches jordanbaird/Ice#1001, but the code allows `0...63`.
- Files: `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:62-75`
- Fix: Decide on the range, then align the comment and the code.

**Hotkeys silently fail to register:**
- Symptoms: An Option-only or Option+Shift-only hotkey can be recorded, but it never fires on macOS 15+. Registration errors are only logged.
- Files: `Ice/Hotkeys/HotkeyRegistry.swift:154-166,227-243`, `Ice/UI/Views/HotkeyRecorder.swift`
- Fix: Validate the combination in the recorder and show the failure.

**Possible XPC service rejection for ad hoc builds on macOS 26:**
- Symptoms: The open "Loading menu bar items…" / `XPCRichError` code 1 reports (see `docs/upstream-bugs.md`). The listener requires `.isFromSameTeam()` on macOS 26 (`MenuBarItemService/Listener.swift:48-55`), but release builds are signed ad hoc with `DEVELOPMENT_TEAM=` (`.github/workflows/release.yml:49`), so they have no team identifier at all.
- Files: `MenuBarItemService/Listener.swift`, `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:28-36` (the in-app fallback)
- Workaround: The in-app fallback (`usesLocalCache`). Fix: For ad hoc builds, use a code-signing requirement on the bundle identifier, or skip the team requirement when the process has no team ID.

**Permission wait can leak a continuation:**
- Symptoms: If `waitForPermission()` is called twice, the second call replaces `hasPermissionCancellable`, so the first continuation is never resumed and its awaiting task hangs.
- Files: `Ice/Permissions/Permission.swift:130-147`
- Fix: Keep one shared waiter, or use `for await` on `$hasPermission.values`.

**Open upstream groups:**
- Item identity across launches, items moved to the wrong section, Ice Bar empty on macOS 26, auto-rehide while a menu is open, appearance not re-applied after sleep, Dock icon appearing. All are tracked in `docs/upstream-bugs.md` ("Open" table).

## Security Considerations

**Unsigned/ad hoc distribution with quarantine removal:**
- Risk: Releases are ad hoc signed, not notarized, with the hardened runtime off (`.github/workflows/release.yml:41-51`). The cask strips quarantine in `postflight_steps` (`Casks/holzice.rb:24-30`), and every release note tells users to run `xattr -dr com.apple.quarantine`. Gatekeeper gives users no assurance, and every update changes the signature, so TCC grants go stale (`Ice/Permissions/Permission.swift:105-127`, `Scripts/install.sh`).
- Files: `.github/workflows/release.yml`, `Casks/holzice.rb`, `Scripts/install.sh`
- Current mitigation: Builds come from CI on tagged commits; the SHA-256 is pinned in the cask.
- Recommendations: Get a Developer ID, sign with the hardened runtime and notarize, then drop the quarantine removal from the cask and the notes.

**URL scheme reachable from any app or web page:**
- Risk: `holzice://` commands (`Ice/Main/URLCommands.swift`) can be opened by any process or by a link in a browser (after a browser prompt). They toggle sections, apply profiles and open settings. They do no destructive I/O, but `profile/<name>` changes the layout. Full URLs are logged with `privacy: .public` (`:37,42`).
- Recommendations: Leave the commands as they are, but log only the host. A confirmation or opt-in setting for commands sent while holzIce is inactive is optional.

**Settings import and sync apply arbitrary keys:**
- Risk: `SettingsBackup.apply` writes every key in an imported plist or the iCloud file into holzIce's defaults (`Ice/Utilities/SettingsBackup.swift:40-51`, `Ice/Utilities/SettingsSync.swift:131-142`), apart from a few excluded prefixes. A crafted file can set any `NSUserDefaults` key the app reads.
- Recommendations: Import only keys from `Defaults.Key.allCases` plus known dynamic prefixes, and validate their types.

**Item screenshots persisted to disk:**
- Risk: Captured images of other apps' menu bar items (which can show message counts, VPN state, and so on) are written to `~/Library/Application Support/holzIce/ItemImages` (`Ice/MenuBar/MacOS27/ItemImageStore27.swift:45-46,413-426`) and are included in backups.
- Recommendations: Store them in `~/Library/Caches/com.holzcloud.holzIce`, which is excluded from Time Machine and already in the cask's `zap`, or mark the directory with `isExcludedFromBackup`.

**Private API surface:**
- Risk: `@_silgen_name` CGS bindings (`Shared/Bridging/Shims.swift`) and `dlopen` of `MenuBarClientCore` (`MenuBarAssessmentAssertion27.swift:57`) can crash or misbehave on any OS update.
- Recommendations: Bind through `dlsym` with feature flags, as noted in Outdated A.

**PATH lookup for `defaults`:**
- Risk: `/usr/bin/env defaults` (`Ice/MenuBar/Spacing/MenuBarItemSpacingManager.swift:54-55`) resolves through the inherited `PATH`.
- Recommendations: Use `/usr/bin/defaults` directly, or the `CFPreferences` API.

## Performance Bottlenecks

**Task storm on mouse movement (show on hover):**
- Problem: Every `mouseMoved` event outside the menu bar while the hidden section is shown, or inside empty menu bar space while it is hidden, starts a new unstructured `Task` that sleeps for `showOnHoverDelay` and then re-checks. Nothing is cancelled or de-duplicated.
- Files: `Ice/Events/HIDEventManager.swift:99-108,599-660`
- Cause: No stored task handle.
- Improvement path: Keep one `hoverTask`, cancel and replace it on each event, or debounce.

**Per-event hit testing on macOS 27:**
- Problem: `isMouseInsideItemsArea` builds item arrays and asks `MenuBarItemProvider27.systemItemFrames()` / `overflowButtonFrame()` on each mouse move.
- Files: `Ice/Events/HIDEventManager.swift:839-875`
- Improvement path: Cache the frames per layout change, and invalidate them on AX notifications or the scan schedule (`Ice/MenuBar/MacOS27/Core/AccessibilityScanSchedule27.swift`).

**Window list enumeration on clicks:**
- Problem: `CGWindowListCopyWindowInfo([.optionOnScreenOnly], …)` runs on the click path, sometimes twice (`windowNumbers()`, `windowsForPanelCheck()`).
- Files: `Ice/Events/HIDEventManager.swift:505-540`, `Ice/MenuBar/MacOS27/ItemClicker27.swift:82`

**`Host.current()` on the main thread:**
- Problem: It can block for seconds on name resolution, and it is called in every push and every 300 s check.
- Files: `Ice/Utilities/SettingsSync.swift:98,121`

**1-second permission polling:**
- Problem: Each tick enumerates menu bar windows and reads their titles.
- Files: `Ice/Permissions/Permission.swift:76-86`, `Ice/Utilities/ScreenCapture.swift:16-29`

**High CPU, energy and memory reports:**
- Open upstream group (#334, #479, #530, #578, #819), listed in `docs/upstream-bugs.md`. Profile with Instruments after the hover-task fix.

## Fragile Areas

**macOS 27 backend:**
- Files: `Ice/MenuBar/MacOS27/` (Concealer27, ItemClicker27, ItemImageStore27, MenuBarItemProvider27, MenuBarAssessmentAssertion27), `Ice/Events/HIDEventManager.swift:397-600` (click bridge)
- Why fragile: It is built on private `MenuBarClientCore` assertions, synthetic clicks that release and re-take assertions, and constants measured on macOS 27.0 (system item numbers 0, 2, 6, 8; 120 ms click restore; 22-point glyph spacing). Reordering items is not possible (`docs/macos27.md`).
- Safe modification: Keep the pure logic in `Ice/MenuBar/MacOS27/Core/` (covered by `swift test`) and verify on a real Mac with `Scripts/macos27/verify-*.sh`.
- Test coverage: Only the pure Core logic is tested; the AppKit, AX and private-API glue is not.

**Status item hiding via constraints (pre-27):**
- Files: `Ice/MenuBar/ControlItem/ControlItem.swift:76-94,440-465`, `Ice/Utilities/Predicates.swift:40`
- Why fragile: It finds and removes an internal `NSLayoutConstraint` of the status bar button window and asserts that exactly one exists.
- Safe modification: Change it only with the assert active in Debug, and test on macOS 14, 15 and 26.

**Event-based item moving (pre-27):**
- Files: `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` (move engine, `AsyncSemaphore`, event taps, timeouts)
- Why fragile: It posts synthetic Command-drags with timeouts and waits for the user to pause input. Upstream reports timeouts with Live Activities and iPhone items (#656, #704, #729, …).

**Window opening through SwiftUI internals:**
- Files: `Ice/Main/AppState.swift:270-285`, `Ice/UI/IceUI/IceWindow.swift:51-75`, `Ice/Main/AppDelegate.swift:95-100`
- Why fragile: It relies on `EnvironmentValues()` actions working without a view and on `DispatchQueue.main.async` / 100 ms delays, and on macOS 14 it closes the window at launch with `.once`.

**Settings sync:**
- Files: `Ice/Utilities/SettingsSync.swift`
- Why fragile: It writes straight into `~/Library/Mobile Documents/com~apple~CloudDocs/holzIce/Settings.plist` without `NSFileCoordinator`. Evicted (`.icloud` placeholder) files fail silently. The device is identified by its *name*, so two Macs with the same name never sync. "Newer" compares wall-clock dates across machines.
- Safe modification: Use `NSFileCoordinator` + `NSMetadataQuery`, or `NSUbiquitousKeyValueStore` for a small settings blob; identify devices by a UUID stored locally.

**Settings import ordering at launch:**
- Files: `Ice/Main/AppDelegate.swift:14-19` (`importIceSettingsIfNeeded`, `SettingsSync.pullIfNeeded` before `AppState()`), `Ice/Utilities/Migration.swift:64-98`
- Why fragile: Importing Ice's window frames and status item positions once locked up a Mac on macOS 27 (comment at `Migration.swift:84-86`). The excluded prefixes are the only guard.

**Force casts:**
- Files: `Ice/Utilities/Extensions.swift:522` (`NSScreenNumber as! CGDirectDisplayID`), `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift:217,369,388,389` (`as! AXUIElement` / `AXValue`)
- Why fragile: They crash if the system ever returns another type. Use `CFGetTypeID` checks for the AX values.

## Scaling Limits

**Menu bar item cache and image store:**
- Current capacity: One image per item and display in `ItemImageStore27`, kept in memory (`loaded`) and on disk with an `index.json`.
- Limit: No eviction is visible for items whose apps were uninstalled, so the store grows over time.
- Scaling path: Prune entries that `knownApplications27` no longer contains, and cap the store's size.

**Allowlisted system items:**
- Current capacity: `0...63` (`MenuBarAssessmentAssertion27.swift:75`).
- Limit: A system item numbered above 63 in a future macOS 27.x would be concealed.
- Scaling path: Widen the range to the measured 127, or derive it at runtime.

## Dependencies at Risk

**AXSwift 0.3.2:**
- Risk: Rarely maintained; not Swift 6 clean; linked into both the app and the XPC service.
- Impact: Blocks the Swift 6 language mode; a source break in a future Swift would stop the build.
- Migration plan: Use direct `AXUIElement*` calls, as in `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift`.

**`norio-nomura/action-swiftlint@3.2.1`:**
- Risk: Unmaintained GitHub Action with an old SwiftLint.
- Impact: False lint failures or misses on modern syntax; CI blocks PRs.
- Migration plan: Use the official `realm/swiftlint` container image, or Homebrew SwiftLint on a macOS runner.

**Private frameworks (`MenuBarClientCore`, SkyLight/CGS):**
- Risk: Can change in any macOS point release.
- Impact: Concealment on macOS 27 or item enumeration stops working.
- Migration plan: None public; keep runtime checks (`MenuBarAssessmentAssertion27.isAvailable`) and add the same kind of check to the CGS bindings.

## Missing Critical Features

**Item reordering on macOS 27:**
- Problem: Not possible yet (`docs/macos27.md`); `Scripts/macos27/reorder-probe.swift` would decide whether it can be built.
- Blocks: The layout editor can assign sections on macOS 27 but cannot set the order.

**Notarized distribution:**
- Problem: Releases are ad hoc signed and not notarized (see Security).
- Blocks: Stable TCC permissions across updates, and installing without a quarantine workaround.

**Stable item identity across launches:**
- Problem: Open upstream group: items lose their section after a restart or an app update (`docs/upstream-bugs.md`).
- Blocks: Reliable layouts and profiles.

## Test Coverage Gaps

**Everything outside `Ice/MenuBar/MacOS27/Core`:**
- What's not tested: Migration, Ice settings import, settings export/import/sync, URL commands, hotkey parsing and registration (`Ice/Hotkeys/`), layout profiles, groups, spacers, reveal rules, the appearance configuration V1-to-V2 migration.
- Files: `Ice/Utilities/Migration.swift`, `Ice/Utilities/SettingsBackup.swift`, `Ice/Utilities/SettingsSync.swift`, `Ice/Main/URLCommands.swift`, `Ice/Hotkeys/KeyCombination.swift`, `Ice/MenuBar/Profiles/LayoutProfiles.swift`
- Risk: Settings are lost or corrupted on import or sync, and URL commands break unnoticed.
- Priority: High

**Unit tests not run in CI:**
- What's not tested: `swift test` (`Package.swift`, `Tests/IceMacOS27CoreTests/`) never runs in `.github/workflows/build.yml`.
- Risk: Core logic regressions are merged unnoticed.
- Priority: High

**No CI on older macOS:**
- What's not tested: The macOS 14 and 15 code paths (legacy window scene, CGWindowList capture, `CGRequestScreenCaptureAccess` branch); CI only builds on `macos-26`.
- Files: `.github/workflows/build.yml`
- Risk: The README claims "macOS 14 – 26 ✅" without verification.
- Priority: Medium

**No UI or integration tests:**
- What's not tested: Event taps, AX scanning, the concealment glue and the click bridge. They are only checked by hand with `Scripts/macos27/verify-*.sh`.
- Priority: Medium

---

*Concerns audit: 2026-10-02*
