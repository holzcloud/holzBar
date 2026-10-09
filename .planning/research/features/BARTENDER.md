# Bartender feature inventory (researched 2026-10-09)

Method: web only. Pages were read via a summarizing fetch tool, so wording is paraphrased; items marked (?) are uncertain or unconfirmed.

## Current state
- Newest: **Bartender 7** (7.0.5 latest listed; shipped 2026-09-14), initial build **macOS 27 "Golden Gate" only**. Tahoe (26) support "coming soon after launch"; Tahoe users stay on **Bartender 6** (latest listed 6.6.2) with the same license key.
- Owner: Bartender was sold by Ben Surtees (Surtees Studios) to **Applause / App Sub 1 LLC** in 2024. "Surtees Studios" is no longer the accurate publisher.
- Sources: https://www.macbartender.com/ , https://www.macbartender.com/Bartender7/release_notes/ , https://www.macbartender.com/Bartender7/Blog/meet-bartender-7/ , https://macbartender.com/Bartender6/release_notes , https://www.macbartender.com/goldengate/releases/

## Feature table
Permissions column: SR = Screen Recording, AX = Accessibility. Official pages do not list per-feature permissions; "(?)" = not stated. Historically (B5/B6) Bartender needs both AX and SR (TidBITS source below).

| Feature | Description | Since | Permissions | macOS |
|---|---|---|---|---|
| Hide/show menu bar items | Move items between visible / hidden / (always hidden) sections; reveal on click, hover, hotkey | B1+ (core) | AX (?) | 7: 27; 6: 26 (Sonoma dropped) |
| Bartender Bar | Floating secondary bar showing hidden items; appears at cursor, on hover/click/hotkey; independent styling | B3; improved 6.3.0; redesigned 7 with Liquid Glass | SR for live item snapshots; optional in 7 | 7: 27 |
| Optional Screen Recording | Without SR, app icons are shown instead of snapshots of real items; captures cached on disk, not sent off-device | **7.0.0** (beta 1 of 7) | Removes SR requirement | 27 |
| Command Bar | Keyboard search of menu bar items, activating presets, viewing/running automations; clipboard history (Pro) | 7.0.0 | (?) | 27 |
| Search | Quick-search of menu bar items (B4+ hotkey search; now in Command Bar) | B4; Command Bar in 7 | (?) | 27 |
| Automations (ex-Triggers) | Condition-based show/hide/preset switching (battery unplugged, VPN/Wi-Fi, scheduled updates, custom scripts) | Triggers since B3/B4; renamed + scheduled triggers in 7.0.0 (returned in 7 beta 2) | (?) | 27 |
| Presets / profiles | Saved menu bar layouts; switch instantly; now sync to monitor setups without a trigger; integrated in layout page; large switches can be slow (known issue) | Profiles B4; monitor sync 7.0.0 | (?) | 27 |
| Hotkeys | Global shortcuts incl. new "Focus Mode" to hide items, toggle whole bar, mouse-free switching | Expanded 7.0.0 | AX (?) | 27 |
| AppleScript | Scripting dictionary; removed in 6.0, restored 6.1.2; updated in 7 | B3+; 6.1.2; 7 | none known | 6/7 |
| App Intents (Shortcuts, Siri) | Same options as AppleScript exposed to Shortcuts and Siri | 7.0.0 | none | 27 |
| Raycast extension / "agent friendly" | Announced as "coming soon" in blog; not verified shipped | planned | n/a | (?) |
| CLI / URL scheme | Not found in any official source; treat as undocumented/unknown | - | - | - |
| Appearance / styling | Menu bar styling: glass, pills, outlines, gradients, solid; Bartender Bar themes (white, black, orange, frosted); glass/material backgrounds | Styling B4/B5; new look 6.0.0; glass options 7 beta 3 | (?) | 27 (glass) |
| Menu bar item spacing | Default / Small / Tiny / No spacing | B5; restored in 7 beta 3 | (?) | 27 |
| Spacers | Visual gaps between items | B3+; restored in 7 beta 2 | (?) | 27 |
| Groups | Organize items into named groups (reviewer uses Network/Utilities/Keyboard/Disk) | 6.x | (?) | 26; **disabled in 7 betas, status in 7.0.x unconfirmed** |
| Item ordering / layout | Layout page drag-and-drop; item indexing so items stay put after reboot; on-demand layout with auto repositioning; item swapping (back in 6.5.1) | B3+; 6.5.1 | AX (?) | 6/7 |
| System item hiding | Hide clock, Control Center items; "Allow hiding system items" no longer needed for Control Center moves (7.0.4) | 7.0.0 / 7.0.4 | (?) | 27 |
| Disabled Items | Shows apps hidden by Control Center settings in separate section | 7 beta 4 | (?) | 27 |
| Notch handling | Auto-hides items blocked by the notch; Top Shelf keeps items from being tucked behind it | B5/6; Top Shelf 6.5.1 | none | 26+ |
| Top Shelf (Pro) | Notch dock: 2 widgets (weather, now playing, calendar), file shelf, clipboard manager, AirDrop, volume/brightness/battery HUD, AirPods alerts (6.5.2), AI-agent live activity (Claude Code/Codex per MacRumors) | 6.5.1 (May 2026) | (?) | 26+, notch Macs implied |
| Option-click to reveal | Option-click reveals hidden items | 6.4.2 | (?) | 26 |
| Widgets | Menu bar widgets / custom items from data sources or scripts | 6.0.0 beta; 6.3.0 customization | (?) | 26+ |
| Spaces / displays | Per-monitor presets (7); ultra-wide display fix (6.5.2). Per-Space behavior: not documented in sources | 7.0.0 | (?) | 27 |
| Notification badges | Not found in B6/B7 sources (B4/5 showed badges in Bartender Bar historically (?)) | ? | ? | ? |
| Performance | <100 MB idle in 7; low-power setting in 6.6.x; multiple CPU/memory reductions | 6.1+, 7.0.0 | none | - |
| Localization | EN, DE, FR, ES, JA, zh-Hans | 7.0.4 | none | - |

