# Coding Conventions

**Analysis Date:** 2026-10-02

## Naming Patterns

**Files:**
- One primary type per file, file named after the type: `Ice/MenuBar/MenuBarSection.swift`, `Ice/Main/AppState.swift`.
- Extensions of system types are gathered in `Extensions.swift` files: `Ice/Utilities/Extensions.swift`, `Shared/Utilities/SharedExtensions.swift`.
- The macOS 27 backend suffixes every file and type with `27`: `Ice/MenuBar/MacOS27/Concealer27.swift`, `Ice/MenuBar/MacOS27/Core/ConcealmentController27.swift`, protocols `ConcealmentBackend27`, enums `RevealState27`, `MacOS27Section`. Keep the suffix on new macOS 27 code.
- Settings panes end in `Pane`, settings managers in `Manager` (`Ice/Settings/SettingsPanes/GeneralSettingsPane.swift`).
- Every file starts with the header required by SwiftLint `file_header`:
  ```swift
  //
  //  <FileName>.swift
  //  Ice
  //
  ```
  (Module is still called `Ice`; do not rename. See `CLAUDE.md`.)

**Functions:**
- lowerCamelCase, Swift API Design Guidelines style (`concealedSets(layout:state:)`, `allowlist(concealing:running:)`).
- Private configuration hooks are named `configureCancellables()` (`Ice/Main/AppState.swift`).

**Variables:**
- lowerCamelCase. Booleans read as assertions (`isActive`, `useIceBar`, `isPresentingError`).
- Cancellable sets are built in a local `var c = Set<AnyCancellable>()` and then stored.

**Types:**
- UpperCamelCase. Namespaces of pure functions are caseless `enum`s (`ConcealmentPlanner27` in `Ice/MenuBar/MacOS27/Core/ConcealmentPlanner27.swift`).
- Nested enums for names/states (`MenuBarSection.Name` with `displayString`, `logString`, `localized`).
- Internal type names keep the Ice names (`IceBar`, `IceSection`); user-visible strings say holzIce.

## Code Style

**Formatting:**
- No formatter (no SwiftFormat/`.editorconfig`). 4 spaces, never tabs (custom SwiftLint rule `prefer_spaces_over_tabs` in `.swiftlint.yml`).
- Trailing commas are mandatory in multiline collections (`trailing_comma: mandatory_comma: true`).
- `// MARK: - Section` is used heavily (about 220 uses in 49 files) to divide extensions and sections.
- Doc comments (`///`) on nearly every type and member, in full sentences; `//` comments explain why.
- Switch expressions with implicit returns are used (`case .visible: "Visible"`), reflecting Swift 5.9+ style.

**Linting:**
- SwiftLint, config `.swiftlint.yml`, scope `Ice/` only (`Shared/`, `MenuBarItemService/`, `Tests/` and `Scripts/` are not in `included`).
- CI: `.github/workflows/lint.yml` runs `norio-nomura/action-swiftlint@3.2.1` with `--strict` on `ubuntu-latest` for every pull request and push to `main` touching `*.swift`. Warnings fail the build.
- Disabled: `cyclomatic_complexity`, `file_length`, `function_body_length`, `function_parameter_count`, `generic_type_name`, `identifier_name`, `large_tuple`, `line_length`, `nesting`, `opening_brace`, `todo`, `type_body_length`. Long files and long lines are accepted (`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift` is over 2000 lines).
- Notable opt-in rules: `force_unwrapping`, `implicitly_unwrapped_optional`, `fatal_error_message`, `multiline_arguments`, `multiline_parameters`, `indentation_width`, `modifier_order`, `closure_end_indentation`, `yoda_condition`, `empty_count`.
- Preferred modifier order: acl, setterACL, override, mutators, lazy, final, required, convenience, typeMethods, owned (so `private final actor`, `private static let`).
- Suppress only with a narrow comment and a reason-bearing context: `// swiftlint:disable:next force_unwrapping` or `// swiftlint:disable:this force_cast` (used in `Ice/Utilities/Extensions.swift`, `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift`, `Ice/Settings/SettingsPanes/AboutSettingsPane.swift`). `Ice/Utilities/Constants.swift` disables `force_unwrapping` for the whole URL-constants block.
- Custom rule `objc_dynamic`: write `@objc dynamic`, never separated.

## Import Organization

**Order:**
1. Framework imports, alphabetical where multiple (`import Combine`, `import OSLog`, `import SwiftUI`).
2. `@testable import IceMacOS27Core` last in tests.

**Path Aliases:**
- None. Files in `Shared/` are compiled into both the app and `MenuBarItemService` by target membership, not by module import.
- `import SwiftUI` (57 files) and `import Cocoa` (30) dominate; `import AppKit` is rare (9). Pure-logic files under `Ice/MenuBar/MacOS27/Core/` import only `Foundation`/`CoreGraphics`/`OSLog` so the SwiftPM test target can compile them on its own.

## Concurrency Style (old and new idioms mixed)

**Observation: `ObservableObject` + Combine is the dominant model; `@Observable` is not used anywhere.**
- 25 types conform to `ObservableObject`, with 78 `@Published` properties. New code, including `Ice/MenuBar/MacOS27/Concealer27.swift`, follows this: use `final class X: ObservableObject` with `@Published`, not `@Observable`.
- Views hold models with `@EnvironmentObject`/`@ObservedObject`/`@StateObject`.
- Combine is used for state wiring in managers: `import Combine` in 41 files, subscriptions collected into `Set<AnyCancellable>` inside `configureCancellables()` (`Ice/Main/AppState.swift`, `Ice/MenuBar/MenuBarManager.swift`).

