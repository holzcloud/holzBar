<!-- refreshed: 2026-10-02 -->
# Architecture

**Analysis Date:** 2026-10-02

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                        UI / Presentation Layer                       │
├───────────────────┬───────────────────┬─────────────────────────────┤
│  Settings window  │  IceBar / Search  │  Appearance editor / Layout │
│ `Ice/Settings/`   │ `Ice/MenuBar/     │ `Ice/MenuBar/Appearance/`   │
│                   │  IceBar/`,`Search/`│ `Ice/MenuBar/LayoutBar/`   │
└─────────┬─────────┴─────────┬─────────┴──────────────┬──────────────┘
          │                   │                         │
          ▼                   ▼                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│          Model / Manager Layer (root: AppState, @MainActor)          │
│  `Ice/Main/AppState.swift`                                           │
│  MenuBarManager · MenuBarItemManager · MenuBarItemImageCache         │
│  HIDEventManager · AppSettings · AppPermissions · LayoutProfiles     │
│  MenuBarItemGroups · MenuBarSpacers · RevealRules · SettingsSync     │
└─────────┬──────────────────────────────┬────────────────────────────┘
          │ macOS <= 26                   │ macOS 27+
          ▼                               ▼
┌──────────────────────────┐   ┌─────────────────────────────────────┐
│ Divider/ControlItem      │   │ macOS 27 backend                     │
│ backend: window list,    │   │ `Ice/MenuBar/MacOS27/`               │
│ CGEvent drag moves       │   │ Concealer27, MenuBarItemProvider27,  │
│ `Ice/MenuBar/ControlItem/`│  │ ItemImageStore27, ItemClicker27      │
│ `MenuBarItems/`          │   │ Pure logic: `MacOS27/Core/`          │
└─────────┬────────────────┘   └──────────────┬──────────────────────┘
          │                                    │
          ▼                                    ▼
┌──────────────────────────┐   ┌─────────────────────────────────────┐
│ Shared/ (app + service)  │   │ Private APIs: MenuBarClientCore      │
│ Bridging (CGS), WindowInfo│  │ assertions, Accessibility (AX)       │
│ SourcePIDCache, AXHelpers│   │ `MenuBarAssessmentAssertion27.swift` │
└─────────┬────────────────┘   └─────────────────────────────────────┘
          │ XPC (macOS 26 only)
          ▼
