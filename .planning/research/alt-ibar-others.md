# Competitor research: iBar, Tuck, Barred, ChocolateBar + extra menu bar managers

Researched 2026-10-09 via WebFetch/WebSearch. Page content treated as data. Confidence tags: stated = on official page/listing, code = read in source, inferred, unknown.
"unknown" = not stated on the official page and no independent source found (many apps publish very little). Dates without a year on App Store/GitHub pages are marked (year inferred).
Note on name clashes: there are several unrelated apps called "Tuck" (Irradiated Software window tool; pakco window splitter; lordkerwin/tuck 350-line OSS tidier). Column "Tuck" = Quartz's usetuck.com menu bar manager (what the brief most likely means); lordkerwin/tuck listed in "Named only".

Sources are keyed [S#] below the table.

| # | Question | iBar (Ningbo Shangguan) | Tuck (Quartz, usetuck.com) | Barred (mcclowes) | ChocolateBar (Aloysius Lim) |
|---|---|---|---|---|---|
| 1 | Price / licence | Free + IAP "iBar Annual Subscription $2.99" (stated) [S1]; separate "iBar Pro" listing $9.99 one-time, no IAP (stated) [S2] | Free tier unlimited; Pro $14.99 one-time, 3 Macs, lifetime updates, 30-day refund (stated) [S3] | Free; licence "TBD" in README (stated) [S4] | $15 one-time, 48 h trial, 7-day refund; licences sold on one-year terms include 1 year of updates, older ones lifetime (stated) [S5] |
| 2 | Open source | No (inferred; closed MAS app) [S1] | No (inferred; GitHub repo for the product 404s, only lordkerwin/tuck is OSS and unrelated) [S3] | Yes, public source on GitHub but no licence chosen yet (stated "TBD") [S4] | No; GitHub repo is issue tracker only, "no source or downloads" (stated) [S6] |
| 3 | macOS versions (26/27) | MAS says macOS 10.12+ (stated) [S1]; 2.0.0 "Adapted to macOS 26", 2.0.2-2.0.4 and 2.0.8 macOS 26 optimisations (stated) [S2]; macOS 27: unknown | macOS 14 through 27 (stated); 26 full, 27 with limits (system controls Wi-Fi/Sound/Control Center/clock stay visible); 1.0.51 "single download supporting macOS 27 and 26" [S3][S7] | macOS 14+ (stated); 26/27 not mentioned (unknown) [S4] | Site: Monterey-Sequoia, "Tahoe soon", no 27 (stated) [S5]; repo says Ventura-Sequoia, Apple Silicon only (conflict) [S6]. Not confirmed for 26/27 |
| 4 | Apple Silicon / Intel | Both, native (stated) [S1] | Both (stated) [S3] | Unknown (inferred AS likely, builds from Xcode 16) [S4] | Site: universal AS+Intel [S5]; repo: Apple Silicon only [S6] (conflict) |
| 5 | Hidden + always-hidden | Folding mode + "always hidden" per-icon setting (stated) [S1] | Push Mode hides everything left of Tuck; per-icon Visible/Hidden/Follow; no separate always-hidden section described (stated) [S3] | One hidden secondary bar only (stated) [S4]; always-hidden: unknown | Hidden icons moved to strip; no always-hidden described (unknown) [S5] |
| 6 | Separate bar / notch | Yes, "aggregation mode" floating window under menu bar for notch Macs (stated) [S1] | Yes, Shelf Mode panel below menu bar; auto-switches on notched Macs on 14/15/26 (stated) [S3] | Yes, "collapsible secondary bar" (stated) [S4]; notch not mentioned | Yes, second-row strip below menu bar; built for the notch; horizontal or vertical (stated) [S5] |
| 7 | Layout profiles | No (inferred; not listed) [S1] | No (unknown) [S3] | No (inferred) [S4] | Yes: profiles save hidden icons, order, strip layout; hotkey cycles profiles (stated) [S5] |
| 8 | Groups, spacers | Groups no; spacers/gaps: icon gap setting only (stated) [S1] | Groups: yes, Shelf groups with sub-panels (Pro, 1.2.0) (stated); spacers unknown [S3] | Unknown [S4] | Groups/spacers: unknown [S5] |
| 9 | Item spacing | Yes: default/smaller/small/none, restart needed (stated) [S1] | Yes, Pro; global spacing disabled on macOS 27 because system ignores it (1.1.3), spacing restored 1.1.5 with restart prompt (stated) [S7] | No (inferred) [S4] | Unknown [S5] |
| 10 | Search | No (inferred) [S1] | Yes, Pro: Shelf search via typing, Cmd-F, magnifier (stated) [S3] | No (inferred) [S4] | Unknown [S5] |
| 11 | Auto rules/triggers | Re-hide after adjustable delay only (stated) [S1] | Auto-hide with delay, hover reveal, app-specific Rules (Pro) (stated) [S3] | Auto-hide after 1-15 s (stated) [S4] | Unknown [S5] |
| 12 | Per-item conditional visibility | No (inferred) | Yes, Pro "Rules Mode": per-app visibility rules based on active app (stated) [S3] | No (inferred) | Unknown |
| 13 | Widgets / own items | No (inferred) | No widgets; custom icons for Tuck's own toggle (Pro) [S3] | No (inferred) | Strip also lists open windows (stated) [S5]; no widgets |
| 14 | Scripts | No (inferred) | No (unknown) [S3] | No (inferred) | No (unknown) |
| 15 | AppleScript | Unknown [S1] | Unknown (not on page; no independent source) [S3] | Unknown [S4] | Unknown [S5] |
| 16 | Shortcuts / Siri | Unknown [S1] | Apple Shortcuts app integration not described; a "Shortcuts" button inside the Shelf on macOS 27 (opens Apple's Shortcuts menu item, stated) [S3] | No (inferred) | Unknown |
| 17 | URL scheme / CLI | Unknown [S1] | Not described (unknown) [S3] | Unknown; has make targets for building only [S4] | Unknown |
| 18 | Hotkeys | Yes: 2.1.0 added shortcut keys to show and click specific menu bar icons (stated) [S2] | Global Cmd-Shift-B; Cmd-F search (stated) [S3] | Only Cmd-drag documented; no global hotkey (stated) [S4] | Yes: hotkey cycles profiles (stated) [S5] |
| 19 | Zen-like mode (fully empty bar) | Unknown; option "show display bar only when iBar icon clicked" (2.0.8) [S2] | Hover-reveal/auto-hide, "optional blank-menu-bar reveal gestures" (1.0.25) [S7]; not named Zen | Unknown | Unknown |
| 20 | Touch ID lock | No (inferred) | No lock of icons; "Lock" freezes drag-to-reorder only (stated) [S3] | No | No (unknown) |
| 21 | Animation | Unknown | Unknown (Liquid Glass Shelf styles) [S3] | Unknown | Hover-to-magnify strip (stated) [S5] |
| 22 | Screen Recording | Unknown (floating window must capture icons; inferred likely) [S1] | Optional: only to show original icon images in Shelf, otherwise app icons (stated) [S3] | No, Accessibility only listed (stated) [S4] | Never asked; Accessibility API only, "menus are mirrored, not captured" (stated) [S5] |
| 23 | Accessibility / other perms / sandbox / helpers | Unknown which permissions. Mac App Store app, so sandboxed (inferred from MAS) [S1] | Accessibility required on macOS 27 (stated) [S7]; signed+notarized DMG, ~8-10 MB, no helper stated [S3] | Accessibility only (stated); no Dock icon [S4] | Accessibility only (stated) [S5]; not sandboxed (inferred, direct DMG) |
| 24 | Network / updates / telemetry | MAS privacy label "Data Not Collected" (unverified by Apple); updates via App Store [S1] | No telemetry; network only for licence validation and Sparkle update checks (stated) [S3] | "no accounts, analytics, or network access" (Product Hunt/hunted listing, stated) [S8]; update mechanism: Homebrew/manual | Contacts servers only for update checks; nothing leaves the Mac (stated) [S5] |
| 25 | Export / import | Unknown | Unknown | Unknown | Unknown (profiles auto-save) |
| 26 | Sync | Unknown | Unknown (3-Mac licence only) | No (inferred) | No (unknown); licence covers every Mac you own [S5] |
| 27 | Languages | 15: English, Czech, Dutch, French, German, Italian, Japanese, Korean, Polish, Portuguese, Russian, Simplified+Traditional Chinese, Spanish, Swedish (stated) [S1] | At least en, de, fr, es, ja, ko, pt-BR, zh (changelog: "six-language", FR/ES/KO added); site has 9 locales (stated) [S3][S7] | Unknown | Unknown |
| 28 | Last release / maintained | MAS 2.1.1 "Sep 14" (year inferred 2026, after 2.0.5 on 12/18/2025); maintained (stated) [S2] | 1.2.0 on Oct 6, 2026; ~weekly releases since May 2026; maintained (stated) [S7] | v1.1.4, 12 Aug (year inferred 2026; repo created 2026-04-08, pushed 2026-08-12); maintained but young, 0 stars, 3 open issues (stated) [S9] | No version shown; Product Hunt launch Jun 2026; copyright 2026; maintained (inferred) [S5][S10] |
| 29 | Distribution | Mac App Store (also second listing iBar Pro) [S1][S2] | Direct DMG; Homebrew `brew install --cask QuartzInkStudio/tap/tuck-menu-bar` (stated) [S3]; App Store/Setapp: no | Homebrew tap `mcclowes/barred` + zip (stated) [S4] | Direct DMG only, "no App Store account" (stated) [S5] |
| 30 | Appearance | Unknown; icon gap, order in preferences [S1] | Shelf styles (Capsule, Floating Glass, Minimal, Segmented, Liquid Glass), colors, opacity, intensity slider, 20 dynamic icon styles, grayscale (stated) [S3][S7] | Unknown | Full/minified strip, horizontal/vertical layout (stated) [S5] |
| 31 | Keyboard-only / VoiceOver | MAS: "developer has not indicated supported accessibility features" (stated) [S2]; keyboard shortcuts since 2.1.0 | Keyboard shortcut + Cmd-F search; VoiceOver unknown [S3] | Unknown | Unknown |
| 32 | Known issues macOS 26/27 | Reviews: occasional clicking glitches (2023-24) [S1]; fixes for icon misidentification/clicking on 26 in 2.0.2-2.0.4, idle CPU on 26 in 2.0.8 [S2]; 27: unknown | macOS 27: system controls cannot be hidden, same-app items grouped, some items need "Show All", iStat Menus icons not individually hideable, spacing needs relaunch/sign-in, Notification Center overlay flash (stated) [S7] | Unknown; 3 open issues [S9] | Official support stops at Sequoia; 26/27 unconfirmed [S5][S6] |

## Extra apps found (not on the brief's list)

| # | Question | SaneBar (sane-apps) | Barbee (App Store) | Hidden Bar (dwarvesf) | Vanilla (Matthew Palmer) | OverflowBar (EvanProgramming) |
|---|---|---|---|---|---|---|
| 1 | Price/licence | Free, every feature unlocked (README); optional $49.99 bundle for other apps. Earlier Pro $14.99 (stated) [S11][S12] | Free + IAP: Lifetime $12.99, Yearly VIP $4.99 (description text says $2.99), tips $1.99-3.99; 3-day trial (stated) [S13] | Free, MIT (stated) [S14] | Free; Pro $10 one-time, 10 Macs (stated) [S15] | Free, MIT (stated) [S16] |
| 2 | Open source | Yes, MIT per README now (earlier PolyForm Shield per search listing, conflict) [S11] | No (inferred) | Yes [S14] | No (inferred) | Yes [S16] |
| 3 | macOS | 14+ (README), Liquid Glass on Tahoe; 27 not stated [S11][S12] | 11.0+; listed "tested on macOS 27" by a rival's blog (not authoritative) [S13][S17] | 13+ (v1.10 for older); rival blog says hides on 27 [S14][S17] | Catalina+ (stated) [S15] | 15 and 26 (stated); 27 unknown [S16] |
| 4 | AS/Intel | Apple Silicon only (stated) [S11] | unknown | unknown | unknown | Both (stated) [S16] |
| 5 | Hidden + always-hidden | Yes, Always Hidden zone (stated) [S12] | unknown; "unlimited show/hide" VIP | hidden only (stated) | "Completely Removed" section in Pro (stated) [S15] | One arrow, selected icons hidden (stated) |
| 6 | Separate bar/notch | Icon Panel + Second Menu Bar; Find Icon works behind notch (stated) [S12] | Notch-compatible; second menu bar (review) [S13][S18] | No notch handling stated | Separate notch page exists, content not read | Second row, notch aware (stated) [S16] |
| 7 | Profiles | Yes [S11] | Yes, cloud profiles (VIP) [S13] | No | No | No |
| 8 | Groups/spacers | Groups yes [S12] | unknown | no | no | no |
| 9 | Item spacing | Yes [S12] | Yes (reduced spacing) [S13] | no | no | no |
| 10 | Search | Yes, Find Icon Cmd-Shift-Space [S11] | unknown | no | no | no |
| 11 | Auto rules/triggers | Yes: 6 smart triggers (battery, Wi-Fi, Focus, app launch, schedule, script) [S12] | Yes, auto show/hide rules (VIP) [S13][S18] | no | auto-hide after 5 s (Pro) | pointer reveal |
| 12 | Per-item conditional | via triggers (stated) | via rules (inferred) | no | no | no |
| 13 | Widgets/own items | no | Custom emoji/SF Symbol icons for menu bar items [S18] | no | no | no |
| 14 | Scripts | Yes, custom script trigger [S11] | VIP "script/shortcut integration" [S13] | no | no | no |
| 15 | AppleScript | Yes (toggle, show hidden, hide items, list icons, hide/show icon by bundle ID) [S11] | unknown | no | no | no |
| 16 | Shortcuts/Siri | Yes per site ("AppleScript/Shortcuts automation") [S12] | VIP shortcut integration [S13] | no | no | no |
| 17 | URL scheme/CLI | not covered [S11] | unknown | hidden Terminal options only [S14] | unknown | unknown |
| 18 | Hotkeys | Yes, global, per-icon hotkeys [S11] | Yes, custom shortcuts [S13] | no (unknown) | Pro [S15] | unknown |
| 19 | Zen mode | unknown | unknown | no | no | no |
| 20 | Touch ID lock | Yes, Touch ID or password [S11] | no | no | no | no |
| 21 | Animation | unknown | unknown | unknown | unknown | Respects reduced motion [S16] |
| 22 | Screen Recording | Not required (Accessibility only stated) [S11] | Yes, plus Accessibility, Automation prompt and separate helper app (rival blog) [S17] | Accessibility only per rival blog [S17] | Screen recording page linked [S15] | Required for live icon capture [S16] |
| 23 | Perms/sandbox/helpers | Accessibility only [S11] | helper app (rival blog) | unknown | unknown | Accessibility + Screen Recording [S16] |
| 24 | Network/telemetry | Updates (Sparkle) + anonymous counts (app version, OS version, channel) (stated) [S11][S12] | MAS label "Data Not Collected" [S13] | unknown | unknown | unknown |
| 25 | Export/import | Yes, incl. import from Bartender and Ice [S12] | Cloud backup (VIP) [S13] | no | no | no |
| 26 | Sync | no | Cloud sync of profiles (VIP) [S13] | no | no | no |
| 27 | Languages | unknown | 20 (stated) [S13] | unknown | unknown | unknown |
| 28 | Last release | 2.1.89/2.1.90 (date not shown); active [S11][S12] | 5.0 "Sep 10" (year inferred 2026); active [S13] | v1.11.1, 18 Sep (year not shown, unknown if 2026) [S19] | unknown | none published; repo created 2026-07-14, pushed 2026-10-08 [S20] |
| 29 | Distribution | Homebrew cask `sane-apps/tap/sanebar`, direct, Setapp listing exists [S11][S21] | Mac App Store | Homebrew `hiddenbar` [S14] | direct | DMG, Homebrew mentioned [S16] |
| 30 | Appearance | Appearance options (stated) [S12] | many menu styles, recolor Apple logo [S13][S18] | none | none | Liquid Glass on 26+ |
| 31 | Keyboard/VoiceOver | Keyboard shortcuts; VoiceOver unknown [S12] | unknown | unknown | unknown | unknown |
| 32 | Known issues | unknown | rival blog notes many prompts [S17] | unknown | unknown | ad-hoc signed, not notarized [S16] |

## Named only (not researched in depth)
- Lounge: $3.99/yr, 7-day trial, Accessibility only, closed source; only evidence is a vendor-run blog [S17] (affiliate-style, treat with caution).
- Thaw (thaw-app/Thaw): GPL-3.0 Ice fork, 2.0 needs macOS 26, 3.0 for macOS 27 on alpha channel, `thaw://` automation layer, Homebrew cask (search summary, [S22]); presumably covered by another research task.
- Bartender 6: paid, closed source (covered elsewhere).
- lordkerwin/tuck: MIT, 350-line tidier, build from source, no release, macOS 14+ [S23].
- OpenBartender (rpsadarangani): MIT-ish OSS Bartender alternative created 2026-08-19, 1 star; barely started [S24].
- Pelmet, AccessMenuBarApps, Dozer: listed as alternatives on AlternativeTo (page returned 403, not verified).
- Dead/no-release evidence: none verified as dead beyond iBar's older 1.x line. Hidden Bar's release years were not visible, so its maintenance status is unknown.

## Questions not answerable from public sources (for all four requested apps)
Q15 AppleScript, Q17 URL scheme/CLI (except Thaw/SaneBar), Q25 export/import, Q26 sync, Q21 animation, Q31 VoiceOver, Q14 scripts, Q8 spacers, Q20 for iBar: no official statement found; kept "unknown"/"inferred". iBar's privacy policy and Tuck's Help pages were not opened.

## Sources
- S1 https://apps.apple.com/app/id6443843900 (iBar listing: "Free", "iBar Annual Subscription $2.99", "Requires macOS 10.12 or later", "Data Not Collected")
- S2 https://apps.apple.com/app/id6737150304 (iBar Pro $9.99; version notes "Adapted to macOS 26", "Added shortcut keys for showing and clicking specific menu bar icons")
- S3 https://usetuck.com (Tuck: "macOS 14 through 27", "Pro $14.99 ... no subscription", "No telemetry ... license validation and Sparkle update checks", "Screen Recording: enables original menu bar images")
- S4 https://github.com/mcclowes/barred (README: license "TBD", "macOS 14 or later", Accessibility, Homebrew tap)
- S5 https://chocolatebar.app ("$15 USD", "Monterey through Sequoia ... Tahoe soon", "Accessibility only ... never asks for Screen Recording", profiles)
- S6 https://github.com/sickle5stone/chocolatebar-release (issue tracker only, "13 Ventura - 15 Sequoia", Apple Silicon only)
- S7 https://usetuck.com/releases (changelog 1.0 to 1.2.0 Oct 6, 2026; macOS 27 known issues)
- S8 https://hunted.space/product/barred ("no accounts and includes no analytics or network access")
- S9 https://github.com/mcclowes/barred/releases (v1.1.4 Latest 12 Aug) and GitHub search metadata (created 2026-04-08)
- S10 https://www.producthunt.com/p/chocolatebar/chocolatebar (maker comment, launch)
- S11 https://github.com/sane-apps/SaneBar (README: MIT, "Every Pro feature is unlocked", AppleScript commands, triggers, Touch ID, Accessibility)
- S12 https://sanebar.com ("Free and open source (MIT)", six smart triggers, import from Bartender/Ice, SaneBar-2.1.90.zip)
- S13 https://apps.apple.com/app/id1548711022 (Barbee: IAP list, macOS 11.0+, 20 languages, v5.0)
- S14 https://github.com/dwarvesf/hidden (MIT, macOS >= 13, `brew install --cask hiddenbar`)
- S15 https://matthewpalmer.net/vanilla/ (Pro $10, "Completely Removed" section)
- S16 https://github.com/EvanProgramming/OverflowBar (MIT, macOS 15/26, Screen Recording + Accessibility)
- S17 https://www.bartendermacoslounge.com/blog/best-macos-menu-bar-managers (vendor blog: Lounge, permission table)
- S18 https://www.mac4ever.com/iphone/195488-l-app-mac-de-jour-barbee-s-occupe-de-votre-barre-de-menu (Barbee review: second menu bar, custom icons)
- S19 https://github.com/dwarvesf/hidden/releases (v1.11.1, 18 September)
- S20 GitHub search metadata for EvanProgramming/OverflowBar
- S21 https://setapp.com/apps/sanebar (Setapp lists SaneBar 2.1.71, macOS 14+)
- S22 https://newreleases.io/project/github/thaw-app/Thaw/release/2.0.0 and https://www.ifun.de/thaw-2-0-ist-da-freier-menueleistenmanager-fuer-macos-26-288052/
- S23 https://github.com/lordkerwin/tuck (MIT, 350 lines)
- S24 GitHub search metadata for rpsadarangani/OpenBartender
- Roundups consulted: https://www.drbuho.com/how-to/bartender-alternatives , https://favtray.com/blog/bartender-alternatives-mac-menu-bar , https://www.producthunt.com/p/tuck-4/tuck-5