**Structured concurrency is layered on top:**
- `async`/`await` has 235 `await` sites in 27 files; `Task { }` appears about 63 times in 23 files; `Task.detached` in 4 files.
- Helpers live in `Ice/Utilities/ConcurrencyHelpers.swift` (`TaskTimeoutError`, a `Task` timeout extension built on a task group). Use these instead of ad-hoc timeouts.
- `@MainActor` is applied explicitly on UI-facing classes and protocols (`MenuBarSection`, `ConcealmentController27`, `ConcealmentBackend27`). Annotate new UI/state types `@MainActor` rather than hopping with `DispatchQueue.main`.
- Only one real actor exists: `private final actor CacheActor` in `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`. Prefer it as the template for isolating mutable caches.

**Legacy GCD still widespread:**
- `DispatchQueue` appears in about 29 files (~100 sites), including 84 `DispatchQueue.main` uses in `Ice/`. Dedicated serial queues are used for AX/IPC/cache work: `Shared/Utilities/AXHelpers.swift`, `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift`, `Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift`, `Ice/MenuBar/MacOS27/MenuBarItemProvider27.swift` (label `com.holzcloud.holzIce.<Type>`).
- Create new queues with the shared helper `DispatchQueue.targetingGlobal(...)` in `Shared/Utilities/SharedExtensions.swift`.
- Bridge GCD results into async code with continuations; `DispatchQueue.global(qos: .userInitiated).async` is used for blocking AX calls (`Ice/MenuBar/MacOS27/ItemClicker27.swift`, `Ice/Events/HIDEventManager.swift`).

**Thread-safety escape hatches:**
- `@unchecked Sendable` (8 sites in 4 files) and `NSLock`/`OSAllocatedUnfairLock` (9 sites in 6 files) guard shared state. `Sendable` conformances are explicit but sparse.
- The Swift language mode is pinned to 5 in `Package.swift` (`.swiftLanguageMode(.v5)`); strict Swift 6 concurrency is not enforced.

**Closures:**
- `[weak self]` (109 sites, 35 files) followed by `guard let self else { return }` is the standard capture pattern. Back-references to the owner are `private weak var appState: AppState?` (`Ice/MenuBar/MenuBarSection.swift`).

## Error Handling

**Patterns:**
- Throwing async APIs with typed domain errors are used in the macOS 27 backend (`ConcealmentBackend27.activate(...) async throws`).
- User-facing errors are wrapped with `LocalizedErrorWrapper` (`Ice/Utilities/LocalizedErrorWrapper.swift`) and shown through `.alert(isPresented:error:)` (`Ice/Settings/SettingsPanes/GeneralSettingsPane.swift`). Custom errors conform to `LocalizedError` with `errorDescription` (`TaskTimeoutError`).
- Background failures are logged and swallowed: `try?` (45 sites) and `catch { logger.error(...) }` (53 `catch` sites). Do not surface errors from timers/event taps to the UI.
- `fatalError` (13 sites) is reserved for programmer errors and must carry a message (`fatal_error_message` lint rule).
- Force unwraps/casts are lint-flagged and only allowed with an explicit `swiftlint:disable` line, mostly for AX API and constant URLs.

## Logging

**Framework:** `os.Logger` (OSLog). No `print` calls exist in `Ice/`, `Shared/` or `MenuBarItemService/` (scripts in `Scripts/` use `print`).

**Patterns:**
- Create loggers with the shared initializer `Logger(category:)` (`Shared/Utilities/Logging.swift`), usually as `private static let logger = Logger(category: "EventTap")` or an instance `private let logger = Logger(category: "AppState")`. Subsystem is the bundle identifier.
- Shared named loggers: `Logger.default`, `.hotkeys`, `.serialization` (`Shared/Utilities/Logging.swift`). Local ones use `private extension Logger` (`Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`).
- Exception: `Ice/Events/HIDEventManager.swift:374` builds `Logger(subsystem: "com.holzcloud.holzIce", category: "ClickBridge27")` directly; prefer `Logger(category:)`.
- `MenuBarSection.Name.logString` supplies human-readable names for log messages.

## Comments

**When to Comment:**
- Every type, property and method gets a `///` summary. Describe invariants and ordering guarantees in the type doc (see `ConcealmentController27`: "activates the new assertions before releasing the old ones").
- Inline `//` comments explain system-quirk workarounds (see the long special-case list in `configureCancellables()` in `Ice/Main/AppState.swift`).
- TODOs are allowed (`todo` rule disabled).

**Documentation language:** English everywhere (`CLAUDE.md`).

## Function Design

**Size:** No limit enforced (body length and complexity rules disabled). Large managers exist; keep new logic small and push pure logic into `Ice/MenuBar/MacOS27/Core/` so it can be tested.

**Parameters:** Labeled, multi-line parameters must be one per line with aligned closing bracket (`multiline_parameters`, `multiline_arguments_brackets`). Overloads add parameters with defaults/extra labels (`concealedSets(layout:state:)` and `concealedSets(layout:state:temporarilyShown:)`).

**Return Values:** Prefer value types for pure results (`[Set<String>]`, structs); async throws for effectful backends.

## Module Design

**Exports:** Default (internal) access; `private` for implementation details, `private extension` for file-local helpers. Singletons are avoided in favor of an `AppState` object that owns the managers and is passed as `weak var appState`.

**Testability seams:** Platform-dependent behavior sits behind protocols (`ConcealmentBackend27`, `ConcealmentToken27`) so the pure controller in `Ice/MenuBar/MacOS27/Core/` has a fake in tests.

**Barrel Files:** Not used.

**Dependency boundaries for Core:** Files under `Ice/MenuBar/MacOS27/Core/` must not import AppKit/SwiftUI or any app type, because `Package.swift` compiles that folder alone for `swift test`.

---

*Convention analysis: 2026-10-02*
