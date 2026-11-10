# macOS 27 notes

macOS 27 draws all menu bar items through `MenuBarAgent` into one bar; items are no longer separate windows. holzBar's macOS 27 backend (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)) hides whole applications with assessment-mode assertions and reads items through Accessibility.

## Reordering items on the bar

In Settings → Menu Bar Layout holzBar sorts the items inside a section on macOS 27. Drag an item to another place in its row, move it with Option and the arrow keys, or use the Move Left and Move Right VoiceOver actions. In the drawing that waits for **Apply**, Apply writes the sections first and then puts each section in order on the bar; with **Apply changes immediately** a move happens at once.

holzBar does it the way macOS lets you do it by hand: it posts one ⌘ Command-drag at a time on the bar, at the item's position, and `MenuBarAgent` accepts it. After each drag it reads the bar again, tries once more from the other side when an item did not move, and stops and reports it when an item still did not move. The pointer is hidden for a moment and put back where it was, and the mouse button is always released. Sorting starts only while Menu Bar Layout is open (so the bar is fully revealed), with no mouse button held, and it needs no permission beyond the Accessibility access holzBar already has. Items that a rule controls, pinned items and macOS's own numbered system items stay where they are.

When macOS does not accept the events (the first drag changes nothing, twice), sorting turns itself off until holzBar is restarted and the sections still apply. The holzBar Shelf cannot sort on macOS 27: an item dragged there only changes its section.

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

From 0.0.8. Single, Paired, the shape of its own for the Apple logo, the outlines and the gradients work on macOS 27 as on macOS 26. Sections is not offered on macOS 27: holzBar hides whole applications, so the items of one section do not stand together and holzBar's dividers mark no boundary on the bar; a Sections choice that comes from another Mac or a settings file is drawn as Paired. The Apple-logo shape takes the Apple menu's position from the application-menu read holzBar already makes (no new permission); on macOS 27 that read skips holzBar's own menus, so the last position is kept while holzBar is in front.

## Show and hide animation

macOS 27 draws the bar through `MenuBarAgent`, which animates the bar by itself when items are concealed or released (about 250 ms, measured on macOS 27.0). holzBar has no divider length there and steps nothing; the **Animation** cards in Settings → General change the holzBar Shelf only there: Instant, Smooth (a fade with a short slide) or Fade, never with Reduce Motion on. On macOS 26 the setting makes the bar's items slide in and out (since 0.0.11); nothing of that runs on macOS 27. No permission, no timer and no network.

## Drag items in the menu bar

From 0.0.8. An optional module in Settings → Modules, on macOS 26 and 27, off until you switch it on. While it is on, holzBar holds back a plain click on an app's menu bar item: moving it sideways turns it into the ⌘ Command-drag macOS performs, and releasing it opens the item's menu as a normal click (so the menu opens on release).