## How it works on macOS 27 (important for holzBar)
Apple rebuilt the menu bar as a single window, breaking per-item window discovery. Bartender 7 uses an undocumented "Load Menu Bar Layout" swap approach (same trick as BetterTouchTool per PublicSpace); Apple could close it in any point update. Known limits: apps with multiple items share one visibility control; incompatible apps (iStat Menus, Setapp) auto-hidden; item images may be stale; large profile switch slow; flicker with native overflow. Source: https://www.publicspace.net/blog/macos-27-menu-bar/

## Licensing / price
- Conflicting figures; confirm on https://www.macbartender.com/purchase/ (prices load dynamically).
- Blog (B7 launch): Bartender 7 $24.99 one-time (updates to v7), Bartender Pro $19.99/yr (?), Mega Supporter lifetime (includes Pro). Trials: 4 weeks new, 2 weeks returning; purchase page says 14-day Pro trial.
- Earlier (May 2026, B6): Bartender 6 $20, Pro $15/yr, Mega Supporter lifetime. https://www.macrumors.com/2026/05/12/bartender-pro/ , https://brettterpstra.com/2026/05/13/bartender-pro-review/
- Free upgrade to 7 for B6 licenses bought in 2026 / upgrades 14 Mar-14 Sep 2026; discounts earlier.

## Privacy
- 2024: after the Applause acquisition, 5.0.52 shipped Amplitude analytics without disclosure; 5.0.53 removed it. https://tidbits.com/2024/06/05/bartender-developer-explains-and-apologizes-for-quiet-acquisition/
- Brett Terpstra (2026) says Amplitude was removed and transparency improved. B7 states screen captures stay local. No current telemetry statement found; absence of telemetry in B7 not independently verified.
- Trust concern remains for AX+SR-class permissions with a changed owner.

## Known complaints
- Trust damage from the silent 2024 sale/telemetry.
- B6/Tahoe: icons shifting, items removed, constant re-indexing, high energy use, mouse jumping (https://talk.macpowerusers.com/t/bartender-6-oh-look-applause-finally-dropped-the-other-shoe/42814 , https://talk.tidbits.com/t/bartender-6-on-tahoe-being-problematic/32061).
- Subscription tier (Pro) vs one-time purchase; 7 requires new/upgraded license.
- B7 launches macOS 27 only; Tahoe support deferred; feature gaps (Groups, multi-item apps).
- Free alternatives gaining ground: Thaw (Ice fork), Ice, Barbee, Dozer, Hidden Bar.

## Gaps / uncertainty
- No official per-feature permission list; Accessibility never mentioned for B7 in fetched pages.
- Release dates for most 7.x builds not shown; B7 ship date 2026-09-14 comes from search snippet.
- Notification badges, Spaces-specific behavior, CLI/URL scheme: not found.
- macOS requirements per feature are inferred from version requirements.