┌──────────────────────────┐
│ MenuBarItemService (XPC) │
│ `MenuBarItemService/`    │
└──────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `IceApp` | SwiftUI `@main`; declares the Settings and Permissions window scenes | `Ice/Main/IceApp.swift` |
| `AppDelegate` | Launch chores, settings migration/import, conflicting-app check, permission gate | `Ice/Main/AppDelegate.swift` |
| `AppState` | Root object graph; owns every manager, runs ordered async setup | `Ice/Main/AppState.swift` |
| `MenuBarManager` | Owns the three `MenuBarSection`s, panels, menu bar visibility state | `Ice/MenuBar/MenuBarManager.swift` |
| `MenuBarSection` | One section (visible/hidden/alwaysHidden), its `ControlItem`, rehide timer | `Ice/MenuBar/MenuBarSection.swift` |
| `ControlItem` | `NSStatusItem` that acts as divider/toggle for a section | `Ice/MenuBar/ControlItem/ControlItem.swift` |
| `MenuBarItemManager` | Caches, moves, clicks and temporarily shows items (macOS <= 26 path, shared by 27) | `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` |
| `MenuBarItemImageCache` | Screen-captures item images for IceBar/layout UI | `Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift` |
| `MenuBarItemService.Connection` | XPC client to resolve item source PIDs (macOS 26) | `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift` |
| `HIDEventManager` | Click/hover/scroll triggers that show hidden sections | `Ice/Events/HIDEventManager.swift` |
| `Concealer27` | Hides applications on macOS 27 using the saved per-app layout | `Ice/MenuBar/MacOS27/Concealer27.swift` |
| `MenuBarItemProvider27` | Reads items through Accessibility (`AXExtrasMenuBar`) | `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift` |
| `ItemImageStore27` | Item images on macOS 27 | `Ice/MenuBar/MacOS27/ItemImageStore27.swift` |
| `ItemClicker27` | Opens a hidden item's menu from the IceBar | `Ice/MenuBar/MacOS27/ItemClicker27.swift` |
| `MenuBarAssessmentAssertion27` | `ConcealmentBackend27` implementation over private `MenuBarClientCore` | `Ice/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift` |
| `ConcealmentController27` / `ConcealmentPlanner27` | Pure, testable assertion lifecycle and planning (backend protocol) | `Ice/MenuBar/MacOS27/Core/` |
| `SectionLayout27` | `MacOS27Section` and per-application layout merge rules | `Ice/MenuBar/MacOS27/Core/SectionLayout27.swift` |
| `AppSettings` | Aggregates General/Advanced/Hotkeys settings models | `Ice/Settings/Models/AppSettings.swift` |
| `HotkeyRegistry` | Carbon hotkey registration | `Ice/Hotkeys/HotkeyRegistry.swift` |
| `URLCommands` | `holzice://` URL scheme dispatch | `Ice/Main/URLCommands.swift` |
| `LayoutProfiles`, `MenuBarItemGroups`, `MenuBarSpacers`, `RevealRules` | holzIce feature additions over Ice | `Ice/MenuBar/Profiles/`, `Groups/`, `Spacers/`, `RevealRules/` |
| `SettingsSync` / `SettingsBackup` / `MigrationManager` | iCloud sync, backup, Ice settings import and migrations | `Ice/Utilities/` |
| `Listener` | XPC listener in the helper service | `MenuBarItemService/Listener.swift` |
| `SourcePIDCache` | Resolves the owning PID of an item window via AX | `Shared/Services/SourcePIDCache.swift` |
| `Bridging` | Wrappers over private CoreGraphics/CGS APIs | `Shared/Bridging/Bridging.swift`, `Shared/Bridging/Shims.swift` |

## Pattern Overview

**Overall:** Single-process AppKit/SwiftUI app with a root `ObservableObject` (`AppState`) that owns feature managers; Combine for reactive wiring; version-gated backends (`#available(macOS 27.0, *)`) selected at runtime.

**Key Characteristics:**
- Every manager is `@MainActor final class ...: ObservableObject` with `performSetup(with appState:)` and a `weak var appState` back-reference.
- Observers are collected as `var c = Set<AnyCancellable>()` in `configureCancellables()` and assigned to a `cancellables` property.
- macOS 27 types carry a `27` suffix and `@available(macOS 27.0, *)`; storage on `AppState` is `AnyObject?` plus a lazy typed accessor (`concealer27`, `itemImageStore27`) so the property exists on all OS versions.
- Pure logic lives in `Ice/MenuBar/MacOS27/Core/` (no AppKit/AppState), is compiled both into the app and into the test-only SwiftPM package (`Package.swift`), and is driven through protocols (`ConcealmentBackend27`) so tests inject fakes.
- Settings persist in `UserDefaults` through typed keys in `Ice/Utilities/Defaults.swift` (`Defaults.Key`).

## Layers

**App entry / lifecycle:**
- Purpose: launch, permissions gate, window scenes
- Location: `Ice/Main/`
- Contains: `IceApp`, `AppDelegate`, `AppState`, `URLCommands`, `ConflictingApps`, navigation state
- Depends on: all managers
- Used by: system

**Managers (domain):**
- Purpose: menu bar state, items, sections, events, features
- Location: `Ice/MenuBar/`, `Ice/Events/`, `Ice/Hotkeys/`, `Ice/Permissions/`, `Ice/Settings/Models/`
- Depends on: `Shared/`, `Ice/Utilities/`
- Used by: UI layer through `AppState`

**macOS 27 backend:**
- Purpose: item discovery (AX), hiding (assertions), clicking, imaging
- Location: `Ice/MenuBar/MacOS27/`; pure part `Ice/MenuBar/MacOS27/Core/`
- Depends on: `AppState` (shell types only), `Defaults`, private `MenuBarClientCore`
- Used by: `AppState`, `MenuBarItemManager`, `HIDEventManager`, `IceBar`, settings panes

