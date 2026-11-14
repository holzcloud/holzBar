# Accessibility checklist

holzBar's screens use system controls with names and keyboard access. 0.0.8 adds names, headings and values for VoiceOver to the newer screens, Escape in every sheet, Increase Contrast and Reduce Motion handling in Settings and the Layout pane, a focus ring in the holzBar Shelf and keyboard access to the colour stops of a gradient. Run this checklist on macOS 26 and 27 and report what fails in an [issue](https://github.com/holzcloud/holzBar/issues).

Accessibility *support* (this page) is not the Accessibility *permission* holzBar asks for; see [Permissions](privacy-and-permissions.md#permissions).

## Before you start

- **VoiceOver**: ⌘F5 turns it on. Actions are in the VoiceOver menu (VO-⌘-Space; VO is Control-Option).
- **Full Keyboard Access**: System Settings → Accessibility → Keyboard.
- **Voice Control**: System Settings → Accessibility → Voice Control. Say "show names", then "click …".
- **Display options**: System Settings → Accessibility → Display: Reduce Motion, Increase Contrast, Reduce Transparency, Differentiate without color.
- **Language**: System Settings → General → Language & Region → Applications, or `open -a holzBar --args -AppleLanguages "(de)"` with any language code of the [Translations](translations.md) table.
- macOS has no Dynamic Type, so check the languages with the longest text instead (French, Spanish, German, Hungarian, Polish and Turkish; the length report of `python3 .github/scripts/translations.py report` lists the longest strings).

## For every screen

Screens: Settings (Layout with its bars and its list, Showing & Hiding, holzBar Shelf, Profiles & History, Appearance, Automation, Modules, General, Hotkeys, Advanced, About, and the settings search), the permissions window, the onboarding window (Introduction to holzBar), the undo notice (in Settings and under the menu bar), the Screen Recording offer, the holzBar Shelf, the search, a group's popover, the letters of Open an item by letter, the notch hub (opened by its hotkey) and its Timers, Calendar, Live activities, File drop, Display controls, Accessory alerts, Notifications and Now Playing tabs and the widened notch of its live activities, holzBar's menu and widgets in the menu bar, the What's New window.

1. **VoiceOver**: every control is read with its name, role, value and state; buttons that show only an icon are named; lists and groups are named; a switch tells its state; nothing is conveyed by colour alone.
2. **Keyboard**: Tab reaches every control, Space or Return uses it, the focus is visible, Escape closes a sheet or panel and Return runs the default button.
3. **Voice Control**: the names Voice Control shows match the visible text, so "click …" works.
4. **Reduce Motion**: nothing slides; at most a fade.
5. **Reduce Transparency**: glass becomes opaque and the text stays readable.
6. **Increase Contrast**: groups are opaque, borders and text are clearly visible.
7. **Differentiate without color**: no state is shown by colour alone.
8. **Languages**: in French, German, Polish and Hungarian (among the longest), and in Japanese or Chinese (taller lines), nothing is cut off or overlaps.
9. **Contrast**: text at least 4.5:1; large text, symbols and borders at least 3:1; in light, in dark and on glass. Measure on a screenshot with Digital Color Meter.

## Screens with special points

- **Automation rule rows**: each row is read by the rule's name; Edit is read as collapsed or expanded; the switch reads the rule's name and state.
- **Rule editor**: Add Rule puts the cursor in Name and is disabled at 50 rules. When and Then are headings. Each condition is a group read by its sentence, with a Remove Condition button. The battery level is read in percent. Weekday buttons are read by their full name, and Voice Control takes the letter or the name.
- **Scripts**: rows are read by the script's name. The approval sheet reads the file name, folder, size and the start of the checksum; Return is Cancel, Escape cancels and Allow needs a click. The same holds for the folder sheet.
- **Profile Hooks**: the title is a heading; rows are read by script; the Profile, When and Script pickers and Remove Hook read their names and values.
- **Layout History**: rows are read by date; the star reads Star or Remove Star; Restore… asks first and a restore is announced; Delete is named.
- **Tidy Up, Share Profile, Import Profile and Copy Diagnostics**: the title is a heading; Escape closes the sheet without acting; Return runs the default button. Every Tidy Up proposal is a checkbox that reads the app's name.
- **Widgets**: each widget in the menu bar is read with its source name and its value in full ("Battery, 80 percent, charging", "unavailable" when it cannot be read). A Shortcut button is read as a button with the Shortcut's name as its hint. A script widget is read as "Script" with its line, "Choose a script" while none is chosen and "Allow this script in Automation, Scripts" while the script is not allowed. In Modules the rows are read by name, Edit is read as collapsed or expanded, and the Widgets switch, Edit, Remove, Move Up and Move Down are reachable by keyboard; a widget moves with the VoiceOver actions Move Up and Move Down. A built-in item (Focus, AirDrop, media controls, fast user switching, a timer, an app launcher) is read as a button with its name (a launcher with its app's name) and a hint that says what a click does; the timer's value is the time it shows, and its end is announced.
- **Notch hub**: opened by its hotkey the hub takes the keyboard and VoiceOver reads it as "Notch hub"; each tab is read by its name, the selected one as selected, and the Left and Right arrow keys move through all of them in the order of the row; the row never has a More menu and scrolls only past 18 buttons; the Timers pill and the top other live activity beside the notch are read by their text; the settings button is read as "Settings"; Esc closes the hub. Opened by hover the hub does not take the keyboard, by design. Under Reduce Motion the hub fades; under Reduce Transparency and Increase Contrast it is opaque and its small texts are stronger; in light mode it stays dark.
- **Timers**: each timer row is read as one item with its name, its state (running, paused or done) and its remaining time, and offers the actions Pause or Resume, Restart and Remove; the preset buttons, the Length, Until and Stopwatch switch, the length field, the date and time field, the label field and the Start button are reached with Tab and have names; a refused length or moment is explained in words with a symbol, not by colour alone; a text field takes the keyboard even when the hub was opened by hover; under Reduce Motion nothing animates beyond what the system draws for the progress bar.
- **Calendar**: each event row reads its time ("Now", the start time or "All day"), its title and its end time as text; the calendar's colour dot is decorative and hidden from VoiceOver. A Join button is read as "Join the meeting" and can be reached with Tab when the hub took the keyboard; a link that cannot be joined yet shows only the service name as text. When access is missing the sentence and its button are read as text and a button. In Settings the all-day switch and the per-calendar switches are read by name and state.
- **Live activities**: when an activity starts, VoiceOver is told once what it is ("Camera in use", "Downloading"); the widened notch is read as one button with the top activity's title and, when more are going on, "+2 more"; its symbol is decorative and hidden. In the open hub each row of the Live activities tab is read as one item with its title and detail. Under Reduce Motion the notch widens at once and only the content fades; the shape is opaque black in every mode, in light mode too, and under Increase Contrast a thin line runs along its lower edge and the count badge is outlined with stronger text. In Settings the two switches under the module's row are read by name and state, and the button to System Settings by its name.
- **File drop**: each tile is read as one item with the file's name (and "Missing" when the file is gone) and offers the actions Show in Finder and Remove; Tab reaches the tiles, Return shows the focused tile in the Finder and the Delete key removes it; dragging out is a pointer action, and Show in Finder is the alternative. While a file is dragged over the tab an outline and the words "Drop to keep" show, solid and at full strength under Increase Contrast, and a fade under Reduce Motion. In Settings the two switches under the module's row are read by name and state.
- **Display controls**: each slider is an adjustable item labelled "Volume", or "Brightness" and the display's name, read with its value in percent, and moves by 5 percent with the increment and decrement actions and with the arrow keys when it has focus; the mute button is read as "Mute" or "Unmute" and selected while the sound is muted; a slider that cannot be used is dimmed and the sentence below it ("This output has no volume control", "macOS cannot change this display from here", "Brightness is not available on this Mac") is read as text. In Settings the module's Brightness switch is a plain toggle with its explanation, and when it is off no brightness row shows in the tab. The Overview tile shows the volume as a ring and a number, or the word "Muted"; neither relies on colour alone.
- **Accessory alerts**: when an accessory connects, disconnects or runs low, VoiceOver is told once what happened ("AirPods connected", with the detail of a low battery) while VoiceOver runs, whether the notch widens or the hub is open; the widened notch is the same live state as for Live activities. In the Accessories tab each row is read as one sentence, "name, connected", "name, connected, battery 80 percent" or "name, battery 80 percent"; the level is always shown as a number as well as a colour, and the symbol is hidden. The right pill beside the notch is read by the activity's title, and the tile as the lowest accessory and its percentage. When Bluetooth is refused the sentence and its button to System Settings are read as text and a button. In Settings the switches (connect and disconnect alerts, Read battery levels, low-battery alert), and the Low battery level stepper are read by name and value, and the Bluetooth row in Advanced is read like the others, with "Granted" or "Not granted" before Grant… or Revoke….
- **Notifications**: each notification is read as one item with the app (when it is known), the title, the text and how long ago, and offers the actions Remove and Never show notifications from this app; Tab reaches the rows, their buttons and Clear all; when the module is not reading, the reason ("Not reading: Accessibility is off", "Notification Center is not running" or "macOS did not allow it") is a sentence in the tab and is read with it; the Excluded apps list in the module's settings has a remove button, named "Remove", for each name; the hub opened by hover does not take the keyboard, by design.
- **Now Playing**: the song is read as one item with its title, artist and album and its state ("Playing" or "Paused"), and the app's name when Read all apps reported it; the artwork is decorative and hidden from VoiceOver. The three buttons are read as "Previous", "Play" or "Pause", and "Next", and can be reached with Tab when the hub took the keyboard; without Accessibility they are dimmed and their help text says "Needs Accessibility access". The progress is read as one item with the elapsed time and the length. Under Reduce Motion the progress bar still advances (it is the system's own progress view) and nothing else moves. When nothing plays, "Nothing is playing" is a sentence in the tab; when Read all apps switched itself off, "Read all apps is not available on this Mac" is a sentence in the tab and in Settings. In Settings the Music, Spotify and Read all apps switches are read by name and state, and the caption of Read all apps is read as text beside its switch.
- **What's New window**: opened after an update it does not take the keyboard focus, by design (a click puts focus in it); opened from About it is read as "What's New". The tab strip is read as "Versions" and each tab as "Version 1.0.1" with its position ("1 of 2") and, for the selected one, as selected; the version you just installed is also read as "Installed" (the small wood dot is decoration and never the only sign). Left and Right move between the tabs, and Tab reaches the strip, the switch and Done. The groups New, Improved and Fixed are headings, and each row is read as its title and its sentence. The switch is read as "Show after an update" with its state. Return is Done and Esc closes the window. Under Reduce Motion a change of tab fades; under Reduce Transparency and Increase Contrast the strip is opaque. In French, German, Polish and Hungarian no title or sentence is cut off.
- **Layout, bars**: Tab to an item; the arrow keys move the focus, Option with an arrow key moves the item, ⌘1, ⌘2 and ⌘3 put it in a section, and ⌘Z and ⇧⌘Z undo and redo. The item's menu (Return, Space or a right-click) starts with Move to. The VoiceOver actions are Move to Visible, Move to Hidden, Move to Always Hidden, Move Left, Move Right and Set Hotkey…. The Bars | List switch is read with its choice. The filter dims the items that do not match; dimming is never the only sign, as the list shows only the matches. With Reduce Motion items jump instead of sliding. On macOS 27 the note that macOS hides whole apps is read as text; the highlight of the other items of an app is a help for the eye, not the only sign.
- **Layout, list**: each row is read by the item's name and its app, and its section pop-up as "Section of <item>" with its value; Tab reaches the filter field, Clear Filter and every pop-up, and a change of a pop-up is a change of the layout like any other.
- **Undo notice**: after a change of the layout a notice shows for five seconds, at the bottom of the Settings window or in a small panel under the menu bar. VoiceOver reads its sentence and offers the action Undo; the Undo button is also reached with Tab while the notice shows in Settings. Under Reduce Motion it fades instead of sliding; under Reduce Transparency and Increase Contrast it is opaque.
- **Onboarding window** (the introduction after the first launch, and Settings → About → Introduction to holzBar): each step is read as "Step 1 of 3" with its title and text; Return goes on, Skip and Escape close the window on every step, and the Tidy Up suggestion of the third step is reached with Tab. In French, German, Polish and Hungarian no text is cut off.
- **Settings search**: ⌘F puts the cursor in the search field at the top of the sidebar; the results are grouped per pane, each read by its label and pane; Return opens the first hit, and Escape empties the field.
- **Info buttons**: every row's info button is read as "Explanation", takes the keyboard focus and opens its explanation with Space; the pointer shows the same text as a tooltip.
- **Layout, Put Back by a Rule**: the title is a heading; each row is read as one sentence ("name was put back in section"), and Edit Rule… and OK are named and reachable by Tab; a put-back that happens while Settings is open is announced. Reduce Motion needs nothing, as the row does not animate.
- **Groups**: the symbol menu is read "Symbol" and names its choices; the colour well and Remove the color are named; the popover's items are read by name.
- **Appearance** (the pane and the floating Menu Bar Appearance editor): Square Cap and Round Cap are named. For a gradient, Tab to each color stop: Left and Right move it by 5 %, Space edits its colour and Delete removes it, but never the last one. VoiceOver reads "Color Stop 1 of 2, 0 percent", adjusts it and offers Add Color Stop and Remove Color Stop.
- **Modules**: every row is reachable by keyboard; the switch reads the module's name and state; a module's settings open under its row only while it is on, and Tab reaches them.
- **Confirmation sheets** (delete a rule, remove a widget, delete a profile, delete all snapshots, reset the appearance, revoke a permission, restore a layout): the sheet reads its title first. For a destructive sheet Return is Cancel and Escape cancels; the confirming button is reached by Tab and named by its action. Restore is the one confirming sheet where Return restores. Revoke also offers Open System Settings.
- **Hotkeys**: Record Hotkey starts recording, a typed combination is taken, Escape cancels the recording and Clear removes the hotkey. A set hotkey is drawn as key caps but read once as a whole shortcut, for example "control option shift command Space"; the caps are not separate stops.
- **Permission rows** (Advanced and the permissions window): each row is read by the permission's name, then its state in words, "Granted" or "Not granted", then Grant… or Revoke…; Revoke… asks first in a confirmation sheet. While a permission is missing the permissions window also offers Reset and Grant Again. The state never rests on colour alone.
- **Screen Recording offer** (once, the first time the Shelf opens): a confirmation in holzBar's own look; its title is read first, and Not Now is reached with Tab and closes it like Escape.
- **Showing & Hiding**: the system's Touch ID or password sheet for the lock appears in front.
- **Advanced**: Revoke… asks first, in a confirmation sheet.
- **The holzBar icon with the count badge**: with **Show the number of hidden items** on (Settings → General), the icon's tooltip and VoiceOver value say "One hidden item" or "N hidden items" while items are hidden, and "Microphone in use. 3 hidden items" when the capture dot shows too (macOS 27); VoiceOver still reads the icon as "holzBar". The badge itself is decoration and not a separate element, and a click on it works as a click on the icon. The setting is a switch that reads its name and state.
- **The holzBar Shelf**: the hotkey opens it; the arrow keys move a ring in the system's focus colour and VoiceOver says "selected"; Return opens the item and Escape closes the Shelf; the Open and Open Menu actions are offered; a system item's tile (Apple Items) is read by the item's name, as a button with the hint "Opens the item". The floating style (Settings → holzBar Shelf → Style) behaves the same, and so does Screen edge as a location. A click on a tile whose item does not open gives a system beep, and VoiceOver says "The item did not open."
- **The search's category buttons** (Smart Categories): the row is read as "Categories", each button by its name and, when chosen, as selected; Option with the left or right arrow switches the category and the field keeps the typing. With Smart Categories off in Layout the row is not there.
- **The search**: typing filters, the arrow keys choose and Return opens. The button at the bottom left is read "holzBar Settings…" and a row is read by the item's name only.
- **Increase Contrast and Reduce Transparency**: Settings' groups are opaque with a visible border, and module and rule rows show no gradient. The holzBar Shelf and System Glass are opaque with a border, as since 0.0.7.

