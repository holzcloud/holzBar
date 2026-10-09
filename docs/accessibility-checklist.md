# Accessibility checklist

holzBar's screens are built with system controls, labels and keyboard access, but **nobody has yet run this checklist with VoiceOver on a Mac**, so the README makes no accessibility claim. Run it on macOS 26 and 27, then report what fails in an issue.

Accessibility *support* (this page) is not the Accessibility *permission* holzBar asks for.

## For every screen

Screens: Menu Bar Layout (items, profiles, Layout History, Tidy Up), Automation (rules, scripts), Appearance, General, Hotkeys, Advanced, About (Copy Diagnostics), the permissions window, the holzBar Shelf and the search.

1. **VoiceOver** (⌘F5): every control is read with a name and its role; buttons that show only an icon (star, delete, remove condition, edit) have a name; lists are read as lists; a switch tells its state; nothing is conveyed by colour alone.
2. **Keyboard**: with Full Keyboard Access on (System Settings, Keyboard), every control can be reached with Tab and used with Space or Return; Escape closes a sheet or panel; the focus is visible.
3. **Reduce Motion**: no movement beyond a short fade.
4. **Reduce Transparency**: glass groups become plain, opaque panels; text stays readable.
5. **Increase Contrast**: borders and text stay clearly visible.
6. **Languages**: switch to German, French, Italian and Romansh; no text is cut off.

## Screens with special points

- **Automation rule row**: the chevron button is read as "Edit"; the switch is read with the rule's name; the editor's condition rows have a "Remove Condition" button.
- **Layout History**: the star button reads "Star" or "Remove Star"; restore asks first.
- **Tidy Up**: every proposal is a switch that reads the app name.
- **Script approval**: the sheet reads the file name, size and checksum.
- **Lock hidden items**: the system's Touch ID or password sheet appears in front.

## Result

Write down per screen and per check: passes, fails, or not tested, with the macOS version. Failed checks are bugs.
