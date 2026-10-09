# Alternatives to Bartender: feature inventory, 2026-10-09

Extends `../COMPETITORS.md` (2026-10-04); it does not repeat that file's per-product table or API facts. Method: web only (WebFetch/WebSearch, 2026-10-09). `(u)` = from a search snippet, an aggregator or a blog, not the product's own page; `—` = not stated. Prices as quoted by the source. Blog roundups (drbuho, badgeify, Lounge blog, publicspace, devsreviews) are partly written by competitors or affiliates: re-open the product page before any claim goes into the README. The fetch tool summarises pages and contradicted itself once (see "Open conflicts").

## 1. What is new since COMPETITORS.md

1. **macOS 27 ("Golden Gate", released 2026-09-14) renders the whole menu bar as one window** instead of one window per status item. This broke every hider that moved or resized item windows: Bartender 5/6, Ice, Hidden Bar (old build), Barbee, SaneBar, Thaw 2.x (publicspace.net, badgeify.app, brow-app.com, devsreviews.com; all agree).
2. **Apple's native answer in macOS 27**: a double-arrow overflow button appears when items do not fit (notch, long app menus); a click shows the hidden items temporarily to the left of the notch (MacStories review, publicspace). Also: show/hide of Apple's own items in System Settings, Cmd-drag reorder (already in 26), a Liquid Glass transparency slider (Clear/Tinted became a slider in Appearance), and the removal of the desktop screenshot API (breaks tools that paint a wallpaper strip to tint the bar or hide the notch). Native gaps per badgeify: no conditional visibility, no styling, no secondary bar, no profiles. holzBar already claims "native overflow button support" and lists "Native overflow support" as a 0.0.7 item.
3. **macOS 26 (Tahoe)**: bar floats without background by default (System Settings > Menu Bar > Show Menu Bar Background); multiple Control Centers; the under-the-hood changes broke Bartender 5 (9to5mac/Tahoe coverage, `(u)`).
4. **Workarounds are undocumented and fragile**: Thaw and Brow use different methods; "Apple could close the door again in any point update" (publicspace). Hidden Bar v1.11 uses a private framework (same mechanism as the exam lockdown mode) and needs Accessibility.
5. **Ice is effectively dead for 27**: no maintainer response since June 2026 (publicspace); last stable 0.11.12, Oct 2024 / Sept 2025 per two blogs (they disagree); GitHub page shows 395 open issues. holzBar's reason to exist (Ice fork with 27 support) is intact.
6. **Bartender changed shape**: Bartender 7 for macOS 27 (beta, free during beta per a search result); Bartender Pro (2026-05-12, MacRumors) is $15/yr and adds "Top Shelf" (widgets for calendar, weather, music in the notch area, clipboard with password ignore, file shelf with AirDrop, audio control, calendar alerts); Bartender 6 one-time $20 (MacRumors) vs. "$12+" (devsreviews, `u`); Mega Supporter $80 lifetime. Bartender 7 "can function without Screen Recording by displaying app icons instead of captured images" (Lounge blog quoting Bartender 7).

## 2. Inventory of alternatives not (or only briefly) covered in COMPETITORS.md

Format per tool: price/licence | maintained | notable features | does what Bartender does not | permissions | macOS | source.

### Lounge (new)
- **Price/licence**: $3.99 per year, 7-day trial, proprietary. Written by the vendor of the "Lounge Blog", so its comparisons are marketing.
- **Maintained**: yes, sold in 2026 `(u)`; claims to hide reliably on 27 in its own test.
- **Features**: drag icons between sections, notch-aware hover panel at the notch showing hidden and shown icons, Cmd+Shift+L toggle, icon styles, dividers, animation speed, clipboard history (blog). Lounge Pro: a local HTTP listener lets Claude Code, Cursor, Gemini, Aider send notifications to the menu bar.
- **Beyond Bartender**: AI-agent notifications into the bar over localhost HTTP.
- **Permissions**: Accessibility only, no Screen Recording (own claim).
- **macOS**: 26.0 or later (own page).
- **Source**: https://www.bartendermacoslounge.com/ , https://www.bartendermacoslounge.com/blog/best-macos-menu-bar-managers

