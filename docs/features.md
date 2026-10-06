# Features

<table>
<tr>
<td valign="top" width="50%">

#### Menu bar items
- ✅ Hide items in a hidden and an always-hidden section
- ✅ Show on hover, click or scroll (trackpad **and mouse wheel**)
- ✅ Automatic rehide
- ✅ Drag-and-drop layout editor
- ✅ **Layout profiles** — "Work", "Home", … one click, hotkey or URL away
- ✅ **Profiles bound to a display or a Space** — applied when you connect the display or switch to the Space
- ✅ **Groups** (folders) — several items behind an icon of their own, in a colour and with a symbol or image of your choice
- ✅ **Item images of your choice** — give any item its own picture, or its app's icon; without Screen Recording, the holzBar Shelf and the search show app icons
- ✅ **Spacers** — empty items of adjustable width
- ✅ **Choose where new items appear**
- ✅ **Keeps items in their section after app updates, title changes and display changes**
- ✅ Search menu bar items — by abbreviation ("cc" for Control Centre) and despite typos
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

#### Appearance
- ✅ Tint, shadow, border, rounded and split shapes
- ✅ **Black menu bar that hides the notch**
- ✅ **Rounded screen corners**
- ✅ **Dashed and dotted borders**
- ✅ **Tints from the wallpaper or the accent colour, and the system's glass** <sub>glass on macOS 26 and later</sub>

</td>
</tr>
<tr>
<td valign="top" width="50%">

#### Automation
- ✅ **Show hidden items when the battery is low or the network drops**
- ✅ **Zen mode** — one hotkey, menu item, URL or Shortcuts action keeps hidden items hidden; optionally on while the screen is mirrored or shared, without any permission
- ✅ **Shortcuts actions** — Zen mode, show or hide a section, apply a profile, open an item by name, search
- ✅ **`holzbar://` URL commands** and [Raycast script commands](../Integrations/Raycast)
- ✅ Hotkeys for sections, search, the holzBar Shelf, app menus, **auto-rehide**, **a quick peek**, **Zen mode**, **each layout profile** and **each menu bar item** — a combination another holzBar hotkey already uses moves only when you choose **Replace**

</td>
<td valign="top" width="50%">

#### Settings
- ✅ **Export and import** all settings
- ✅ **Sync between Macs** through iCloud Drive or any folder your Macs sync (Nextcloud, Dropbox, OneDrive, Syncthing, a network share) — changes from another Mac arrive as soon as the folder delivers them, with no polling; holzBar asks before it replaces either Mac's settings ([details](#settings-sync))
- ✅ **Imports your Ice settings** on first launch
- ✅ **Alerts in Settings are sheets** on its window, so holzBar keeps working while one is open
- ✅ Launch at login
- ✅ **English, German, French, Italian and Romansh** — holzBar follows your Mac's language; choose another one for holzBar alone in System Settings → General → Language & Region → Applications

</td>
</tr>
</table>

## Settings sync