## Result

Write down per screen and macOS version whether a check passes or fails; a failed check is a bug.

| Screen | macOS 26 | macOS 27 |
|---|---|---|
| Layout (bars and list) | — | — |
| Showing & Hiding | — | — |
| holzBar Shelf (pane) | — | — |
| Profiles & History | — | — |
| Appearance | — | — |
| Automation | — | — |
| Modules | — | — |
| General | — | — |
| Hotkeys | — | — |
| Advanced | — | — |
| About | — | — |
| Settings search | — | — |
| Permissions window | — | — |
| Onboarding window | — | — |
| Undo notice | — | — |
| holzBar Shelf | — | — |
| Search | — | — |
| A group's popover | — | — |
| Open an item by letter | — | — |
| holzBar's menu | — | — |
| Widgets in the menu bar | — | — |
| Notch hub | — | — |
| Timers tab of the notch hub | — | — |
| Calendar tab of the notch hub | — | — |
| Live activities in the widened notch and tab of the notch hub | — | — |
| File drop tab of the notch hub | — | — |
| Display controls tab of the notch hub | — | — |
| Accessory alerts in the widened notch and tab of the notch hub | — | — |
| Notifications tab of the notch hub | — | — |
| Now Playing tab of the notch hub | — | — |
| What's New window | — | — |
