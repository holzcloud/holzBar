# macOS 27 notes

macOS 27 draws all menu bar items through `MenuBarAgent` into one bar; items are no longer separate windows. holzBar's macOS 27 backend (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)) hides whole applications with assessment-mode assertions and reads items through Accessibility.

## Reordering items on the bar

Not available yet. On earlier macOS versions holzBar moves an item by posting a ⌘ Command-drag to its window; on macOS 27 there is no item window to post it to, and it is not known whether `MenuBarAgent` accepts a synthetic ⌘-drag on the bar.

`Scripts/macos27/reorder-probe.swift` answers that on a real Mac: it ⌘-drags one application item past another and prints `REORDER WORKS` or `REORDER BLOCKED`. If it works, reordering can be built on the same events; if not, macOS 27 decides the order and holzBar can only assign sections.

## Hiding application menus

Turned off on purpose. macOS 27 folds the items that do not fit behind its own overflow button, so shown items never cover the application menus, and activating holzBar to hide them only took keyboard focus from the frontmost app (measured in #995). There is nothing to hide; the setting stays off on macOS 27.

## Camera and microphone indicator

While holzBar conceals items, Control Centre does not draw its indicator for the camera, the microphone or screen recording (measured on macOS 27.0); it comes back while holzBar hides no item. holzBar cannot keep it, so it puts a dot on its own icon instead: orange while another app uses the microphone, green while one uses a camera. It reads only whether another process uses them, through CoreAudio and CoreMediaIO on a background queue, with no permission and only while **Show a dot on the holzBar icon…** in Settings → General is on (the default). There is no public signal for screen recording, so that is not covered.

## Liquid Glass and transparency

Available since 0.0.7. The maintainer has not yet checked it on real macOS 26 and 27 systems. System Glass (Settings, Appearance, Tint, macOS 26 and later) and the holzBar Shelf follow Reduce Transparency and Increase Contrast (System Settings, Accessibility, Display). With either on, they are drawn opaque with a visible border (a border you chose stays as it is); with both off, they look as before. holzBar reads the two options through `NSWorkspace` and listens for their change notification only while System Glass is in use or the holzBar Shelf is open, so a change applies at once and nothing polls. It needs no permission. The Shelf part also works before macOS 26; the glass part needs macOS 26.

The Liquid Glass slider of macOS 27 (System Settings, Appearance; three steps according to press coverage, and Apple documents no API for it) is not followed, because the macOS 27.0 SDK has no property, notification or environment value that reports it. `Scripts/macos27/scan-glass-api.sh` lists every glass, transparency and contrast identifier of AppKit, SwiftUI and the Accessibility framework and finds only the glass views an app draws with and the two options above (scan of 2026-10-09 against MacOSX27.0.sdk, version 27.0, with no hit that reports the slider); it is re-run with every new SDK. Reading the system's preference file or an undocumented notification is not public API, so holzBar does neither. Whether macOS draws System Glass by itself according to the slider is not known here: only a look at a real macOS 27 system can say.