- **A quiet hint, never a dialog.** Changes from another Mac wait as **Settings changed on another Mac** with **Restart**, in Settings → Advanced and at the top of holzBar's menu.
- **holzBar asks before it replaces settings.** When both Macs changed their settings, or a Mac joins a folder that holds another Mac's different settings, the hint reads **Choose Settings…** and holzBar asks which settings to use, in a sheet on the Settings window. It never overwrites another Mac's settings unasked. It also asks about another Mac's change dated before this Mac's last sync, as a clock running behind leaves it, and **Keep This Mac's Settings** replaces only the settings it asked about: settings that arrive while the question is open are asked about too, whatever their date.
- **The launch never waits for the cloud.** holzBar waits at most a second for the sync file and checks a file that is not on this Mac yet after launch.
- **Each macOS version keeps its own layout.** A Mac on macOS 26 and one on macOS 27 never compare their layouts or ask about them; each passes the other's on unchanged, and settings a Mac lacks are kept.
- **A network share is used only while it is mounted**; holzBar never mounts it itself. Until it is, Settings → Advanced shows "The sync folder cannot be found", and syncing picks up again by itself once the share is mounted.
- **Only your changes count.** holzBar's own placement of new menu bar items never turns **Restart** into **Choose Settings…** and never shows a hint on another Mac. It is not synced by itself: it goes along with your next layout change, or with any other change of yours when no other Mac has seen the item yet. Layout changes you make (in the Layout pane, by Command-dragging, by applying a profile or by importing settings) count; a Command-click that moves nothing does not, nor does a profile applied again without changing the layout. Before macOS 27, holzBar records where macOS put a new item as its own placement, so only moving an item counts, and it never records its own placement over a section you saved meanwhile. It also compares the bar with the one it last read before you started arranging: your first move of an item counts even when holzBar had not saved it yet, and an item macOS moved before that, as on a display change or wake, keeps its saved section instead of being saved as your arrangement. **Restart** right after a Command-drag asks which settings to use, so the move is not lost.
- **A Mac that joins takes the folder's layout** for its macOS version, unless you rearranged its items since it last synced; then holzBar asks if the layouts differ. While holzBar runs, the layout arrives with a restart the hint offers.
- **Another Mac's arrangement is never replaced by holzBar's own.** Only a layout you rearranged on this Mac is written over another Mac's. **Keep This Mac's Settings** keeps the other Mac's arrangement when you did not rearrange this Mac's, and this Mac takes it with the restart the hint offers, or at the next launch, also after sync was turned off and on before it. If you rearrange this Mac's menu bar before then, holzBar asks first, also after sync was turned off and on or the same folder chosen again. Meanwhile your other changes keep syncing, and the restart takes in only the layout. An older version of this Mac's own settings that a sync app brings back is never taken in: holzBar writes this Mac's layout over it with your next change. The other macOS version's layout in a version older than this Mac's last sync, this Mac's own or another Mac's, is never taken in either, and holzBar passes it on only as a copy that updated Macs ignore, so the Macs of that version keep their arrangement. A Mac that joins again asks about another Mac's older version whose arrangement it never took, instead of taking it as synced.
- **Macs still on 0.0.7 beta 1** keep their menu bar layout: an updated Mac passes it on unchanged and asks before your rearrangement replaces it. An old copy of this Mac's own layout that a beta 1 Mac writes back is replaced without a question; holzBar remembers the last 64 layouts it synced, and keeps recognising a copy that a beta 1 Mac keeps writing back. Another Mac's arrangement that **Keep This Mac's Settings** kept counts as this Mac's only once this Mac took it in. While a Mac of the other macOS version is still on beta 1, a sync file that is deleted, damaged, recreated or rewritten without that version's layout gets the updated Mac's copy of it, which may be older and which the beta 1 Mac applies at its next launch: update that Mac first.
- **The sync file stays under 1 MB.** holzBar never writes a larger one, such as with a large custom icon, and leaves one alone that another Mac made larger, also one a Mac still on 0.0.7 beta 1 wrote; sync then stops until the settings are smaller.
- **A deleted or damaged sync file** is written again by the next Mac with a change. Each updated Mac records which version its write was based on, so a Mac whose last change is not in the new file asks which settings to use instead of taking it, and a version that waits for you stays offered when the file goes away. While this Mac keeps another Mac's arrangement it has not taken in, it writes its own layout over a missing file only as a copy, so that Mac keeps its arrangement. A Mac still on 0.0.7 beta 1 records nothing: its write over a deleted or damaged file is taken without asking, as before.

## macOS 27

macOS 27 no longer draws menu bar items as separate windows — `MenuBarAgent` draws them all into one bar. holzBar ships a dedicated backend for it (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)):

- **Hiding** via assessment-mode assertions, with per-app sections
- **Item discovery** through Accessibility instead of window lists
- **holzBar Shelf** with real item images and even spacing
- **Layout editor** that assigns apps to sections — your old layout is carried over on first launch
- **A second display** works like the first: hovering and clicking items there opens their menus instead of revealing hidden items
- **Notched MacBooks**: holzBar's icon is kept out from under the notch, and items folded beside the notch come back on a wider display
- **No screenshots under the bar**: no screen-recording indicator when items are shown or hidden, and a click on the clock no longer flashes hidden items
- **Split shape** that follows the icons, on every display
- **A dot on holzBar's icon** while hidden items are concealed and an app uses the microphone (orange) or the camera (green), in place of Control Centre's indicator. On by default in Settings → General, with no permission; the icon appears for the dot even when **Show holzBar icon** is off

**Known limitations on macOS 27**

