# Glow (macglow.app) research, 2026-10-09

Caveat: web search found NO independent reviews or coverage (publicspace, badgeify, nmac etc. not found; searches return only unrelated apps). Every "stated" fact comes from the developer's own pages. The macOS 27 "broke on beta" coverage was not found; the developer's own release notes are the only evidence. Single-developer closed-source product; independent confirmation of anything is unknown.

Sources:
- S1 https://macglow.app/ (home, features, FAQ, changelog)
- S2 https://macglow.app/privacy-policy
- S3 https://macglow.app/terms-of-use
- S4 https://github.com/mrmango1/glow-releases/releases (release list, dates day/month only)

| # | Question | Value | Confidence | Source / quote |
|---|---|---|---|---|
| 1 | Price, licence, trial | $19.99 one-time, no subscription, free updates, licence for up to 3 own Macs (deactivate in settings), 14-day refund, trial with all features (length not stated) | stated | S1 "No subscriptions", "valid for up to 3 Macs that you personally own"; trial "unrestricted access to the full application"; S3 "maximum of three (3) licenses (activations)". Sold via Lemon Squeezy |
| 2 | Open source | ❌ closed source (GitHub repo `glow-releases` only hosts DMGs); proprietary licence | inferred | S4 repo name; S3 "limited, non-transferable, revocable licence" |
| 3 | macOS versions | Two builds. macOS 26: 2.x line (last v2.1.3, "macOS 26+" in footer). macOS 27: 3.x line, first beta 3.0.0-beta.1 (16 Jul 2026), stable 3.0.0 on 10 Sep 2026, current 3.2.0. macOS 26 stays on 2.x. Works on 27 now: ✅ per developer. Earlier than 26 unsupported | stated | S4 "This release is for macOS 27", macOS 26 stays on 2.x; S1 "rewritten core for macOS 26 and 27", footer "v2.1.3 · macOS 26+" |
| 4 | Apple Silicon / Intel | ✅ both | stated | S1 "Apple Silicon and Intel" |
| 5 | Hidden / always-hidden sections | Three sections: Always Visible, Collapsible, Floating (each toggleable; can use only two). No separate "always-hidden" concept stated; Floating is the third section | stated | S1 "Always Visible, Collapsible, and Floating sections"; changelog 3.1.6 third section "is now always Floating" |
| 6 | Separate bar / notch | Floating section / "GlowBar" (anchor to icon, right screen edge, or under cursor; hover reveal). Menu bar styles Single, Paired, Sections (3.0.0). Notch handling not mentioned | stated / unknown (notch) | S1 changelog v1.2.1, v3.0.0 |
| 7 | Layout profiles | Partial: "Moods" = saved named looks (appearance), switchable in one click, per display, can set a wallpaper. Not item-layout profiles as far as stated | inferred | S1 v3.0.0 "Moods" |
| 8 | Groups/folders, spacers | Groups: ❌ not mentioned (Floating groups mentioned in 2.2.0-beta.1 notes, meaning unclear). Spacers: unknown | unknown | S4 "Adds macOS 26 item spacing controls and Floating groups" |
| 9 | Item spacing | ✅ spacing control (macOS 26 spacing controls in 2.2.0-beta.1; "spacing" listed under Personalize) | stated | S1 "spacing, borders, styles"; S4 2.2.0-beta.1 |
| 10 | Search | ✅ Item Search, find and launch any item by typing, across sections (since 2.0.0, Jun 2026) | stated | S1 "Instant Search"; v2.0.0 "Item Search" |
| 11 | Automatic rules/triggers (Wi-Fi, location, time, app, power, display, Focus, VPN, BT, audio, camera/mic, script), AND/OR | ❌ none found. Only reveal triggers (hover, click, gestures, hotkey). Moods are switched manually per display | inferred | S1 mentions no rules; "Not mentioned: rules, Focus, Wi-Fi" |
| 12 | Per-item conditional visibility | ❌ not mentioned | inferred | S1 |
| 13 | Widgets / own items | ❌ not mentioned (item count badges only) | inferred | S1 v1.0.9 |
| 14 | Scripts | ❌ not mentioned | inferred | S1 |
| 15 | AppleScript | ❌ not mentioned | inferred | S1 |
| 16 | Shortcuts / App Intents / Siri | ❌ not mentioned | inferred | S1 |
| 17 | URL scheme / CLI | ❌ not mentioned | inferred | S1 |
| 18 | Hotkeys | ✅ custom shortcuts; hotkey to reach hidden items when the Glow icon is hidden (1.2.1); hold-to-show-full-bar shortcut (3.2.0) | stated | S1 "custom shortcuts"; v3.2.0 |
| 19 | Zen-like mode | ❌ not mentioned (Hide Strategy has 4 options incl. "Never") | inferred | S1 v3.1.6 |
| 20 | Touch ID / password lock | ❌ not mentioned | inferred | S1 |
| 21 | Show/hide animation | ✅ "Buttery Smooth" animations, marked Beta; GlowBar animations (1.1.x) | stated | S1 "fluid animations" Beta |
| 22 | Screen Recording | Privacy policy says screen captures for menu bar features are processed in memory, so Screen Recording is almost certainly required; the permission is not named on the pages. Permissions page in app (3.0.0) | inferred | S2 "never saved to disk or transmitted off your device"; S1 "Permissions page" |
| 23 | Accessibility, other permissions, sandbox, helpers | Full Disk Access was needed for reordering/Collapsible on 27; since 3.0.1 file-picker (one file) instead. Accessibility not named. Sandbox: uses private macOS APIs so almost certainly not sandboxed (inferred). Helper/login items: unknown | inferred / unknown | S4 3.0.1 "Reordering no longer needs Full Disk Access"; S3 "relies on certain private macOS APIs" |
| 24 | Network | Periodic check-in (macOS version, Glow version, licensing status, tied to anonymous ID, only date recorded). Licence validated via order info (Lemon Squeezy). No usage analytics "currently"; policy reserves optional analytics/diagnostics in future. No update framework (Sparkle) or host named; updates are manual DMG downloads from GitHub as far as shown | stated (check-in), unknown (update mechanism/host) | S2 "the app periodically sends a small check-in"; "does not currently collect usage analytics or diagnostic data"; "may introduce optional diagnostics or usage analytics in a future version" |
| 25 | Export/import settings | unknown (not mentioned) | unknown | S1 |
| 26 | Sync between Macs | ❌ not mentioned | inferred | S1 |
| 27 | Languages | English plus German, Spanish, Japanese (3.0.0) | stated | S1 v3.0.0 |
| 28 | Last release, cadence | v3.2.0, 2 Oct 2026 (Oct 2026). Active: 3.0.0 10 Sep, 3.0.1 12 Sep, 3.1.0 16 Sep, 3.1.3 22 Sep, 3.1.6 23 Sep, 3.2.0 2 Oct; frequent releases; first release 1.0.0 Dec 2025 | stated | S4, S1 changelog |
| 29 | Distribution | Direct DMG via GitHub releases + Lemon Squeezy purchase. Homebrew, App Store, Setapp: none found | stated (direct), inferred (others) | S1 download links to github.com/mrmango1/glow-releases |
| 30 | Appearance | Liquid Glass effects, wallpaper-matching and dynamic tone, borders (colour option 3.2.0), corners (rounded screen corners 3.0.0), styles (Single/Paired/Sections), shadow (Tight Shadow removed 3.2.0), Apple logo customisation, Moods, Low Power mode. Black bar/tint: unknown | stated | S1 "liquid glass effects", "Personalize Everything", v3.2.0, v3.0.0 |
| 31 | Keyboard-only / VoiceOver | Keyboard shortcuts yes; v1.1.2 "accessibility descriptions for screen readers were improved"; full keyboard-only operation and VoiceOver support unknown | unknown | S1 changelog v1.1.2 |
| 32 | Dependencies / Swift | unknown | unknown | not published |
| 33 | Known issues macOS 26/27 | Stability on macOS betas "not guaranteed"; macOS changed item-order storage in the 27 betas, fixed in 3.0.0/3.0.1; multi-display, Spaces and Notification Center fixes in 3.2.0; private APIs may break. A "Known Issues" page is referenced but not linked. No independent coverage of a beta breakage found (developer's 3.0.0-beta line is the macOS 27 fix) | stated | S3 "Stability on macOS Beta versions is not guaranteed"; S1 v3.0.0 |
| 34 | Developer ID signed + notarized | unknown (not stated anywhere) | unknown | none |
| 35 | Maker | Anderson Grefa (individual; terms governed by Ecuador law; GitHub account mrmango1); first release 1.0.0 Dec 2025 | stated | S1 footer "Made with care by Anderson Grefa"; S3 "laws of Ecuador" |