### Brow (Menu Bar Manager module) (new)
- **Price/licence**: free, closed `(u)`. An all-in-one utility with about 25 modules; menu bar management is one.
- **Maintained**: yes; stable on macOS 27 since 1.0.63 (August 2026).
- **Features**: hides icons, hidden ones expand from the notch; simpler feature set. Method: screenshots the bar to identify individual icons (publicspace), so it presumably needs Screen Recording `(u)`.
- **Beyond Bartender**: bundled other utilities.
- **macOS**: 27 confirmed; older not checked.
- **Source**: https://devsreviews.com/reviews/macos-27-menu-bar-managers/ , https://www.publicspace.net/blog/macos-27-menu-bar/ , https://brow-app.com/blog/macos-27-menu-bar (not the product page; product page not opened).

### OverflowBar (new, open source)
- **Price/licence**: free, MIT. 106 commits, active.
- **Features**: persistent arrow; hidden status icons appear in a second row (a bar below) on click or pointer move; real menu bar controls activate the original icons; Liquid Glass look on 26+; keeps Wi-Fi, Battery, Clock always visible.
- **Permissions**: Accessibility (discovery, activation, layout), Screen Recording (live icon capture).
- **macOS**: 15 or later, Apple Silicon and Intel. 27 support not stated.
- **Source**: https://github.com/EvanProgramming/OverflowBar

### Hidden Bar (update to COMPETITORS.md)
- **Price/licence**: free, MIT. v1.11 / v1.11.1 ("Hiding works again on macOS 27") released 2026-10, so **maintained again**; COMPETITORS.md did not say so.
- **How**: on 27 a status item that is too wide is dropped, so the old spacer trick failed. v1.11 asks macOS to hide icons through a private framework; the arrow is the divider (Cmd-drag left of it to hide, right to keep). Hover-to-expand is off by default (`defaults write com.dwarvesv.minimalbar hoverToExpand -bool true`). Per-app, not per-icon; system items (clock, Wi-Fi) always visible; must run from /Applications; login item via `SMAppService`.
- **Permissions**: Accessibility on 27 (without it the bar stays expanded). The non-sandboxed download works; **the App Store build is sandboxed and cannot hide on 27**.
- **macOS**: 13+.
- **Source**: https://newreleases.io/project/github/dwarvesf/hidden/release/v1.11 , https://github.com/dwarvesf/hidden
- Note for holzBar: another independent confirmation that a private-framework path to "hide by app" exists on 27 (relevant to the macOS 27 backend; no detail on which framework).

### Dozer
- **Licence**: free, MPL-2.0. **Effectively abandoned**: one source says no GitHub activity after 2021, Homebrew deprecated the cask on 2023-11-26 as discontinued, another source claims active (conflict; the two are not reconcilable from here). No 26/27 support stated. Source: https://github.com/Mortennn/Dozer , https://alternativeto.net/software/dozer

### Vanilla
- Free; Pro $10 one-time. Page lists no macOS 26/27 statement; Catalina+. Not in any macOS 27 working list. Treat as unmaintained for 27 `(u)`. Source: https://matthewpalmer.net/vanilla/

### Barbee
- Free with in-app purchases: lifetime $12.99, yearly VIP $4.99, 3-day trial. Version 5.0 (Sept 10; year not shown) "refactored codebase for better compatibility with the latest macOS". Notch support, automation rules (display of apps), cloud backup, emoji/SF Symbol/text/image icons, VoiceOver support, hide app menus, reduce spacing. **Permissions: Screen Recording and a helper utility** (reviewer: "unnecessarily broad"); no search. One roundup lists it as open source (Lounge blog); the App Store page does not say so: treat as closed. Broken on 27 per devsreviews/brow `(u)`. Source: https://apps.apple.com/app/id1548711022

### iBar
- Free; yearly subscription $2.99 (price now captured, was `(u)`). Aggregation mode (floating window below the bar), normal fold mode, spacing, drag reorder, always-hidden. 15+ languages. Listed "macOS 10.12 or later". Reported UI lag when toggling. No data collection claimed. No 27 statement. Source: https://apps.apple.com/app/id6443843900

