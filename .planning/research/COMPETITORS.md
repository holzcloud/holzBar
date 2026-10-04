# Competitor check, 2026-10-04

Purpose: decide what the milestone "Automation" (0.0.7) builds, and which smaller gaps are worth a phase. Method: the products' own pages, GitHub READMEs, App Store pages and release notes, read on 2026-10-04 with WebFetch/WebSearch. **Only what a source says is written here.** `(u)` = unverified: a search snippet or a page that did not state it; `—` = not stated by any source I could open. Prices are as quoted by the source on that day. Page contents were summarised by a fetch tool, so before any claim goes into the README or the website (CLAUDE.md: re-check every claim), open the linked page again.

## 1. The products

| Product | Price / licence | Source |
|---|---|---|
| **Bartender 7** (macOS 27) and **Bartender 6** (macOS 26 and earlier) | Paid, closed source. Bartender 7 one-time, "Bartender Pro" yearly subscription with future upgrades, "Mega Supporter" lifetime; the page showed "Loading price" for all three, so **no amount verified**. 4-week trial. Bartender 6 is "Designed for macOS Tahoe, Sequoia and Sonoma"; Bartender 7 "is built for macOS 27. For macOS 26, grab the latest copy of Bartender 6". Also on Setapp (page for Bartender 5). Acquired by Applause in 2024 (MacStories, AlternativeTo: users complained it happened unannounced) | macbartender.com, /Bartender6/, /Bartender7/ |
| **Vanilla** | Free; Vanilla Pro one-time $10 (custom shortcut, "Completely Removed" section, auto-hide after 5 s, launch at login, 10 devices per licence). macOS Catalina and later | matthewpalmer.net/vanilla |
| **Hidden Bar** | Free, MIT. macOS 13 and later (v1.10 for 10.13 to 12). Mac App Store, Homebrew | github.com/dwarvesf/hidden |
| **Dozer** | Free, MPL-2.0. Repository metadata says macOS High Sierra and later; Sequoia/Tahoe support not stated by the page `(u)` | github.com/Mortennn/Dozer |
| **Barbee** | Free with in-app purchases: 3-day trial, lifetime $12.99, yearly $4.99. macOS 11 and later, 20 languages. A reviewer criticised "unnecessarily broad and invasive permission requests" including a helper install and Screen Recording | App Store id1548711022 |
| **iBar** (Menubar icon control tool) | Paid via in-app purchases, exact price not captured `(u)`. Aggregation mode for notched MacBooks (a floating window below the bar), normal mode with fold/hide, icon gap presets, always-hidden icons, hotkeys | App Store (search snippets) |
| **ExtraBar** | Not a hider: a command-centre bar of launch items (36+ app presets, deep links, shell scripts, Shortcuts, Terminal commands, 16 action types), floating or inline mode. Lifetime licence, launch price EUR 9.99, regular EUR 24.99. Claims "no network access, no data collection" | search snippets, hunted.space, docs on readthedocs `(u: not opened)` |
| **SaneBar** | Free, MIT, "every Pro feature is unlocked for everyone". macOS 14+, Apple Silicon only. Updates through Sparkle; "network activity is limited to updates and a few simple anonymous app counts". Also on Setapp | github.com/sane-apps/SaneBar |
| **Thaw** 3.0 beta | Free, GPL-3.0, macOS 26+, 20 languages, Accessibility required, Screen Recording optional, "no tracking, no account, no subscription"; Sparkle (see the README comparison table) | github.com/thaw-app/Thaw |
| **Ice** 0.11.12 | Free, GPL-3.0, macOS 14+. Its own README lists as planned: groups and profiles, conditional display triggers, menu bar widgets | github.com/jordanbaird/Ice |
| **MenubarX** | Free with in-app purchases (sources differ: one-time $5, Pro $6.99 `(u)`); a menu bar browser: web pages as menu bar mini apps; also on Setapp | search snippets, App Store |
| **iStat Menus 7.5** | Paid (price not shown on the page), 14-day trial, Setapp. macOS 11+. Monitoring items (CPU, GPU, memory, disk, network, battery, Bluetooth, sensors, weather, world clocks), "customizable rules/notifications", "no ads, analytics, or tracking" | bjango.com/mac/istatmenus |
| **Stats** | Free, MIT, macOS 12+. CPU, GPU, memory, disk, network, battery, fans, sensors, Bluetooth, clocks; desktop widgets. **Location Services for the Wi-Fi network name**. Contacts `api.mac-stats.com` (update checks, public IP) and `api.github.com`; "does not collect any telemetry" | github.com/exelban/stats |
| **Itsycal** | Menu bar calendar, Sparkle and MASShortcut, macOS 11+, Mac Calendar integration (so Calendar permission); price not stated. Used only as widget inspiration: one small item that opens a popover | mowglii.com/itsycal |
| Others named by AlternativeTo/MacStories/search | **Tuck** (hides clutter incl. Apple icons), **Barred** (open source, collapsible secondary bar), **AccessMenuBarApps**, **ChocolateBar** (Capterra listing) — only names seen, nothing read `(u)`. "Menu Bar Controller" and "Menu Bar Ninja": **no source found** by two searches, not covered | search results |

