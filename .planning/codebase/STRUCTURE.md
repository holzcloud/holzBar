# Codebase Structure

**Analysis Date:** 2026-10-02

## Directory Layout

```
holzIce/
├── Ice/                         # The app target (module name Ice)
│   ├── Main/                    # Entry point, AppDelegate, AppState, URL commands, navigation
│   ├── MenuBar/                 # Core domain: sections, items, appearance, IceBar, layout
│   │   ├── Appearance/          # Menu bar appearance manager, overlay, editor, configurations
│   │   ├── ControlItem/         # Section divider status items
│   │   ├── Groups/ Profiles/ RevealRules/ Spacers/ Spacing/ Search/
│   │   ├── IceBar/              # Secondary bar panel
│   │   ├── LayoutBar/           # Drag-to-arrange AppKit views
│   │   ├── MenuBarItems/        # Item model, manager, image cache, XPC client
│   │   └── MacOS27/             # macOS 27 backend
│   │       └── Core/            # Pure logic, also built by Package.swift
│   ├── Events/                  # Event taps, HID event manager
│   ├── Hotkeys/                 # Carbon hotkeys
│   ├── Permissions/             # Accessibility / Screen Recording
│   ├── Settings/                # Models/ and SettingsPanes/, SettingsView/Window
│   ├── UI/                      # IceUI/ controls, Modifiers/, Shapes/, Utilities/, Views/
│   ├── Utilities/               # Defaults, Constants, helpers, Migration, sync, backup
│   └── Resources/               # Info.plist, Assets.xcassets, Acknowledgements
├── MenuBarItemService/          # XPC service target (main.swift, Listener.swift)
├── Shared/                      # Code compiled into app and service
│   ├── Bridging/ Services/ Utilities/
├── Tests/IceMacOS27CoreTests/   # XCTest suites for MacOS27/Core (swift test)
├── Package.swift                # Test-only SwiftPM package over MacOS27/Core
├── Ice.xcodeproj/               # Xcode project; schemes Ice and MenuBarItemService
├── Casks/holzice.rb             # Homebrew cask (repo is also the tap)
├── Scripts/                     # install.sh, check-panels.swift, macos27/ probes and verify scripts
├── Integrations/Raycast/        # holzice:// shell scripts
├── Resources/                   # README media (gif, mov); Logo sources
├── docs/                        # macos27.md, upstream-bugs.md, release-notes/v<version>.md
├── .github/workflows/           # build.yml, lint.yml, release.yml
├── .planning/                   # GSD planning state
├── .swiftlint.yml               # Lint config (CI runs --strict)
├── CLAUDE.md, README.md, NOTICE, LICENSE (GPL-3.0), FREQUENT_ISSUES.md
```

## Directory Purposes

**`Ice/Main/`:**
- Purpose: launch and wiring
- Contains: `IceApp.swift`, `AppDelegate.swift`, `AppState.swift`, `URLCommands.swift`, `ConflictingApps.swift`, `Navigation/`
- Key files: `Ice/Main/AppState.swift` (setup order)

**`Ice/MenuBar/`:**
- Purpose: everything about the menu bar
- Key files: `MenuBarManager.swift`, `MenuBarSection.swift`, `MenuBarItems/MenuBarItemManager.swift` (largest file, about 2000 lines)

**`Ice/MenuBar/MacOS27/`:**
- Purpose: macOS 27 backend; files end in `27`
- Contains: app-side classes (`Concealer27`, `MenuBarItemProvider27`, `ItemImageStore27`, `ItemClicker27`, `MenuBarAssessmentAssertion27`)

**`Ice/MenuBar/MacOS27/Core/`:**
- Purpose: dependency-free logic, compiled into both the app (synchronized folder group) and `IceMacOS27Core`
- Contains: planners, controllers, layout, hit-testing, drawing rules

**`Ice/Settings/`:**
- Purpose: settings models (`Models/`) and SwiftUI panes (`SettingsPanes/`)

**`Ice/UI/`:**
- Purpose: reusable SwiftUI (`IceUI/` prefixed `Ice*`, `Modifiers/`, `Views/`)

