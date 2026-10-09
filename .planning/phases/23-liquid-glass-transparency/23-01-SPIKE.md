---
phase: 23-liquid-glass-transparency
plan: 01
date: 2026-10-09
sdk: MacOSX27.0.sdk (version 27.0, Command Line Tools)
status: static half done, runtime half pending U-13
---

# Spike M27-04: is there a public signal for macOS 27's Liquid Glass slider?

## Question

Is there a public API that reports or sets the user's system-wide Liquid Glass choice (the slider of macOS 27, System Settings, Appearance), so that holzBar's System Glass tint could follow it (M27-04)? The slider's existence rests on press coverage (igeeksblog.com, ioshacker.com) and not on Apple's developer documentation, which names no API for it. "Public" here means a documented symbol in the SDK.

## Decision

M27-04: not-applicable

The scan of the macOS 27.0 SDK found no documented symbol that reports or sets the user's glass choice: every glass, transparency and contrast identifier in the public headers and Swift interfaces is either something an app draws with or one of the old accessibility options. The runtime half (does anything react while the slider moves on macOS 27) is pending UAT item U-13 and could only reopen this decision through a symbol the SDK does not document, which holzBar would not use (see "Out of bounds").

## Evidence: SDK scan

SDK: `/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk`, version 27.0. Run on 2026-10-09 with `Scripts/macos27/scan-glass-api.sh` (all six anchors found, 322 focused files). The verdict, quoted verbatim:

```
VERDICT: no public signal for a Liquid Glass slider in MacOSX27.0.sdk (16 glass and 23 transparency/contrast identifiers, all known)
```

Distinct glass identifiers (all known, none a signal): `defaultglasseffectshape`, `glass`, `glassbuttonstyle`, `glasseffect`, `glasseffectcontainer`, `glasseffectid`, `glasseffecttransition`, `glasseffectunion`, `glassprominent`, `glassprominentbuttonstyle`, `nsbezelstyleglass`, `nsglasseffectcontainerview`, `nsglasseffectview`, `nsglasseffectviewstyle`, `nsglasseffectviewstyleclear`, `nsglasseffectviewstyleregular`.

Distinct transparency and contrast identifiers (all known): `_accessibilityreducetransparency`, `_colorschemecontrast`, `_contrasteffect`, `_transparent`, `accessibilitydisplayshouldincreasecontrast`, `accessibilitydisplayshouldreducetransparency`, `accessibilityreducetransparency`, `colorschemecontrast`, `contrast`, `contrasting`, `dithertransparency`, `istransparent`, `nsappearancenameaccessibilityhighcontrastaqua`, `nsappearancenameaccessibilityhighcontrastdarkaqua`, `nsappearancenameaccessibilityhighcontrastvibrantdark`, `nsappearancenameaccessibilityhighcontrastvibrantlight`, `nsapplicationpresentationdisablemenubartransparency`, `nsimagedithertransparency`, `nstransparentbinding`, `titlebarappearstransparent`, `translucent`, `transparency`, `transparent`.

The informational sweep over every public framework (does not change the verdict) found nothing else about the system's glass choice: the other hits are HealthKit glasses, Core Image filters, Bluetooth and AVFoundation constants, and prose ("clarity", "liquid").

Re-run `Scripts/macos27/scan-glass-api.sh` with every new SDK or Xcode; a new unlisted identifier reopens this decision.

## Candidates the outline named

| Candidate | Result in the SDK |
|-----------|-------------------|
| Effective appearance notifications | `NSAppearance.Name` has only the four `AccessibilityHighContrast*` names (Aqua, DarkAqua, VibrantLight, VibrantDark, macOS 10.14); no glass name. |
| Key-value observation of `NSGlassEffectView` properties | `contentView`, `cornerRadius`, `tintColor`, `style` and, on macOS 27, `effectIsInteractive` are inputs an app sets on its own view; none reports system state. |
| `NSGlassEffectView.Style` | Regular and clear, chosen by the app per view. |
| New SwiftUI environment values | Only `accessibilityReduceTransparency` and `colorSchemeContrast`, both old; no glass or clarity value. |
| `NSApplication` properties | Only `NSApplication.PresentationOptions.disableMenuBarTransparency`, an option an app sets for itself. |
| `Accessibility.framework` | `AXSettings.h` and the other headers list no glass or transparency entry. |

## Public signals that exist

What holzBar can follow, in the SDK's own words (`NSAccessibility.h`, `NSWorkspaceAccessibilityDisplay`):

- `NSWorkspace.accessibilityDisplayShouldReduceTransparency` (macOS 10.10): "If this property's value is true, UI (mainly window) backgrounds should not be semi-transparent; they should be opaque."
- `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` (macOS 10.10): "UI should be presented with high contrast such as utilizing a less subtle color palette or bolder lines."
- `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`, posted on the workspace's notification center with no payload to read, when any of these options changes.

Plan 23-02 builds on these.

## Runtime half (pending, UAT item U-13)

`Scripts/macos27/glass-signals.swift` has to show on macOS 27, while the slider moves across its three steps (watch mode, optionally `--all-notifications`):

- whether `reduceTransparency` or `increaseContrast` flips at some step (if one does, README and docs may say that step turns the option on, only after that observation);
- whether any other public line changes (appearance, glass style or tint of a fresh `NSGlassEffectView`);
- whether holzBar's System Glass changes by itself with the slider (a visual note, not a claim).

### Observations

Not yet run.

## Out of bounds

Reading the system's preference domains (the `defaults` command or any file under `Library/Preferences`) is not a public API. Neither is a distributed notification whose name appears in no SDK header, even when the probe's `--all-notifications` mode shows it firing while the slider moves. Such a name is recorded here as an observation and never used by holzBar (CLAUDE.md: Apple's way, no private API).
