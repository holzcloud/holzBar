---
phase: 04-outdated-apis
plan: 03
subsystem: dependencies-and-search
status: complete
tags: [dependencies, axswift, ifrit, fuzzy-search, swiftpm, ci]
requires:
  - "04-02: complete, AXSwift imported nowhere, PR #37 green on 6108602"
provides:
  - "FuzzyMatch.score(query:in:) and FuzzyMatch.rank(_:query:key:) (Core, tested, written for holzBar)"
  - "Menu bar search ranked by FuzzyMatch"
  - "project.pbxproj and Package.resolved without AXSwift and Ifrit"
  - "Build log sections '==> Resolved source packages' and '==> App size'"
affects:
  - "The XPC service links no Swift package any more"
  - "Acknowledgements: 3 packages, 3 license files"
  - "Search behaviour: subsequence match instead of Fuse's typo-tolerant match"
tech-stack:
  added: []
  removed: [AXSwift 0.3.2, Ifrit 2.0.6]
  patterns:
    - "Linear-gap dynamic programming over the folded candidate (O(query x candidate)) for the best-scoring subsequence match"
key-files:
  created:
    - holzBar/Core/FuzzyMatch.swift
    - Tests/HolzBarCoreTests/FuzzyMatchTests.swift
  modified:
    - holzBar/MenuBar/Search/MenuBarSearchPanel.swift
    - holzBar/MenuBar/Search/MenuBarSearchModel.swift
    - .github/workflows/build.yml
    - holzBar.xcodeproj/project.pbxproj
    - holzBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
    - holzBar/Core/Acknowledgements.swift
  deleted:
    - holzBar/Resources/Acknowledgements/License-AXSwift.txt
    - holzBar/Resources/Acknowledgements/License-Ifrit.txt
decisions:
  - "USER DECISION (Task 1, no checkpoint): replace Ifrit entirely with holzBar's own FuzzyMatch, written fresh (no Ifrit, Fuse or FuzzyFind code, so no third-party credit and no NOTICE change)"
  - "API-07: AXSwift removed from both targets, Package.resolved and the acknowledgements"
  - "DEP-01: CompactSlider 2.1.0, LaunchAtLogin-Modern 1.1.0, Semaphore 0.1.0 are the latest stable tags (git ls-remote, 2026-10-02); LaunchAtLogin-Modern minimumVersion 1.0.0 -> 1.1.0"
  - "FuzzyMatch ignores case, diacritics and the query's spaces; start +24, word start +16, camel-case hump +16, consecutive +12, gap -3 per character, leading/trailing -1 per character, exact +32; ties keep their order"
metrics:
  duration: 20min
  completed: 2026-10-02
actuals:
  tokens: 9600
  tasks: 2
  commits: 2
plan_head_before: 7151a7ee4c775bffc2103cbc656b28cb22539914
plan_head_after: d23fec178327ab23971b1cf64d4219fbef8f8d7c
---

# Phase 4 Plan 03: AXSwift and Ifrit removed, holzBar's own fuzzy search, latest packages Summary

By the user's decision Ifrit is replaced by holzBar's own tested `FuzzyMatch`, so the menu bar search no longer needs a package; AXSwift is gone from the app and the XPC service (API-07); the three remaining packages are on their latest stable releases with minimum versions equal to their pins (DEP-01); the build log now lists the resolved packages and the app's size. PR #37 is green on d23fec1.

## User decision

Task 1 (the checkpoint) was resolved before execution: none of the four options; Ifrit is replaced entirely by `holzBar/Core/FuzzyMatch.swift`, written for holzBar. Task 1 was skipped without a checkpoint, and Task 2 did this instead of the option branches.

## What was done

### Task 2: own fuzzy search, resolved packages in the build log, commit 5cc38e5

- `FuzzyMatch.score(query:in:)`: `nil` unless the query's letters appear in order (case, diacritics and the query's spaces ignored; characters that fold to several, like "ß", give a position each). The best of all matches is found by dynamic programming with linear gap costs, O(query x candidate) per item. Bonuses: start of the candidate, start of a word, camel-case hump, consecutive letters, exact match; costs: gaps, leading and trailing characters.
- `FuzzyMatch.rank(_:query:key:)`: drops non-matches, sorts by score, keeps the order of ties; a blank query returns the items as they are.
- `@Suite("FuzzyMatch")`, 10 tests: missing letters have no score; "cc" ranks "Control Centre" above "accent"; camel case above scattered; prefix above middle; consecutive above scattered; exact match first; case and diacritics ignored; spaces in the query ignored; ties keep their order; an empty query keeps the order. The expectations were checked against a Python port of the algorithm before pushing (scores: "cc" 62 vs 40, "ic" in iCloud 96 vs Music 41).
- `MenuBarSearchPanel` ranks with `FuzzyMatch.rank(selectableItems, query:) { $0.title }`; `import Ifrit`, `MenuBarSearchModel.fuse` and the score tuple are gone. The empty query still shows every section in today's order.
- `build.yml`: after the warnings, `==> Resolved source packages` and the block xcodebuild wrote; after the build, `==> App size: <KB>`.

