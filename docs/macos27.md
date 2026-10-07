# macOS 27 notes

macOS 27 draws all menu bar items through `MenuBarAgent` into one bar; items are no longer separate windows. holzBar's macOS 27 backend (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)) hides whole applications with assessment-mode assertions and reads items through Accessibility.

## Reordering items on the bar

Not available yet. On earlier macOS versions holzBar moves an item by posting a ⌘ Command-drag to its window; on macOS 27 there is no item window to post it to, and it is not known whether `MenuBarAgent` accepts a synthetic ⌘-drag on the bar.

`Scripts/macos27/reorder-probe.swift` answers that on a real Mac: it ⌘-drags one application item past another and prints `REORDER WORKS` or `REORDER BLOCKED`. If it works, reordering can be built on the same events; if not, macOS 27 decides the order and holzBar can only assign sections.

## Hiding application menus

Turned off on purpose. macOS 27 folds the items that do not fit behind its own overflow button, so shown items never cover the application menus, and activating holzBar to hide them only took keyboard focus from the frontmost app (measured in #995). There is nothing to hide; the setting stays off on macOS 27.

## Camera and microphone indicator

While holzBar conceals items, Control Centre does not draw its indicator for the camera, the microphone or screen recording (measured on macOS 27.0); it comes back while holzBar hides no item. holzBar cannot keep it, so it puts a dot on its own icon instead: orange while another app uses the microphone, green while one uses a camera. It reads only whether another process uses them, through CoreAudio and CoreMediaIO on a background queue, with no permission and only while **Show a dot on the holzBar icon…** in Settings → General is on (the default). There is no public signal for screen recording, so that is not covered.