**`Ice/Utilities/`:**
- Purpose: cross-cutting helpers; `Defaults.swift` holds all `UserDefaults` keys, `Constants.swift` holds URLs and bundle info

**`Shared/`:**
- Purpose: code used by the app and `MenuBarItemService`; keep it free of app-only types

## Key File Locations

**Entry Points:**
- `Ice/Main/IceApp.swift`: `@main`
- `Ice/Main/AppDelegate.swift`: lifecycle
- `MenuBarItemService/main.swift`: XPC service

**Configuration:**
- `Ice/Resources/Info.plist`, `MenuBarItemService/Resources/Info.plist`
- `.swiftlint.yml`, `Ice.xcodeproj/project.pbxproj`, `Package.swift`
- `Ice/Utilities/Defaults.swift`: defaults keys
- `Ice/Utilities/Constants.swift`: repository, issues, website, original-Ice URLs

**Core Logic:**
- `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`
- `Ice/MenuBar/MacOS27/Concealer27.swift`
- `Ice/MenuBar/MacOS27/Core/ConcealmentController27.swift`
- `Shared/Bridging/Bridging.swift`

**Testing:**
- `Tests/IceMacOS27CoreTests/*Tests.swift`: run with `swift test` (Package.swift)

**Release / distribution:**
- `Casks/holzice.rb`, `.github/workflows/release.yml`, `docs/release-notes/`

## Naming Conventions

**Files:**
- One primary type per file, file named after the type: `MenuBarSection.swift`
- macOS 27 backend types and files: `<Name>27.swift`; tests: `<Name>27Tests.swift`
- Reusable SwiftUI controls: `Ice<Name>.swift` in `Ice/UI/IceUI/`
- Settings: `<Area>Settings.swift` (model), `<Area>SettingsPane.swift` (view)
- Every file starts with the `//  File.swift` / `//  Ice` header comment

**Directories:**
- PascalCase, grouped by feature (`MenuBar/Spacers/`)

**Code:**
- Types PascalCase; internal types keep the `Ice` prefix (`IceBar`, `IceSection`); user-visible text says holzIce
- Defaults keys: camelCase enum case with PascalCase string value in `Defaults.Key`
- Dispatch queue labels use `com.holzcloud.holzIce.<Name>`

## Where to Add New Code

**New feature (all macOS versions):**
- Manager: `Ice/MenuBar/<Feature>/<Feature>.swift` as `@MainActor final class ...: ObservableObject` with `performSetup(with:)`; add a `let` on `AppState` and call setup in `AppState.setupTask` (`Ice/Main/AppState.swift`)
- Settings: model in `Ice/Settings/Models/`, key in `Ice/Utilities/Defaults.swift`, UI in `Ice/Settings/SettingsPanes/`
- Update the README feature list and comparison with Ice

**macOS 27 behavior:**
- Decision logic: `Ice/MenuBar/MacOS27/Core/<Name>27.swift` plus tests in `Tests/IceMacOS27CoreTests/`
- Side effects: `Ice/MenuBar/MacOS27/`, `@available(macOS 27.0, *)`

**New Swift files in the app:** drop into `Ice/` (synchronized folder group, no pbxproj edit needed); files for the XPC service need target membership.

**New URL command:** `Ice/Main/URLCommands.swift` plus a script in `Integrations/Raycast/`.

**Utilities:**
- App-only helpers: `Ice/Utilities/`; helpers needed by the service: `Shared/Utilities/`

**Release notes:** `docs/release-notes/v<version>.md`; upstream bug status: `docs/upstream-bugs.md`.

## Special Directories

**`.planning/`:**
- Purpose: GSD planning state and codebase maps
- Generated: Yes
- Committed: Yes

**`Ice/Resources/Assets.xcassets/`:**
- Purpose: app icon, accent color, images
- Generated: No
- Committed: Yes

**`Scripts/macos27/`:**
- Purpose: manual probes and verify scripts run on a real Mac
- Generated: No
- Committed: Yes

**`Ice.xcodeproj/`:**
- Purpose: project, schemes; target and module still named `Ice`
- Generated: No (hand-maintained by Xcode)
- Committed: Yes

---

*Structure analysis: 2026-10-02*
