---
phase: 04-outdated-apis
plan: 02
subsystem: app-lifecycle-and-accessibility
status: complete
tags: [url-commands, app-delegate, swiftui-scenes, window-actions, deep-link, accessibility, axswift]
requires:
  - "04-01: complete, PR #37 green on 654c05d"
provides:
  - "URLCommand(url:scheme:) (Core, tested): lower-cased command, percent-decoded arguments with their case"
  - "AppDelegate.application(_:open:) performs holzbar:// URLs"
  - "AppState.setWindowActions(open:dismiss:) with a replay queue for early requests"
  - "Screen Recording deep link through com.apple.settings.PrivacySecurity.extension"
  - "AXHelpers on the AXUIElement C API with type-checked values (app and XPC service)"
affects:
  - "04-03: AXSwift is imported nowhere, so the package and its acknowledgement can go"
  - "HolzBarWindow now takes the app state (init(id:appState:content:))"
tech-stack:
  added: []
  removed: [AXSwift (code use only; package still linked until 04-03)]
  patterns:
    - "CFGetTypeID check, then unsafeDowncast(_:to:) for every Accessibility value (no force cast)"
    - "Scenes hand their environment's window actions to the model once, in .once { }"
key-files:
  created:
    - holzBar/Core/URLCommand.swift
    - Tests/HolzBarCoreTests/URLCommandTests.swift
  modified:
    - holzBar/Main/URLCommands.swift
    - holzBar/Main/AppDelegate.swift
    - holzBar/UI/HolzBarUI/HolzBarWindow.swift
    - holzBar/Main/AppState.swift
    - holzBar/Settings/SettingsWindow.swift
    - holzBar/Permissions/PermissionsWindow.swift
    - holzBar/Permissions/Permission.swift
    - Shared/Utilities/AXHelpers.swift
    - Shared/Services/SourcePIDCache.swift
    - holzBar/MenuBar/MenuBarManager.swift
decisions:
  - "API-05: URL commands come through NSApplicationDelegate.application(_:open:); both scenes use handlesExternalEvents(matching: []) so SwiftUI never opens a window for a URL"
  - "API-05: URLCommand decodes the percent-encoded path once (the old code decoded already-decoded pathComponents a second time)"
  - "API-08: AppState opens and dismisses windows through the actions captured from the scenes; requests before any scene existed are queued and replayed through the same main-queue hop"
  - "API-06: Screen Recording opens x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
  - "API-07: AXHelpers keeps every helper's name and role, typed with AXUIElement; the system-wide element is stored once (nonisolated(unsafe), an immutable CF reference)"
metrics:
  duration: 16min
  completed: 2026-10-02
actuals:
  tokens: 5800
  tasks: 3
  commits: 3
plan_head_before: 8dc66947265ed893711ea0ceaaf250eb9ec2dadd
plan_head_after: 6108602bbb85a99ebe1251d6fe16102d02502dc3
---

# Phase 4 Plan 02: URL commands through the app delegate, captured window actions, current deep link and direct Accessibility Summary

`holzbar://` commands arrive through `application(_:open:)` and are parsed by a tested Core `URLCommand` (API-05), windows open through the `OpenWindowAction`/`DismissWindowAction` the scenes hand to `AppState` (API-08), the Screen Recording button uses the current pane identifier (API-06), and the app and the XPC service call the Accessibility C API directly, so no source file imports AXSwift (API-07, code part). PR #37 is green on 6108602.

## What was done

### Task 1: URL commands through the app delegate, commit ef30ba0

- New `holzBar/Core/URLCommand.swift`: `struct URLCommand: Equatable, Sendable` (`name`, `arguments`), `init?(url:scheme:)` returns nil for another scheme or a missing or empty host; arguments come from `path(percentEncoded: true)` split on "/" and decoded once. Six tests in `@Suite("URLCommand")` (the five planned plus "A command without arguments has none").
- `URLCommands`: `register(appState:)`, the private `Handler: NSObject` with its `@objc` method and `MainActor.assumeIsolated` are gone; `perform(_:appState:)` switches over `command.name`; every command behaves as before; the two public log lines stay for SEC-02 (Phase 5).
- `AppDelegate.application(_:open:)` performs each URL; the registration call is gone from `applicationWillFinishLaunching`.
- `HolzBarWindow`: `.handlesExternalEvents(matching: [])` on the modern and the legacy `Window` scene.