### Thaw (update)
- COMPETITORS.md said 3.0 beta, macOS 26+. New: its 3.0.0-beta.2 notes (release page date read as "October 7, 2024", clearly a typo for 2026) add dynamic triggers (show items while an app runs, restore layout when it closes), URL scheme, troubleshooting restore of stuck items, gradients with angle, layout badges for items macOS will not let follow their section. **For macOS 27 it ships replacements for Apple items it cannot hide** (Time Machine, Focus, AirDrop, Now Playing, Fast User Switching) and a **swap bar** for toggling sections. 11.9k stars; Raycast integration; Homebrew `brew install thaw`; nightly channel. A second source calls 2.0 the working 27 release, 3.0 the beta line. Source: https://github.com/thaw-app/Thaw/releases

### SaneBar (update)
- Latest 2.1.89, free, MIT, macOS 14+, Apple Silicon only; Icon Panel or Second Menu Bar; Touch ID/password lock; auto-show on battery, Wi-Fi, Focus, app launch; per-icon hotkeys, profiles, AppleScript; search reaches icons hidden behind the notch. Reported **broken on 27** by two roundups (`u`). Source: https://github.com/sane-apps/SaneBar

### Ice (update)
- GPL-3.0, 29.8k stars, 395 open issues, macOS 14+. Feature list on the README now also names menu bar widgets and a search; broken on 27, no maintainer response since June 2026. Source: https://github.com/jordanbaird/Ice

### Bartender 6 / 7 / Pro (update)
- See section 1 point 6. Bartender 7 page features: Command Bar (items plus clipboard history), styles (glass, pills, outlines, gradients, solid), spacing down to tiny, triggers (battery when unplugged, VPN on public Wi-Fi), Shortcuts/AppleScript/hotkeys/Siri, profiles with hotkey or trigger switching, automatic notch handling with the Bartender Bar. Sources: https://www.macbartender.com/Bartender7/ , https://www.macrumors.com/2026/05/12/bartender-pro/

### Other menu bar tools seen (not hiders, or only names)
- **Boring Old Menu Bar** (publicspace): $9.95, 14-day trial; solid Catalina-style bar, per-Space, rounded corners; version 1.29+ needed on 27, 1.31 adds features. https://www.publicspace.net/BoringOldMenuBar
- **TopNotch**: free, black bar to hide the notch; broken on 27 as of 2026-09-29 (needs the removed screenshot API); update promised.
- **Barred** (Product Hunt/hunted.space), **TobiBar** (leinss.xyz), **ChocolateBar** (Capterra), **BrowBro** (alternativeto), **BetterTouchTool** (partial workarounds): names only, nothing opened `(u)`.
- Search found no product named "Glow" except as cited in one blog title; treat as unverified.

## 3. Matrix

Legend: Y = stated, N = stated absent, ? = not stated, B = broken or unconfirmed on macOS 27 per roundups `(u)`. Tools: Bartender 7 (B7), Thaw, Ice, Hidden Bar (HB), Lounge, Brow, SaneBar (Sane), Barbee, iBar, OverflowBar (OvB), Vanilla, Dozer, holzBar claim (README, 2026-10-09), macOS 27 native (Apple).

