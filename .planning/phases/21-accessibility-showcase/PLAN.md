---
phase: 21-accessibility-showcase
status: planned (outline; run /gsd-plan-phase 21)
requirements: [A11Y-01, A11Y-02, A11Y-03]
depends_on: every phase that adds UI (8, 9, 10, 12, 14, 15, 16, 17, 18, 19, 20, 22, 23, 24, 25), so it audits the final screens
---

# Phase 21: Accessibility showcase

## Goal

Every holzBar screen works with the keyboard and VoiceOver and respects the system accessibility settings; the claim on the README and website names only what was verified.

## Why

holzBar already has keyboard and VoiceOver work in the Layout pane and the Shelf (README feature list: arrow keys, undo, VoiceOver move actions). The milestone adds an Automation pane, snapshots, a palette, an assistant and more custom controls; each is a chance to regress. A menu bar utility is used by people who rely on keyboard-only and screen-reader access more than most.

## Scope: what is audited

Menu Bar Layout pane (including item and snapshot lists, item context menu), the holzBar Shelf, the search panel, the command palette (Phase 14), the Automation pane (rules, item rules, widgets, scripts folder and confirmation sheet), the assistant (Phase 16), the share sheets (Phase 15), diagnostics sheet (Phase 20), Settings panes (General, Appearance, Hotkeys, Advanced, About), the permissions window, menu bar menus and alerts, and the custom-drawn menu bar appearance and overlay.

## Checks (each becomes a line in the checklist)

- **VoiceOver**: every control has a label, role, value and, where useful, a hint; custom `NSView`s (`LayoutBarItemView`, shelf items, widgets) expose `accessibilityLabel`, `accessibilityRole`, actions ("Move to Hidden", "Move to Visible", "Open"); lists read as lists with position; state changes (rule enabled, restore done) are announced; no information only by colour or position.
- **Keyboard**: every function reachable with the keyboard, logical Tab order, visible focus, Escape closes sheets and panels, Return runs the default; Full Keyboard Access (System Settings > Keyboard) on; the hotkey recorder is operable by keyboard.
- **System settings**: Reduce Motion (`accessibilityDisplayShouldReduceMotion`; Phase 19's animation and the panels' open animations), Increase Contrast (`accessibilityDisplayShouldIncreaseContrast`: borders, tints, the Shelf), Reduce Transparency (`accessibilityDisplayShouldReduceTransparency`; with the Phase 23 glass work), Differentiate Without Color, text size (macOS has no Dynamic Type; check layouts at the larger "Text size" of macOS 14+ and with long German and Romansh strings), Voice Control (visible text equals the accessible label, so "click <name>" works).
- **Five languages**: labels, hints and announcements are in `Localizable.xcstrings` in English, German, French, Italian and Romansh; `strings-check.py` keeps catalogs complete.
- **Contrast**: text and symbols meet at least 4.5:1 (3:1 for large text and icons) in light and dark and with the glass appearance, measured on the real screens.

## Verification

- **Checklist** in `docs/accessibility-checklist.md`: per screen, the steps and expected result for VoiceOver, keyboard and each system setting; the user runs it on macOS 26.7.1 and 27 (there is no Mac in the development environment); results recorded in the phase summary.
- **Automation** (question 29): Xcode's `performAccessibilityAudit()` (XCUITest) is a spike (K: availability on macOS and whether a GitHub macOS runner can run UI tests unattended). Only if it runs in CI without flakiness does it become a CI job; otherwise the checklist stays the verifier.
- Code-level checks that are cheap: a Swift Testing test that every `SettingsSection` and palette action has a non-empty localized accessibility title; SwiftLint rule for images without labels if one exists.

## Claim policy (A11Y-03, question 30)

The README and website name accessibility **only for what the checklist verified**, and say on which macOS versions. No comparison-table row (Thaw already lists keyboard and VoiceOver support), only the feature text and a link to the checklist.

## Privacy and permission analysis

No permission and no data. Accessibility **permission** (the app's own Accessibility grant) is unrelated to this phase's accessibility **support**; the docs must not confuse them.

## Plans (outline)

1. **21-01 Audit and fix list**: walk every screen with VoiceOver and keyboard (the user, on a Mac, guided by the draft checklist) and record issues; fix labels, focus order and missing actions.
2. **21-02 System settings and languages**: Reduce Motion, Increase Contrast, Reduce Transparency, contrast values, long strings; labels and hints in five languages.
3. **21-03 Checklist, optional CI audit, claims**: `docs/accessibility-checklist.md`, the UI-audit spike, README and website text for the verified items.

## Risks

- Cannot be verified without a Mac and a person using VoiceOver; the phase depends on the user's time.
- Custom drawing and AppKit/SwiftUI mixes make focus order hard; some fixes may change controls.
- Over-claiming: the claim policy limits it to verified items.

## Open design questions

29. **How is accessibility verified?** A. The checklist run by the user on macOS 26 and 27, plus a code audit (**recommended**); B. A, plus an XCUITest accessibility audit in CI if the spike shows it is stable.
30. **When may the README and website mention it?** A. Only after the user ran the checklist (**recommended**); B. After the code audit alone.
