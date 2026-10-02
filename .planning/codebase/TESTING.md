# Testing Patterns

**Analysis Date:** 2026-10-02

## Test Framework

**Runner:**
- Swift Testing (`import Testing`, `@Suite`, `@Test`), via SwiftPM, tools version 6.0 (`Package.swift`).
- XCTest is not used.
- Config: `Package.swift` defines a test-only package `IceMacOS27Core`:
  - Library target `IceMacOS27Core` with `path: "Ice/MenuBar/MacOS27/Core"`. The same files are also compiled into the app through the synchronized `Ice` folder group in `Ice.xcodeproj`.
  - Test target `IceMacOS27CoreTests` with `path: "Tests/IceMacOS27CoreTests"`.
  - Platform `.macOS(.v14)`, `swiftLanguageMode(.v5)` on both targets.
- The Xcode project (`Ice.xcodeproj`) has no test target; the app scheme does not run tests.

**Assertion Library:**
- Swift Testing macros: `#expect(...)`, `try await` inside `@Test` functions (also `#require` is available but unused so far).

**Run Commands:**
```bash
swift test                          # Run all tests (needs a Swift 6 toolchain; the Core folder only imports Foundation/CoreGraphics/OSLog)
swift test --filter ConcealmentController27   # Run one suite
swift test --enable-code-coverage   # Coverage (not wired into any workflow)
```
No script or documentation in the repo spells out these commands; they are the standard SwiftPM invocations for `Package.swift`.

## Test File Organization

**Location:**
- Separate `Tests/` tree, not co-located with sources.

**Naming:**
- `<Subject>27Tests.swift` mirrors the `<Subject>27.swift` file in `Ice/MenuBar/MacOS27/Core/` (`ConcealmentPlanner27Tests.swift`, `StuckOverflow27Tests.swift`). `Plan2Core27Tests.swift` is a catch-all (700 lines, 55 tests) holding several suites for newer Core files.

**Structure:**
```
Tests/IceMacOS27CoreTests/
├── ConcealmentController27Tests.swift   # 7 tests, fake backend
├── ConcealmentPlanner27Tests.swift      # 6 tests
├── ItemDrawing27Tests.swift             # 4 tests
├── MenuBarGeometry27Tests.swift         # 23 tests
├── Plan2Core27Tests.swift               # 55 tests, multiple @Suite structs
├── SectionLayout27Tests.swift           # 12 tests
└── StuckOverflow27Tests.swift           # 7 tests
```
About 114 tests, roughly 1,280 lines.

## Test Structure

**Suite Organization:**
```swift
import Testing
@testable import IceMacOS27Core

@Suite("ConcealmentController27")
@MainActor
struct ConcealmentController27Tests {
    let running: Set<String> = ["visible.app", "hidden.app", "always.app"]

    @Test("Hiding conceals the target set")
    func hiding() async throws {
        let backend = FakeConcealmentBackend(universe: running)
        let controller = ConcealmentController27(backend: backend)
        try await controller.apply(target: allHidden, running: running)
        #expect(backend.concealed == ["hidden.app", "always.app"])
    }
}
```

**Patterns:**
- Suites are `struct`s with `@Suite("Display name")`; each test is `@Test("Sentence describing the behavior")` on a short camelCase function.
- Shared fixtures are stored `let` properties on the suite struct; Swift Testing creates a fresh instance per test, so there is no setUp/tearDown.
- `@MainActor` is placed on suites that test `@MainActor` types.
- One concern per test, assertions with `#expect(a == b)`; collection checks use `allSatisfy`, set literals compare against `Set`.
- Several suites live in one file when they test related small types (`Plan2Core27Tests.swift`).

## Mocking

**Framework:** Hand-written fakes; no mocking library.

**Patterns:**
```swift
@MainActor
final class FakeConcealmentBackend: ConcealmentBackend27 {
    final class Token: ConcealmentToken27 { ... }
    struct Rejected: Error {}
    var rejectNextActivation = false
    private(set) var history = [Set<String>]()
    func activate(allowedBundleIDs: [String]) async throws -> ConcealmentToken27 { ... }
    func invalidate(_ token: ConcealmentToken27) { ... }
}
```
- The fake simulates the real system semantics (assertions combine as a union of allowlists) and records `history` so tests can assert invariants over time ("never exposes always-hidden apps").
- Failure injection via flags (`rejectNextActivation`) and a nested `Rejected: Error`.

