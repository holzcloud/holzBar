---
phase: 03-ice-and-sparkle-leftovers
plan: 01
subsystem: settings-about-and-docs
status: complete
tags: [acknowledgements, licenses, swiftui, swift-testing, docs, issue-template, ci]
requires:
  - "Phase 2 merged (PR #35); branch claude/ice-fork-development-hzdl1d at 046b2a9"
provides:
  - "holzBar/Core/Acknowledgements.swift: Acknowledgement struct, Acknowledgements.adaptedCode (Ice, Barometer, Thaw) and Acknowledgements.packages (5 pins)"
  - "Tests/HolzBarCoreTests/AcknowledgementsTests.swift (suite \"Acknowledgements\", 5 tests tied to Package.resolved and the license files)"
  - "holzBar/Settings/SettingsPanes/AcknowledgementsView.swift: native SwiftUI sheet presented from About"
  - "holzBar/Resources/Acknowledgements/License-*.txt (5 verbatim license texts)"
  - "build.yml step \"Check the acknowledgements\" (==> Acknowledgements: N license files in the app)"
  - "Draft PR #37 for Phases 3 to 5"
affects:
  - "Phase 4 (removing AXSwift, bumping Ifrit or replacing it): AcknowledgementsTests fails until Acknowledgements.packages and the license files follow Package.resolved"
tech-stack:
  added: []
  patterns:
    - "Acknowledgements as pure Core data, checked by swift test against Package.resolved and the resource folder"
    - "License texts as flat-copied bundle resources, loaded lazily when a DisclosureGroup expands"
key-files:
  created:
    - holzBar/Core/Acknowledgements.swift
    - Tests/HolzBarCoreTests/AcknowledgementsTests.swift
    - holzBar/Settings/SettingsPanes/AcknowledgementsView.swift
    - holzBar/Resources/Acknowledgements/License-AXSwift.txt
    - holzBar/Resources/Acknowledgements/License-CompactSlider.txt
    - holzBar/Resources/Acknowledgements/License-Ifrit.txt
    - holzBar/Resources/Acknowledgements/License-LaunchAtLogin-Modern.txt
    - holzBar/Resources/Acknowledgements/License-Semaphore.txt
  modified:
    - holzBar/Settings/SettingsPanes/AboutSettingsPane.swift
    - holzBar.xcodeproj/project.pbxproj
    - .github/workflows/build.yml
    - NOTICE
    - README.md
    - .github/ISSUE_TEMPLATE/bug_report.yml
  deleted:
    - holzBar/Resources/Acknowledgements.pdf
    - holzBar/Resources/Acknowledgements.rtf
    - FREQUENT_ISSUES.md
decisions:
  - "LEFT-01 (D-01): acknowledgements are pure Core data shown in a native SwiftUI sheet from About; the Ice-era PDF/RTF (which listed Sparkle) are removed"
  - "LEFT-03 (D-03): FREQUENT_ISSUES.md removed; its two still-valid answers plus the Reset and Grant Again hint moved to a README Troubleshooting section"
  - "LEFT-08 (D-04): superseded by REN-06; Image(.appLogo) in SettingsView.swift and AppLogo.svg confirmed, no change"
  - "Ifrit's license file bundles Ifrit's MIT license, Fuse's MIT license and the FuzzyFind notice with the full Apache License 2.0 text"
metrics:
  duration: 16min
  completed: 2026-10-02
actuals:
  tokens: 11800
  tasks: 2
  commits: 2
plan_head_before: 046b2a90bdb4627c1accec31a75efc5227805af2
plan_head_after: 12129ad2e0dcfe8a2a0ef8d54818a4e867332c56
---

# Phase 3 Plan 01: Native acknowledgements, credits, troubleshooting and the draft PR Summary

Settings, About, Acknowledgements now opens a native SwiftUI sheet built from pure, `swift test`-checked Core data (Ice, Barometer, Thaw and the five linked packages with their versions and full license texts, no Sparkle); NOTICE and README credit Barometer and Thaw, FREQUENT_ISSUES.md became a README Troubleshooting section, the bug form asks for the holzBar version, macOS version and install method, and draft PR #37 is open and green.

## What was done

### Task 1 (tracer): native, tested acknowledgements sheet (LEFT-01) — commit d5a0a41