macOS 27 draws no holzBar dividers, so sections are reached through two drop targets: drop an item on the holzBar icon, or on the open Shelf, and its app moves to Hidden, as in Menu Bar Layout; drag an item of a hidden app elsewhere while the hidden items show and its app becomes visible again. A drag that goes straight down from the bar onto the open Shelf stays a drag (the item's menu does not open), and the Shelf draws an accent outline while an item is over it. Settings → About → Copy Diagnostics has a Last drop line that names, in plain words and without any app name, where the last drop landed and what holzBar did with it, and a Last Shelf click line that names, in plain words and without any app name, how a click on a Shelf tile reached its item and whether the item took it. Every other drop of this module is macOS's own reorder, which holzBar does not record; to put items in order use Menu Bar Layout. A ⌘ Command-drag you make yourself is covered by the next section.

Apple's own items, holzBar's items, ⌘, ⌃ and ⌥ clicks and double-clicks are left alone, and the module does nothing on a full-screen Space or while macOS hides the menu bar. holzBar watches only the left mouse button, only while the module is on, and needs no permission beyond Accessibility.

## Command-drag across the holzBar icon

From 1.0.5, on macOS 27. A switch in Settings → Menu Bar Layout, on by default, lets a ⌘ Command-drag of an app's item set that app's section. macOS 27 draws no dividers, so the holzBar icon is the only anchor: the section changes only when the dragged item crosses the icon. Dragged from the right of the icon to its left, the app is hidden; dragged from the left to its right, it is visible. A reorder on the same side leaves the app alone, because on macOS 27 the order on the bar no longer means sections. An app in Always hidden stays there when it is dragged left, and becomes visible when it is dragged right.

A drop exactly on the icon does nothing from this feature; macOS decides, and the Drag in the Menu Bar module keeps its own drop on the icon (see above). holzBar's own sorting drags, the module's drags, a ⌘ Command-click without a drag, a drag with Control or Option, and a drag that starts on another display's bar are never read as a section change.

The section is per app on macOS 27, so an app with several items changes as a whole, and the notice in Menu Bar Layout names it once. The notice offers **Undo**, which puts the app back only if its section is still the one the drag set. Rule-controlled items, pinned Control Center controls and macOS's own numbered system items, such as the Clock, are not changed by the drop; the notice says why. The notices stay in memory and are gone when holzBar quits.

holzBar notes the ⌘ Command press on an item and its release, waits about 1.2 seconds for macOS to settle the bar, reads the bar once through Accessibility (once more after about 0.6 seconds if it is still moving) and writes the section from where the item came to rest. Nothing runs between drags: no timer, no polling, and the monitors exist only while the switch is on on macOS 27. It moves no pointer, needs no permission beyond the Accessibility holzBar already has and never touches the network. With the switch off, a ⌘ Command-drag stays macOS's own reorder.

Settings → About → Copy Diagnostics has a Last command-drag line in plain words and numbers, without any app name: how long holzBar waited, how many reads it took and what it decided, such as `waited 1210 ms, 1 read, set hidden, applied`, a kept reason, or `ignored: no movement`.

## Apple items

An optional module in Settings → Modules, on macOS 27, off until you switch it on. It needs no permission beyond the Accessibility holzBar already has.

**Hide the clock, Control Center, Wi-Fi or the battery.** macOS 27 draws these four as numbered system items of `MenuBarAgent`, and holzBar always asked for them to stay on the bar. With the module on, a switch for each leaves it out of that list while holzBar conceals the hidden section: the item is gone while the hidden items are hidden and comes back when you show them (a click on holzBar's icon, hover, the hotkey) and while Settings → Menu Bar Layout is open. It is the call holzBar already makes to hide applications, with a shorter list. With the holzBar Shelf on they are hidden too, and the Shelf of the hidden section shows a symbol tile for each hidden one; a click on the tile shows the item for a moment, opens it and puts it away again. Hiding a system item keeps holzBar's assertion alive even when no application is hidden, so Control Centre's camera and microphone indicator is not shown then either (see "Camera and microphone indicator" above; holzBar's dot on its icon covers the microphone and the camera).

**Replacement items.** macOS 27 hides whole applications, and several of Apple's items can belong to one Apple application, so hiding one of them can hide the others too. A replacement item is an icon of holzBar's own, with a symbol you choose, that opens one Apple item when you click it: hide the application's items in Menu Bar Layout and keep the ones you want one click away. You can add up to six, from the Apple items on the bar; the four system items above are not offered, because they are hidden as described above. A click opens the item the way item hotkeys and groups do: with "Open hidden items in the menu bar" off, a hidden Apple item is pressed through Accessibility without being shown, otherwise its application is shown for a moment.

holzBar stores only which system items you hid and your replacements' symbols and item keys, on this Mac, and has no network access. Settings → About → Copy Diagnostics says whether the module is on and how many items it hides and replaces, without any name.

## Apps that launch while items are hidden

holzBar hides whole applications through an assertion that names, by bundle identifier, the apps that stay visible. Since 1.0.5 an app that launches while items are hidden and is to stay visible (a new app when new items go to Visible or where macOS puts them, or a helper app inside another app, such as a login item) is added to it at once, so its item appears within about a second. An app that is slow to answer Accessibility right after it starts is asked again at every read for its first 30 seconds instead of being skipped for minutes. When an app such as Slack or an Electron app changes its items often, holzBar reads every app for it at most once every 30 seconds. If `MenuBarAgent` restarts, holzBar applies the hiding again with fresh assertions.

Items of processes without a bundle identifier, such as some script-based apps, cannot be named in the assertion: while holzBar hides any app, they stay hidden and are not listed in the holzBar Shelf. They come back while holzBar hides nothing.

Settings → About → Copy Diagnostics has a Hiding line with the reveal state and counts of these events (agent restarts, late refreshes, young retries, forced and held-back reads, notch rechecks), never an app name.

## Updating from macOS 26

holzBar remembers the macOS version it last ran on. When macOS was updated, it turns the sections it saved for each item before macOS 27 into the macOS 27 layout (one section per application) at the next launch, so what was hidden stays hidden; an installation that was updated earlier and hides nothing is repaired the same way. A layout you arranged on macOS 27 is never replaced. The sections come from holzBar's own saved settings, not from the order of the bar, which macOS 27 may already have rearranged. No permission and no network.
