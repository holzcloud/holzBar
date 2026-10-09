# Module decisions (2026-10-09)

Context: holzBar becomes an all-in-one with optional modules replacing Vorssaint, AltTab, Flameshot, Rectangle and MonitorControl, planned for **1.0.0** (todo `2026-10-09-all-in-one-optional-modules.md`). Research: `MODULE-*.md`.

## Decisions by the maintainer
1. **Private APIs are allowed as an exception for modules** that cannot work without them (AltTab: other Spaces and cross-Space focus; MonitorControl: DDC brightness and volume). This departs from the principle "never build on private or deprecated API" and from the researcher's recommendation (public APIs only).
2. **Vorssaint parts that need a root helper or the network** (fan control, closed-lid mode, update manager, Homebrew, notification mirroring, companion, AI agent tracking): decide later, after 1.0.0 is planned. Not rejected for good.
3. **Clipboard history is stored on disk** (survives a restart), with a clear warning.

## Conditions to design in (so the exceptions stay safe)
- Every module is off by default and switchable; a module that is off runs no code and asks for no permission.
- A module that uses a private API is labelled as such in Settings, isolated behind one wrapper per API, checked at launch for availability (it must switch itself off and say so when macOS changes it, never crash), and covered by a kill switch.
- Never any network use, in any module, including the ones above (Sparkle, update checks, uploads, AppCenter and Pro licence code are dropped).
- Clipboard on disk: encrypted with a key held in the Keychain, concealed pasteboard types skipped, per-app exclusions, a retention limit with automatic clearing, and one-click erase. Off by default.
- CLAUDE.md principles ("Apple's way", "least privilege") need an explicit module-exception clause before the first private-API module is built; confirm the wording with the maintainer then.

## Effort and order (from MODULE-VORSSAINT.md, to be refined)
1. Module registry and permission explainer
2. Keep awake, public system-monitor subset
3. Output/mic, colour picker, port/kill, file shelf
4. Windows layout (Rectangle)
5. Clipboard, keyboard, mouse
6. Command Bar
7. Switcher and Dock (AltTab)
8. Capture (Flameshot), volume mixer, brightness (MonitorControl)
9. Reduced Dynamic Island (own design; Vorssaint's name, logo and look are trademarked)
