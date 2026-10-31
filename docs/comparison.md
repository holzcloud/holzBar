# holzBar vs. Ice, Thaw and Bartender, in detail

Two comparisons live here: the detailed one against Ice, Thaw and Bartender, and [the wider one against 14 apps](#against-every-other-menu-bar-manager) further down. The README carries a short version.

What the original [Ice](https://github.com/jordanbaird/Ice) 0.11.12 and the other active fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta do, and what holzBar adds, next to [Bartender](https://www.macbartender.com/) 7, the paid app for macOS 27 (Bartender 6 covers macOS 14 – 26). The Bartender column comes from its product pages; — means not stated there. — means not available or not documented. 🔜 means planned, with the release where one is set (1.0.0, or later): it is **not available yet**.

| | Ice 0.11.12 | Thaw 3.0 beta | Bartender 7 | holzBar |
|---|:---:|:---:|:---:|:---:|
| **Compatibility** | | | | |
| macOS 14 – 26 | ✅ | macOS 26 only | ✅ <sub>Bartender 6</sub> | ✅ |
| **macOS 27** (new menu bar drawn by `MenuBarAgent`) | ❌ | ✅ | ✅ | ✅ |
| Launched and unit tested in CI on macOS 26 and 27 | ❌ | — | — | ✅ 26 and 27 |
| **Features** | | | | |
| Hidden and always-hidden sections, Ice Bar / holzBar Shelf, search, appearance | ✅ | ✅ | — | ✅ |
| Layout profiles | ❌ | ✅ | ✅ | ✅ |
| Groups and spacers | ❌ | ✅ | — | ✅ |
| Folders with their own icon and colour; item images of your choice | ❌ | ✅ | — | ✅ |
| Choose where new items appear | ❌ | — | — | ✅ |
| Move items in the menu bar by dragging, without ⌘ Command | ❌ | — | — | ✅ <sub>macOS 26 and 27</sub> |
| Bar only on some displays, notch overflow | ❌ | — | — | ✅ |
| Floating bar for hidden items, at the icon, the screen edge or the pointer | ❌ <sub>the bar hangs below the menu bar</sub> | — | ✅ <sub>Bartender Bar, at the cursor</sub> | ✅ |
| Shelf and macOS 27's own overflow button: no item listed twice | ❌ | — | — | ✅ |
| Black menu bar, rounded screen corners | ❌ | corners only | — | ✅ |
| Dashed and dotted borders, wallpaper, accent and glass tints | ❌ | ✅ | — | ✅ |
| One shape per section of the bar (Sections) | ❌ | — | — | ✅ <sub>macOS 14 – 26</sub> |
| A shape of its own for the Apple logo | ❌ | — | — | ✅ |
| Outlines in the accent colour or a gradient; vertical gradients, one gradient per shape, tint strength | ❌ | gradient at any angle | outline and gradient styles | ✅ |
| Show hidden items on low battery or when offline | ❌ | — | — | ✅ <sub>as rules since 0.0.8</sub> |
| Rules that apply a profile or show items when a Wi-Fi network, an app, the time of day, the power source or a display matches (all or any) | ❌ | ✅ | ✅ | ✅ |
| Rules that use the sound output or a connected Bluetooth device | ❌ | ✅ | — | ✅ <sub>Bluetooth asks for its permission only when you add the condition</sub> |
| Profile applied by a Focus filter | ❌ | ✅ | — | ✅ |
| Scripts as a rule condition or action | ❌ | ✅ | — | ✅ <sub>from a folder you choose, after you allowed the exact content</sub> |
| Script hooks before or after a profile | ❌ | ✅ | — | ✅ |
| Menu bar items of your own (clock, battery, CPU, Shortcut button) | ❌ | — | ✅ | ✅ |
| Hide the clock, Control Center, Wi-Fi or the battery on macOS 27 | — | — | ✅ | ✅ |
| Replacement icons for Apple items on macOS 27 | — | ✅ | — | ✅ |
| AppleScript dictionary | — | — | ✅ | ✅ <sub>a small, read-mostly set; asks before lasting changes</sub> |
| Touch ID or password to show hidden items | — | — | — | ✅ |
| Smooth show and hide | — | — | — | partly: the holzBar Shelf has Instant, Smooth and Fade styles; the bar's own items slide on macOS 26 only (not macOS 14 and 15; macOS 27 animates its own bar) |
| Click on the clock opens Notification Center while items are hidden (macOS 27), as a setting | — | — | — | ✅ |
| Per display: always show everything, or collapse; the display under the pointer decides | — | — | — | ✅ |
| Layout editor that draws first and applies in one pass, with a tile for where new items land | ❌ | — | — | ✅ |
| Moods: save the look of the menu bar and switch to it in one click, from the palette or with a rule | ❌ | — | — | ✅ |
| holzBar Shelf as a row, a grid or a column | ❌ | — | — | ✅ |
| Type in the Shelf to find an item and open it with Return | — | — | — | ✅ <sub>the Shelf takes the keyboard when a hotkey opens it</sub> |
| Always-hidden items behind one fold tile in the Shelf | — | — | — | ✅ |
| Apps that are not running shown dimmed in the Shelf, a click launches them | — | — | — | ✅ <sub>opt-in</sub> |
| Drag an item in the Shelf to put it in order, into another section or onto the menu bar | — | — | — | ✅ <sub>macOS 27 only changes the section</sub> |
| Own menu bar items for Focus, AirDrop, media controls, fast user switching and a timer, which hide and move like any item | ❌ | — | — | ✅ <sub>optional module, up to twelve widgets</sub> |
| App launchers: a holzBar icon for any app you pick, a click opens it | ❌ | — | — | ✅ <sub>same module</sub> |
| A hub at the notch (at the top centre without one) that holds optional modules, off until you switch it on | ❌ | — | — | ✅ <sub>its first modules are Timers, Calendar and Live activities</sub> |
| Timers, countdowns to a moment and a stopwatch in that hub (optional module, no permission) | ❌ | — | — | ✅ |
| Next events and a Join button for meetings in that hub (optional module; Calendar access asked only when you switch it on) | ❌ | — | — | ✅ |
| A capsule at the notch for downloads and for a camera or microphone in use (optional module in that hub) | ❌ | — | — | ✅ |
| Connection and low-battery alerts for AirPods and other accessories, as a capsule at the notch (optional module in that hub; Bluetooth asked only when you switch it on; battery levels use a macOS call that Apple does not document) | ❌ | — | — | ✅ |
| A file stash at the notch: drag files in, drag them out later as copies (optional module in that hub, no permission) | ❌ | — | — | ✅ |
| Volume and brightness sliders at the notch (optional module in that hub, no permission; brightness uses a macOS call that Apple does not document) | ❌ | — | — | ✅ |
| The banners of your apps listed at the notch (optional module in that hub; read through Accessibility, kept in memory only, no Notifications permission; only what macOS shows on screen, and it follows a structure macOS may change) | ❌ | — | — | ✅ |
| Show or hide a single item while a condition holds (a VPN is connected, an app is running) | ❌ | ✅ | — | ✅ |
| Automatic layout snapshots with a one-click restore | — | — | — | ✅ |
| Command palette for holzBar's own actions | — | — | — | ✅ |
| Settings with a Modules pane: every optional module off until you switch it on | ❌ | — | — | ✅ |
| Share one profile as a file | ❌ | ✅ | — | ✅ |
| First-launch assistant that proposes an arrangement | — | — | — | ✅ |
| Smart Categories in the search (system, network, media and more) | ❌ | — | — | ✅ |
| Suggests hiding items you never click (opt-in, counters stay on your Mac) | — | — | — | ✅ |
| Redacted diagnostics report you read before you copy it | — | — | — | ✅ |
| URL commands and Raycast | ❌ | ✅ | — | ✅ |
| Zen mode (also while presenting) | ❌ | ✅ | — | ✅ |
| Hotkeys per profile and per item | ❌ | ✅ | — | ✅ |
| Shortcuts actions (App Intents) | ❌ | ✅ | ✅ | ✅ |
| Profiles bound to a display or a Space | ❌ | ✅ | — | ✅ |
| Open an item by letter | ❌ | ✅ | — | ✅ |
| Layout editor and Shelf from the keyboard, undo, VoiceOver actions | ❌ | ✅ | — | ✅ |
| Opened items stay up to 30 s, or open without showing the item | ❌ | ✅ | — | ✅ |
| Show an item briefly when it changes | ❌ | ✅ | — | ✅ <sub>opt-in per item</sub> |
| Export and import settings | ❌ | ✅ | — | ✅ |
| Settings sync: iCloud Drive or any synced folder | ❌ | ❌ | — | 🔜 1.0.0 <sub>planned, not available</sub> |
| Languages | English | many, through Crowdin | — | 11: English, German, French, Italian, Romansh, Spanish, Brazilian Portuguese, Japanese, Simplified Chinese, Korean, Russian |
| Keep Live Activities visible | ❌ | — | — | ✅ <sub>experimental</sub> |
| Show on scroll with a mouse wheel | ❌ | — | — | ✅ |
| Search tolerates typos and abbreviations | ✅ (library) | ✅ | — | ✅ (built in) |
| Refuses hotkeys macOS cannot register, and says why; asks before taking another hotkey's combination | ❌ | — | — | ✅ |
| Input never stalls when an app hangs | ❌ | ✅ | — | ✅ |
| Items keep their section when an app changes its title | ❌ | ✅ | — | ✅ |
| Pauses while the screen is locked, settles after wake | ❌ | ✅ | — | ✅ |
| Look on every desktop, follows the icons, steps aside in fullscreen | ❌ | ✅ | — | ✅ |
| No screen-recording indicator when showing or hiding (macOS 27) | — | ✅ | — | ✅ |
| Hover and click on a second display (macOS 27) | — | ✅ | — | ✅ |
| Dot on its icon while the microphone or camera is in use and Control Centre's indicator is not drawn (macOS 27) | — | — | — | ✅ |
| Number of hidden items as a badge on the icon (off until you switch it on) | ❌ | — | — | ✅ |
| URL commands ask before they change anything lasting; no URL shows hidden items while Zen mode is on or ends it during a screen share | — | — | — | ✅ |
| Validated hotkeys, colours and numbers in imported settings (no crash loop from bad settings) | ❌ | — | — | ✅ |
| **Privacy and permissions** | | | | |
| Network connections (update checks, telemetry, analytics) | Sparkle update checks | Sparkle update checks | — | **none** — enforced by CI |
| Personal data (app names, item titles, paths) in logs | partly public | — | — | private, enforced by CI |
| Asks for Screen Recording only when a feature needs it | ❌ | — | ✅ <sub>not required</sub> | ✅ |
| Asks for Location Services only when you add a Wi-Fi-name condition, and for Bluetooth only when you add a Bluetooth condition or switch on Accessory alerts | — | — | — | ✅ |
| Scripts run only from a folder you chose and only after you allowed their exact content; never from a URL command, an import or sync | — | — | — | ✅ |
| Hardened runtime (no injected code or libraries) | ✅ | ✅ | — | ✅ (checked by CI) |
| Only one entitlement (Calendar), no `get-task-allow` | — | — | — | ✅ (checked by CI and the release; no entitlement at all from 0.0.7-beta2 to 0.0.13) |
| Settings import accepts only known keys of the right type, in range | — (no import) | — | — | ✅ |
| No helper process runs with holzBar's permissions | ❌ (menu bar item service) | — | — | ✅ from 0.0.7-beta2: one executable, no nested code (checked by CI) |
| Fix for the permissions loop | ❌ | — | — | ✅ |
| **Code and resources** | | | | |
| Swift packages | 5 | 9 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern and others) | closed source | **none** |
| Swift language mode | Swift 5 | Swift 6 | — | Swift 6 (data-race safety checked by the compiler), built with Swift 6.4 and Xcode 27 |
| State management | Combine | `@Observable` and Combine | — | `@Observable`, no Combine |
| Mouse event tap when "Show on hover" is off | always running | — | — | off <sub>macOS 27 keeps a click tap so clicks reach the system items</sub> |
| Timers and polling while nothing is shown | yes | — | — | only while needed |
| Settings migration | 6 version steps at every launch | — | — | once each: Ice settings while they are imported, holzBar's own older settings at the first launch that needs it |
| Runtime patching of AppKit (method swizzling) | yes | yes | — | none |
| Item images in memory | kept | — | — | released when unused |
| Unit tests run on every code change | none | ✅ | — | ✅ 981 |
| App size | — | — | — | 22.9 MB <sub>CI build of 13 Oct 2026</sub> |
| Widgets do nothing while hidden: no timer, no refresh | — | — | — | ✅ |
| **Distribution and maintenance** | | | | |
| Price and licence | free, open source | free, open source | paid (one-time; Pro yearly; Mega Supporter lifetime), closed source | free, open source (GPL-3.0) |
| Install and update with Homebrew | ✅ | ✅ | — | ✅ |
| Updates | Sparkle (dialog can hang on macOS 26) | Sparkle | — | Homebrew |
| Every bug group of Ice's 282 open reports solved | — | — | — | ✅ <sub>all but one group confirmed on a Mac in 0.0.6</sub>, [see the list](upstream-bugs.md) |
| Signed with a Developer ID | ✅ | — | — | ❌ (own certificate instead; the cask handles quarantine) |
| Stable signature, so Accessibility survives updates | ✅ | — | — | ✅ (own certificate, [docs/signing.md](signing.md)) |
| Build provenance attestation (`gh attestation verify`) | ❌ | — | — | ✅, and SLSA Build Level 3 provenance from 0.0.7-beta2 |
| GitHub Actions pinned by commit SHA (Dependabot keeps them current), OpenSSF Scorecard | — | — | — | ✅ <sub>except the SLSA generator, referenced by its release tag</sub> |

The AppleScript, Touch ID and smooth show and hide rows are about features other menu bar apps have (AppleScript: Bartender 7 and SaneBar; Touch ID lock: SaneBar; smooth show and hide: Vanilla), not Ice or Thaw as far as their documentation says.

## Against every other menu bar manager

An honest comparison with every menu bar manager and menu bar toolkit we found that is on sale or maintained, **including where holzBar loses**. Researched on 9 October 2026 from each project's own pages, repositories and listings. ✅ yes · ❌ no · ❓ not found (not stated, which is not the same as no) · 🔜 planned for holzBar and **not available yet**.

| | holzBar | Bartender 7 | Ice | Thaw | SaneBar | Tuck | Barbee | Hidden Bar | Dozer | Vanilla | iBar | Glow | Brow | Lounge | Vorssaint |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Maintenance | active (0.0.13) | active (7.0.5) | stalled (0.11.12, Oct 2025) | active (3.0 beta, 7 Oct) | **sunset 30 Jun 2026** (last 2.1.91, 9 Sep) | active (1.2.0, 6 Oct) | active (5.0, 10 Sep) | active (1.11.1, 18 Sep) | none since 2022 | 2.2, date ❓ | active (2.1.1, 14 Sep) | active (3.2.0, 2 Oct) | active (version ❓) | active (1.3.1, 4 Oct) | active (3.4.1, 8 Oct) |
| Price | free | paid, one-time <sup>1</sup> | free | free | free | free; Pro $14.99 | free + in-app (lifetime $12.99) | free | free | free; Pro $10 | free + $2.99/yr | $19.99 once | free; Pro $49/yr (AI only) | $3.99/yr | free |
| Open source | ✅ GPL-3.0 | ❌ | ✅ GPL-3.0 | ✅ GPL-3.0 | ✅ MIT | ❌ | ❌ | ✅ MIT | ✅ MPL-2.0 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ GPL-3.0+ |
| macOS 26 / 27 | ✅ / ✅ | ❌ / ✅ <sup>2</sup> | dev builds / ❌ | ✅ / ✅ <sup>3</sup> | ✅ / ❌ | ✅ / ✅ <sup>4</sup> | ❓ / ❓ <sup>5</sup> | ✅ / partly <sup>6</sup> | ❓ / ❓ | ✅ / ❓ | ✅ / ❓ | ✅ / ✅ <sup>13</sup> | ❓ / vendor claim | ✅ / vendor claim | ✅ / ✅ |
| Apple Silicon / Intel | both (one universal app) | ✅ Apple Silicon (27) | ❓ | ❓ | Apple Silicon only | both | ❓ | both | Intel only (Rosetta) | both | both | both | ❓ | both | Apple Silicon only |
| Hidden + always-hidden sections | ✅ | ✅ | ✅ | ✅ | ✅ | hidden; per-icon | hidden only ❓ | ✅ | ✅ | hidden; always-hidden in Pro | ✅ | 3 sections | hide, reorder; always-hidden ❓ | visible / hidden; no always-hidden | ❓ |
| Separate bar, notch handling | ✅ Shelf; no duplicates with the macOS 27 overflow (<sup>14</sup>) | ✅ | ✅ Ice Bar | ✅ Thaw Bar | ✅ | ✅ Shelf | ✅ | ❌ | ❌ | partly | ✅ | ✅ GlowBar; notch ❓ | notch hover panel | ✅ floating panel | ❓ |
| Floating bar (icon, screen edge, pointer) | ✅ | ✅ Bartender Bar, at the cursor | ❌ | ❓ | ✅ Icon Panel | ❓ | ❓ | ❌ | ❌ | ❓ | ✅ floating window | ✅ GlowBar: icon, right edge, cursor | ❓ | ✅ floating panel | ❓ |
| Move items in the menu bar by dragging, without ⌘ | ✅ <sup>14</sup> <sub>macOS 26, 27</sub> | ❓ | ❌ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Layout profiles | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ ❓ | ✅ (VIP) | ❌ | ❌ | ❌ | ❌ | looks only (Moods) | ❌ | ❓ | ❓ |
| Groups, spacers | ✅ | ✅ | ❌ | ✅ | groups, dividers | groups (Pro) | dividers | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ | ❓ |
| Item count badge on the icon | ✅ | ❓ | ❌ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ <sup>15</sup> | ❓ | ❓ | ❓ |
| Smart Categories | ✅ | ❓ | ❌ | ❓ | ✅ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Item spacing | ✅ beta | ✅ | ✅ beta | ✅ beta | ✅ | Pro | ✅ | ❌ | own icons only | ❌ | ✅ | ✅ | ❌ | ❓ | ❓ |
| Search | ✅ | ✅ Command Bar | ✅ | ✅ | ✅ | Pro | weak | ❌ | ❌ | ❌ | ❌ | ✅ | ❓ | ❌ | ❓ |
| Rules / triggers | ✅ <sup>14</sup> | ✅ <sup>7</sup> | ❌ | ✅ many <sup>8</sup> | ✅ 8 types | per app (Pro) | ✅ (VIP) | timer only | timer only | timer (Pro) | timer | ❌ <sup>12</sup> | ❌ <sup>12</sup> | ❌ <sup>12</sup> | ❓ |
| Per-item conditional visibility | ✅ <sup>14</sup> | ✅ | ❌ | ✅ | ❌ | by active app (Pro) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❓ |
| Widgets / own items | ✅ <sup>14</sup> | ✅ | ❌ | planned | ❌ | ❌ | custom icons | ❌ | ❌ | ❌ | ❌ | ❌ | notch widgets | clipboard, agent notifications | ❓ |
| Scripts as trigger/action | ✅ <sup>14</sup> | as widget source | ❌ | ✅ | trigger | ❓ | VIP ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | HTTP /notify endpoint | ❓ |
| AppleScript | ✅ | ✅ | ❌ <sup>9</sup> | ❌ <sup>9</sup> | ✅ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ | ❓ |
| Shortcuts / Siri | ✅ | ✅ | ❌ | partly | via AppleScript | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ | ❓ |
| URL scheme / CLI | ✅ holzbar:// | ✅ URL actions | ❌ | ✅ thaw:// | ✅ sanebar:// | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ | ❓ |
| Hotkeys | ✅ also per profile and item | ✅ | ✅ | ✅ | ✅ per icon | ✅ | ✅ | one | ✅ | Pro | ✅ | ✅ | ✅ | ✅ | ❓ |
| Zen mode (lock reveal gestures) | ✅ | Focus filter only | ❌ | ✅ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ | ❓ |
| Lock behind Touch ID / password | ✅ <sup>14</sup> | ❌ <sup>10</sup> | ❌ | ❌ | ✅ | ❌ | ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ |
| Show/hide animation | Shelf (three styles); the bar on macOS 26 only | ❓ | ❓ | Reduce Motion only | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ | ❓ | ✅ beta | ❓ | ✅ speed setting | ❓ |
| Screen Recording | optional | optional | optional | optional | not needed | optional | required | not needed | not needed | required | ❓ | likely required | for its screenshot tools | not needed | ❓ |
| Network connections | **none** | vendor: none <sup>11</sup> | Sparkle | Sparkle | Sparkle + anonymous event counts | licence + Sparkle | App Store: none | none | Sparkle | ❓ | App Store: none | check-in (versions, licence status) | none for core; AI servers (Pro) | analytics, crash reports, licence check | update check on by default; other network features opt-in |
| Export / import settings | ✅ | ❓ | ❌ | ✅ | ✅ (also from Bartender, Ice) | ❓ | cloud backup (VIP) | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Sync between Macs | 🔜 1.0.0 | ❌ | ❌ | ❌ | ❌ | ❓ | ✅ profiles (VIP) | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ (planned) | ❓ | ❓ |
| Languages | 11 | 6 | ❓ | 20 | English? | >=8 | 20 | 10 | ❓ | ❓ | 15 | 4 | ❓ | English? | 12+ |
| Dependencies, Swift | none, Swift 6 | closed | 5 packages, Swift 5 | 9 packages, Swift 6 | 3 packages, Swift 6 | ❓ | closed | 1 package, Swift 5 | 5, Swift 5 | closed | closed | closed | closed, native Swift | closed | none, Swift |
| Distribution | Homebrew | direct, Setapp (beta) | GitHub, Homebrew | GitHub, Homebrew | direct, Homebrew | direct, Homebrew | App Store | App Store, GitHub, Homebrew | GitHub, Homebrew | direct | App Store | direct | direct, Homebrew, App Store | direct | Homebrew, direct |
| Appearance (tint, border, shapes, black bar, corners, glass) | ✅ all; Sections and Apple-logo shapes, accent and gradient outlines (<sup>14</sup>), moods | styles: Glass, Pills, Outline, Gradient, Solid | tint, shadow, border, shapes | ✅ many, wallpaper tint | tint, border, corners, Liquid Glass | shelf styles, colours | menu bar shape, Apple-logo style | ❌ | icon size only | blends dots | ❓ | ✅ Liquid Glass, corners, borders, Moods, Single/Paired/Sections styles, Apple logo | ❓ | icon styles only | ❓ |
| Replaces or hides Apple's own items on macOS 27 | ✅ hides the clock, battery, Wi-Fi and Control Center; replacement icons | hides the clock and Control Center (vendor notes) | ❌ | ✅ replacement icons | ❓ | system controls stay visible | ❓ | cannot (per app only) | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Signed with Developer ID and notarized | ❌ (own certificate) | ❓ | ✅ | ✅ | ✅ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ vendor claim | ✅ |
| Build provenance (attestation, SLSA) | ✅ SLSA 3 | ❓ | ❌ | ✅ Cosign + SLSA | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Hides desktop icons | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❓ |
| Clipboard history, extras beyond the menu bar | ❌ | ✅ Command Bar, Top Shelf | ❌ | ❌ | ❌ | ❌ | MCP server | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ clipboard, launcher, AI | ✅ clipboard history | ✅ clipboard, Command Bar, many tools |
| Imports settings from other apps | ✅ Ice | ❓ Bartender 6 profiles (experimental) | ❌ | ❌ | ✅ Bartender, Ice | ❓ | ❓ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ | ❓ |
| Notch hub (widgets, files, now playing in the notch) | Hub ✅, Timers ✅, Calendar ✅, Live activities ✅, File drop ✅, Display controls ✅, Accessory alerts ✅, Notifications ✅, other modules 🔜 1.0.0 | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Calendar and meeting link in the hub (reads your calendars on this Mac only) | ✅ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Live activities in the hub (a capsule at the notch while something is going on; holzBar's are downloads and a camera or microphone in use) | ✅ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ❓ |
| Accessory alerts (connect, disconnect and low battery of AirPods and other accessories; holzBar's battery levels use a call that Apple does not document) | ✅ | ❓ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ | ❓ | ✅ |
| System readouts in the menu bar (CPU, memory, network, disk) | 🔜 1.1.0; CPU, memory and disk as text widgets ✅ <sup>14</sup> | ✅ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Launcher, command bar | ✅ palette, 🔜 1.2.0 launcher | ✅ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Clipboard history | 🔜 1.3.0 | ✅ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ✅ | ✅ |
| Window management, app switcher | 🔜 1.4+ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Screenshots, OCR, screen recording | 🔜 1.4+ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ | ❌ | ✅ |
| Per-app volume, audio output switcher | 🔜 1.4+ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❌ | ✅ |
| AI tools (translate, dictate, grammar), kept on the device | 🔜 1.4+, on-device only | ❓ | ❌ | ❌ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ✅ partly cloud (Pro) | ❌ | ❓ |
| Keyboard / VoiceOver | ✅ / ✅ | ✅ / ❓ | ❓ / ❓ | ✅ / ✅ | ✅ / ❓ | ✅ / ❓ | ✅ / ✅ | 1 hotkey / ❓ | 1 hotkey / ❓ | ❓ | ✅ / ❌ | ✅ / ❓ | ❓ | ❓ | ❓ |

<sup>1</sup> Bartender 7 is a one-time purchase; Bartender Pro is yearly, Mega Supporter lifetime. The vendor's pages show no amounts; a competitor's blog names $25, $20 a year and $80 (not verified). Bartender 6 covers macOS 26 and 15.
<sup>2</sup> Bartender 7 needs macOS 27; for macOS 26 the vendor recommends Bartender 6.
<sup>3</sup> Thaw's stable 2.0.1 (2 Sep) runs on macOS 26; the 3.0 beta (7 Oct) is for macOS 27.
<sup>4</sup> Tuck lists macOS 14 to 27; on macOS 27 the system controls (Wi-Fi, Sound, Control Center, clock) stay visible.
<sup>5</sup> Barbee's listing does not say; a user report says hidden-item icons display wrongly on macOS 27.
<sup>6</sup> Hidden Bar: the direct build works on macOS 27 with Accessibility but only hides per app; the App Store build cannot hide on macOS 27.
<sup>7</sup> Bartender 7 lists schedule, Focus filter, battery, app, VPN, microphone and display triggers; the vendor publishes no full list and no AND/OR logic.
<sup>8</sup> Thaw: app, network, VPN, Wi-Fi, Bluetooth, audio, display, time, Focus, battery and a script's exit code; battery and power are always on, the rest is enabled one by one.
<sup>9</sup> No AppleScript dictionary found in the project's Info.plist or documentation (checked, not stated).
<sup>10</sup> Not mentioned on any official Bartender page.
<sup>11</sup> The vendor says Bartender sends nothing anywhere. Bartender 5.0.52 briefly shipped analytics (Amplitude) and removed it; Sparkle and RevenueCat appear in third-party dependency lists (inferred).
<sup>12</sup> Glow, Brow and Lounge: ❌ means the vendor's site, changelog and privacy policy do not mention the feature (one source each, no independent test). Lounge's own blog says it lacks automation rules.
<sup>13</sup> Glow ships two builds: 2.x for macOS 26 and 3.x for macOS 27 (stable since 10 September 2026).
<sup>14</sup> New in 0.0.8. Rules react to power, Low Power Mode, apps, time, displays, the network, a VPN, the Wi-Fi name, camera and microphone in use and a script's result, and since 0.0.9 to the sound output and a connected Bluetooth device; Thaw's list also has a Focus as a trigger, where holzBar's Focus filter applies a profile on its own. Scripts run as you with holzBar's permissions, only from the folder you chose and only after you allowed their exact content; nothing about them is exported, imported or synced, and no URL command or Shortcut can turn on a rule that uses one. Widgets (macOS 14 to 27) show text from seven permission-free sources (date and time, battery, CPU load, memory, uptime, free disk space, a countdown), run a Shortcut you name, or show the first line of the output of a script you allowed (a script widget); at most twelve, their timers run only while a widget is visible, a script widget never runs on a timer, nothing runs while the module is off, and Shortcut names and the choice of a script never leave your Mac (the widgets' basic steps were checked on macOS 27). Dragging items without ⌘ (macOS 26 and 27) is an optional module that is off until you switch it on; it moves apps' items, not Apple's own, and on macOS 27 hides an app when you drop one of its items on the holzBar icon.
<sup>15</sup> Glow's changelog lists item count badges; it does not say what they count. Bartender 7: no badge of this kind found in its sources.

### Where holzBar is behind today

- **Automation:** Thaw, SaneBar and Bartender 7 have rules, per-item conditions and scripts. holzBar has them since 0.0.8, with a similar set of triggers; Thaw can use a Focus as a trigger, holzBar's Focus filter only applies a profile.
- **No Developer ID signature or notarization**, unlike Thaw, SaneBar, Ice and Lounge (the vendor's claim). holzBar needs the `xattr` step or the Homebrew cask.
- **Fewer languages** than Thaw and Barbee (20 each).
- **Little animation of the bar itself**: the holzBar Shelf has animation styles and the bar's items slide on macOS 26 only; not on macOS 14 and 15, and macOS 27 animates its own bar. Vanilla has smooth show and hide today. The AppleScript dictionary is small next to Bartender 7's.
- **No settings sync** since 0.0.7-beta3; the redesigned sync comes in 1.0.0. Barbee has cloud sync of profiles.
- **Not checked on real hardware** for several features, and one maintainer. SaneBar was sunset in June; Tuck and Glow ship updates every week or two.
- **Apple's own items on macOS 27** (clock, Control Center, Wi-Fi) cannot be hidden by Hidden Bar and Tuck; Thaw offers replacement icons and Bartender 7 hides the clock and Control Center. holzBar does both since 0.0.12.

- **Brow and Vorssaint already ship dozens of modules** (notch hub, launcher, clipboard, windows, capture, sound, system monitor, AI). holzBar's are planned (see below), one release at a time. Vorssaint is open source, notarized and has 25k stars on GitHub; holzBar has a fraction of that user base.

### What holzBar does better

- **Never connects to the network**, and a CI check proves it on every pull request; Ice, Thaw, SaneBar (anonymous counts), Glow, Lounge and Tuck all do.
- **No third-party packages** (Ice 5, Thaw 9, SaneBar 3), Swift 6.4 in Swift 6 mode, checked on macOS 26 and 27 on every code change.
- **Screen Recording is optional**, and permissions are listed and explained.
- A **build provenance attestation** for every release since 0.0.6, and SLSA Build Level 3 provenance since 0.0.7-beta2.