**UI:**
- Purpose: SwiftUI views, panels, reusable controls
- Location: `Ice/Settings/SettingsPanes/`, `Ice/Settings/SettingsView.swift`, `Ice/MenuBar/IceBar/`, `Ice/MenuBar/LayoutBar/`, `Ice/MenuBar/Search/`, `Ice/UI/`
- Depends on: managers via `AppState` environment/objects

**Shared (app + XPC service):**
- Purpose: code compiled into both targets
- Location: `Shared/`
- Contains: CGS bridging, `WindowInfo`, `SourcePIDCache`, AX helpers, logging, XPC `Request`/`Response` types

**XPC service:**
- Purpose: resolve source PIDs of item windows out of process (macOS 26)
- Location: `MenuBarItemService/`

## Data Flow

### Launch and setup

1. `IceApp` creates `AppDelegate`, whose `init` imports Ice settings, pulls iCloud settings, then builds `AppState` (`Ice/Main/AppDelegate.swift`).
2. `applicationDidFinishLaunching` resolves conflicting apps, checks `permissions.permissionsState`, then calls `appState.performSetup(hasPermissions:)`.
3. `AppState.setupTask` runs ordered setup: settings, menuBarManager, item service connection (macOS 26) or synthetic bounds provider (macOS 27), appearance, HID events, `concealer27` (before item manager), item manager, image cache, profiles, sync, groups, spacers, reveal rules, then `configureCancellables()` (`Ice/Main/AppState.swift`).

### Show/hide a section (macOS <= 26)

1. `HIDEventManager` (click/hover/scroll) or a hotkey/URL command calls `MenuBarSection.show()/hide()`.
2. `MenuBarSection` toggles its `ControlItem` length so the divider expands/collapses (`Ice/MenuBar/MenuBarSection.swift`, `Ice/MenuBar/ControlItem/ControlItem.swift`).
3. `MenuBarItemManager` moves items between sections with synthetic CGEvents (`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`).

### Show/hide on macOS 27

1. `MenuBarItemProvider27` reads items via AX; `MenuBarItemManager` builds the cache and assigns sections from the saved layout (`Defaults.Key.macOS27Layout`).
2. `Concealer27` computes concealed applications from section state, `ConcealmentPlanner27` plans, `ConcealmentController27` activates new assertions then releases old ones through `MenuBarAssessmentAssertion27`.
3. Clicking a hidden item in the IceBar goes through `ItemClicker27` (allow app briefly, click, restore).

### Source PID resolution (macOS 26)

1. `MenuBarItemService.Connection.shared` sends `Request.sourcePID(WindowInfo)` over XPC (`Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift`).
2. `Listener` decodes it and calls `SourcePIDCache.shared.pid(for:)` (`MenuBarItemService/Listener.swift`).
3. On repeated failure the connection falls back to a local cache in the app.

**State Management:**
- `AppState` holds `@Published` global state (active space, drag state); managers publish their own state; SwiftUI observes via `ObservableObject`. `AppSettings` forwards child `objectWillChange`. Persistent state is `UserDefaults` via `Defaults`.

## Key Abstractions

**MenuBarItem / MenuBarItemTag:**
- Purpose: an item and its stable identity
- Examples: `Ice/MenuBar/MenuBarItems/MenuBarItem.swift`, `Ice/MenuBar/MenuBarItems/MenuBarItemTag.swift`
- Pattern: value types; on macOS 27 a synthetic `CGWindowID` stands in for the missing window (`Ice/MenuBar/MacOS27/Core/SyntheticWindowID27.swift`)

**MenuBarSection (+ ControlItem):**
- Purpose: visible / hidden / always-hidden grouping
- Examples: `Ice/MenuBar/MenuBarSection.swift`

**ConcealmentBackend27 protocol:**
- Purpose: seam between pure concealment logic and the private API
- Examples: `Ice/MenuBar/MacOS27/Core/ConcealmentController27.swift`

