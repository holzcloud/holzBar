# holzBar vs. Ice and Thaw

What the original [Ice](https://github.com/jordanbaird/Ice) 0.11.12 and the other active fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta do, and what holzBar adds. — means not available or not documented. 🔜 means planned, with the release (0.0.8 or 0.0.9): it is **not available yet**.

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| **Compatibility** | | | |
| macOS 14 – 26 | ✅ | macOS 26 only | ✅ |
| **macOS 27** (new menu bar drawn by `MenuBarAgent`) | ❌ | ✅ | ✅ |
| Launched and unit tested in CI on every supported macOS | ❌ | — | ✅ 14, 15, 26 and 27 |
| **Features** | | | |
| Hidden and always-hidden sections, Ice Bar / holzBar Shelf, search, appearance | ✅ | ✅ | ✅ |
| Layout profiles | ❌ | ✅ | ✅ |
| Groups and spacers | ❌ | ✅ | ✅ |
| Folders with their own icon and colour; item images of your choice | ❌ | ✅ | ✅ |
| Choose where new items appear | ❌ | — | ✅ |
| Bar only on some displays, notch overflow | ❌ | — | ✅ |
| Black menu bar, rounded screen corners | ❌ | corners only | ✅ |
| Dashed and dotted borders, wallpaper, accent and glass tints | ❌ | ✅ | ✅ |
| Show hidden items on low battery or when offline | ❌ | — | ✅ |
| Rules that apply a profile or show items when a Wi-Fi network, an app, the time of day, the power source or a display matches (all or any) | ❌ | ✅ | 🔜 0.0.8 |
| Profile applied by a Focus filter | ❌ | ✅ | 🔜 0.0.8 |
| Scripts as a rule condition or action | ❌ | ✅ | 🔜 0.0.8 <sub>only from a folder you choose, after you confirm</sub> |
| Menu bar items of your own (clock, battery, CPU, Shortcut button) | ❌ | — | 🔜 0.0.9 |
| AppleScript dictionary | — | — | 🔜 0.0.9 |
| Touch ID or password to show hidden items | — | — | 🔜 0.0.8 |
| Smooth show and hide | — | — | 🔜 0.0.9 |
| Show or hide a single item while a condition holds (a VPN is connected, an app is running) | ❌ | ✅ | 🔜 0.0.8 |
| Automatic layout snapshots with a one-click restore | — | — | 🔜 0.0.8 |
| Command palette for holzBar's own actions | — | — | 🔜 0.0.9 |
| Share one profile as a file | ❌ | ✅ | 🔜 0.0.8 |
| First-launch assistant that proposes an arrangement | — | — | 🔜 0.0.8 |
| Suggests hiding items you never click (opt-in, counters stay on your Mac) | — | — | 🔜 0.0.9 |
| Redacted diagnostics report you read before you copy it | — | — | 🔜 0.0.8 |
| URL commands and Raycast | ❌ | ✅ | ✅ |
| Zen mode (also while presenting) | ❌ | ✅ | ✅ |
| Hotkeys per profile and per item | ❌ | ✅ | ✅ |
| Shortcuts actions (App Intents) | ❌ | ✅ | ✅ |
| Profiles bound to a display or a Space | ❌ | ✅ | ✅ |
| Open an item by letter | ❌ | ✅ | ✅ |
| Layout editor and Shelf from the keyboard, undo, VoiceOver actions | ❌ | ✅ | ✅ |
| Opened items stay up to 30 s, or open without showing the item | ❌ | ✅ | ✅ |
| Show an item briefly when it changes | ❌ | ✅ | ✅ <sub>opt-in per item</sub> |
| Export and import settings | ❌ | ✅ | ✅ |
| Settings sync: iCloud Drive or any synced folder | ❌ | ❌ | ✅ <sub>paused in 0.0.7-beta2</sub> |
| Languages | English | many, through Crowdin | English, German, French, Italian, Romansh |
| Keep Live Activities visible | ❌ | — | ✅ <sub>experimental</sub> |
| Show on scroll with a mouse wheel | ❌ | — | ✅ |
| Search tolerates typos and abbreviations | ✅ (library) | ✅ | ✅ (built in) |
| Refuses hotkeys macOS cannot register, and says why; asks before taking another hotkey's combination | ❌ | — | ✅ |
| Input never stalls when an app hangs | ❌ | ✅ | ✅ |
| Items keep their section when an app changes its title | ❌ | ✅ | ✅ |
| Pauses while the screen is locked, settles after wake | ❌ | ✅ | ✅ |
| Look on every desktop, follows the icons, steps aside in fullscreen | ❌ | ✅ | ✅ |
| No screen-recording indicator when showing or hiding (macOS 27) | — | ✅ | ✅ |
| Hover and click on a second display (macOS 27) | — | ✅ | ✅ |
| Dot on its icon while the microphone or camera is in use and Control Centre's indicator is not drawn (macOS 27) | — | — | ✅ |
| URL commands ask before they change anything lasting; no URL shows hidden items while Zen mode is on or ends it during a screen share | — | — | ✅ |
| Validated hotkeys, colours and numbers in imported and synced settings (no crash loop from bad settings) | ❌ | — | ✅ |
| **Privacy and permissions** | | | |
| Network connections (update checks, telemetry, analytics) | Sparkle update checks | Sparkle update checks | **none** — enforced by CI |
| Personal data (app names, item titles, paths) in logs | partly public | — | private, enforced by CI |
| Asks for Screen Recording only when a feature needs it | ❌ | — | ✅ |
| Hardened runtime (no injected code or libraries) | ✅ | ✅ | ✅ (checked by CI) |
| No entitlements, not even `get-task-allow` | — | — | ✅ from 0.0.7-beta2 (checked by CI and the release) |
| Settings import accepts only known keys of the right type, in range | — (no import) | — | ✅ |
| Settings import and sync can't turn sync on; the sync file carries no computer name | — (no sync) | — | ✅ |
| No helper process runs with holzBar's permissions | ❌ (menu bar item service) | — | ✅ from 0.0.7-beta2: one executable, no nested code (checked by CI) |
| Fix for the permissions loop | ❌ | — | ✅ |
| **Code and resources** | | | |
| Swift packages | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern and 5 from Apple) | **none** |
| Swift language mode | Swift 5 | Swift 6 | Swift 6 (data-race safety checked by the compiler), built with Swift 6.4 and Xcode 27 |
| State management | Combine | `@Observable` and Combine | `@Observable`, no Combine |
| Mouse event tap when "Show on hover" is off | always running | — | off |
| Timers and polling while nothing is shown | yes | — | only while needed |
| Settings sync checks for changes | — (no sync) | — (no sync) | when the synced folder delivers them, no polling <sub>paused in 0.0.7-beta2</sub> |
| Settings migration | 6 version steps at every launch | — | once, while importing Ice settings |
| Runtime patching of AppKit (method swizzling) | yes | yes | none |
| Item images in memory | kept | — | released when unused |
| Unit tests run on every change | none | ✅ | ✅ 610 |
| App size | — | — | 16.7 MB |
| **Distribution and maintenance** | | | |
| Install and update with Homebrew | ✅ | ✅ | ✅ |
| Updates | Sparkle (dialog can hang on macOS 26) | Sparkle | Homebrew |
| Every bug group of Ice's 282 open reports solved | — | — | ✅ confirmed on a Mac in 0.0.6, [see the list](upstream-bugs.md) |
| Signed with a Developer ID | ✅ | — | ❌ (own certificate instead; the cask handles quarantine) |
| Stable signature, so Accessibility survives updates | ✅ | — | ✅ (own certificate, [docs/signing.md](signing.md)) |
| Build provenance attestation (`gh attestation verify`) | ❌ | — | ✅, and SLSA Build Level 3 provenance from 0.0.7-beta2 |
| GitHub Actions pinned by commit SHA (Dependabot keeps them current), OpenSSF Scorecard | — | — | ✅ <sub>except the SLSA generator, referenced by its release tag</sub> |

The AppleScript, Touch ID and smooth show and hide rows are about features other menu bar apps have (AppleScript: Bartender 7 and SaneBar; Touch ID lock: SaneBar; smooth show and hide: Vanilla), not Ice or Thaw as far as their documentation says.