### Task 3: AXSwift and Ifrit out, packages checked, commit d23fec1

- Latest stable tags (`git ls-remote --tags`): CompactSlider 2.1.0 (`52a01bd09156152881c53ba235c862e3bf5690b1`), LaunchAtLogin-Modern v1.1.0 (`a04ec1c363be3627734f6dad757d82f5d4fa8fcc`), Semaphore 0.1.0 (`2543679282aa6f6c8ecf2138acd613ed20790bc2`): all already pinned, none newer.

| Package | Before | After |
|---------|--------|-------|
| AXSwift | 0.3.2 (`81dcc36`), app and XPC service | removed |
| Ifrit | 2.0.6 (`3f961f6`), minimum 2.0.3 | removed (replaced by FuzzyMatch) |
| CompactSlider | 2.1.0, minimum 2.1.0 | unchanged |
| LaunchAtLogin-Modern | 1.1.0, minimum 1.0.0 | 1.1.0, minimum 1.1.0 |
| Semaphore | 0.1.0, minimum 0.1.0 | unchanged |

- `project.pbxproj`: the AXSwift build files, product dependencies and package reference, and Ifrit's (`IfritStatic`) likewise, are gone; the XPC service's Frameworks phase and `packageProductDependencies` are empty.
- `Package.resolved`: the `axswift` and `ifrit` pins removed; `originHash` left as it was.
- `Acknowledgements.packages`: AXSwift and Ifrit removed; `License-AXSwift.txt` and `License-Ifrit.txt` deleted (intentional deletions).
- PR #37 body: API-07 (package removed from both targets) and DEP-01 (each package, version and the search decision).

## CI

Head d23fec1: build (BUILD SUCCEEDED, the same 8 warnings as before, none in a file this plan touched; `==> Acknowledgements: 3 license files in the app`; `==> App size: 14828 KB`), test (171 tests in 31 suites passed, up from 161; "The acknowledgements list exactly the resolved packages" and Suite "FuzzyMatch" passed), swiftlint (0 violations in 137 files), former-name: all success on the first run. No CI fix was needed. The build log mentions AXSwift nowhere.

Resolved source packages (build log):

```
Resolved source packages:
  LaunchAtLogin: https://github.com/sindresorhus/LaunchAtLogin-Modern @ 1.1.0
  Semaphore: https://github.com/groue/Semaphore @ 0.1.0
  CompactSlider: https://github.com/buh/CompactSlider @ 2.1.0
```

Bundle size: 14,828 KB after this plan. No earlier build log printed the size, so there is no measured "before" value; the next builds can be compared against this one.

## Deviations from Plan

### Following the user decision

**1. [User decision] Ifrit removed instead of bumped to 4.0.0**
- The plan's Task 3 verify expects an `ifrit` pin, a `fuse.searchSync` call and 4 license files; after the decision the expected state is 3 pins (compactslider, launchatlogin-modern, semaphore), no Fuse call and 3 license files, which is what CI shows.
- No NOTICE paragraph and no `adaptedCode` entry: FuzzyMatch is written for holzBar, so nothing third-party is adapted; the "The adapted code is credited" test is unchanged.

**2. [Rule 2 - Correctness] Two extra tests**
- "Spaces in the query are ignored" and "An empty query keeps every item in its order" cover the panel's empty-query path and multi-word queries.

**3. [Rule 2 - Lean] App size in the build log**
- Added `==> App size` to the Build step so the bundle size the user asked for is measurable from now on.

## Behaviour change to note

Fuse (threshold 0.5) tolerated misspellings; FuzzyMatch only matches the typed letters in order, so a misspelt name ("Spotlihgt") no longer finds its item. Abbreviations, word starts and camel-case humps rank higher than before.

## Open human checks (on a Mac)

- Search: type "cc", the first letters of an app and a part of an app's name; the expected items come first. A misspelt name finds nothing (by design now).
- Settings, About, Acknowledgements lists CompactSlider, LaunchAtLogin-Modern and Semaphore, no AXSwift and no Ifrit.
- The layout editor, the holzBar Shelf and hiding still work on macOS 26 (the XPC service runs without AXSwift).

## Self-Check: PASSED

- FOUND: holzBar/Core/FuzzyMatch.swift, Tests/HolzBarCoreTests/FuzzyMatchTests.swift
- MISSING as intended: holzBar/Resources/Acknowledgements/License-AXSwift.txt, License-Ifrit.txt
- FOUND: commits 5cc38e5, d23fec1
