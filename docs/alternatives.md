# holzBar and its alternatives

Every menu bar manager we could find that is still on sale or maintained, compared on the same 30 questions. Researched on 9 October 2026 from each project's own pages, repositories, release notes and app listings (sources: `.planning/research/alt-*.md`). ✅ yes · ❌ no · ❓ not found after checking the official pages and at least one more source (so: not stated, not "no") · 🔜 planned for holzBar, **not available yet**.

| | holzBar | Bartender 7 | Ice | Thaw | SaneBar | Tuck | Barbee | Hidden Bar | Dozer | Vanilla | iBar |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Maintenance | active (0.0.7-beta4) | active (7.0.5) | stalled (0.11.12, Oct 2025) | active (3.0 beta, 7 Oct) | **sunset 30 Jun 2026** (last 2.1.91, 9 Sep) | active (1.2.0, 6 Oct) | active (5.0, 10 Sep) | active (1.11.1, 18 Sep) | none since 2022 | 2.2, date ❓ | active (2.1.1, 14 Sep) |
| Price | free | paid, one-time <sup>1</sup> | free | free | free | free; Pro $14.99 | free + in-app (lifetime $12.99) | free | free | free; Pro $10 | free + $2.99/yr |
| Open source | ✅ GPL-3.0 | ❌ | ✅ GPL-3.0 | ✅ GPL-3.0 | ✅ MIT | ❌ | ❌ | ✅ MIT | ✅ MPL-2.0 | ❌ | ❌ |
| macOS 26 / 27 | ✅ / ✅ | ❌ / ✅ <sup>2</sup> | dev builds / ❌ | ✅ / ✅ <sup>3</sup> | ✅ / ❌ | ✅ / ✅ <sup>4</sup> | ❓ / ❓ <sup>5</sup> | ✅ / partly <sup>6</sup> | ❓ / ❓ | ✅ / ❓ | ✅ / ❓ |
| Apple Silicon / Intel | not yet checked | ✅ Apple Silicon (27) | ❓ | ❓ | Apple Silicon only | both | ❓ | both | Intel only (Rosetta) | both | both |
| Hidden + always-hidden sections | ✅ | ✅ | ✅ | ✅ | ✅ | hidden; per-icon | hidden only ❓ | ✅ | ✅ | hidden; always-hidden in Pro | ✅ |
| Separate bar, notch handling | ✅ Shelf | ✅ | ✅ Ice Bar | ✅ Thaw Bar | ✅ | ✅ Shelf | ✅ | ❌ | ❌ | partly | ✅ |
| Layout profiles | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ ❓ | ✅ (VIP) | ❌ | ❌ | ❌ | ❌ |
| Groups, spacers | ✅ | ✅ | ❌ | ✅ | groups, dividers | groups (Pro) | dividers | ❌ | ❌ | ❌ | ❌ |
| Item spacing | ✅ beta | ✅ | ✅ beta | ✅ beta | ✅ | Pro | ✅ | ❌ | own icons only | ❌ | ✅ |
| Search | ✅ | ✅ Command Bar | ✅ | ✅ | ✅ | Pro | weak | ❌ | ❌ | ❌ | ❌ |
| Rules / triggers | 🔜 0.0.8 | ✅ <sup>7</sup> | ❌ | ✅ many <sup>8</sup> | ✅ 8 types | per app (Pro) | ✅ (VIP) | timer only | timer only | timer (Pro) | timer |
| Per-item conditional visibility | 🔜 0.0.8 | ✅ | ❌ | ✅ | ❌ | by active app (Pro) | ✅ | ❌ | ❌ | ❌ | ❌ |
| Widgets / own items | 🔜 0.0.9 | ✅ | ❌ | planned | ❌ | ❌ | custom icons | ❌ | ❌ | ❌ | ❌ |
| Scripts as trigger/action | 🔜 0.0.8 | as widget source | ❌ | ✅ | trigger | ❓ | VIP ❓ | ❌ | ❌ | ❌ | ❌ |
| AppleScript | 🔜 0.0.9 | ✅ | ❌ <sup>9</sup> | ❌ <sup>9</sup> | ✅ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ |
| Shortcuts / Siri | ✅ | ✅ | ❌ | partly | via AppleScript | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ |
| URL scheme / CLI | ✅ holzbar:// | ✅ URL actions | ❌ | ✅ thaw:// | ✅ sanebar:// | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ |
| Hotkeys | ✅ also per profile and item | ✅ | ✅ | ✅ | ✅ per icon | ✅ | ✅ | one | ✅ | Pro | ✅ |
| Zen mode (lock reveal gestures) | ✅ | Focus filter only | ❌ | ✅ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ |
| Lock behind Touch ID / password | 🔜 0.0.8 | ❌ <sup>10</sup> | ❌ | ❌ | ✅ | ❌ | ❓ | ❌ | ❌ | ❌ | ❌ |
| Show/hide animation | 🔜 0.0.9 | ❓ | ❓ | Reduce Motion only | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ | ❓ |
| Screen Recording | optional | optional | optional | optional | not needed | optional | required | not needed | not needed | required | ❓ |
| Network connections | **none** | vendor: none <sup>11</sup> | Sparkle | Sparkle | Sparkle + anonymous event counts | licence + Sparkle | App Store: none | none | Sparkle | ❓ | App Store: none |
| Export / import settings | ✅ | ❓ | ❌ | ✅ | ✅ (also from Bartender, Ice) | ❓ | cloud backup (VIP) | ❌ | ❌ | ❌ | ❓ |
| Sync between Macs | 🔜 1.0.0 | ❌ | ❌ | ❌ | ❌ | ❓ | ✅ profiles (VIP) | ❌ | ❌ | ❌ | ❓ |
| Languages | 5 | 6 | ❓ | 20 | English? | >=8 | 20 | 10 | ❓ | ❓ | 15 |
| Dependencies, Swift | none, Swift 6 | closed | 5 packages, Swift 5 | 9 packages, Swift 6 | 3 packages, Swift 6 | ❓ | closed | 1 package, Swift 5 | 5, Swift 5 | closed | closed |
| Distribution | Homebrew | direct, Setapp (beta) | GitHub, Homebrew | GitHub, Homebrew | direct, Homebrew | direct, Homebrew | App Store | App Store, GitHub, Homebrew | GitHub, Homebrew | direct | App Store |
| Keyboard / VoiceOver | ✅ / ✅ | ✅ / ❓ | ❓ / ❓ | ✅ / ✅ | ✅ / ❓ | ✅ / ❓ | ✅ / ✅ | 1 hotkey / ❓ | 1 hotkey / ❓ | ❓ | ✅ / ❌ |

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

## Also seen

- **SaneBar** announced its sunset on 30 June 2026 because the developer says macOS 27 breaks menu bar managers; it sends anonymous event counts (app version, OS version) to `dist.saneapps.com`, read in `EventTracker.swift`.
- **OverflowBar** (open source, macOS 15 and 26, Apple Silicon, young), **Barred** (open source, no licence yet), **ChocolateBar** (officially Monterey to Sequoia only) and **Lounge** exist; they are not in the table because too little is documented.
- A blog that ranks Bartender alternatives (bartendermacoslounge.com) belongs to a competitor and lists Barbee as open source; Barbee is closed source. We did not use it as a source.

## How reliable is this?

Most cells are read from the vendor's page, the README or the source. Cells from a single search snippet or a competitor's blog are marked ❓ rather than guessed. Check the quote in `.planning/research/alt-*.md` before you rely on a cell. holzBar's own architecture (Apple Silicon or universal) is not yet checked.
