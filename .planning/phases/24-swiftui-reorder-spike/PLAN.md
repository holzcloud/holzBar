---
phase: 24-swiftui-reorder-spike
status: planned (spike with explicit decision criteria; "drop if not clearly better"; run /gsd-plan-phase 24)
requirements: [M27-05]
depends_on: Phase 9 (snapshots protect an arrangement-editor change); Phase 21 is the verifier of accessibility
---

# Phase 24: Layout editor with SwiftUI reordering (spike)

## Goal

Decide, with evidence, whether the Layout pane's custom AppKit drag and drop can be replaced by SwiftUI's new reordering API. Replace it **only if it clearly reduces code and keeps every accessibility and keyboard behaviour**. Otherwise drop the phase and record why.

## What is known

- WWDC26 session 271, "Code-along: Build powerful drag and drop in SwiftUI" (developer.apple.com/videos/play/wwdc2026/271): a new reordering API: `reorderable()` applied to views in a `ForEach`, and a `reorderContainer(for:)` modifier on the container that receives a collection **difference** to apply; plus `dragContainer` for multi-item drags and customising the drag lifecycle. The transcript summary I could read says `reorderable` and `reorderContainer` are available on **macOS 26 and newer** (the multi-item and preview modifiers are stated for the 27 releases); the premise "macOS 27 only" is therefore **unverified, probably too narrow**: confirm in the macOS 26 and 27 SDK documentation in the spike. The summary also did not describe accessibility behaviour: unknown.
- Today: the Layout pane's editor is AppKit: `LayoutBar`, `LayoutBarContainer` (drag updates, `updateArrangedViewsForDrag`), `LayoutBarPaddingView` (drop destination), `LayoutBarItemView` (`NSDraggingSource`, custom item images, VoiceOver actions "Move to ..."), together 1,327 lines in `holzBar/MenuBar/LayoutBar/`; keyboard arrangement with arrow keys and undo with ⌘Z, VoiceOver move actions, section padding views, per-backend rules (macOS 27 assigns apps to sections only, no ordering on the bar).
- holzBar's deployment target stays macOS 14: any SwiftUI reorder code lives behind `#available(macOS 26, *)` (or 27 if the spike says so) with the existing implementation kept for older versions. That means **two implementations** stay in the code base: a cost the decision must count.

## Decision criteria (all must hold to adopt; otherwise drop)

1. **Less code**: the net lines of the replaced path (AppKit drag code that can be deleted, not just bypassed) exceed the new SwiftUI code by at least 30 percent, counting that the macOS 14 to 25 path remains. If both implementations must stay, the gain is small, and the phase is dropped unless the new path also removes a bug.
2. **Accessibility parity**: VoiceOver move actions, full keyboard arrangement (arrow keys, ⌘Z undo), focus handling and announcements work at least as well as today (verified by the Phase 21 checklist items for this pane).
3. **Behaviour parity**: dragging between sections (Visible, Hidden, Always hidden, new items, groups, spacers), drop indicators, auto-scroll, cancel with Escape, multiple displays, and the per-backend limits all work; drag of an item that is an image of another app's item (our item views draw captured images) works with the API's preview.
4. **Cost**: no extra CPU while idle; drag performance with 40 items no worse (measured with Instruments by the user).
5. **Appearance**: same look in light, dark and glass tints.

## Plans (outline)

1. **24-01 Spike**: a throwaway SwiftUI view with three `reorderable` ForEach sections using fake items, built behind `#available`, run on macOS 26 and 27: can items move between containers (`reorderContainer(for:)` per section, one container?), what the `difference` contains, how VoiceOver and keyboard behave (the user runs a 10-minute script). Count lines. Write `24-01-SPIKE.md` with the criteria checked one by one and a go or drop recommendation.
2. **24-02 Decision**: the user decides from the spike note (a multiple-choice question then: adopt on macOS 26+ / adopt on 27 only / drop).
3. **24-03 (only on adopt) Replace**: new SwiftUI path behind `#available`, snapshots before arrangement changes (Phase 9), tests for the pure difference-to-move mapping, strings, accessibility checklist lines.

## Privacy and permission analysis

No permissions, no data.

## Risks

- Two implementations to maintain: the main reason this is "drop if not clearly better".
- The layout bar is not an ordinary list: items are live images, sections have padding views, and macOS 27 does not reorder at all.
- A regression in an editor many users rely on; Phase 9 snapshots mitigate but do not remove it.
- Possible API gaps on macOS 26 versus 27.

## Open design question

33. **Plan the phase now or skip it?** A. Keep it as a spike with the criteria above and decide after the spike (**recommended**: costs one spike); B. Drop it now (no spike); C. Adopt without a spike (not recommended).
