<div align="center">

<img src="Resources/Logo/banner.png" alt="holzBar — the menu bar manager for macOS" width="100%">

<br>

[![Release](https://img.shields.io/github/v/release/holzcloud/holzBar?include_prereleases&style=for-the-badge&label=release&color=2A86E0)](https://github.com/holzcloud/holzBar/releases)
[![Homebrew](https://img.shields.io/badge/brew-holzbar-D58C4A?style=for-the-badge&logo=homebrew&logoColor=white)](#-install)
[![macOS](https://img.shields.io/badge/macOS-14%20→%2027-111827?style=for-the-badge&logo=apple&logoColor=white)](docs/features.md#macos-27)
[![Privacy](https://img.shields.io/badge/privacy-no%20network%20connections-0E7C66?style=for-the-badge)](docs/privacy-and-permissions.md)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/holzcloud/holzBar/badge)](https://scorecard.dev/viewer/?uri=github.com/holzcloud/holzBar)
[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](https://slsa.dev)
[![CodeQL](https://img.shields.io/github/actions/workflow/status/holzcloud/holzBar/codeql.yml?style=for-the-badge&label=CodeQL&logo=github)](https://github.com/holzcloud/holzBar/actions/workflows/codeql.yml)
[![License](https://img.shields.io/github/license/holzcloud/holzBar?style=for-the-badge&color=4B5563)](LICENSE)
[![Website](https://img.shields.io/badge/website-holzcloud.ch%2Fholzbar-0E7C66?style=for-the-badge)](https://holzcloud.ch/holzbar)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%99%A5-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/holzcloud)

**holzBar** keeps your menu bar tidy: hide what you don't need, reveal it when you do,<br>
and make the bar look the way you like — on the notch, on every display, on macOS 27.

**[🌐 holzcloud.ch/holzbar](https://holzcloud.ch/holzbar)**

[Install](#-install) · [Verify](#-verify-a-download) · [Features](docs/features.md) · [Comparison](#-holzbar-vs-everyone-else) · [Privacy](docs/privacy-and-permissions.md) · [Troubleshooting](docs/build-and-troubleshooting.md) · [Credits](#-credits)

</div>

---

> [!IMPORTANT]
> ### 🪵 holzBar is a fork of the wonderful [Ice](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird)
> Ice is one of the best menu bar managers ever made for the Mac, and nearly everything you see here is Jordan's work.
> holzBar only keeps it going on macOS 27 while upstream development is slow. **If you enjoy holzBar, please ⭐ star
> [Ice](https://github.com/jordanbaird/Ice) and consider [sponsoring Jordan](https://github.com/sponsors/jordanbaird).**
> holzBar is independent and not affiliated with or endorsed by the Ice project.


## ✨ Why holzBar?

An independent fork of [Ice](https://github.com/jordanbaird/Ice), kept alive for macOS 27:

| | |
|---|---|
| 🪵 **macOS 14 to 27** | A dedicated backend for the redesigned macOS 27 menu bar. Every pull request launches the app on macOS 26 and 27 and runs the unit tests there; older macOS versions are not tested. |
| 🔒 **Never online** | No update checks, telemetry or analytics. A CI check proves there is no network code in the app. |
| 📦 **Zero dependencies, modern Swift** | Built with Swift 6.4 and Xcode 27, Swift 6 language mode, no third-party packages. |
| 🛡️ **Least privilege** | Only Accessibility at first launch; Screen Recording only when a feature needs it. From 0.0.7-beta2, one executable with no helper process or nested code, and no entitlements, not even one that lets a debugger attach. |
| 🔏 **Verifiable releases** | Signed with holzBar's own certificate, with GitHub build provenance and, from 0.0.7-beta2, SLSA Build Level 3 provenance. Actions pinned by commit SHA (except the SLSA generator, which must be referenced by its release tag), rated by OpenSSF Scorecard. |
| ✨ **More features** | Profiles, folders, spacers, Zen mode, Shortcuts actions, a black menu bar, URL commands, a camera and microphone dot on macOS 27. |
| 🌍 **Five languages** | English, German, French, Italian and Romansh. |

## ⚖️ holzBar vs. everyone else

An honest comparison with every menu bar manager we found that is on sale or maintained, **including where holzBar loses**. Researched on 9 October 2026 from each project's own pages, repositories and listings; the raw answers with quotes are in [`.planning/research/`](.planning/research). ✅ yes · ❌ no · ❓ not found (not stated, which is not the same as no) · 🔜 planned for holzBar and **not available yet**.

| | holzBar | Bartender 7 | Ice | Thaw | SaneBar | Tuck | Barbee | Hidden Bar | Dozer | Vanilla | iBar | Glow | Brow | Lounge |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Maintenance | active (0.0.7-beta4) | active (7.0.5) | stalled (0.11.12, Oct 2025) | active (3.0 beta, 7 Oct) | **sunset 30 Jun 2026** (last 2.1.91, 9 Sep) | active (1.2.0, 6 Oct) | active (5.0, 10 Sep) | active (1.11.1, 18 Sep) | none since 2022 | 2.2, date ❓ | active (2.1.1, 14 Sep) | active (3.2.0, 2 Oct) | active (version ❓) | active (1.3.1, 4 Oct) |
| Price | free | paid, one-time <sup>1</sup> | free | free | free | free; Pro $14.99 | free + in-app (lifetime $12.99) | free | free | free; Pro $10 | free + $2.99/yr | $19.99 once | free; Pro $49/yr (AI only) | $3.99/yr |
| Open source | ✅ GPL-3.0 | ❌ | ✅ GPL-3.0 | ✅ GPL-3.0 | ✅ MIT | ❌ | ❌ | ✅ MIT | ✅ MPL-2.0 | ❌ | ❌ | ❌ | ❌ | ❌ |
| macOS 26 / 27 | ✅ / ✅ | ❌ / ✅ <sup>2</sup> | dev builds / ❌ | ✅ / ✅ <sup>3</sup> | ✅ / ❌ | ✅ / ✅ <sup>4</sup> | ❓ / ❓ <sup>5</sup> | ✅ / partly <sup>6</sup> | ❓ / ❓ | ✅ / ❓ | ✅ / ❓ | ✅ / ✅ <sup>13</sup> | ❓ / vendor claim | ✅ / vendor claim |
| Apple Silicon / Intel | not yet checked | ✅ Apple Silicon (27) | ❓ | ❓ | Apple Silicon only | both | ❓ | both | Intel only (Rosetta) | both | both | both | ❓ | both |
| Hidden + always-hidden sections | ✅ | ✅ | ✅ | ✅ | ✅ | hidden; per-icon | hidden only ❓ | ✅ | ✅ | hidden; always-hidden in Pro | ✅ | 3 sections | hide, reorder; always-hidden ❓ | visible / hidden; no always-hidden |
| Separate bar, notch handling | ✅ Shelf | ✅ | ✅ Ice Bar | ✅ Thaw Bar | ✅ | ✅ Shelf | ✅ | ❌ | ❌ | partly | ✅ | ✅ GlowBar; notch ❓ | notch hover panel | ✅ floating panel |
| Layout profiles | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ ❓ | ✅ (VIP) | ❌ | ❌ | ❌ | ❌ | looks only (Moods) | ❌ | ❓ |
| Groups, spacers | ✅ | ✅ | ❌ | ✅ | groups, dividers | groups (Pro) | dividers | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ |
| Item spacing | ✅ beta | ✅ | ✅ beta | ✅ beta | ✅ | Pro | ✅ | ❌ | own icons only | ❌ | ✅ | ✅ | ❌ | ❓ |
| Search | ✅ | ✅ Command Bar | ✅ | ✅ | ✅ | Pro | weak | ❌ | ❌ | ❌ | ❌ | ✅ | ❓ | ❌ |
| Rules / triggers | 🔜 0.0.8 | ✅ <sup>7</sup> | ❌ | ✅ many <sup>8</sup> | ✅ 8 types | per app (Pro) | ✅ (VIP) | timer only | timer only | timer (Pro) | timer | ❌ <sup>12</sup> | ❌ <sup>12</sup> | ❌ <sup>12</sup> |
| Per-item conditional visibility | 🔜 0.0.8 | ✅ | ❌ | ✅ | ❌ | by active app (Pro) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Widgets / own items | 🔜 0.0.9 | ✅ | ❌ | planned | ❌ | ❌ | custom icons | ❌ | ❌ | ❌ | ❌ | ❌ | notch widgets | clipboard, agent notifications |
| Scripts as trigger/action | 🔜 0.0.8 | as widget source | ❌ | ✅ | trigger | ❓ | VIP ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | HTTP /notify endpoint |
| AppleScript | 🔜 0.0.9 | ✅ | ❌ <sup>9</sup> | ❌ <sup>9</sup> | ✅ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ |
| Shortcuts / Siri | ✅ | ✅ | ❌ | partly | via AppleScript | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ |
| URL scheme / CLI | ✅ holzbar:// | ✅ URL actions | ❌ | ✅ thaw:// | ✅ sanebar:// | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ |
| Hotkeys | ✅ also per profile and item | ✅ | ✅ | ✅ | ✅ per icon | ✅ | ✅ | one | ✅ | Pro | ✅ | ✅ | ✅ | ✅ |
| Zen mode (lock reveal gestures) | ✅ | Focus filter only | ❌ | ✅ | ❌ | ❓ | ❓ | ❌ | ❌ | ❌ | ❓ | ❌ | ❓ | ❓ |
| Lock behind Touch ID / password | 🔜 0.0.8 | ❌ <sup>10</sup> | ❌ | ❌ | ✅ | ❌ | ❓ | ❌ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ |
| Show/hide animation | 🔜 0.0.9 | ❓ | ❓ | Reduce Motion only | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ | ❓ | ✅ beta | ❓ | ✅ speed setting |
| Screen Recording | optional | optional | optional | optional | not needed | optional | required | not needed | not needed | required | ❓ | likely required | for its screenshot tools | not needed |
| Network connections | **none** | vendor: none <sup>11</sup> | Sparkle | Sparkle | Sparkle + anonymous event counts | licence + Sparkle | App Store: none | none | Sparkle | ❓ | App Store: none | check-in (versions, licence status) | none for core; AI servers (Pro) | analytics, crash reports, licence check |
| Export / import settings | ✅ | ❓ | ❌ | ✅ | ✅ (also from Bartender, Ice) | ❓ | cloud backup (VIP) | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ | ❓ |
| Sync between Macs | 🔜 1.0.0 | ❌ | ❌ | ❌ | ❌ | ❓ | ✅ profiles (VIP) | ❌ | ❌ | ❌ | ❓ | ❌ | ❌ (planned) | ❓ |
| Languages | 5 | 6 | ❓ | 20 | English? | >=8 | 20 | 10 | ❓ | ❓ | 15 | 4 | ❓ | English? |
| Dependencies, Swift | none, Swift 6 | closed | 5 packages, Swift 5 | 9 packages, Swift 6 | 3 packages, Swift 6 | ❓ | closed | 1 package, Swift 5 | 5, Swift 5 | closed | closed | closed | closed, native Swift | closed |
| Distribution | Homebrew | direct, Setapp (beta) | GitHub, Homebrew | GitHub, Homebrew | direct, Homebrew | direct, Homebrew | App Store | App Store, GitHub, Homebrew | GitHub, Homebrew | direct | App Store | direct | direct, Homebrew, App Store | direct |
| Appearance (tint, border, shapes, black bar, corners, glass) | ✅ all | styles: Glass, Pills, Outline, Gradient, Solid | tint, shadow, border, shapes | ✅ many, wallpaper tint | tint, border, corners, Liquid Glass | shelf styles, colours | menu bar shape, Apple-logo style | ❌ | icon size only | blends dots | ❓ | ✅ Liquid Glass, corners, borders, Moods | ❓ | icon styles only |
| Replaces or hides Apple's own items on macOS 27 | limit, replacements 🔜 0.0.9 | ❓ | ❌ | ✅ replacement icons | ❓ | system controls stay visible | ❓ | cannot (per app only) | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Signed with Developer ID and notarized | ❌ (own certificate) | ❓ | ✅ | ✅ | ✅ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ✅ vendor claim |
| Build provenance (attestation, SLSA) | ✅ SLSA 3 | ❓ | ❌ | ✅ Cosign + SLSA | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ | ❓ |
| Hides desktop icons | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| Clipboard history, extras beyond the menu bar | ❌ | ✅ Command Bar, Top Shelf | ❌ | ❌ | ❌ | ❌ | MCP server | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ clipboard, launcher, AI | ✅ clipboard history |
| Imports settings from other apps | ✅ Ice | ❓ Bartender 6 profiles (experimental) | ❌ | ❌ | ✅ Bartender, Ice | ❓ | ❓ | ❌ | ❌ | ❌ | ❌ | ❓ | ❓ | ❓ |
| Keyboard / VoiceOver | ✅ / ✅ | ✅ / ❓ | ❓ / ❓ | ✅ / ✅ | ✅ / ❓ | ✅ / ❓ | ✅ / ✅ | 1 hotkey / ❓ | 1 hotkey / ❓ | ❓ | ✅ / ❌ | ✅ / ❓ | ❓ | ❓ |

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

### Where holzBar is behind today

- **Automation:** Thaw, SaneBar and Bartender 7 have rules, per-item conditions and scripts now. holzBar gets them in 0.0.8, with fewer trigger types than Thaw.
- **No Developer ID signature or notarization**, unlike Thaw, SaneBar, Ice and Lounge (the vendor's claim). holzBar needs the `xattr` step or the Homebrew cask.
- **Fewer languages** than Thaw and Barbee (20 each); our translations into French, Italian and Romansh are machine-made and unchecked.
- **No widgets, AppleScript or animation yet** (0.0.9), no Touch ID lock yet (0.0.8). Bartender 7, SaneBar and Vanilla have them today.
- **No settings sync** since 0.0.7-beta3; the redesigned sync comes in 1.0.0. Barbee has cloud sync of profiles.
- **Not checked on real hardware** for several features, and one maintainer. SaneBar was sunset in June; Tuck and Glow ship updates every week or two.
- **Apple's own items on macOS 27** (clock, Control Center, Wi-Fi) cannot be hidden; Hidden Bar and Tuck cannot either, Thaw offers replacement icons. holzBar plans replacement items for 0.0.9.

### What holzBar does better

- The only one that **never connects to the network**; Ice, Thaw, SaneBar (anonymous counts), Glow, Lounge and Tuck all do.
- **No third-party packages** (Ice 5, Thaw 9, SaneBar 3), Swift 6.4 in Swift 6 mode, checked on macOS 26 and 27 on every change.
- **Screen Recording is optional**, and permissions are listed and explained.
- A **build provenance attestation** (SLSA Build Level 3) for every release.

## 🚀 Install

```sh
brew tap holzcloud/holzbar https://github.com/holzcloud/holzBar
brew trust --cask holzcloud/holzbar/holzbar
brew install --cask holzbar
```

`brew trust` is needed once: Homebrew only installs casks from third-party taps that you have trusted. Quit Ice, Thaw, Bartender or Hidden Bar first; your Ice settings are imported on the first launch.

**Update:** `brew update && brew upgrade --cask holzbar`. Coming from 0.0.5? It was a different app and cask; the [0.0.6 release notes](docs/release-notes/v0.0.6.md) list the steps.

**If macOS says holzBar "can't be opened":**

```sh
xattr -dr com.apple.quarantine /Applications/holzBar.app
```

Then open it again. The release is signed with holzBar's own certificate, SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`, and carries a build provenance attestation and, from 0.0.7-beta2, SLSA Build Level 3 provenance: [verify a download](#-verify-a-download). To build from source, see [Build and troubleshooting](docs/build-and-troubleshooting.md).

<p align="center"><img src="Resources/Screenshots/shelf.png" alt="The menu bar with the holzBar Shelf open below it, showing the hidden items" width="560"></p>

> [!WARNING]
> **macOS 27:** while holzBar hides menu bar items, Control Centre does not show its camera, microphone and screen recording indicator (the green dot beside the clock still shows the camera). holzBar cannot prevent this; it comes back while no item is hidden. Instead, holzBar puts a dot on its own icon while the microphone (orange) or the camera (green) is in use; it needs no permission, is on by default (**Settings → General**) and does not cover screen recording. [Details](docs/features.md#macos-27)

## 🔏 Verify a download

The certificate holzBar is signed with; this prints the SHA-256 above:

```sh
codesign -d --extract-certificates=/tmp/holzbar-certificate /Applications/holzBar.app && shasum -a 256 /tmp/holzbar-certificate0
```

The build provenance of the zip Homebrew downloaded, pinned to the release workflow and the version's tag ([GitHub CLI](https://cli.github.com): `brew install gh`, then `gh auth login`):

```sh
V=$(brew list --cask --versions holzbar | awk '{print $2}')
gh attestation verify "$(brew --cache --cask holzbar)" -R holzcloud/holzBar \
  --signer-workflow holzcloud/holzBar/.github/workflows/release.yml \
  --source-ref "refs/tags/v$V" --deny-self-hosted-runners
```

The SLSA provenance, from 0.0.7-beta2 on (`brew install slsa-verifier`):

```sh
gh release download "v$V" -R holzcloud/holzBar -p "holzBar-$V.zip" -p "holzBar-$V.intoto.jsonl"
slsa-verifier verify-artifact "holzBar-$V.zip" --provenance-path "holzBar-$V.intoto.jsonl" \
  --source-uri github.com/holzcloud/holzBar --source-tag "v$V"
```

A zip changed after the build, or built anywhere else, fails. Older releases and more detail: [docs/signing.md](docs/signing.md). Verifying uses the network from your terminal; holzBar itself never does.

## 🔜 Planned next

**None of this is available yet.** Plans can change; *spike* = only built if a short test shows it works well.

**0.0.7 is out** (see the [release notes](docs/release-notes/v0.0.7.md)): a bugfix release with no new features. Settings sync is removed from the app (a redesigned sync is planned for 1.0.0; Export… and Import… stay), and System Glass and the holzBar Shelf follow Reduce Transparency and Increase Contrast. macOS has no public API for the macOS 27 Liquid Glass slider, so holzBar cannot follow that. The Reduce Transparency treatment has not yet been checked on real macOS 26 and 27 systems. **Native macOS 27 overflow button support** did not make it into 0.0.7 and is planned for a later release.

**0.0.8 "Automation"** brings the first set of new features:

| | |
|---|---|
| ⚙️ **Automation** | **Rules** (Wi-Fi, app, time, power, display, Focus; *spike first: Focus*) · **per-item conditions** · **scripts** (only from a folder you choose, after you confirm) |
| 🛟 **Safety** | **Layout snapshots** with a one-click restore · **shareable profiles** · **Touch ID** to show hidden items · **revoke permissions in Settings** (with a guide) · **copy diagnostics** (redacted, nothing is sent) |
| 🪄 **Convenience** | **First-launch assistant** · **works without Screen Recording** (app icons instead of live snapshots) · system items such as Clock, Wi-Fi and Battery **pinned visible** · more **menu bar styles** |
| 🪵 **Polish** | SwiftUI reordering (*spike*) · keyboard and VoiceOver audit · Swift 6.4 clean-up |

**0.0.9** brings the rest:

| | |
|---|---|
| ⚙️ **Automation** | **Widgets** (text from permission-free sources such as CPU, memory, battery and disk, a countdown, a Shortcut button) · **AppleScript dictionary** · **App Intents** for Shortcuts and Siri · **command palette** · a keep-awake action · a "focus mode" hotkey |
| 🪄 **Convenience** | Opt-in **usage suggestions** (counters stay on your Mac) · **smooth show and hide** · replacement items for Apple items macOS 27 cannot hide · hiding system items such as Clock and Control Center |
| 🪵 **Polish** | Control Center control (*spike*, optional) |

**1.0.0** brings settings sync and the optional modules:

| | |
|---|---|
| 🔄 **Settings sync** | Your settings kept in step between your Macs through any folder they sync, such as iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing or a network share; **redesigned from scratch** |
| 🧩 **Modules** | The optional **all-in-one modules** |

**Wish list**, not scheduled yet: **more rule triggers** (VPN, Bluetooth, audio, camera and microphone, Energy Mode), **Shelf layouts** (grid, vertical) and **script hooks** before and after a profile is applied.

Details: [docs/features.md](docs/features.md#planned-next).

## 📚 More

[Features and gallery](docs/features.md) · [macOS 27 notes](docs/features.md#macos-27) · [Privacy and permissions](docs/privacy-and-permissions.md) · [Troubleshooting](docs/build-and-troubleshooting.md) · [More detail on Ice, Thaw and Bartender](docs/comparison.md) · [Notes on the comparison](docs/alternatives.md)

## 🙏 Credits

- [**Ice**](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird) — the app holzBar is built on: its design, its features and almost all of its code. Thank you, Jordan! 💙 If you like it, [sponsor Jordan](https://github.com/sponsors/jordanbaird) or [buy him a coffee](https://www.buymeacoffee.com/jordanbaird).
- [**RabenkoYevhenii**](https://github.com/RabenkoYevhenii) — the macOS 27 backend ([jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)).
- [**Barometer**](https://github.com/mackid1993/Barometer) by [mackid1993](https://github.com/mackid1993) and [**Thaw**](https://github.com/thaw-app/Thaw) by [thaw-app](https://github.com/thaw-app) — the macOS 27 assertion code holzBar's hiding is adapted from.

holzBar links no third-party package. The adapted projects and their licenses are listed in the app under **Settings → About → Acknowledgements**.

## 📄 License

holzBar is available under the [GPL-3.0 license](LICENSE), like Ice. See [NOTICE](NOTICE) for attribution and a summary of the changes made in this fork.