**Settings models:**
- Purpose: typed wrappers over `Defaults` with `performSetup(with:)`
- Examples: `Ice/Settings/Models/GeneralSettings.swift`, `AdvancedSettings.swift`, `HotkeysSettings.swift`

## Entry Points

**App:**
- Location: `Ice/Main/IceApp.swift`
- Triggers: launch
- Responsibilities: scenes, adaptor for `AppDelegate`

**URL scheme:**
- Location: `Ice/Main/URLCommands.swift`
- Triggers: `holzice://` Apple events (Raycast scripts in `Integrations/Raycast/`)

**XPC service:**
- Location: `MenuBarItemService/main.swift`
- Triggers: launchd on connection to `com.holzcloud.holzIce.MenuBarItemService`

**Test package:**
- Location: `Package.swift` (target `IceMacOS27Core`, tests `Tests/IceMacOS27CoreTests/`)

## Architectural Constraints

- **Threading:** Managers are `@MainActor`. Blocking AX/capture calls run on dedicated `DispatchQueue`s, not the Swift concurrency pool (`MenuBarItemProvider27.queue`, `MenuBarItemImageCache.captureQueue`). Move operations are serialized by `AsyncSemaphore` in `MenuBarItemManager`.
- **Global state:** `Bridging.syntheticWindowBoundsProvider`, `MenuBarItemService.Connection.shared`, `SourcePIDCache.shared`, `Listener.shared`, static caches in `MenuBarItemProvider27` (guarded by `NSLock`, `nonisolated(unsafe)`).
- **Circular references:** managers hold `weak var appState` while `AppState` holds them strongly.
- **Compatibility:** deployment spans macOS 14+ to 27; every 27-only symbol is `@available(macOS 27.0, *)` and referenced behind `#available`. Pure Core files must stay free of app dependencies so `swift test` compiles them.
- **Private APIs:** CGS (`Shared/Bridging/`), `MenuBarClientCore` (`MenuBarAssessmentAssertion27.swift`), AX.
- **Swift language mode:** the app's modules are built with Xcode 27; the test package uses Swift 5 language mode.

## Anti-Patterns

### Putting macOS 27 logic in an app-dependent file

**What happens:** logic that touches `AppState`/AppKit is mixed with decision logic.
**Why it's wrong:** it cannot be unit tested on Linux or via `swift test`.
**Do this instead:** put pure functions/types in `Ice/MenuBar/MacOS27/Core/` with a `*27` suffix and a test in `Tests/IceMacOS27CoreTests/`; keep side effects in `Ice/MenuBar/MacOS27/`.

### Referencing 27-only types unguarded

**What happens:** a stored property typed `Concealer27` on `AppState`.
**Why it's wrong:** breaks availability on earlier macOS.
**Do this instead:** follow the `AnyObject?` storage plus `@available` computed accessor pattern in `Ice/Main/AppState.swift`.

### Blocking calls on the main actor

**What happens:** AX or screen-capture calls made from `@MainActor` code.
**Why it's wrong:** stalls the UI (first item read measured at seconds on macOS 27).
**Do this instead:** dispatch to a private queue as in `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift`.

## Error Handling

**Strategy:** Log and degrade; avoid throwing to the UI.

**Patterns:**
- `Logger(category:)` with `logger.error`/`debug`; failures leave features inactive (for example `Concealer27.performSetup` returns when assertions are unavailable).
- XPC failure falls back to local lookup (`MenuBarItemServiceConnection.swift`).
- `LocalizedErrorWrapper` for user-visible errors (`Ice/Utilities/LocalizedErrorWrapper.swift`).

## Cross-Cutting Concerns

**Logging:** OSLog via `Logger(category:)` extension in `Shared/Utilities/Logging.swift`.
**Validation:** guards on permissions (`Ice/Permissions/`), `MenuBarAssessmentAssertion27.isAvailable`.
**Authentication:** Not applicable; the XPC listener requires same-team peers on macOS 26 (`Listener.swift`). Accessibility and Screen Recording permissions are managed by `AppPermissions`.

---

*Architecture analysis: 2026-10-02*
