---
phase: 23-liquid-glass-transparency
status: planned (outline; spike first; run /gsd-plan-phase 23)
requirements: [M27-03, M27-04]
depends_on: Phase 7; feeds Phase 21 (Reduce Transparency checks)
---

# Phase 23: Liquid Glass follows the transparency setting

## Goal

holzBar's glass appearance (the menu bar glass tint and the holzBar Shelf) follows the system's transparency choices live: Reduce Transparency and, only if a public signal exists, macOS 27's Liquid Glass slider. No private API.

## What is known (and what is not)

- **The slider exists** (not from Apple's developer documentation but from several news sources): macOS 27 adds a Liquid Glass appearance slider in System Settings > Appearance, with a live preview and three notches (most clear, medium, most opaque; igeeksblog.com, ioshacker.com via search). Apple's own wording in coverage: it "adjusts the transparency of Liquid Glass to improve the visibility of various buttons and labels" (Gigazine, which does not mention a slider; so the slider rests on the other sources).
- **No public API for the slider value was found.** The same coverage says apps benefit automatically: "apps will automatically benefit from these improvements ... without the need to modify code" and the design "adapts to accessibility settings such as reducing transparency and increasing contrast". That applies to system-drawn glass. holzBar's own glass uses `NSGlassEffectView` in `MenuBarOverlayPanel.swift` (so it follows the system automatically where AppKit draws it) plus its own tint and shape drawing, and `NSVisualEffectView` in `VisualEffectView.swift`.
- **Public Reduce Transparency**: `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and, for changes, `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` (macOS 10.10+, Apple: "posts when any of the accessibility display options change", no `userInfo`, must be observed on `NSWorkspace.shared.notificationCenter`; V). SwiftUI: the `accessibilityReduceTransparency` environment value (K). `accessibilityDisplayShouldIncreaseContrast` is the same family (K).
- **Whether any public signal reports the slider**: unknown. Candidates to check in the spike, public only: a change of `NSAppearance`/effective appearance notifications, KVO of `NSGlassEffectView` properties, `NSGlassEffectView.Style`, new SwiftUI `glassEffect` environment values or `NSApplication` properties in the macOS 27 SDK headers (read `AppKit` swiftinterface in Xcode 27). Reading the preference domain of System Settings (`defaults read` of a system key) is **not** a public API and is out of bounds (CLAUDE.md: never build on private or undocumented API).

## Design

- **Spike (23-01)**: on macOS 27, write a tiny probe that prints Reduce Transparency, Increase Contrast, the effective appearance and any new glass-related property from the SDK headers while the user moves the slider; record in `23-01-SPIKE.md` which public signals change with the slider. Also check how holzBar's overlay (`MenuBarOverlayPanel`, glass tint kind in `MenuBarTintKind`) currently looks at the three notches and with Reduce Transparency on.
- **Reduce Transparency, certain** (M27-03): when on, the glass tint kind falls back to an opaque solid colour of the tint (or the system material without translucency), and the Shelf background becomes opaque with a visible border (also meets Increase Contrast). Observed via the workspace notification only while a glass appearance or the Shelf is in use, then re-rendered once; no polling, no timer.
- **Slider, only if public** (M27-04): if the spike finds a public signal, map its levels to the tint's opacity range and re-render on change. If not, the phase records "not possible without private API" in the spike note, the README says only Reduce Transparency is followed, and M27-04 is closed as not applicable.
- **macOS 14 to 25**: no glass; the notification handler is shared and harmless; macOS 26 has glass without the slider, so only Reduce Transparency applies. Guarded with `#available`.
- **Settings**: no new switch; the appearance pane states that glass follows the system's transparency setting (five languages).
- **Pure logic**: a function from (kind, reduceTransparency, increaseContrast, optional slider level) to (opacity, border) in `holzBar/Core`, Swift Testing at the edges.

## Privacy and permission analysis

None: reading accessibility display options needs no permission. No data stored.

## Plans (outline)

1. **23-01 Spike on macOS 27**: probe, record, decide M27-04 yes or not applicable.
2. **23-02 Reduce Transparency and Increase Contrast**: mapping function, workspace notification observer with the lifecycle above, overlay and Shelf changes, tests, strings.
3. **23-03 Slider (only if 23-01 says yes)** and docs: README/website claim only what was verified on macOS 26 and 27.

## Risks

- The slider may be unobservable by design; promising it would be false (the roadmap makes the slider conditional).
- Opaque fallbacks change the look for users who enabled Reduce Transparency; that is the intent of the setting.
- A re-render storm if the notification fires in bursts: coalesce with the existing `Debouncer`.

## Open design question

32. **What if no public slider signal exists?** A. Follow Reduce Transparency and Increase Contrast only and say so (**recommended**); B. Also follow the slider by reading the system's preference file (not public: rejected by the principles, listed for completeness); C. Leave glass as it is.