## 2. Feature comparison

Legend: ✅ stated by the source, ❌ the source says it is not there, — not stated, `(u)` unverified. holzBar column is from README.md (feature list and comparison table, 0.0.6) and the code.

| | holzBar 0.0.6 | Ice | Thaw 3.0 β | SaneBar | Bartender 6 / 7 | Vanilla | Hidden Bar / Dozer | Barbee | iBar |
|---|---|---|---|---|---|---|---|---|---|
| **Hiding and layout** | | | | | | | | | |
| Hidden + always-hidden sections | ✅ | ✅ | ✅ | ✅ (zones) | ✅ | ✅ (Pro: always hidden) | ✅ / ✅ | ✅ | ✅ |
| Separate bar for hidden items (notch) | ✅ Shelf | ✅ | ✅ | — | ✅ Bartender Bar | — | — | notch support | ✅ aggregation |
| Notch handling | ✅ | partly | ✅ | — | ✅ automatic | ✅ | — | ✅ | ✅ |
| Layout profiles / presets | ✅ | ❌ (planned) | ✅ | ✅ profiles | ✅ presets | — | — | — | — |
| Groups, spacers | ✅ | ❌ | ✅ | ✅ groups | ✅ | — | — | — | — |
| Item spacing | ✅ beta | ✅ | ✅ | ✅ | ✅ | — | — | ✅ | ✅ |
| Search / command bar | ✅ search | ✅ | ✅ | — | ✅ Quick Search; Bartender 7: Command Bar with clipboard history | — | — | — | — |
| Smooth show/hide animation | ❌ | ❌ | — | — | — | ✅ ("fluid animations", MacStories) | — | — | — |
| Hide desktop icons | ❌ | ❌ | — | — | — | ✅ ("bonus", MacStories) | — | — | — |
| Lock hidden items (Touch ID / password) | ❌ | ❌ | — | ✅ | — | — | — | — | — |
| **Triggers and automation** | | | | | | | | | |
| Auto-reveal on battery / offline | ✅ (low battery, offline) | ❌ | ✅ | ✅ battery | ✅ | — | — | "auto-hide/show based on workflow" `(u)` | — |
| Triggers: Wi-Fi network | ❌ | ❌ | ✅ | ✅ | ✅ | — | — | — | — |
| Triggers: location | ❌ | ❌ | ✅ | — | ✅ | — | — | — | — |
| Triggers: time / schedule | ❌ | ❌ | ✅ | ✅ schedule | ✅ time, date | — | — | — | — |
| Triggers: app running / frontmost / launch | ❌ | ❌ | ✅ | ✅ app launch | — (6/7 page: "and more") | — | — | — | — |
| Triggers: Focus mode | ❌ | ❌ | ✅ (also Focus filter binds a profile) | ✅ | — | — | — | — | — |
| Triggers: external display | ✅ profile bound to a display | ❌ | ✅ | ✅ | — | — | — | — | — |
| Triggers: VPN, Bluetooth, audio, camera/mic, Energy Mode, thermal | ❌ | ❌ | ✅ all | — | Bartender 7 page: "your VPN on public Wi-Fi, your mic in meetings" | — | — | — | — |
| Trigger = script result | ❌ | ❌ | ✅ | ✅ custom script | — | — | — | — | — |
| Conditions combined (AND / OR) | ❌ | ❌ | ✅ | — | — | — | — | — | — |
| Auto-apply a profile from a trigger | ❌ (display and Space only) | ❌ | ✅ | ✅ profiles | ✅ "automatically apply presets" | — | — | — | — |
| Pre/post hooks (scripts) when a profile applies | ❌ | ❌ | ✅ | — | — | — | — | — | — |
| Shortcuts / App Intents | ✅ | ❌ | ✅ | — | ✅ (Bartender 7: Shortcuts, Siri) | — | — | — | — |
| AppleScript | ❌ | ❌ | — | ✅ "full scripting integration" | ✅ Bartender 7 | — | — | — | — |
| URL scheme | ✅ `holzbar://` | ❌ | ✅ `thaw://` | — | — | — | — | — | — |
| Zen mode (lock all reveal gestures) | ✅ | ❌ | ✅ | — | — | — | — | — | — |
| **Widgets** | | | | | | | | | |
| Custom menu bar items without code | ❌ | ❌ (planned) | — (not in the README) | — | ✅ "Widgets", beta in 6.0.0, rename and describe in 6.3.0; Bartender 7: "built-in data sources, or make your own with custom scripts" | — | — | emoji, SF Symbols, text, images as the item's look | — |
| Script output as an item | ❌ | ❌ | — | — | ✅ Bartender 7 (custom scripts) | — | — | — | — |
| Run scripts as launchers | ❌ | ❌ | — | — | — | — | — | — | ExtraBar does (shell scripts, Shortcuts) |
| **Appearance** | | | | | | | | | |
| Tint, border, shadow, shapes | ✅ | ✅ | ✅ | ✅ custom styling | ✅ glass, gradients, rounded | — | — | ✅ customization | — |
| Black bar / rounded corners | ✅ | ❌ | corners | — | ✅ rounded corners, per-Space style | — | — | — | — |
| **Settings, privacy, support** | | | | | | | | | |
| Export / import | ✅ | ❌ | ✅ | — | — | — | — | — | — |
| Sync between Macs | ✅ any folder | ❌ | ❌ | — | — | Pro licence on up to 10 devices (a licence, not settings) | — | — | — |
| Network connections | **none** | Sparkle | Sparkle | Sparkle + anonymous counts | — (Bartender 6 checks licence/updates, `u`) | — | — | — | — |
| Screen Recording | optional | required | optional | — (Accessibility only stated) | Bartender 7: "functions without requiring screen recording" | required on newer macOS | — | requested (reviewer complaint) | — |
| macOS | 14 to 27 | 14+ (not 27) | 26+ | 14+ | 6: 14 to 26; 7: 27 | Catalina+ | 13+ / High Sierra+ | 11+ | — |
| Open source | ✅ GPL-3.0 | ✅ | ✅ | ✅ MIT | ❌ | ❌ | ✅ / ✅ | ❌ | ❌ |

