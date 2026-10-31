# Features

<table>
<tr>
<td valign="top" width="50%">

#### Menu bar items
- ✅ Hide items in a hidden and an always-hidden section
- ✅ Show on hover, click or scroll (trackpad **and mouse wheel**)
- ✅ Automatic rehide
- ✅ Drag-and-drop layout editor — it draws first and lays the bar out in one pass when you choose Apply (or at once, if you prefer)
- ✅ **Drag items in the menu bar without ⌘ Command** (macOS 26 and 27) — an optional module in Settings, Modules, off until you switch it on
- ✅ **Apple Items** (macOS 27) — hide the clock, Control Center, Wi-Fi or the battery, and keep an Apple item one click away with a replacement icon; an optional module, off until you switch it on
- ✅ **Notch hub** — a panel at the notch for optional modules, off until you switch it on; Timers, Calendar, Live activities and File drop are its first modules
- ✅ **Layout profiles** — "Work", "Home", … one click, hotkey or URL away
- ✅ **Profiles bound to a display or a Space** — applied when you connect the display or switch to the Space
- ✅ **Groups** (folders) — several items behind an icon of their own, in a colour and with a symbol or image of your choice
- ✅ **Item images of your choice** — give any item its own picture, or its app's icon; without Screen Recording, the holzBar Shelf and the search show app icons
- ✅ **Spacers** — empty items of adjustable width
- ✅ **Choose where new items appear** — a tile in the Layout pane shows where, and you can change it there
- ✅ **Per display: always show everything, or collapse** — the display under the pointer decides
- ✅ **Animation styles** — Instant, Smooth or Fade, as picture cards
- ✅ **Keeps items in their section after app updates, title changes and display changes**
- ✅ Search menu bar items — by abbreviation ("cc" for Control Centre), by short name ("bt" for Bluetooth), despite typos, and with what you open from it first
- ✅ **Open an item by letter** — a hotkey shows a letter under every item; type it to open the item's menu
- ✅ **Keyboard and VoiceOver** — arrange items in the Layout pane with the arrow keys, undo with ⌘Z, move items with VoiceOver actions
- ✅ **Opened items stay** up to 30 s after their menu closes — or open without showing the item at all
- ✅ **Show When It Changes** — a marked item shows for 5 s when its title or value changes
- ✅ **Privacy indicators stay visible** — the camera and microphone indicator, the FaceTime item and the Screenshot tool's recording button can be moved, never hidden <sub>macOS 14 to 26</sub>
- ✅ Item spacing <sub>BETA</sub>

</td>
<td valign="top" width="50%">

#### holzBar Shelf
- ✅ Hidden items in a bar below the menu bar
- ✅ **Only on the built-in display or on displays with a notch**
- ✅ **Shows items the notch covers**
- ✅ **Works from the keyboard** — open it with its hotkey, then the arrow keys, Return and Escape
- ✅ **Row, grid or column** — and it fades in, never with Reduce Motion on
- ✅ **Type to find an item** — the best match is highlighted, Return opens its menu
- ✅ **Always-hidden items behind a fold** — one tile, "+3", opens them
- ✅ **Closed apps, dimmed** — a click launches the app <sub>off by default</sub>
- ✅ **Rearrange by dragging** — in order, into another section, or up onto the menu bar

#### Appearance
- ✅ Tint, shadow, border; Single and Paired shapes with round or square ends
- ✅ **Black menu bar that hides the notch**
- ✅ **Rounded screen corners**
- ✅ **Dashed and dotted borders**
- ✅ **Tints from the wallpaper or the accent colour, and the system's glass** <sub>glass on macOS 26 and later</sub>
- ✅ **Moods** — save the look of the menu bar under a name and switch to it in one click, from the palette or with a rule
- ✅ **Menu bar styles**: a **Sections** shape, one shape per section on the bar (macOS 14 to 26; macOS 27 draws Paired), a **shape of its own for the Apple logo** (bar tint, accent colour, wallpaper or a colour), **outlines** in the accent colour or a gradient, **vertical gradients**, one gradient per shape and the **tint strength**

</td>
</tr>
<tr>
<td valign="top" width="50%">