| Feature | B7 | Thaw | Ice | HB | Lounge | Brow | Sane | Barbee | iBar | OvB | Vanilla | Dozer | holzBar | Apple 27 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Works on macOS 27 | Y beta | Y | N | Y 1.11 | Y (own test) | Y | B | B | ? | ? | ? | ? | Y | n/a |
| macOS 14-26 | Y (6) | 26+ | Y | 13+ | 26+ | ? | 14+ | 11+ | 10.12+ | 15+ | Catalina+ | old | Y | n/a |
| Price | $/sub | free | free | free | $3.99/yr | free | free | $12.99 / $4.99 yr | free, $2.99/yr | free | free, $10 | free | free | free |
| Open source | N | GPL | GPL | MIT | N | N `u` | MIT | N | N | MIT | N | MPL | GPL | n/a |
| Hide / always-hide | Y | Y | Y | hide | Y | hide | Y | Y | Y | hide | Y (Pro) | hide | Y | overflow only |
| Second bar / panel | Y Bartender Bar | Y + swap bar | Y | N | Y notch panel | N (expands from notch) | Y | ? | Y | Y | N | N | Y Shelf | N |
| Per-icon control | Y | Y | Y | N (per app) | Y | ? | Y | Y | Y | Y | Y | Y | Y | Y (Apple items) |
| Profiles | Y | Y (+Focus filter) | N | N | ? | ? | Y | ? | N | N | N | N | Y | N |
| Rule/trigger engine | Y | Y broad | N | N | ? | ? | Y | Y rules | N | N | N | N | partial, 0.0.7 | N |
| Conditional show (battery, VPN, Wi-Fi) | Y | Y | N | N | ? | ? | Y | ? | N | N | N | N | partial | N |
| Search / command bar | Y + clipboard | Y | Y | N | ? | ? | Y | N | N | N | N | N | Y | N |
| Widgets / Top Shelf | Y Pro | N | planned | N | clipboard, AI | bundled modules | N | N | N | N | N | N | roadmap | N |
| Clipboard / file shelf | Y Pro | N | N | N | Y clipboard | ? | N | N | N | N | N | N | N (declined) | N |
| Touch ID lock | N | ? | N | N | ? | ? | Y | ? | N | N | N | N | roadmap | N |
| AppleScript | Y | ? | N | N | ? | ? | Y | ? | N | N | N | N | roadmap | N |
| Shortcuts / App Intents | Y | Y | N | N | ? | ? | ? | ? | N | N | N | N | Y | N |
| URL scheme | ? | Y | N | N | ? | ? | ? | ? | N | N | N | N | Y | N |
| Local HTTP API for agents | N | N | N | N | Y Pro | ? | N | N | N | N | N | N | N | N |
| Styling (tint, border, shape) | Y | Y | Y | N | icon styles | ? | Y | Y | ? | glass | N | N | Y | Liquid Glass slider |
| Replacements for unhideable Apple items | ? | Y | N | N | ? | ? | ? | ? | N | N (pins them visible) | N | N | ? | n/a |
| Hide app menus | ? | ? | N | N | ? | ? | ? | Y | N | N | N | N | ? | N |
| Spacing control | Y | Y | Y | N | ? | ? | Y | Y | Y | ? | N | N | beta | N |
| Settings export / sync | ? | Y export | N | N | ? | ? | ? | cloud backup | N | ? | N | N | Y export, sync paused | iCloud n/a |
| Permission: Accessibility | Y | Y | Y | Y (27) | Y only | ? | Y | ? | ? | Y | ? | ? | Y | none |
| Permission: Screen Recording | optional | optional | required (limited mode possible) | N | N | probably `u` | ? | Y | ? | Y | Y newer macOS | N | optional | none |
| Helper / extra component | ? | N | N | N | ? | ? | ? | Y helper | ? | ? | ? | N | N (single executable) | n/a |
| Network use | licence/update | Sparkle | Sparkle | N `u` | licence/update `u` | ? | Sparkle + counts | N claimed | N claimed | ? | ? | N | none | n/a |
| Private framework for hiding on 27 | ? | undocumented method | n/a | Y | ? | screenshot method | ? | ? | ? | ? | ? | ? | see 27 backend | n/a |
| Distribution | direct, Setapp | brew, DMG | brew | brew, DMG (MAS broken on 27) | DMG | ? | brew, DMG, Setapp | MAS | MAS | GitHub | DMG | brew (deprecated) | brew | OS |

## 4. What others do that Bartender does not (and holzBar may care about)

- **Thaw**: Focus filter profile binding, script/AND-OR triggers, replacements for Apple items that 27 forbids hiding, swap bar, nightly channel.
- **SaneBar**: Touch ID lock (Bartender has none), per-icon hotkeys.
- **Lounge**: localhost HTTP API for AI agents, one permission only, annual price under $4.
- **Hidden Bar / OverflowBar / iBar**: minimal single-purpose design; OverflowBar keeps system controls (Wi-Fi, Battery, Clock) from being hidden, which avoids a class of bug reports on 27.
- **Barbee**: hides app menus; cloud backup.
- **Bartender only**: Top Shelf (widgets, clipboard, file shelf, AirDrop) and a Command Bar with clipboard; both are outside holzBar's stated principles (Private, Lean), consistent with COMPETITORS.md gap 11.

## 5. Implications for holzBar (inventory-level, not a decision)