### Widget apps (inspiration only)

| App | What a "widget" is | Data sources | Permission / network |
|---|---|---|---|
| iStat Menus 7.5 | One or several status items per data type, combined mode to save space, rules and notifications | CPU, GPU, memory, disk, network, battery, Bluetooth, sensors, fans, weather, clocks | weather needs network (6 months of data in every licence); "no analytics" |
| Stats | One status item per module, each with a chosen view (text, chart, ...) | same families | Location Services for the Wi-Fi name; contacts two hosts for updates and public IP |
| Itsycal | One item (date/time text) opening a calendar popover | Calendar | Calendar access |
| Bartender 6 / 7 Widgets | Custom items, no code, "built-in data sources, or make your own with custom scripts" (7) | not listed on the page | not stated |
| Barbee | The item's appearance: emoji, SF Symbols, text, images | — | — |

What these tell us: the simplest widgets are a status item that shows a string from a cheap source (clock, battery, CPU load, memory) and refreshes on a timer or an event. The permission problem shows up only with Wi-Fi name (Location), calendars (Calendar) and weather (network).

## 3. What holzBar lacks, ranked

Ranking = value to holzBar's users (how many competitors have it, how often asked) times fit to the principles (Modern, Lean, Private/never online, Apple's way, Least privilege). Fit: A good, B workable with care, C poor.