- `holzBar/Core/Acknowledgements.swift`: `Acknowledgement` (`Identifiable, Hashable, Sendable`; name, repository string, version, use, license, licenseFile) and the caseless `enum Acknowledgements` with `gplLicense`, `adaptedCode` (Ice, Barometer, Thaw; GPL-3.0) and `packages` (AXSwift 0.3.2, CompactSlider 2.1.0, Ifrit 2.0.6, LaunchAtLogin-Modern 1.1.0, Semaphore 0.1.0; sorted by name).
- Five license files in `holzBar/Resources/Acknowledgements/`, copied verbatim (trailing whitespace stripped) from shallow clones at the pinned tags. `License-Ifrit.txt` holds Ifrit's `LICENSE.md`, Fuse's `Fuse_LICENSE` and the FuzzyFind notice followed by the full Apache License 2.0 from apache.org.
- `Tests/HolzBarCoreTests/AcknowledgementsTests.swift`: suite "Acknowledgements" with the five behaviors from the plan, named exactly as quoted; it decodes `Package.resolved` and reads the license folder relative to `#filePath`.
- `AcknowledgementsView.swift`: title, scrollable groups "holzBar" (GPL-3.0 sentence + License link), "Based on" and "Open-source packages" (name, version, use, license, Repository link, `DisclosureGroup("License")` whose text loads only when expanded, flat or from the `Acknowledgements` subdirectory, with a missing-text fallback), and a Done button with `.keyboardShortcut(.defaultAction)`; width 560, height 480 to 640.
- `AboutSettingsPane.swift`: the force-unwrapped PDF URL and its `NSWorkspace.open` are gone; the button sets `isShowingAcknowledgements`, and the pane presents `.sheet { AcknowledgementsView() }`.
- `Acknowledgements.pdf` and `.rtf` removed, plus the `Resources/Acknowledgements.rtf,` membership exception (`Resources/Info.plist,` kept).
- `build.yml`: step "Check the acknowledgements" after "Check the identifiers".
- Tracer gate: the task's automated verify was re-run after the commit and passed; CI proof came with the single push in Task 2.

### Task 2: credits, troubleshooting, bug template, draft PR (LEFT-02, LEFT-03, LEFT-05, LEFT-06, LEFT-08) — commit 12129ad

- NOTICE: a paragraph crediting Barometer (mackid1993) and Thaw (thaw-app) for `MenuBarAssessmentAssertion27.swift`, and a line pointing to Settings, About, Acknowledgements.
- README: Barometer and Thaw credit bullets plus the in-app acknowledgements sentence; "Ice, Thaw, Bartender or Hidden Bar"; "Fixes from 282 open bug reports"; a new "Troubleshooting" section (and nav link) with the automatically-hidden-menu-bar fix, the new-items placement setting and "Reset and Grant Again".
- `FREQUENT_ISSUES.md` removed; nothing outside `.planning/`/`.claude/` referenced it.
- Bug template: "holzBar Version" (description "Shown in Settings, About.", placeholder `e.g. 0.0.6-beta1`), macOS placeholder `e.g. 26.7.1`, required dropdown `install_method` with the three install methods.
- LEFT-08 superseded by REN-06: `Image(.appLogo)` in `holzBar/Settings/SettingsView.swift:83` and `AppLogo.imageset/AppLogo.svg` exist; no change.
- Pushed once (046b2a9..12129ad) and opened draft PR #37.

## CI (PR #37, head 12129ad)

| Job | Result |
|-----|--------|
| build | success, `** BUILD SUCCEEDED **`, `==> Acknowledgements: 5 license files in the app` |
| test | success, `Test run with 145 tests in 27 suites passed` (140/26 before; +5 tests, +1 suite) |
| swiftlint | success, `Done linting! Found 0 violations, 0 serious in 135 files` |
| former-name | success |

Build warnings: 9 (unchanged from main); none in a file this plan created or changed. They are the pre-existing HIDEventManager/ItemClicker27 Sendable warnings, the ScreenCapture deprecation, the "Copy to Applications" script phase (03-02 removes it), the AppIntents metadata note and "SwiftLint not installed".

CI fixes: none needed; the first push was green.

PR: #37, https://github.com/holzcloud/holzBar/pull/37 (draft, base main, head claude/ice-fork-development-hzdl1d).

## Deviations from Plan

None - plan executed exactly as written.

## Open human checks

- On the Mac: Settings, About, Acknowledgements opens a sheet inside the settings window (no Preview/TextEdit); it names holzBar's GPL-3.0 license, credits Ice, Barometer and Thaw, lists AXSwift, CompactSlider, Ifrit, LaunchAtLogin-Modern and Semaphore with versions; expanding "License" shows each text; links open the browser only when clicked; Done closes it; no Sparkle.
- On GitHub: the bug report form shows "holzBar Version" (e.g. 0.0.6-beta1), "macOS Version" (e.g. 26.7.1) and a required "Install Method" dropdown; the README renders the Troubleshooting section and the new credits.

## Self-Check: PASSED

- All created files exist; d5a0a41 and 12129ad are on origin/claude/ice-fork-development-hzdl1d; both task verify commands passed on 12129ad.
