# Accessibility checklist

holzBar's screens use system controls with names and keyboard access. 0.0.8 adds names, headings and values for VoiceOver to the newer screens, Escape in every sheet, Increase Contrast and Reduce Motion handling in Settings and the Layout pane, a focus ring in the holzBar Shelf and keyboard access to the colour stops of a gradient. All of it is a **Preview**: **nobody has yet run this checklist with VoiceOver on a Mac**, and until it was run holzBar adds no new accessibility claim. Run it on macOS 26 and 27, then report what fails in an [issue](https://github.com/holzcloud/holzBar/issues).

Accessibility *support* (this page) is not the Accessibility *permission* holzBar asks for; see [Permissions](privacy-and-permissions.md#permissions).

## Before you start

- **VoiceOver**: ⌘F5 turns it on. Actions are in the VoiceOver menu (VO-⌘-Space; VO is Control-Option).
- **Full Keyboard Access**: System Settings → Accessibility → Keyboard.
- **Voice Control**: System Settings → Accessibility → Voice Control. Say "show names", then "click …".
- **Display options**: System Settings → Accessibility → Display: Reduce Motion, Increase Contrast, Reduce Transparency, Differentiate without color.
- **Language**: System Settings → General → Language & Region → Applications, or `open -a holzBar --args -AppleLanguages "(de)"` with de, fr, it or rm.
- macOS has no Dynamic Type, so check long German and Romansh text instead.

## For every screen

Screens: Settings (General, Menu Bar Layout, Menu Bar Appearance, Automation, Modules, Hotkeys, Advanced, About), the permissions window, the holzBar Shelf, the search, a group's popover, the letters of Open an item by letter, holzBar's menu and widgets in the menu bar.

1. **VoiceOver**: every control is read with its name, role, value and state; buttons that show only an icon are named; lists and groups are named; a switch tells its state; nothing is conveyed by colour alone.
2. **Keyboard**: Tab reaches every control, Space or Return uses it, the focus is visible, Escape closes a sheet or panel and Return runs the default button.
3. **Voice Control**: the names Voice Control shows match the visible text, so "click …" works.
4. **Reduce Motion**: nothing slides; at most a fade.
5. **Reduce Transparency**: glass becomes opaque and the text stays readable.
6. **Increase Contrast**: groups are opaque, borders and text are clearly visible.
7. **Differentiate without color**: no state is shown by colour alone.
8. **Languages**: in German and Romansh nothing is cut off or overlaps.
9. **Contrast**: text at least 4.5:1; large text, symbols and borders at least 3:1; in light, in dark and on glass. Measure on a screenshot with Digital Color Meter.

## Screens with special points

- **Automation rule rows**: each row is read by the rule's name; Edit is read as collapsed or expanded; the switch reads the rule's name and state.
- **Rule editor**: Add Rule puts the cursor in Name and is disabled at 50 rules. When and Then are headings. Each condition is a group read by its sentence, with a Remove Condition button. The battery level is read in percent. Weekday buttons are read by their full name, and Voice Control takes the letter or the name.
- **Scripts**: rows are read by the script's name. The approval sheet reads the file name, folder, size and the start of the checksum; Return is Cancel, Escape cancels and Allow needs a click. The same holds for the folder sheet.
- **Profile Hooks**: the title is a heading; rows are read by script; the Profile, When and Script pickers and Remove Hook read their names and values.
- **Layout History**: rows are read by date; the star reads Star or Remove Star; Restore… asks first and a restore is announced; Delete is named.
- **Tidy Up, Share Profile, Import Profile and Copy Diagnostics**: the title is a heading; Escape closes the sheet without acting; Return runs the default button. Every Tidy Up proposal is a checkbox that reads the app's name.
- **Widgets**: each widget in the menu bar is read with its source name and its value in full ("Battery, 80 percent, charging", "unavailable" when it cannot be read). A Shortcut button is read as a button with the Shortcut's name as its hint. A script widget is read as "Script" with its line, "Choose a script" while none is chosen and "Allow this script in Automation, Scripts" while the script is not allowed. In Modules the rows are read by name, Edit is read as collapsed or expanded, and the Widgets switch, Edit, Remove, Move Up and Move Down are reachable by keyboard; a widget moves with the VoiceOver actions Move Up and Move Down.
- **Menu Bar Layout bars**: Tab to an item; the arrow keys move it and ⌘Z undoes. The VoiceOver actions are Move to Visible, Move to Hidden, Move to Always Hidden, Move Left, Move Right and Set Hotkey…. With Reduce Motion items jump instead of sliding.
- **Menu Bar Layout, Put Back by a Rule**: the title is a heading; each row is read as one sentence ("name was put back in section"), and Edit Rule… and OK are named and reachable by Tab; a put-back that happens while Settings is open is announced. Reduce Motion needs nothing, as the row does not animate.
- **Groups**: the symbol menu is read "Symbol" and names its choices; the colour well and Remove the color are named; the popover's items are read by name.
- **Menu Bar Appearance**: Square Cap and Round Cap are named. For a gradient, Tab to each color stop: Left and Right move it by 5 %, Space edits its colour and Delete removes it, but never the last one. VoiceOver reads "Color Stop 1 of 2, 0 percent", adjusts it and offers Add Color Stop and Remove Color Stop.
- **Modules**: every row is reachable by keyboard; the switch reads the module's name and state; a module's settings open under its row only while it is on, and Tab reaches them.
- **Confirmation sheets** (delete a rule, remove a widget, delete a profile, delete all snapshots, reset the appearance, revoke a permission, restore a layout): the sheet reads its title first. For a destructive sheet Return is Cancel and Escape cancels; the confirming button is reached by Tab and named by its action. Restore is the one confirming sheet where Return restores. Revoke also offers Open System Settings.
- **Hotkeys**: Record Hotkey starts recording, a typed combination is taken, Escape cancels the recording and Clear removes the hotkey. A set hotkey is drawn as key caps but read once as a whole shortcut, for example "control option shift command Space"; the caps are not separate stops.
- **Permission pills** (Advanced, the permissions window, the Screen Recording hint): VoiceOver reads "Needs <permission>" or "Permission Granted" before the Grant or Revoke button; the state never rests on colour alone.
- **Advanced**: the system's Touch ID or password sheet for the lock appears in front; Revoke… asks first, in a confirmation sheet.
- **The holzBar Shelf**: the hotkey opens it; the arrow keys move a ring in the system's focus colour and VoiceOver says "selected"; Return opens the item and Escape closes the Shelf; the Open and Open Menu actions are offered.
- **The search**: typing filters, the arrow keys choose and Return opens. The button at the bottom left is read "holzBar Settings…" and a row is read by the item's name only.
- **Increase Contrast and Reduce Transparency**: Settings' groups are opaque with a visible border, and module and rule rows show no gradient. The holzBar Shelf and System Glass are opaque with a border, as since 0.0.7.

## Result

Write down per screen and macOS version whether a check passes, fails or was not tested; a failed check is a bug.

| Screen | macOS 26 | macOS 27 |
|---|---|---|
| General | not tested | not tested |
| Menu Bar Layout | not tested | not tested |
| Menu Bar Appearance | not tested | not tested |
| Automation | not tested | not tested |
| Hotkeys | not tested | not tested |
| Advanced | not tested | not tested |
| About | not tested | not tested |
| Permissions window | not tested | not tested |
| holzBar Shelf | not tested | not tested |
| Search | not tested | not tested |
| A group's popover | not tested | not tested |
| Open an item by letter | not tested | not tested |
| holzBar's menu | not tested | not tested |
| Widgets in the menu bar | not tested | not tested |