| # | Gap | Who has it | Fit | Decision |
|---|---|---|---|---|
| 1 | **Automatic triggers that apply a profile or reveal items** (Wi-Fi, app, time, power, display; AND/OR) | Bartender 5/6/7, Thaw, SaneBar | A for app, power, time, display, network type; B for Wi-Fi name (Location) and Focus | Milestone, phase 8 |
| 2 | **Profile bound to a Focus filter** | Thaw | A if `SetFocusFilterIntent` works on macOS 26/27 (a forum report says `perform` is never called on 26.5, Section 4) | Phase 8, behind a spike |
| 3 | **Custom menu bar items (widgets) without code** | Bartender 6/7, Ice (planned), iStat/Stats as separate apps | B: holzBar already creates status items (spacers, group icons); cost is energy and the macOS 27 backend | Milestone, phase 10, staged |
| 4 | **Scripts as trigger condition and action / profile hooks** | Thaw, SaneBar, Bartender 7 (AppleScript), ExtraBar | B: an escalation surface in an unsandboxed app with Accessibility; only with the security design in phase 9 | Milestone, phase 9 |
| 5 | **Lock hidden items behind Touch ID / password** | SaneBar | A: `LocalAuthentication`, no permission, no network. Caveat: a lock the user can bypass in Settings is theatre; say what it protects (shoulder surfing, a child at the Mac) | Phase 11 |
| 6 | **Smooth show/hide animation** | Vanilla | B: animation costs frames; only during the 0.2 s of a reveal, no timers when idle | Phase 12 |
| 7 | **AppleScript dictionary for holzBar itself** (show/hide, apply profile) | Bartender 7, SaneBar | B: Automation permission protects callers, but it is one more input path; the URL scheme and Shortcuts already cover it | Backlog, not this milestone |
| 8 | **Hide desktop icons** | Vanilla | C/B: no public API; the known way is a Finder preference plus a Finder restart `(u)` | Phase 13 spike, dropped if there is no clean API |
| 9 | Triggers for VPN, Bluetooth, audio output, camera/mic in use, Energy Mode, thermal | Thaw | A for VPN/network (NWPathMonitor), audio (CoreAudio), thermal and low-power (ProcessInfo notifications); B for Bluetooth (permission) | Later triggers on the phase 8 framework; the framework must make adding one cheap |
| 10 | Items react to another icon changing (watched icon) | Thaw | exists as "Show When It Changes" | none |
| 11 | Bartender 7 Command Bar with clipboard history; Top Shelf, AirPods/battery alerts | Bartender 7 / Pro | C: clipboard history is a privacy liability and leaves the menu bar's job | Not planned |
| 12 | Menu bar per-Space style | Bartender 5 | already: "Look on every desktop" | none |
| 13 | Icon fold-away window aggregated like iBar | iBar | holzBar Shelf covers it | none |

Where holzBar already leads, per the sources: no network at all (SaneBar, Ice, Thaw, Barbee/Stats contact servers or ask broad permissions), no dependencies, settings sync through any folder, macOS 14 to 27 launched in CI, Zen mode, unit-tested logic.

Competitive pressure: Thaw already ships the broadest trigger set (battery, power, frontmost/running app, network, VPN, Wi-Fi, Bluetooth, audio, displays, time, Focus, place, Energy Mode, thermal, camera/mic, script, watched icon), AND/OR, profile hooks and Focus filters; SaneBar ships triggers, AppleScript and a lock for free; Bartender 7 adds widgets and AppleScript for macOS 27. holzBar's reason to exist next to them is privacy and least privilege: the right answer is **fewer, permission-free triggers first, the permissioned ones opt-in**, not copying all of Thaw's list.

## 4. API facts behind the trigger ranking

Verified in Apple's documentation (the `.md` form of developer.apple.com pages) or an Apple DTS answer, 2026-10-04:

- **Wi-Fi name**: `CWInterface.ssid()` needs Location Services since macOS 14: Apple DTS (Quinn): "Accessing the `ssid` property now requires the location privilege"; the CoreWLAN header says "SSID information is not available unless Location Services is enabled and the user has authorized the calling app to use location services" (forums.developer.apple.com/thread/732431). Without it `ssid()` returns nil. Stats lists Location Services for exactly this reason.
- **Wi-Fi events**: `CWWiFiClient.startMonitoringEvent(with: .ssidDidChange)` with a `CWEventDelegate` (macOS 10.10+) is event-driven. The docs say the `com.apple.wifi.events` entitlement is required, but an Apple forum thread (11307) says the documentation is wrong and a non-sandboxed app works; **needs a test on a Mac**, because holzBar must not add an entitlement that a self-signed app cannot carry.
- **Focus, INFocusStatusCenter**: macOS 12+, needs authorization and the Info.plist usage text, and the Communication Notifications capability; it only returns a Boolean "is focused", never which Focus. Communication Notifications is an entitlement that needs a provisioning profile, which holzBar's self-signed build cannot have. **Not usable.**
- **Focus filter**: `SetFocusFilterIntent` (App Intents, macOS 13+): the system runs the app's intent when the user turns the Focus on or off; the user sets it up in System Settings, so holzBar gets no permission and reads no Focus data. holzBar already ships App Intents. Risk: an unanswered forum post (May 2026, developer.apple.com/forums/thread/826766) reports that after macOS 26.5 `perform` is never called and entity selection is broken; **spike on macOS 26.x and 27 first**. Thaw's README says it binds profiles to a Focus filter, so it works for somebody.
- **Reading the active Focus by file** (`~/Library/DoNotDisturb/DB/Assertions.json`) needs Full Disk Access. Rejected: far beyond least privilege.
- **Location**: `CLLocationManager` needs `requestWhenInUseAuthorization` or always, an Info.plist usage text, and the user's approval. The region/visit services exist, but holzBar needs a location trigger only if the user wants "at home"; **recommended: no location trigger** (a Wi-Fi name covers "at home/at work" without GPS).
- **Time**: no permission. Event-driven means one timer armed for the next rule boundary, re-armed on `NSCalendarDayChanged`, `NSSystemClockDidChange`, time-zone and wake notifications. `NSBackgroundActivityScheduler` is documented for activities of 10 minutes or more and gives the system freedom to defer, so it is **wrong for "08:00 sharp"**.
- **Scripts**: `NSUserScriptTask` and its subclasses `NSUserUnixTask`, `NSUserAppleScriptTask`, `NSUserAutomatorTask` (macOS 10.8+) are "intended to execute user-supplied scripts" outside the sandbox, with results for the Unix and AppleScript variants. `NSAppleScript` runs in-process and "you cannot use this method to send Apple events to other applications" with `executeAppleEvent`, but a script body can still address other apps, which raises the Automation (Apple events) permission prompt per target app.

From my own knowledge, to verify on a Mac before the phase plan is final (not read from a source today): `NSWorkspace.didActivateApplicationNotification`, `didLaunchApplicationNotification`, `didTerminateApplicationNotification` (no permission); `IOPSNotificationCreateRunLoopSource` for power source (already in `RevealRules.swift`); `ProcessInfo.isLowPowerModeEnabled` with `NSProcessInfoPowerStateDidChange`; `ProcessInfo.thermalState` with `thermalStateDidChangeNotification`; `NSApplication.didChangeScreenParametersNotification` (already used); `NWPathMonitor` interface types (`usesInterfaceType(.wifi)`, `.wiredEthernet`, `.other` for VPN-like) (already used for "offline").

## 5. Sources

- Bartender: https://www.macbartender.com/ , https://www.macbartender.com/Bartender6/ , https://www.macbartender.com/Bartender7/ , https://www.macbartender.com/Bartender5/ , https://macbartender.com/Bartender6/release_notes
- Vanilla: https://matthewpalmer.net/vanilla/
- Hidden Bar: https://github.com/dwarvesf/hidden
- Dozer: https://github.com/Mortennn/Dozer
- Thaw: https://github.com/thaw-app/Thaw , https://raw.githubusercontent.com/thaw-app/Thaw/main/README.md
- SaneBar: https://github.com/sane-apps/SaneBar
- Ice: https://github.com/jordanbaird/Ice
- Barbee: https://apps.apple.com/app/id1548711022
- iBar: https://apps.apple.com/app/id6443843900 (search snippet), https://alternativeto.net/software/ibar-menubar/about/
- ExtraBar: https://extrabar-documentation.readthedocs.io/en/latest/introduction.html , https://hunted.space/product/extrabar
- MenubarX: https://setapp.com/apps/menubarx , https://alternativeto.net/software/menubarx/about
- iStat Menus: https://bjango.com/mac/istatmenus/
- Stats: https://github.com/exelban/stats
- Itsycal: https://www.mowglii.com/itsycal/
- Roundups: https://www.macstories.net/roundups/managing-your-mac-menu-bar-a-roundup-of-my-favorite-bartender-alternatives/ , https://alternativeto.net/software/bartender (403 for direct fetch; search snippet only), https://sixcolors.com/link/2024/06/rounding-up-bartender-alternatives/
- Apple: https://developer.apple.com/forums/thread/732431 , https://developer.apple.com/documentation/corewlan/cweventdelegate , https://developer.apple.com/documentation/corewlan/cwwificlient/startmonitoringevent(with:) , https://developer.apple.com/forums/thread/11307 , https://developer.apple.com/documentation/intents/infocusstatus , https://developer.apple.com/documentation/appintents/setfocusfilterintent , https://developer.apple.com/forums/thread/826766 , https://developer.apple.com/documentation/corelocation/cllocationmanager , https://developer.apple.com/documentation/foundation/nsuserscripttask , https://developer.apple.com/documentation/foundation/nsapplescript , https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler
