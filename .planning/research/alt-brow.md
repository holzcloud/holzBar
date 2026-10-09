# Brow (brow-app.com) - competitor research, checked 2026-10-09

Key finding: Brow is NOT a dedicated menu bar manager. It is an "everything app" (launcher, clipboard, window manager, screenshots, AI ...) whose "Menu bar hide" is one small free module. Vendor itself says (blog): "fewer controls than Bartender: no per-app rules, triggers, or spacing". Independent coverage found: none (only AlternativeTo / Product Hunt / hunted.space listings, all vendor-written; AlternativeTo returned 403). reddit not used. Confidence: stated = on vendor page; inferred = deduced; unknown = not found.

| # | Question | Value | Confidence | Source / quote |
|---|---|---|---|---|
| 1 | Price, licence, trial | Free tier $0 forever (40+ non-AI tools incl. menu bar hide). Pro $4.99/mo or $49/yr (AI features only). No trial mentioned. Licence: proprietary EULA ("limited, non-exclusive, non-transferable license") | stated | [1] "Free. Pro if you want AI." "$4.99/month or $49/year"; [5] "limited, non-exclusive, non-transferable license". Note: vendor pages inconsistent on whether grammar fix/dictation are free or Pro |
| 2 | Open source | ❌ no (not stated anywhere; terms silent) | inferred | [5] no mention of open source; no source repo found (only Homebrew tap repo [7]) |
| 3 | macOS versions, 26, 27 | Site/FAQ: macOS 14+. Cask: >= Ventura (13). Product Hunt: 13+. macOS 27: vendor claims works since 1.0.63 ("Working (stable, from 1.0.63)"), after a "substantial rebuild"; relies on undocumented behavior. macOS 26: not stated (inferred works) | stated (vendor), 26 inferred | [1] "macOS 14 or later"; [2] blog macos-27-menu-bar; [6] support FAQ "requires macOS 14 (Sonoma)"; [7] cask. No independent confirmation |
| 4 | Apple Silicon / Intel | unknown (site says "Mac only, about 20MB", native Swift, not Electron) | unknown | [1] |
| 5 | Hidden + always-hidden sections | Hide / show on demand / reorder icons; always-hidden section not mentioned | stated (partly) / unknown | [2] "hide icons, show them on demand, and reorder them from the notch" |
| 6 | Separate bar / notch | Icons are shown/reordered from the notch ("where icons get cut off"); no separate bar described. Notch module is a hover panel (widgets, file drop) | stated | [2], [8] "expands into a full control panel" |
| 7 | Layout profiles | ❌ not mentioned | inferred | [2] "no per-app rules, triggers, or spacing" |
| 8 | Groups/folders, spacers | unknown (not mentioned) | unknown | [2] |
| 9 | Item spacing | ❌ no. A spacing slider was shipped and removed the same day | stated | [2] "no ... spacing"; "shipped a spacing slider and removed it the same day" |
| 10 | Search | Menu bar search not mentioned (app has a launcher/app search, unrelated) | unknown | [1] |
| 11 | Automatic rules/triggers (Wi-Fi, location, time, app, power, display, Focus, VPN, Bluetooth, audio, cam/mic, script; AND/OR) | ❌ none | stated | [2] "no per-app rules, triggers" |
| 12 | Per-item conditional visibility | ❌ no | stated | [2] |
| 13 | Widgets / own items | Notch widgets (CPU/mem/battery/disk/network/fan stats, now playing, weather, calendar, timer), not menu bar items | stated | [1] "Notch widgets and file drop"; [8] |
| 14 | Scripts | AI Workflows "generates AppleScript" (Pro); no user script triggers for menu bar | stated | [1] |
| 15 | AppleScript | No scripting dictionary documented. Automation permission used for "app launching and system commands" | unknown | [3] |
| 16 | Shortcuts / App Intents / Siri | unknown (not documented) | unknown | all pages |
| 17 | URL scheme / CLI | unknown (not documented) | unknown | all pages |
| 18 | Hotkeys | Yes, global hotkeys, configurable in Settings > Shortcuts (activation + per-module). Menu-bar-specific hotkey unknown | stated | [6] "Open Settings (⌘,), then choose Shortcuts" |
| 19 | Zen-like mode | unknown (not mentioned) | unknown | - |
| 20 | Touch ID / password lock | unknown (not mentioned) | unknown | - |
| 21 | Show/hide animation | unknown (notch "hides everything automatically" on mouse-away) | unknown | [8] |
| 22 | Screen Recording | Required for screenshot/screen recording features (not for menu bar hide, unclear) | stated | [3] "Required for screenshot and screen recording features" (note: support FAQ [6] does not mention it) |
| 23 | Accessibility, other permissions, sandbox, helpers | Accessibility (hotkeys, window mgmt, text transforms), Screen Recording, Microphone (dictation only), Automation. Sandbox: privacy page says Mac App Store distribution (so sandboxed there) but DMG/cask build is also offered; entitlements/helpers/login item unknown. Bundle IDs differ: com.brow-app.Brow [6] vs com.bp.brow (cask zap [7]) | stated / unknown | [3] permissions list; [6]; [7] |
| 24 | Network: updates, licence, telemetry | Privacy: no analytics, crash reporting or usage telemetry; "works entirely offline" for core features; AI text sent to Brow's own AI servers (Pro); site stores email for iOS launch list. Update check mechanism not documented (Homebrew cask is `version :latest`); licence check: App Store purchase, none described. Privacy policy "Last updated: January 2025" | stated | [3] "Brow does not include: Analytics tracking, Crash reporting services, Usage telemetry"; "Text is sent to Brow's own AI models" |
| 25 | Export/import | unknown | unknown | - |
| 26 | Sync between Macs | ❌ no; clipboard history local, "Cross-device sync with iPhone is coming soon" | stated | [6] |
| 27 | Languages | UI languages unknown; AI Translation supports 19 languages (a different feature) | unknown | [1] |
| 28 | Last release, date, cadence, maintained | Version 1.0.63 or later exists (macOS 27 support); releases page loads dynamically, no date retrievable. Reviews page: "in active beta and improving every week". Maintained: yes (vendor) | inferred | [2], [4], [9] |
| 29 | Distribution | Direct DMG (releases.brow-app.com/Brow-latest.dmg), Homebrew third-party tap (`brew install --cask mac-brow-app/tap/brow`), Mac App Store (per privacy/support/terms pages). Setapp: unknown | stated | [1], [7], [3], [6] |
| 30 | Appearance options | unknown for menu bar | unknown | - |
| 31 | Keyboard-only / VoiceOver | unknown | unknown | - |
| 32 | Dependencies / Swift | "native Swift, not Electron"; dependencies unknown | stated | [1] |
| 33 | Known issues macOS 26/27 | Vendor blog: relies on undocumented behavior, "no official API for this"; may need fixes with later 27 betas. No independent bug reports found | stated (vendor) | [2] |
| 34 | Developer ID signed + notarized | unknown (not documented; DMG distribution implies likely, not verified) | unknown | - |
| 35 | Who / since when | Brow, no legal entity or address; "© 2026 Brow"; Product Hunt hunter Bohdan Pyryn, "co-founder and one of the developers behind brow". Start date unknown (privacy policy dated Jan 2025) | stated / unknown | [3], [5], [10] |

## Not answerable (unknown after checking site + only vendor-derived listings)
4, 8, 10, 15, 16, 17, 19, 20, 21, 25, 27 (UI), 30, 31, 34; 28 exact version/date; 23 sandbox/helpers detail. No independent reviews exist for Brow's menu bar manager, so all feature claims are vendor claims.

## Sources
1. https://brow-app.com/ (pricing, features, macOS 14+, Homebrew, "native Swift")
2. https://brow-app.com/blog/macos-27-menu-bar (vendor blog: macOS 27 support from 1.0.63, no rules/triggers/spacing)
3. https://brow-app.com/privacy (permissions, no telemetry, AI processing)
4. https://brow-app.com/releases (content loads dynamically, empty when fetched)
5. https://brow-app.com/terms (licence, pricing, Mac App Store refunds)
6. https://brow-app.com/support (FAQ: macOS 14, hotkeys, multi-monitor, sync, bundle id)
7. https://github.com/Mac-Brow-App/homebrew-tap and raw Casks/brow.rb (`version :latest`, `depends_on macos: ">= :ventura"`)
8. https://brow-app.com/notch (notch panel)
9. https://brow-app.com/reviews (3 testimonials, "active beta")
10. https://hunted.space/product/brow (Product Hunt mirror: maker, macOS 13+, "menu bar manager so your status bar doesn't look like a disaster zone")