#### Automation
- ✅ **Rules, scripts, profile hooks and widgets** — see [New in 0.0.8](#new-in-008)
- ✅ **Command palette** — a Spotlight-like panel for actions, profiles, moods, rules and items
- ✅ **AppleScript dictionary** — show, hide, apply a profile, switch rules and Zen mode; lasting changes ask first
- ✅ **Sound output and Bluetooth as rule conditions**
- ✅ **Show hidden items when the battery is low or the network drops** — since 0.0.8 these are rules in the Automation pane (the old settings are moved there once)
- ✅ **Zen mode** — one hotkey, menu item, URL or Shortcuts action keeps hidden items hidden; optionally on while the screen is mirrored or shared, without any permission
- ✅ **Shortcuts actions** — Zen mode, show or hide a section, apply a profile, open an item by name, search
- ✅ **`holzbar://` URL commands** and [Raycast script commands](../Integrations/Raycast)
- ✅ Hotkeys for sections, search, the holzBar Shelf, app menus, **auto-rehide**, **a quick peek**, **Zen mode**, **each layout profile** and **each menu bar item** — a combination another holzBar hotkey already uses moves only when you choose **Replace**

</td>
<td valign="top" width="50%">

#### Settings
- ✅ **Export and import** all settings
- ✅ **Imports your Ice settings** on first launch
- ✅ **Alerts in Settings are sheets** on its window, so holzBar keeps working while one is open
- ✅ **A Settings window with three sidebar groups and a Modules pane** for the optional modules, each off until you switch it on
- ✅ **Usage suggestions** <sub>off by default</sub> — local counters, **View Data** and **Forget Everything**
- ✅ Launch at login
- ✅ **English, German, French, Italian, Romansh, Spanish, Brazilian Portuguese, Japanese, Simplified Chinese, Korean and Russian** — holzBar follows your Mac's language; choose another one for holzBar alone in System Settings → General → Language & Region → Applications

</td>
</tr>
</table>

## New in 0.0.14

- **File drop**: a module of the Notch hub, off until you switch it on in Settings → Modules, under Notch, and costing nothing while it is off. Drag files toward the notch and the hub opens on the File drop tab (the switch **Open when you drag a file to the notch**, on by default, turns that off; like every hover-opened hub it does not open in a fullscreen space, with the menu bar hidden by the system, while the screen is mirrored or shared, or on a display **Show the hub on** excludes, and a window or a piece of text dragged there opens nothing). Drop the files on the tab and they are kept as tiles with the file's icon and name, up to 50; a file that is already there moves to the front, and a full stash says "The stash is full" instead of dropping anything silently. Drag a tile out onto a folder, a mail, a chat or a web page and the file is copied there; the original stays where it is, and the tile leaves the stash after the drop unless you turn that off (**Remove a file from the stash after you dropped it**, on by default). Show in Finder and Remove work from the keyboard and with VoiceOver (Return shows the focused tile in the Finder, Delete removes it), **Remove all** clears the stash, and a file that was moved or deleted since shows as Missing, dimmed, and cannot be dragged. The Overview shows how many files are in the stash, and a pill beside the notch shows the same number, never a name. holzBar keeps only where each file is, in memory: it does not open, read, copy or move your files, makes no previews, and forgets the stash when you quit holzBar or switch the module off. It takes files, folders and apps (each counts as one item), not text, links or pictures from a web page, and not files that another app only promises, such as some Mail attachments and Photos pictures. It asks for no permission; macOS may ask the app or folder you drop a file on for access to a protected folder.
- **Live activities**: a module of the Notch hub, off until you switch it on in Settings → Modules, under Notch, and costing nothing while it is off. While another app uses the camera or the microphone (macOS 14.2 and later), or a download is in progress in your Downloads folder, a small capsule hangs below the notch (below the menu bar at the top centre on a display without a notch). It never covers a menu bar item and shows the activity's symbol and a short phrase ("Camera in use", "Microphone in use", "Downloading"), with a count such as +2 when more than one is going on. It never shows a file name. Point at it or click it and the hub opens: the Live activities tab lists what is going on, with the file name of a download, and the Overview shows a tile. A finished download reads "Download finished" for five seconds and then leaves. The capsule does not appear in a fullscreen space, with the menu bar hidden by the system or while the screen is mirrored or shared, and it follows **Show the hub on**. The two sources have a switch each under the module's row: **Camera and microphone in use** (on) and **Downloads** (off). The camera and microphone source needs no permission; it listens the way the dot on holzBar's icon does and opens no audio or video. The Downloads source recognises the unfinished-download marks of Safari, Chrome, Edge, Brave, Firefox and Opera, so a download from a browser that uses another mark is not shown; it watches the entries of your Downloads folder without polling, shows no percentage, and macOS asks for access to the Downloads folder once, with holzBar's own sentence, when you switch it on. If you refuse, the row says so and offers a button to System Settings; nothing asks again by itself, and holzBar never reads what you download. File names are held in memory while an activity is shown; nothing is stored, logged, exported or sent. These are holzBar's own activities. They are not Apple's Live Activities from your iPhone, which the setting "Keep Live Activities visible" in Advanced keeps in the menu bar and which this module does not change. Timers and countdowns are the Timers module.
- **Calendar**: a module of the Notch hub, off until you switch it on in Settings → Modules, under Notch, and costing nothing while it is off. It asks for Calendar access when you switch it on (macOS shows its own question; you can refuse it, and revoke it in System Settings or with Revoke in holzBar's Permissions window). The hub's Calendar tab lists what is on now and the next events of today and tomorrow, up to six, with each calendar's colour, the time and the title; all-day events of today come first (**Show all-day events** under the module's row switches them off), and cancelled and declined events are left out. Under the module's row there is one switch per calendar; that choice stays on this Mac and is never exported or synced. An event that has a link on a known meeting service (Zoom, Google Meet, Microsoft Teams, Webex or FaceTime), in its URL field, its location or its notes, or any other https link in its URL field or location, gets a Join button from ten minutes before it starts until it ends; the button opens the link in your browser or the meeting app, only when you click it, and closes the hub. The Overview shows the next event with its start. The list refreshes when Calendar changes and when an event starts or ends, without polling. Event text is held in memory while the hub shows it; it is never stored, logged, exported or sent. The module does not create or edit events, reminders or contacts, and it reads the calendars macOS lists, not the web. If access is missing, the tab says so and offers the button that asks or opens System Settings; nothing asks again by itself.
- **Timers**: a module of the Notch hub, off until you switch it on in Settings → Modules, under Notch, and costing nothing while it is off. It needs no permission and sends no system notification. Start a timer from a preset (1, 5, 10 or 25 minutes, or 1 hour), by typing a length (`25` is minutes, `1:30` minutes and seconds, `1h 30m`), as a countdown to a moment you choose with a date and time field, or as a stopwatch that counts up; give it a label if you like. Up to eight run at once. The Timers tab shows each one with its remaining time and a progress bar, and lets you pause, resume, restart and remove it; the Overview shows the leading timer and a pill beside the notch shows when the next one ends, or Done. A system sound rings once when a timer ends (Glass; choose another or none under the module's row in Settings). A timer that ended while holzBar was not running or the Mac slept shows as Done without a sound. Timers are kept when you quit holzBar, on this Mac only (they are never exported or synced); when the module is off nothing runs and the stored timers are left as they are. A timer does not keep the Mac awake, and if you change the Mac's clock the timers move with it. For a countdown that stays in the menu bar all day, use the countdown widget.
- **Count badge**: a small number on the holzBar icon says how many items are hidden right now, in the menu bar's own colours, while they are hidden and there is at least one (the items of the hidden section; the always-hidden ones are not counted, and a count above 99 reads "99+"). The tooltip and VoiceOver say it too ("3 hidden items"; with the capture dot on macOS 27, both: "Microphone in use. 3 hidden items"). Off until you switch it on under **Show the number of hidden items on the icon** in Settings → General (the switch is there while the holzBar icon is shown); nothing is drawn or watched while it is off.

## New in 0.0.13

0.0.13 is out; see its [release notes](release-notes/v0.0.13.md).

Four upgrades of the holzBar Shelf, with their settings in Settings → General under the holzBar Shelf options. None needs a permission, a timer or the network, and nothing of them runs while the Shelf is closed.

- **Type to find an item**: with a hotkey that opens the holzBar Shelf, which takes the keyboard, start typing. A small field at the start of the Shelf shows what you typed; the best match is highlighted with the same fuzzy search as the item search (abbreviations and typos work), the items that do not match step back, and the arrow keys step through the matches. **Return** (or Space) opens the highlighted item's real menu, **Backspace** deletes a character and **Escape** closes the Shelf. Spaces are not typed, and a key with Command or Control is left alone. **Find items by typing** is on by default; with it off the Shelf behaves as before and shows no field.
- **Always-hidden items behind a fold**: in the Shelf of the hidden section the always-hidden items (when that section is on in Settings → Advanced) are one tile at the start, "+3" for three items. A click on it opens them to the left of the hidden items, after a divider in a row; the tile becomes a minus that folds them again. Typing opens the fold, so a search reaches every item. **Always-hidden items** in Settings → General sets whether the fold starts folded **each time** or **as you left it**; the state you left stays on this Mac and is in no export. The Shelf opened for the always-hidden section, with its hotkey, lists those items directly, as before.
- **Closed apps**: with **Show applications that are not running** on (off by default), the Shelf also lists, dimmed, the apps that you hid an item of and that are not running, with their icon; a click launches the app and closes the Shelf. holzBar takes them from the sections it already remembers for your items (on macOS 27 per app, before per item), compares them with the running apps as the Shelf opens, and lists at most 24 for a section. Apps that are no longer installed, Apple's own apps, holzBar's items and widgets are left out.
- **Rearrange by dragging**: drag an item of the Shelf. Drop it on another item of the same section to put it before or after it (before macOS 27; macOS 27 puts the items of a section in order itself, so there an item only changes its section), on an item of the other section or on the fold tile to move it into that section, or up onto the menu bar to show it there. A line marks where it lands, and the Shelf steps back while the pointer is over the menu bar. It uses the same moves as Menu Bar Layout, so a refused move is reported the same way and an app that does not answer is not dragged. **Rearrange items by dragging** is on by default; with it off the items are only clicked.

### Behaviour and the layout editor

None of this needs a permission beyond the Accessibility access holzBar already has, the network or a timer.

- **Animation styles**: Settings → General has an **Animation** setting with three picture cards, **Instant**, **Smooth** and **Fade**. It replaces the two switches *Animate showing and hiding* and *Fade in*: Smooth is the slide of the bar's items on macOS 26 and, for the holzBar Shelf, a fade with a short slide of its content (about 0.22 seconds); Fade is the Shelf's fade alone (0.15 seconds); Instant changes at once. Reduce Motion always wins and nothing runs while idle. macOS 27 animates its own bar, so there the cards change the Shelf only, and the card text says so; macOS 14 and 15 keep the instant change of the bar. A setting you had before is carried over once.
- **Notification Center from the clock** (macOS 27): macOS 27 ignores a click on the clock while items are hidden. holzBar lifts the hiding for a moment and clicks again, so Notification Center opens. **Open Notification Center from the clock** in Settings → General is on by default; turn it off to leave the click to macOS, and the clock then does nothing while items are hidden. macOS offers no way to open Notification Center without that click, so there is no hotkey for it.
- **Per display**: under **Displays** in Settings → General (shown when more than one display is connected, or a choice is stored) each display is set to **Default**, **Always show everything** or **Collapse**. The display under the pointer wins. *Always show everything* keeps every section shown there: what hides the items by itself (rehiding after a delay or when the pointer leaves, a click on empty space) is refused, while a click on holzBar's icon, a section hotkey and Zen mode still hide them. *Collapse* keeps the hidden items hidden there like Zen mode does: hovering, clicking empty space, scrolling, rules and URL commands do not reveal them, while the holzBar icon and the hotkeys still do. Moving the pointer onto the display shows or hides the sections once. Neither is used with the holzBar Shelf, which holds the hidden items itself. With no display set, nothing runs; with one set, a single mouse-moved monitor costs one rectangle test per event until the pointer changes display.
- **A layout editor that draws first**: in Menu Bar Layout, dragging an item, the arrow keys and the VoiceOver actions change a drawing and not the bar. A strip above the rows counts the changes and offers **Apply** and **Discard**. Apply lays the bar out in one pass: on macOS 27 the sections of the applications are stored and applied once; before, the items change section as a profile does and each section is then put in order with the fewest moves. A snapshot of the arrangement is taken first, items that a rule controls are left to their rule, and a line afterwards says how many changes were made. The drawing follows the bar while the pane is open. **Apply changes immediately** turns the old behaviour back on (every move at once); turning it on applies what waits. Moves made outside the pane, in the Shelf or by dragging in the menu bar, still happen at once.
- **The tile "New items"**: it sits in the section where items holzBar has never seen land, the same choice as **Place new menu bar items in** in Settings → Advanced, and a picker on it moves it to another section (in the drawing until you apply it).

### Built-in items and app launchers

The **Widgets** module (Settings → Modules, off until you switch it on) also offers items that do one small job. Each is a menu bar item of holzBar's own, like a widget: it can be put in any section, hides with it, is kept in layout profiles and shows in the holzBar Shelf and the search, so it keeps working while macOS hides its own items. None needs a permission of its own, a network connection or a private framework, and nothing of them runs while the module is off. **Add Widget** lists them.

- **Focus**: a click opens Apple's Focus item when it is in the menu bar (a hidden one is pressed without being shown), and the Focus settings of System Settings otherwise.
- **AirDrop**: a click opens Apple's AirDrop item, or Finder's AirDrop window; files dropped on the icon are offered to AirDrop, and macOS shows its own picker.
- **Media controls**: a click plays or pauses, a right-click (or Control-click) offers previous and next. They are the keys on a keyboard, so whatever app answers those keys answers the item; holzBar needs the Accessibility access it already has. **Only while sound plays** shows the item while the Mac plays sound and for two minutes after it stops; it follows two events of Core Audio, with no polling and no audio opened. It cannot name the track, because macOS offers no public way to read it.
- **Fast user switching**: a click opens Apple's fast user switching item, or Users & Groups in System Settings. holzBar does not switch the user itself.
- **Timer**: a click starts a countdown of 1 to 60 minutes (shown as minutes and seconds), the next click stops it; a sound plays at the end and VoiceOver announces it. It ticks every second only while the item is shown, and waits for the end only while it is hidden.
- **App launcher**: the icon of any app you pick, in the menu bar; a click opens the app. It is the way to keep an app one click away in a hidden section, or to hide the app's own icon and keep a launcher. The launcher stores the app's bundle identifier, so it travels with a settings export and does nothing on a Mac without the app.

The module now holds up to twelve widgets, the readouts, buttons and scripts included.

### Menu bar icon, search and design

None of this needs a permission, a timer or the network.

- **Icon styles as picture cards**: Settings → General shows holzBar's own menu bar icon as a row of cards: the holzBar logo, **Chevron**, **Arrow**, **Eye**, **Dots**, **Grid**, **Panel**, **Dot**, and the older **Door**, **Ice Cube** and **Sunglasses**, with **Choose image…** for an image of your own. Each style has a look for hidden and for shown items. **No icon** replaces the old switch *Show holzBar icon*: the settings are the same, and a style you chose before stays stored. Without the icon, Settings stays one step away: open holzBar again from Finder, Launchpad or Spotlight, use the `holzbar://settings` link, or use a hotkey you set for the search or the command palette. On macOS 27 the icon still appears for the dot that marks a microphone or camera in use.
- **Short names in the search**: type `bt`, `wlan`, `dnd`, `vol`, `bat`, `cc`, `tm` and about fifty more short names to find Bluetooth, Wi-Fi, Focus, Sound, Battery, Control Center, Time Machine and the like. The table also holds the names the system items carry in the languages holzBar speaks, so `bat` finds *Akku* and *バッテリー* as well. A short name ranks a little below an item you typed the real name of, and the typed text still matches as before, typos included.
- **The search puts what you open first**: an item you open from the search ranks higher the more often and the more lately you did, and with nothing typed the items of a section you opened come first. The favour is a bonus on the match, not a replacement for it: a favourite beats a slightly better match, never a much better one. holzBar keeps one count per item and day for 30 days (the same small counters as the usage suggestions, in a file of their own: mode 0600, not backed up, in no export, snapshot or log), reads the file only when the search or the setting is shown, and writes it only when you open an item. **Items you open come first** in Settings → Menu Bar Layout, under **Search**, has **Forget**, which deletes the file. Only an open from the search counts, never a click in the menu bar.
- **Six more languages**: Spanish, Brazilian Portuguese, Japanese, Simplified Chinese, Korean and Russian join English, German, French, Italian and Romansh, so holzBar speaks 11 languages. Every text, the permission prompts and the Shortcuts phrases are translated; holzBar follows your Mac's language.
- **Picture cards where a choice looks like something**: the animation, the holzBar Shelf's **Style** (attached or floating) and **Layout** (row, grid or column), the menu bar's **Shape Kind** in Menu Bar Appearance and the icon above are small pictures with a name under them, one selected at a time, instead of menus. A choice that is only words, or has many options, stays a menu. The groups of the General pane carry titles (Startup, Menu Bar Icon, holzBar Shelf, Showing Items, Displays, Rehiding, Item Spacing), and the note under the Displays group sits below its card like the other notes. Nothing about what the settings do has changed.

## New in 0.0.12

0.0.12 is out; see its [release notes](release-notes/v0.0.12.md).

- **Apple Items** (macOS 27): an optional module in Settings → Modules, off until you switch it on, with no permission beyond Accessibility. Hide the **clock**, **Control Center**, **Wi-Fi** or the **battery** with a switch each: the item is gone while the hidden items are hidden and comes back when you show them; nothing is hidden while the holzBar Shelf is on, and while one is hidden Control Centre's camera and microphone indicator is not shown (holzBar's dot covers the microphone and the camera). Add up to six **replacement items**, icons of holzBar's own with a symbol you choose, that open an Apple item you picked from the bar, so you can hide its application and keep the item one click away. See the [macOS 27 notes](macos27.md#apple-items).
- **Notch hub**: an optional module in Settings → Modules, under Notch, off until you switch it on and costing nothing while it is off. It is a panel that hangs from the notch, or from the top centre of a display without one, and needs no permission. It opens when the pointer rests at the notch for a quarter of a second (**Open on hover**, on by default) and with a hotkey you set under Settings → Hotkeys. A hub that hover opened closes 0.4 seconds after the pointer has left it and the notch; any hub closes on Esc, on a click outside and when the Space or the displays change. It does not open in a fullscreen space, with the menu bar hidden by the system, or while the screen is mirrored or shared, and **Show the hub on** limits it to all displays, the built-in display or displays with a notch. It has an icon strip with the Overview first and the modules you switched on after it (five tabs show, the rest sit in a More menu), the Overview with a card for each module that has one, and status pills and a settings button beside the notch. It is always dark, uses glass on macOS 26 and later, and follows Reduce Motion, Reduce Transparency and Increase Contrast. The Overview is empty and says so until you switch on a module; the first ones are Timers, Calendar, Live activities and File drop (see [New in 0.0.14](#new-in-0014)), and more come in later releases.
- **Smart Categories**: the search shows category buttons under its field, **All** and then the categories your items fall into: System, Network, Media, Communication, Productivity, Developer, Cloud and Backup, Utilities and Other. One click lists only the items of that category, and Option with the left or right arrow moves from one button to the next; the choice starts at All each time the search opens. A category is a hint for browsing, worked out from static facts on your Mac (the item's identifier and name, the category its application declares in its own `Info.plist`, and the short tables Tidy Up uses), so it is best-effort: an app that declares no category and that holzBar does not know is under Other. Nothing is moved or hidden by a category, nothing is recorded or sent, and with **Smart Categories** off in Settings → Menu Bar Layout (it is on by default) the buttons are gone, nothing is classified and no application is read.
- **Floating Shelf**: in Settings → General the holzBar Shelf has a **Style**, Attached (the default, hanging directly below the menu bar as before) or Floating. A floating Shelf is a bar of its own, a pill for one row and a rounded panel for a grid or a column, 8 points below the menu bar with a hairline and a soft shadow, in the menu bar's colour so the item pictures stay readable; Reduce Transparency and Increase Contrast give it an opaque fill and a visible border. **Location** now also offers **Screen edge**, which puts the Shelf at the right edge of the screen, and with **Mouse pointer** a floating Shelf hangs below the pointer wherever it is (also when you open it with its hotkey), above it near the bottom of the screen. The Shelf keeps the place it opened at while it is open. Items, keyboard use, VoiceOver actions, closing and the notch rules are the same in both styles. It needs no permission and nothing runs for it.
- **Glass command palette**: the command palette has the same glass look as the item search and the hints panel.

## New in 0.0.11

0.0.11 is out; see its [release notes](release-notes/v0.0.11.md).

- **Smooth show and hide** (macOS 26 only): with **Animate showing and hiding** on in Settings → General (the default), hidden menu bar items slide in and out in about 0.18 seconds instead of appearing at once. The state changes first and the slide only draws it, so nothing is delayed; a quick show and hide cancel each other instead of queuing. It never runs with Reduce Motion on, while you drag an item or with the holzBar Shelf in use (there the Shelf fades instead). The setting is shown on macOS 26 only: macOS 27 animates its own bar (see [macOS 27 notes](macos27.md#show-and-hide-animation)), and macOS 14 and 15 keep the instant change. It needs no permission, no timer while idle and no network; the one short task lives only while a slide runs. Since 0.0.13 the setting is the **Smooth** card of **Animation** (see [Behaviour and the layout editor](#behaviour-and-the-layout-editor)).
- **Glass Search and Hints panels**: the item search and the hints panel (open an item by letter) have the new glass look, with key caps for the hint letters.
- **Design tokens**: the type sizes and spacing in Settings come from one shared set of values; nothing should look different.

## New in 0.0.9

0.0.9 is out; see its [release notes](release-notes/v0.0.9.md).

**The Settings window**
- **Three sidebar groups**: Menu Bar Layout, Menu Bar Appearance and Automation; Modules; General, Hotkeys, Advanced and About.
- **Modules** is a pane that lists the optional modules, each off until you switch it on; a module's settings open under its row only while it is on. **Widgets** and **Drag in the Menu Bar** moved there from Menu Bar Layout.
- **The window ground** falls from a calm colour to a deeper one with two soft glows under the glass (flat with Increase Contrast), and Settings can shrink to 760 by 540 points.
- **Permission pills** in Advanced, the permissions window and the Screen Recording hint show "Needs <permission>" or "Permission Granted" as a small label; **key caps** draw a set hotkey in the hotkey recorder.
- **Confirmation sheets** of one design ask before a lasting change (delete a rule, a profile or all snapshots, remove a widget, reset the appearance, revoke a permission, restore a layout, allow a script); Return is Cancel on a destructive one.
- **The strips of Menu Bar Layout** look like the menu bar of macOS: a translucent band in the colour of the real bar with a soft sheen at the top.

**Automation**
- **Command palette**: a hotkey (set it in Settings → Hotkeys) opens a Spotlight-like panel. Type to find an action, a layout profile, a mood, a rule or a menu bar item; Return runs it, Escape closes it. Abbreviations and typos work as in the item search, and starting with `>` leaves out the menu bar items. It keeps no history and needs no permission; with the Touch ID lock on it asks first, because it lists hidden items.
- **AppleScript dictionary**: `show section`, `hide section`, `toggle section`, `apply profile`, `enable rule`, `disable rule`, `enable zen mode` and `disable zen mode`, and the read-only properties `profile names`, `current profile`, `rule names`, `enabled rule names`, `zen mode` and `hidden section is shown`. Every command goes through the same decision as a `holzbar://` URL command: lasting changes ask first, nothing reveals hidden items while Zen mode is on, and Zen mode does not end while the screen is shared. A script cannot create, change or delete a rule, a profile, a script or a setting, and a rule that uses a script is never turned on this way. macOS asks the calling app (Script Editor, a Shortcut) for permission to control holzBar; holzBar sends no Apple events itself.
- **Keep the Mac awake** from a hotkey and from the command palette, as well as from a rule. Sound output and Bluetooth are new rule conditions (below).
- **Sound output and Bluetooth as rule conditions**: "the Mac plays sound through …" follows the default output device with one Core Audio listener and needs no permission. "A Bluetooth device is connected" reads which of your paired devices are connected and asks macOS for the Bluetooth permission only when you add such a condition. Energy Mode has no public API on the Mac, so only Low Power Mode, which exists since 0.0.8, is a condition.
- **Moods**: save the current look of the menu bar (colours, shape, border, corners) under a name in Menu Bar Appearance, switch to it in one click, from the command palette, or with a rule ("switch to a mood"), for example by time of day or when a display is connected. At most twelve.

**The holzBar Shelf**
- **Layouts**: a row (as before), a grid of six per row, or a column; a grid and a column grow downwards and scroll after ten rows, and the arrow keys move up and down.
- **Fade in** (since 0.0.13 the **Fade** card of **Animation**): the holzBar Shelf appears in 0.15 seconds instead of at once; it never fades while Reduce Motion is on, and closing is never delayed. The bar's own items slide on macOS 26 since 0.0.11 (see above).

**Convenience**
- **Usage suggestions** (off by default): count how often you open each item, once a day at most per click, for 30 days. After 14 days holzBar suggests hiding visible items you did not open for 14 days, never the clock, the battery, Control Center, items that show a live value, apps that carry badges, holzBar's own items or items a rule controls. The counts are one file on this Mac (mode 0600, excluded from backups); they are in no export, snapshot, diagnostic or log, **View Data** shows all of it, and **Forget Everything** and turning it off delete it. A suggestion moves nothing until you click **Move to Hidden**, and a snapshot of the layout is taken first.
- **Item rules, put back by a rule**: when you move an item that a rule controls and the rule does not allow it, holzBar puts it back at the next evaluation, a few seconds after your move, and says so in a **Put Back by a Rule** section at the top of Menu Bar Layout, with an **Edit Rule…** button and an **OK** button. While the rule shows the item, a move by hand is kept as the section the item has when shown, as long as it is more visible than the hiding section. holzBar remembers the section the item had, so it returns there and not to the visible bar, also after a restart. The remembered sections stay on this Mac and are in no export, import or backup; the notices are kept in memory only and an item name never reaches a log.

## New in 0.0.8

0.0.8 is out; see its [release notes](release-notes/v0.0.8.md).

**Automation**
- **Rules** that apply a profile, reveal items, switch Zen mode or keep the Mac awake when a Wi-Fi network, an app, the time of day, the power source or Low Power Mode, a display, the network or a VPN, a camera or the microphone in use, or a script's result matches (all or any). The Wi-Fi name needs Location access, asked for only when you use it.
- **URL and Shortcuts for rules**: `holzbar://automation/enable/<name>` and `/disable/<name>` ask first, and Shortcuts can turn a rule on or off and list the rules that are active; a rule that uses a script can be turned off this way but never on. Rules are created and edited only in the settings.
- **Camera and microphone in use** as rule conditions, for example to switch Zen mode on during a call. holzBar reads only whether another app records or a camera runs, with no permission and no polling (macOS 14.2 and later).
- **Low battery and offline are rules now**: the two fixed settings of earlier versions moved from Advanced into the Automation pane; if you had them on, holzBar turned them into two rules the first time 0.0.8 started. Unlike before, unplugging a low battery shows the items again.
- **Focus filter**: add the holzBar filter to a Focus in System Settings to apply a layout profile while that Focus is on; the previous profile comes back when it ends. Whether macOS calls the filter on your Mac depends on macOS: it has been reported not to work on macOS 26.5.
- **Per-item conditions**: a rule action "Show an item only while this is true" makes one item follow a condition, for example a VPN item that is visible only while a VPN is connected. The item moves after a hold of three seconds, so a flapping condition does not move it every second; an unknown condition leaves it where it is. On macOS 27 the rule moves all items of the item's application. Make the rule from the item itself: right-click it in Menu Bar Layout and choose **Show Only When…** (VoiceOver has the same action). An item with a rule wears a small eye badge, a profile leaves it where its rule puts it, and an item has one rule.
- **Scripts** as a rule condition ("a script succeeds") or a rule action ("run a script", at the start and, if you choose "Also run it when the rule stops being true", when the rule ends). A script runs only from the folder you choose (by default `~/Library/Application Support/holzBar/Scripts`, which is a real folder that only you can write to) and only after you allowed its exact content on a sheet that names the file, its folder, its size and the start of its checksum; the content is checked again before every run, so a changed file needs a new approval. There are no arguments and no shell, and the only thing a script is told is the event, in `HOLZBAR_EVENT`, which is one of six fixed values: `rule-started`, `rule-ended`, `check`, `profile-will-apply`, `profile-did-apply` and `widget-refresh` (a script widget's refresh). A script gets 10 seconds by default (1 to 60 in the pane), then it is stopped together with what it started; at most ten condition checks and ten other runs a minute (a run that is dropped for that, or because the script still runs, is shown as skipped), and a condition is asked at most every 30 seconds. The first line of its output is shown in the pane as plain text, in memory only. A script runs as you with holzBar's permissions, and macOS asks separately before a script controls another app. Whether an allowed script can use holzBar's Accessibility and Screen Recording itself has **not been measured on a Mac yet**, so treat an allowed script as being as powerful as holzBar. Scripts, their approvals and the rules that use them stay on this Mac in a file only you can read: they are never exported, imported or synced, and an import says how many rules it left out. No URL command or Shortcut can turn on a rule that uses a script.
- **Profile hooks**: a script that runs before or after a profile is applied, for one profile or for every profile. Before hooks run first (at most five) and holzBar waits for them, each at most its time limit and all together at most a minute, then applies the profile whatever their outcome; after hooks start once the items have moved and are not waited for; applying another profile cancels one that is still waiting. A profile applied by a URL command, a Shortcut or the Focus filter runs no hooks. A hook needs an allowed script like any other, and a hook follows a renamed profile and goes with a deleted one (undoing a deletion brings the profile back without its hooks).
- **Widgets**: menu bar items of your own, an optional module in Settings, Modules that is off until you switch it on and costs nothing while it is off. On macOS 14 to 27.
  - **Seven sources, none needs a permission**: date and time, battery (percent, with or without the charging state), CPU load, memory (percent used or gigabytes used), uptime, free disk space (gigabytes or percent) and a countdown that only shows the time left until a moment you pick (no alarm, no sound, no pause). At most twelve widgets. Focus, AirDrop, media controls, fast user switching, a timer and app launchers are built-in items of the same module ([what they do](#built-in-items-and-app-launchers)).
  - **Formats are presets**, written in your language and region, with an optional symbol in front. Seconds exist for the clock only and the pane says what they cost: "Wakes the Mac every second while visible." A widget keeps one fixed width for its format, so the text never moves the items beside it; a value that cannot be read shows an en dash and VoiceOver says "unavailable".
  - **A Shortcut button** shows a title or a symbol and runs a Shortcut chosen by typing its name, through the Shortcuts app. holzBar shows nothing of its own, and a Shortcut that does not exist shows only the Shortcuts app's own error. A text widget has no click action.
  - **A script widget** shows the first line of the output of a script you allowed, cleaned to plain text (at most 80 characters) in a narrow, medium or wide fixed width with an optional symbol; a longer line is cut with an ellipsis, and a script that fails, times out, is empty or is not allowed shows an en dash. You choose the script by its name from your scripts folder, and it must be allowed in Automation, Scripts first: the pane says so and takes you there. It runs when the widget appears (a reveal, an unlock, the start of holzBar) and when you click it, and again on the system events that an enabled automation rule follows (such as power, apps, displays, the network, the Wi-Fi name, or camera and microphone use); with no such rule it runs only when it appears and on a click. It never runs on a timer and never while the widget is hidden, or while the Mac is asleep or locked, and at most every 30 seconds per widget (your own click or a new choice skips that wait) and ten widget runs a minute. The script is told `HOLZBAR_EVENT=widget-refresh` and nothing else, and runs under every rule of Scripts above. Which script a widget runs is kept on this Mac only: it is never exported, imported or shared, so an imported script widget says "Choose a script".
  - **Energy**: a widget refreshes only while it is visible, never while it is hidden, or while the Mac is asleep or locked; it refreshes once when it is shown again. The battery is read from power events, not by a timer, and Low Power Mode doubles the polling intervals (CPU load 5 s, memory 10 s, uptime 1 min, free disk space 5 min by default).
  - **Part of the bar like any item**: widgets can be moved between sections in Menu Bar Layout, are kept in layout profiles, and appear in the holzBar Shelf, the search, groups and hints (a Shortcut button runs from there too). On macOS 27 holzBar hides a widget itself, by collapsing it; "Show When It Changes" does nothing for a widget there.
  - **Settings export** carries the widgets without Shortcut names or scripts, so an imported button says "Choose a Shortcut" and an imported script widget says "Choose a script"; shared profiles never carry a widget. Each widget has a VoiceOver label and value.

**Safety and convenience**
- **Layout snapshots** taken automatically when the bar settles, once a day and before a profile rearranges it, with a preview and a one-click restore that can be undone; the newest ten kept by default (you can change the number), on this Mac only.
- **Share a profile** as a small validated file: only the applications you leave checked and their sections, no display, Wi-Fi, hotkey or other setting, and no code. Importing adds the profile to the list and moves nothing until you apply it. Double-clicking a `.holzbarprofile` in Finder is not set up yet; use Import Profile in Menu Bar Layout.
- **Touch ID or password** to show hidden items, in Advanced: hover, click, hotkeys, the Shelf, the search, URLs and Shortcuts ask once, then a minute of grace; your own safety rules (low battery, offline, rules, items you chose) do not ask. Turning it off asks too. It keeps a bystander away from your hidden items; it is not protection against someone who knows your password.
- **Revoke permissions in Settings**: a button per permission that withdraws it again (for holzBar's own entry only) or opens the right System Settings pane, so you never have to hunt for it.
- **Copy diagnostics**: in About, a report of versions and counts (and, on macOS 27, the state of its overflow button) you read before you copy it; no names of items, apps, profiles or networks, no paths; nothing is sent.
- **Tidy Up assistant**: proposes which visible items to hide from static facts only (system extras, the app's category, a short list of known helpers); live values, the clock, the battery and apps with messages stay. You decide item by item, the arrangement is kept as a snapshot first, and nothing is recorded. Offered once after the first launch when nothing was arranged yet, and any time from Menu Bar Layout.
- **Works without Screen Recording**: the Menu Bar Layout pane, the Shelf and the search show app icons instead of live pictures, with an offer to allow Screen Recording for the pictures (a window asks once, the first time the Shelf opens; Settings → Advanced allows and revokes it).
- **System items pinned visible** (macOS 26 and earlier): profiles, restored layouts and rules leave the clock, battery, Wi-Fi, Control Center and sound where they are; you can still move them yourself.
- **Drag in the menu bar** (macOS 26 and 27): an optional module in Settings, Modules, off until you switch it on. Drag an app's item sideways to move it, with no ⌘ Command; on macOS 26 drag it past holzBar's divider into the hidden or always-hidden section. On macOS 27 drop it on the holzBar icon to hide its app, or drag a hidden app's item elsewhere while it shows to make the app visible again; the order within a section is up to macOS. On macOS 26 every drop is kept like a move in Menu Bar Layout; on macOS 27 only a drop that hides or shows an app is, and a plain reorder is macOS's own. A click opens the item's menu when you release it; Apple's own items, holzBar's items, ⌘, ⌃ and ⌥ clicks and double-clicks work as before. holzBar watches only the left mouse button, only while the module is on, with no permission beyond Accessibility.

**Polish**
- A [keyboard and VoiceOver checklist](accessibility-checklist.md) to run on a Mac; holzBar makes no accessibility claim until it was run.

## macOS 27

macOS 27 no longer draws menu bar items as separate windows — `MenuBarAgent` draws them all into one bar. holzBar ships a dedicated backend for it (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)):

- **Hiding** via assessment-mode assertions, with per-app sections
- **Item discovery** through Accessibility instead of window lists
- **holzBar Shelf** with real item images and even spacing
- **Layout editor** that assigns apps to sections — your old layout is carried over on first launch
- **A second display** works like the first: hovering and clicking items there opens their menus instead of revealing hidden items
- **Notched MacBooks**: holzBar's icon is kept out from under the notch, and items folded beside the notch come back on a wider display
- **No screenshots under the bar**: no screen-recording indicator when items are shown or hidden, and a click on the clock no longer flashes hidden items
- **Paired shape** (the former split shape) that follows the icons, on every display
- **Menu bar styles**: Single, Paired, the Apple-logo shape, outlines and gradients as on macOS 26; Sections is not offered. See [macOS 27 notes](macos27.md#menu-bar-styles)
- **macOS 27's own overflow button**: while macOS shows its folded items expanded beside the notch, the holzBar Shelf does not list them a second time; in any doubt it lists them as before. See [macOS 27 notes](macos27.md#macos-27s-own-overflow-button)
- **Drag in the menu bar**: with the optional module on, drag an item without ⌘ to move it as macOS allows, or drop it on the holzBar icon to hide its app. See [macOS 27 notes](macos27.md#drag-items-in-the-menu-bar)
- **Apple Items**: hide the clock, Control Center, Wi-Fi or the battery, and keep an Apple item one click away with a replacement icon of holzBar's own. See [macOS 27 notes](macos27.md#apple-items)
- **A dot on holzBar's icon** while hidden items are concealed and an app uses the microphone (orange) or the camera (green), in place of Control Centre's indicator. On by default in Settings → General, with no permission; the icon appears for the dot even when the icon is set to **No icon**

**Known limitations on macOS 27**

- holzBar cannot reorder items on the bar by itself: Menu Bar Layout, profiles and rules only assign sections. Dragging an item yourself (with ⌘, or without it while **Drag in the Menu Bar** is on) places it where macOS lets it go.
- Opening a system item (clock, battery, Wi-Fi) while hidden items are concealed adds ~150 ms.
- **Control Centre's privacy indicator is hidden while items are hidden.** Its indicator for the camera, the microphone and screen recording is not shown while holzBar hides any item, including a system item you hid with Apple Items, and comes back while holzBar hides no item. holzBar's dot covers the microphone and the camera, not screen recording; the small green dot beside the clock still shows the camera. See [Permissions](privacy-and-permissions.md#permissions).
- Coming from 0.0.5 or earlier, macOS asks for Accessibility once more. If holzBar is stuck on the permissions window, click **Reset and Grant Again**.

## Planned next

**None of this is available yet.** Every release is published as numbered betas first. Plans can change; items marked *spike* are only built if a short test shows it works well and safely.

### After 0.0.9 (release not fixed yet)

**Nothing here is in 0.0.9.**

**Automation**
- More **App Intents** for Shortcuts and Siri, and a **focus mode** hotkey that hides everything except chosen items.

**Convenience**
- **Smooth show and hide** of the bar itself on macOS 14, 15 and 27: macOS 27 animates its own bar, and macOS 14 and 15 keep the instant change. (macOS 26 has it since 0.0.11, see above; the holzBar Shelf fades in since 0.0.9.)

**Polish**
- A Control Center control to toggle Zen mode or apply a profile. *Spike, optional.*

### 1.0.0

- **Settings sync between your Macs** through any folder they sync (iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing, a network share), **redesigned from scratch**, designed not to lose or silently overwrite a change.
- **Modules for the notch hub**: the hub itself is built (see [New in 0.0.12](#new-in-0012)); the first modules, Timers, Calendar, Live activities and File drop, are in (see [New in 0.0.14](#new-in-0014)); the modules planned for it are Now Playing and lyrics, display controls and AirPods and accessory alerts. Notifications in the hub only if a feasibility test shows it can be done; macOS has no public API for it.
- Up to **20 languages**, with a review process for the translations.

### 1.1.0: system monitor

CPU, GPU, memory, network, disk and power readouts in the menu bar and in the hub, connected devices with battery levels, and alerts when CPU, temperature or disk cross a limit.

### 1.2.0: launcher and tools

An app launcher and search panel, file search through Spotlight, a calculator and unit converter (no currencies, because that needs the network), an emoji picker (no GIFs), text snippets, quick actions for system commands and Shortcuts, a radial menu, a scratchpad, and a tool to end a process or the one using a port.

### 1.3.0: clipboard

Clipboard history (opt-in, local, password managers excluded, erasable), paste as plain text, cut and paste in Finder, and clean URLs without tracking parameters.

### 1.4.0 and later (order open)

Window management (app switcher, Dock previews, layouts), mouse and keyboard tweaks (scroll direction, smooth scrolling, no acceleration, mouse button shortcuts, trackpad middle click, shortcut management), sound (per-app volume, output switcher, microphone mute, music app blocker), energy and display (extra brightness, display tools, cleaning mode), capture (screenshots, text from the screen, screen and GIF recording, colour picker, measure, QR, camera preview), system tools (cleanup scan, app uninstaller, Homebrew manager, wallpaper tools, focus timer) and text tools with on-device AI (translation, dictation, grammar fix, agent and workflows).

### Principles for every module

Each module is optional and costs nothing while it is off. It asks for its permission only when you switch it on, and says why. No module uses the network. **All AI features run on your Mac with Apple's own on-device models.** Cloud features, weather, speed tests, fan control, a charge limit and a hosts-file blocker are not planned.

The comparison tables in [comparison.md](comparison.md) mark these with 🔜 and the release.

## Gallery

Screenshots of holzBar 0.0.9 in dark mode.

<p align="center"><img src="../Resources/Screenshots/settings-general.png" alt="holzBar settings, General pane: Launch at login, the holzBar icon, the holzBar Shelf with its location, the displays it is used on and items covered by the notch, showing hidden items on click, hover or scroll, and automatic rehide with the Smart strategy" width="760"></p>

<table>
<tr>
<td width="50%" valign="top"><b>Hidden</b> — only holzBar's dot in the menu bar<br><img src="../Resources/Screenshots/menu-bar.png" alt="The right side of the menu bar with holzBar's dot; the hidden items are collapsed"></td>
<td width="50%" valign="top"><b>holzBar Shelf</b> — hidden items below the menu bar<br><img src="../Resources/Screenshots/shelf.png" alt="The menu bar with the holzBar Shelf open below it, showing the hidden items"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Menu</b> — right-click the dot for settings, search, Zen mode and updates<br><img src="../Resources/Screenshots/menu.png" alt="holzBar's menu: holzBar Settings…, Search Menu Bar Items, Show Hidden Section, Zen Mode, How to Update…, Quit holzBar"></td>
<td width="50%" valign="top"><b>Rehide and spacing</b> — automatic rehide and item spacing <sub>BETA</sub><br><img src="../Resources/Screenshots/settings-spacing.png" alt="holzBar settings, General pane further down: items covered by the notch, show on click, hover or scroll, automatic rehide with the Smart strategy, the menu bar item spacing slider marked BETA, and on macOS 27 the note that the camera and microphone indicator is hidden with the dot setting"></td>
</tr>
</table>

<table>
<tr>
<td width="50%" valign="top"><b>Layout</b> — drag items into sections, with profiles, groups and spacers<br><img src="../Resources/Screenshots/settings-layout.png" alt="holzBar settings, Menu Bar Layout pane: the Visible and Hidden sections with the menu bar items, Tidy Up, Usage Suggestions and the layout profiles"></td>
<td width="50%" valign="top"><b>Appearance</b> — moods, tint, shadow, border, shapes, a black bar and rounded screen corners<br><img src="../Resources/Screenshots/settings-appearance.png" alt="holzBar settings, Menu Bar Appearance pane: Moods, dynamic appearance, Tint, Shadow, Border, Shape Kind, Black menu bar and Round the screen corners"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Hotkeys</b> — a shortcut for every frequent action, profile and item<br><img src="../Resources/Screenshots/settings-hotkeys.png" alt="holzBar settings, Hotkeys pane: hotkeys for the hidden section, the search, opening an item by letter, the layout profile, the holzBar Shelf, app menus, auto-rehide and Zen mode, each with Record Hotkey"></td>
<td width="50%" valign="top"><b>Advanced</b> — new items, delays, Zen mode, Touch ID lock and settings backup<br><img src="../Resources/Screenshots/settings-advanced.png" alt="holzBar settings, Advanced pane: where new items go, the secondary context menu, the hover delay, hiding opened items again after 15 seconds, opening hidden items in the menu bar, Zen mode while the screen is shared, Touch ID or password before showing hidden items, settings Export… and Import…, and the permissions"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Layout, further down</b> — usage suggestions, profiles, groups, spacers and the layout history<br><img src="../Resources/Screenshots/settings-layout-more.png" alt="holzBar settings, Menu Bar Layout pane further down: Usage Suggestions, the home profile with Apply, Bind, Import Profile and Save Current Layout, Groups with New Group, Spacers, and Layout History with 8 snapshots"></td>
<td width="50%" valign="top"><b>Automation</b> — rules, scripts and profile hooks<br><img src="../Resources/Screenshots/settings-automation.png" alt="holzBar settings, Automation pane: the Scripts folder with Choose Folder and Open Scripts Folder, profile hooks, and Add Rule"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Modules</b> — widgets and dragging in the menu bar, each with its own switch<br><img src="../Resources/Screenshots/settings-modules.png" alt="holzBar settings, Modules pane: Widgets switched on with a CPU load and a free disk space widget, and Drag in the Menu Bar switched off"></td>
<td width="50%" valign="top"><b>Permissions</b> — what holzBar has, with Revoke<br><img src="../Resources/Screenshots/settings-advanced-permissions.png" alt="holzBar settings, Advanced pane, the end: Back up or move your settings with Export and Import, and the permissions Accessibility and Screen Recording, each shown as Permission Granted with a Revoke button"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>First launch</b> — holzBar asks only for Accessibility and says why<br><img src="../Resources/Screenshots/permissions.png" alt="holzBar's Permissions window on the first launch: Accessibility with what holzBar needs it for, Grant Permission and Reset and Grant Again; Screen Recording marked optional with Grant Permission; Quit and a disabled Continue"></td>
<td width="50%" valign="top"><b>Ready</b> — Accessibility granted, Screen Recording optional<br><img src="../Resources/Screenshots/permissions-granted.png" alt="holzBar's Permissions window after Accessibility was granted: Accessibility shows Permission Granted, Screen Recording still offers Grant Permission, and Continue is enabled"></td>
</tr>
</table>