- Items can't be reordered on the bar itself — only assigned to sections.
- Opening a system item (clock, battery, Wi-Fi) while hidden items are concealed adds ~150 ms.
- **Control Centre's privacy indicator is hidden while items are hidden.** Its indicator for the camera, the microphone and screen recording is not shown while holzBar hides any item, and comes back while holzBar hides no item. holzBar's dot covers the microphone and the camera, not screen recording; the small green dot beside the clock still shows the camera. See [Permissions](privacy-and-permissions.md#permissions).
- Coming from 0.0.5 or earlier, macOS asks for Accessibility once more. If holzBar is stuck on the permissions window, click **Reset and Grant Again**.

## Planned for 0.0.7 "Automation"

**None of this is available yet.** It is the plan for the next release, which is published as numbered betas first. Plans can change; items marked *spike* are only built if a short test shows it works well and safely.

**Automation**
- **Rules** that apply a profile, reveal items or switch Zen mode when a Wi-Fi network, an app, the time of day, the power source, a display or a Focus matches (all or any). The Wi-Fi name needs Location access, asked for only when you use it. *Spike first: the Focus filter.*
- **Per-item conditions**: show a single item only while a condition holds, for example while a VPN is connected.
- **Scripts** as a rule condition or action: only from a folder you choose, pinned by hash, run only after you confirm.
- **Widgets**: menu bar items of your own (text from permission-free sources, a Shortcut button); script widgets come last.
- **AppleScript dictionary** to show, hide, switch profiles and turn rules on or off.
- **Command palette**: one hotkey opens a panel to run any holzBar action.

**Safety and convenience**
- **Layout snapshots** taken automatically, with a one-click restore.
- **Share a profile** as a small validated file; it never contains personal data or code.
- **First-launch assistant** that proposes an arrangement from static facts, skippable and re-runnable.
- **Usage suggestions** (opt-in): suggests hiding items you never click; counters stay on your Mac and can be erased with one click.
- **Touch ID or password** to show hidden items.
- **Smooth show and hide**, respecting Reduce Motion.
- **Copy diagnostics**: a redacted report you read before you copy it; nothing is sent.

**macOS 27 and polish**
- Cooperation with macOS 27's own overflow button, so items are not shown twice.
- Glass tint and Shelf follow Reduce Transparency (and the macOS 27 slider, if a public signal exists). *Spike.*
- Reordering in the Layout pane with SwiftUI's new reordering API, only if clearly better. *Spike.*
- A Control Center control to toggle Zen mode or apply a profile. *Spike.*
- A keyboard and VoiceOver audit of every pane.
- Swift 6.4 clean-up without behaviour changes.

The "holzBar vs. Ice and Thaw" table above marks these with 🔜.

## Gallery

<p align="center"><img src="../Resources/Screenshots/settings-general.png" alt="holzBar settings, General pane: Launch at login, the holzBar icon, the holzBar Shelf with its location, the displays it is used on and items covered by the notch, showing hidden items on click, hover or scroll, and automatic rehide with the Smart strategy" width="760"></p>

<table>
<tr>
<td width="50%" valign="top"><b>Hidden</b> — only holzBar's dot in the menu bar<br><img src="../Resources/Screenshots/menu-bar.png" alt="The right side of the menu bar with holzBar's dot; the hidden items are collapsed"></td>
<td width="50%" valign="top"><b>holzBar Shelf</b> — hidden items below the menu bar<br><img src="../Resources/Screenshots/shelf.png" alt="The menu bar with the holzBar Shelf open below it, showing the hidden items"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Menu</b> — right-click the dot for settings, search, Zen mode and updates<br><img src="../Resources/Screenshots/menu.png" alt="holzBar's menu: holzBar Settings…, Search Menu Bar Items, Show Hidden Section, Zen Mode, How to Update…, Quit holzBar"></td>
<td width="50%" valign="top"><b>Rehide and spacing</b> — automatic rehide and item spacing <sub>BETA</sub><br><img src="../Resources/Screenshots/settings-spacing.png" alt="holzBar settings, General pane further down: the holzBar Shelf on all displays and items covered by the notch, show on click, hover or scroll, automatically rehide with the Smart strategy, the menu bar item spacing slider marked BETA, and on macOS 27 the note that the camera and microphone indicator is hidden"></td>
</tr>
</table>

<table>
<tr>
<td width="50%" valign="top"><b>Layout</b> — drag items into sections, with profiles, groups and spacers<br><img src="../Resources/Screenshots/settings-layout.png" alt="holzBar settings, Menu Bar Layout pane: the profile home with Apply and Bind, Save Current Layout…, groups with New Group…, spacers, and the Visible and Hidden sections with the menu bar items"></td>
<td width="50%" valign="top"><b>Appearance</b> — tint, shadow, border, shapes, a black bar and rounded screen corners<br><img src="../Resources/Screenshots/settings-appearance.png" alt="holzBar settings, Menu Bar Appearance pane: Dynamic appearance, Tint, Shadow, Border, Shape Kind, Black menu bar and Round the screen corners"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Hotkeys</b> — a shortcut for every frequent action, profile and item<br><img src="../Resources/Screenshots/settings-hotkeys.png" alt="holzBar settings, Hotkeys pane: hotkeys for the hidden section, the search, opening an item by letter, the layout profile home, the holzBar Shelf, app menus, auto-rehide and Zen mode, each with Record Hotkey"></td>
<td width="50%" valign="top"><b>Advanced</b> — new items, delays, Zen mode, automatic reveal and settings backup<br><img src="../Resources/Screenshots/settings-advanced.png" alt="holzBar settings, Advanced pane: the always-hidden section, where new items go, the secondary context menu, the hover delay, hiding opened items again after 15 seconds, opening hidden items in the menu bar, Zen mode while the screen is shared, showing hidden items when the battery is low or the network is lost, and settings Export… and Import…"></td>
</tr>
<tr>
<td width="50%" valign="top"><b>Sync and permissions</b> — settings sync through any folder your Macs sync, and the state of every permission<br><img src="../Resources/Screenshots/settings-advanced-sync.png" alt="holzBar settings, Advanced pane further down: showing hidden items automatically, Export… and Import…, Sync settings between your Macs with Turn On… through iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing or a network share, and Accessibility and Screen Recording both granted"></td>
<td width="50%" valign="top"></td>
</tr>
</table>