1. holzBar is one of very few tools that run on 14-26 and 27 from one build; Thaw is 26+, Lounge 26+, Ice 14-26 only, SaneBar/Barbee/Hidden-Bar-App-Store broken on 27.
2. The macOS 27 gaps in Apple's native overflow (no conditions, no styling, no profiles, no second bar) are exactly holzBar's feature list; say so in the README, with the MacStories and publicspace sources, after checking them again.
3. New ideas not in COMPETITORS.md ranking: (a) replacement items for Apple items that cannot be hidden on 27 (Thaw has it); (b) keeping system items (Clock, Wi-Fi, Battery) pinned visible (OverflowBar); (c) a Screen-Recording-free mode (Bartender 7 shows app icons instead of captures, Lounge claims Accessibility only): matches the Least privilege principle; holzBar's own README says Screen Recording only when needed, so the comparison row should highlight it; (d) a local control API for agents (Lounge): conflicts with Private/least surface unless limited to the existing URL scheme; probably not.
4. Risk to track: Apple "could close the door again in any point update" (publicspace); Hidden Bar and Thaw use private or undocumented routes too. holzBar's own backend carries the same risk; the compat CI job (macos-26, xcode-27) is the guard.

## 6. Open conflicts and gaps

- Ice last release: "October 2024" (drbuho/teenyapps-era blog) vs. "no updates since September 2025" (devsreviews) vs. 0.11.12 per holzBar README. Not resolved; GitHub releases page not opened.
- Dozer maintained vs. abandoned: unresolved.
- Bartender 6 price: $20 (MacRumors) vs. "$12+" (devsreviews). Use MacRumors; macbartender.com showed "Loading price" on 2026-10-04.
- Thaw release date typo on the releases page summary (2024 vs. 2026).
- Not read: Brow product page, Barred, TobiBar, ChocolateBar, BrowBro, BetterTouchTool, Setapp pages, AlternativeTo (403). Apple developer documentation on the 27 overflow API: none found; no source says whether Apple exposes any API for managing overflow.
- No product named "MenuBarX" newer information was fetched; keep the COMPETITORS.md row.

## 7. Sources

- https://www.publicspace.net/blog/macos-27-menu-bar/
- https://badgeify.app/macos-27-golden-gate-menu-bar-changes/
- https://devsreviews.com/reviews/macos-27-menu-bar-managers/
- https://brow-app.com/blog/macos-27-menu-bar
- https://www.macstories.net/stories/macos-27-the-macstories-review/3/
- https://eclecticlight.co/2026/09/14/apple-has-released-macos-golden-gate-and-security-updates-to-tahoe-26-7-sequoia-15-8/ (release date, from a search snippet)
- https://www.macrumors.com/2026/05/12/bartender-pro/ , https://www.macbartender.com/Bartender7/
- https://www.bartendermacoslounge.com/ , /blog/best-macos-menu-bar-managers , /blog/bartender-alternatives-macos-27
- https://github.com/thaw-app/Thaw , /releases ; https://github.com/jordanbaird/Ice ; https://github.com/sane-apps/SaneBar ; https://github.com/EvanProgramming/OverflowBar ; https://github.com/holzcloud/holzBar
- https://newreleases.io/project/github/dwarvesf/hidden/release/v1.11
- https://apps.apple.com/app/id1548711022 (Barbee) , https://apps.apple.com/app/id6443843900 (iBar)
- https://matthewpalmer.net/vanilla/ , https://alternativeto.net/software/dozer , https://www.publicspace.net/BoringOldMenuBar
- https://www.drbuho.com/how-to/bartender-alternatives , https://teenyapps.com/articles/bartender-alternatives/ (search results only)

holzBar README claims as read 2026-10-09: hide/show/style, profiles and groups, spacers and folders, Zen mode, Shelf, URL commands, Shortcuts actions, black bar, folder sync (paused in 0.0.7-beta2), macOS 27 camera/mic indicator dot, native overflow support, dedicated 27 backend; permissions Accessibility plus Screen Recording only when needed, no debugger entitlement from 0.0.7-beta2; macOS 14, 15, 26, 27; GPL-3.0; 0.0.7 "Automation" roadmap (rules, per-item conditions, scripts, widgets, AppleScript, command palette, layout snapshots, Touch ID unlock, native overflow, keyboard/VoiceOver audits). README comparison table covers only Ice and Thaw: consider adding a row for "works on macOS 14-26 and 27".