### Task 2: captured window actions, current deep link, commit 8214250

- `AppState`: `openWindowAction`, `dismissWindowAction`, `pendingWindowRequests`; `setWindowActions(open:dismiss:)` stores the actions and replays pending requests in order; `openWindow(_:)` / `dismissWindow(_:)` keep their signatures, the main-queue hop and the debug logs, and queue the request while no action is stored. No `EnvironmentValues()` left.
- `HolzBarWindow` takes `appState` and calls `setWindowActions` in its `.once { }` before the open-and-dismiss trick; `SettingsWindow` and `PermissionsWindow` pass theirs.
- `Permission.swift`: Screen Recording opens `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture`.

### Task 3: Accessibility called directly, commit 6108602

- `Shared/Utilities/AXHelpers.swift`: `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt`; `AXUIElementCopyElementAtPosition` on one stored system-wide element; `AXUIElementCreateApplication` (nil for a terminated app); `kAXExtrasMenuBarAttribute`, `kAXChildrenAttribute` (array checked with `CFArrayGetTypeID`, each child with `AXUIElementGetTypeID`), `kAXEnabledAttribute` (`CFBooleanGetTypeID`), `AXFrame` (`AXValue` of type `.cgRect`), `kAXRoleAttribute` (`CFStringGetTypeID`), `applicationMenuBar(at:)` unchanged in behaviour. Every call runs inside `queue.sync`.
- `SourcePIDCache` caches an `AXUIElement?`; `MenuBarManager.hasValidMenuBar` compares with `kAXMenuBarRole`; `Extensions.swift` compiles unchanged.
- PR #37 body: API-05, API-06, API-08 and API-07 (AXSwift no longer used, package removed next) added.

## CI

Head 6108602: build (BUILD SUCCEEDED; the same 8 warnings as before, none in a file this plan touched, the XPC service included), test (161 tests in 30 suites passed, up from 155; Suite "URLCommand" and "Profile names keep their case and spaces" passed), swiftlint (0 violations in 136 files), former-name: all success on the first run. No CI fix was needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Arguments are percent-decoded once, not twice**
- **Found during:** Task 1
- **Issue:** the old parse decoded `pathComponents`, which Foundation has already decoded, a second time, so a profile named `a%41` arrived as `aA`.
- **Fix:** `URLCommand` decodes the still-encoded path exactly once.
- **Files modified:** holzBar/Core/URLCommand.swift
- **Commit:** ef30ba0

**2. [Rule 2 - Correctness] One extra test**
- "A command without arguments has none" covers `holzbar://settings`, the form most commands use.

Otherwise the plan was executed as written.

## Open human checks (on a Mac)

- URL commands: `open "holzbar://toggle/hidden"`, `open "holzbar://settings"`, `open "holzbar://profile/<a saved profile>"`, `open "holzbar://search"` work and no other holzBar window appears; once more with holzBar not running.
- Windows: without Screen Recording (`tccutil reset ScreenCapture com.holzcloud.holzBar`) the permissions window opens by itself; Settings opens from the menu, the holzBar Shelf and the search panel; close and reopen works.
- Deep link: the Screen Recording button opens Privacy & Security, Screen & System Audio Recording.
- Layout editor (macOS 26.7.1, and macOS 14 or 15 if available): Menu Bar Layout lists the items of every section (the XPC service found their source processes); the hidden section still avoids the app menus at the notch; Accessibility is still detected.

## Self-Check: PASSED

- FOUND: holzBar/Core/URLCommand.swift, Tests/HolzBarCoreTests/URLCommandTests.swift
- FOUND: commits ef30ba0, 8214250, 6108602
