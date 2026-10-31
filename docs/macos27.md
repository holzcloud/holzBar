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

Available since 0.0.7. System Glass (Settings, Appearance, Tint, macOS 26 and later) and the holzBar Shelf follow Reduce Transparency and Increase Contrast (System Settings, Accessibility, Display). With either on, they are drawn opaque with a visible border (a border you chose stays as it is); with both off, they look as before. holzBar reads the two options through `NSWorkspace` and listens for their change notification only while System Glass is in use or the holzBar Shelf is open, so a change applies at once and nothing polls. It needs no permission. The Shelf part also works before macOS 26; the glass part needs macOS 26.

The Liquid Glass slider of macOS 27 (System Settings, Appearance; three steps according to press coverage, and Apple documents no API for it) is not followed, because the macOS 27.0 SDK has no property, notification or environment value that reports it. `Scripts/macos27/scan-glass-api.sh` lists every glass, transparency and contrast identifier of AppKit, SwiftUI and the Accessibility framework and finds only the glass views an app draws with and the two options above (scan of 2026-10-09 against MacOSX27.0.sdk, version 27.0, with no hit that reports the slider); it is re-run with every new SDK. Reading the system's preference file or an undocumented notification is not public API, so holzBar does neither. Whether macOS draws System Glass by itself according to the slider is not known here: only a look at a real macOS 27 system can say.

## macOS 27's own overflow button

From 0.0.8. On a crowded bar beside the notch, macOS 27 folds the items that do not fit behind its own « control and shows them left of the notch when it is clicked. The only public description of that control is a press article; there is no API, and apps cannot control it.

holzBar tells four states from the frames it already reads through Accessibility (no new permission, no new data): none, collapsed, expanded and unknown. Expanded needs two agreeing facts: nothing is stacked on the control, and items are drawn left of the notch. While it is expanded, the holzBar Shelf leaves out a covered item that macOS draws beside the notch, so nothing is listed twice. In every other state, including unknown, and on another display, the Shelf lists covered items as before, because hiding an item that is not on screen would make it unreachable. The state is read again when the Shelf or Copy Diagnostics opens and after holzBar's own concealment settles (which includes a click on the control while items are concealed), with no timer. holzBar never clicks the control and conceals exactly as before.

What Accessibility reports for the folded items differs by version. On macOS 27.0 they report frames stacked against the control. On macOS 27.2 (build 26B123) it reports no folded item at all while the control is collapsed; expanded, they are all back. So on macOS 27.2 holzBar keeps the items it read before and lists them in their saved section, in the Menu Bar Layout editor and the holzBar Shelf, for as long as the control is on the bar and the app still runs. They are listed as not drawn, with the picture stored earlier or the app's icon. An item is dropped when the control is gone, when its app quits, or when it is read again. Items that were never read, because holzBar started with the bar already collapsed, cannot be listed until they are read once. Pressing a folded item from the Shelf asks the app through Accessibility; if the app no longer answers, nothing opens and the attempt is logged.

The last line of Settings → About → Copy Diagnostics names the state on macOS 27. `Scripts/macos27/overflow-state-probe.swift` prints the control's attributes and the items' frames in both states; it is read-only and has no network access.

## Menu bar styles

From 0.0.8. Single, Paired, the shape of its own for the Apple logo, the outlines and the gradients work on macOS 27 as on macOS 26. Sections is not offered on macOS 27: macOS decides the order of the items and holzBar hides whole applications, so the items of one section do not stand together and holzBar's dividers mark no boundary on the bar; a Sections choice that comes from another Mac or a settings file is drawn as Paired. The Apple-logo shape takes the Apple menu's position from the application-menu read holzBar already makes (no new permission); on macOS 27 that read skips holzBar's own menus, so the last position is kept while holzBar is in front.

## Show and hide animation

macOS 27 draws the bar through `MenuBarAgent`, which animates the bar by itself when items are concealed or released (about 250 ms, measured on macOS 27.0). holzBar has no divider length there and steps nothing; the **Animation** cards in Settings → General change the holzBar Shelf only there: Instant, Smooth (a fade with a short slide) or Fade, never with Reduce Motion on. On macOS 26 the setting makes the bar's items slide in and out (since 0.0.11); nothing of that runs on macOS 27. No permission, no timer and no network.

## Drag items in the menu bar

From 0.0.8. An optional module in Settings → Modules, on macOS 26 and 27, off until you switch it on. While it is on, holzBar holds back a plain click on an app's menu bar item: moving it sideways turns it into the ⌘ Command-drag macOS performs, and releasing it opens the item's menu as a normal click (so the menu opens on release).

macOS 27 draws no holzBar dividers and decides the order of the items itself, so sections are reached through the holzBar icon: drop an item on the holzBar icon and its app moves to Hidden, as in Menu Bar Layout; drag an item of a hidden app elsewhere while the hidden items show and its app becomes visible again. Every other drop is macOS's own reorder, which holzBar does not record, because Menu Bar Layout cannot reorder items on macOS 27 either.

Apple's own items, holzBar's items, ⌘, ⌃ and ⌥ clicks and double-clicks are left alone, and the module does nothing on a full-screen Space or while macOS hides the menu bar. holzBar watches only the left mouse button, only while the module is on, and needs no permission beyond Accessibility.

## Apple items

An optional module in Settings → Modules, on macOS 27, off until you switch it on. It needs no permission beyond the Accessibility holzBar already has.

**Hide the clock, Control Center, Wi-Fi or the battery.** macOS 27 draws these four as numbered system items of `MenuBarAgent`, and holzBar always asked for them to stay on the bar. With the module on, a switch for each leaves it out of that list while holzBar conceals the hidden section: the item is gone while the hidden items are hidden and comes back when you show them (a click on holzBar's icon, hover, the hotkey) and while Settings → Menu Bar Layout is open. It is the call holzBar already makes to hide applications, with a shorter list. Nothing is hidden while the holzBar Shelf is on, because the Shelf cannot show a system item and nothing else would bring it back. Hiding a system item keeps holzBar's assertion alive even when no application is hidden, so Control Centre's camera and microphone indicator is not shown then either (see "Camera and microphone indicator" above; holzBar's dot on its icon covers the microphone and the camera). That macOS really hides an item left out of the list has not been measured on a Mac yet.

**Replacement items.** macOS 27 hides whole applications, and several of Apple's items can belong to one Apple application, so hiding one of them can hide the others too. A replacement item is an icon of holzBar's own, with a symbol you choose, that opens one Apple item when you click it: hide the application's items in Menu Bar Layout and keep the ones you want one click away. You can add up to six, from the Apple items on the bar; the four system items above are not offered, because they are hidden as described above. A click opens the item the way item hotkeys and groups do: with "Open hidden items in the menu bar" off, a hidden Apple item is pressed through Accessibility without being shown, otherwise its application is shown for a moment.

holzBar stores only which system items you hid and your replacements' symbols and item keys, on this Mac, and has no network access. Settings → About → Copy Diagnostics says whether the module is on and how many items it hides and replaces, without any name.

## Updating from macOS 26

holzBar remembers the macOS version it last ran on. When macOS was updated, it turns the sections it saved for each item before macOS 27 into the macOS 27 layout (one section per application) at the next launch, so what was hidden stays hidden; an installation that was updated earlier and hides nothing is repaired the same way. A layout you arranged on macOS 27 is never replaced. The sections come from holzBar's own saved settings, not from the order of the bar, which macOS 27 may already have rearranged. No permission and no network.