**What to Mock:**
- Anything touching private macOS APIs (`MenuBarClientCore` assertions), Accessibility, windows or event taps: define a protocol in `Ice/MenuBar/MacOS27/Core/` (`ConcealmentBackend27`) and fake it in `Tests/`.

**What NOT to Mock:**
- Pure planners and geometry code (`ConcealmentPlanner27`, `SectionLayout27`, `ItemDrawing27`, `ItemImages27`); call them directly with value inputs and `CGRect` fixtures.

## Fixtures and Factories

**Test Data:**
```swift
let layout: [String: MacOS27Section] = [
    "ru.keepcoder.Telegram": .hidden,
    "com.caldis.Mos": .alwaysHidden,
]
ItemImages27.cropRect(
    itemFrame: CGRect(x: 1478, y: 2, width: 33, height: 24),
    stripFrame: CGRect(x: 0, y: 0, width: 1920, height: 30),
    scale: 1
)
```
- Inline literals with real bundle identifiers and real-looking menu bar geometry; no factory helpers or fixture files.

**Location:**
- Defined at the top of each suite or test file; shared fakes are declared in the file that uses them.

## Coverage

**Requirements:** None enforced. No coverage tooling or threshold is configured.

**What is covered:** Only the pure logic in `Ice/MenuBar/MacOS27/Core/` (concealment planning/control, section layout and editing, geometry, item drawing/images, stuck-overflow detection, hit testing and click logic).

**What is not covered:** Everything outside `Ice/MenuBar/MacOS27/Core/`: the app-level managers (`Ice/Main/`, `Ice/MenuBar/MenuBarItems/`), event handling (`Ice/Events/`), SwiftUI views (`Ice/UI/`, `Ice/Settings/`), the macOS 27 adapters (`Ice/MenuBar/MacOS27/Concealer27.swift`, `ItemClicker27.swift`, `MenuBarItemProvider27.swift`), and `MenuBarItemService/`.

## Test Types

**Unit Tests:**
- The only automated tests. Fast, deterministic, no UI or system access; async tests use protocol fakes.

**Integration Tests:**
- Not automated. Manual shell/Swift probes live in `Scripts/macos27/` (`verify-conceal.sh`, `verify-layout.sh`, `verify-icebar.sh`, `verify-hover.sh`, `verify-clock.sh`, plus Swift probes like `ax-items.swift`, `reorder-probe.swift`) and `Scripts/check-panels.swift`. They need a running holzIce on macOS and are run by hand.

**E2E Tests:**
- Not used.

## CI

- `.github/workflows/build.yml` (runs-on `macos-26`): `xcodebuild ... -scheme Ice -configuration Release build` on pull requests and pushes to `main`. It only compiles; it does not run tests.
- `.github/workflows/lint.yml` (ubuntu): SwiftLint `--strict` on `Ice/`.
- `.github/workflows/release.yml`: builds and publishes on `v*` tags; no test step.
- **`swift test` is not run in any workflow.** Core tests run only when a developer runs them locally. Adding a `swift test` step (for example on `macos-26` in `build.yml`, or on `ubuntu-latest` since Core is Foundation-only if it has no Apple-only imports such as OSLog) would put the 114 tests under CI.
- `Tests/` is not covered by SwiftLint (`included: [Ice]`).

## Common Patterns

**Async Testing:**
```swift
@Test("Hiding again never exposes always-hidden apps")
func hidingAgain() async throws {
    let backend = FakeConcealmentBackend(universe: running)
    let controller = ConcealmentController27(backend: backend)
    try await controller.apply(target: allHidden, running: running)
    #expect(backend.history.allSatisfy { $0.contains("always.app") })
}
```

**Error Testing:**
```swift
backend.rejectNextActivation = true
// then assert the thrown error / unchanged state, e.g.
await #expect(throws: FakeConcealmentBackend.Rejected.self) {
    try await controller.apply(target: allHidden, running: running)
}
```
Use `#expect(throws:)` for expected failures; assert on fake state afterward to verify no partial transition.

**Adding tests for new logic:**
1. Put the pure logic in `Ice/MenuBar/MacOS27/Core/<Name>27.swift` (Foundation/CoreGraphics only).
2. Add `Tests/IceMacOS27CoreTests/<Name>27Tests.swift` with `@Suite`/`@Test`.
3. Fake any system dependency behind a protocol.
4. Run `swift test`; the Xcode build picks up the same source file automatically.

---

*Testing analysis: 2026-10-02*
