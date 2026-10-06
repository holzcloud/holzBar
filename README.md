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

[Install](#-install) · [Verify](#-verify-a-download) · [Features](docs/features.md) · [Comparison](docs/comparison.md) · [Privacy](docs/privacy-and-permissions.md) · [Troubleshooting](docs/build-and-troubleshooting.md) · [Credits](#-credits)

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
| 🪵 **macOS 14 to 27** | A dedicated backend for the redesigned macOS 27 menu bar. Every pull request launches the app on macOS 14, 15, 26 and 27 and runs the unit tests. |
| 🔒 **Never online** | No update checks, telemetry or analytics. A CI check proves there is no network code in the app. |
| 📦 **Zero dependencies, modern Swift** | Built with Swift 6.4 and Xcode 27, Swift 6 language mode, no third-party packages. |
| 🛡️ **Least privilege** | Only Accessibility at first launch; Screen Recording only when a feature needs it. From 0.0.7-beta2, one executable with no helper process or nested code, and no entitlements, not even one that lets a debugger attach. |
| 🔏 **Verifiable releases** | Signed with holzBar's own certificate, with GitHub build provenance and, from 0.0.7-beta2, SLSA Build Level 3 provenance. Actions pinned by commit SHA (except the SLSA generator, which must be referenced by its release tag), rated by OpenSSF Scorecard. |
| ✨ **More features** | Profiles, folders, spacers, Zen mode, Shortcuts actions, a black menu bar, URL commands, settings sync through any folder, a camera and microphone dot on macOS 27. |
| 🌍 **Five languages** | English, German, French, Italian and Romansh. |

## ⚖️ holzBar vs. Ice and Thaw

— means not available or not documented. 🔜 means planned: **not available yet**. The [full comparison](docs/comparison.md) has every row.

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| macOS 14 – 26 | ✅ | macOS 26 only | ✅ |
| macOS 27 | ❌ | ✅ | ✅ |
| Layout profiles, groups, spacers | ❌ | ✅ | ✅ |
| Zen mode, URL commands, Shortcuts actions | ❌ | ✅ | ✅ |
| Settings sync: iCloud Drive or any synced folder | ❌ | ❌ | ✅ |
| Network connections | Sparkle update checks | Sparkle update checks | **none** |
| Swift packages | 5 | 10 | **none** |
| Swift language mode | Swift 5 | Swift 6 | Swift 6 |
| One executable, no helper process with the app's permissions | ❌ | — | ✅ <sub>from 0.0.7-beta2</sub> |
| Build provenance: GitHub attestation, SLSA Build Level 3 | ❌ | — | ✅ <sub>SLSA from 0.0.7-beta2</sub> |
| OpenSSF Scorecard, actions pinned by commit SHA | — | — | ✅ <sub>except the SLSA generator (release tag)</sub> |
| Rules (Wi-Fi, app, time, power, display, Focus) | ❌ | ✅ | 🔜 |

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

## 🔜 Planned for 0.0.7 "Automation"

**Not available yet.** Plans can change; *spike* = only built if a short test shows it works well.

| | |
|---|---|
| ⚙️ **Automation** | **Rules** (Wi-Fi, app, time, power, display, Focus; *spike first: Focus*) · **per-item conditions** · **scripts** (only from a folder you choose, after you confirm) · **widgets** · **AppleScript dictionary** · **command palette** |
| 🛟 **Safety** | **Layout snapshots** with a one-click restore · **shareable profiles** · **Touch ID** to show hidden items · **copy diagnostics** (redacted, nothing is sent) |
| 🪄 **Convenience** | **First-launch assistant** · opt-in **usage suggestions** (counters stay on your Mac) · **smooth show and hide** |
| 🪵 **macOS 27 and polish** | Native overflow button support · Reduce Transparency · SwiftUI reordering (*spike*) · Control Center control (*spike*) · keyboard and VoiceOver audit · Swift 6.4 clean-up |

Details: [docs/features.md](docs/features.md#planned-for-007-automation).

## 📚 More

[Features and gallery](docs/features.md) · [macOS 27 notes](docs/features.md#macos-27) · [Privacy and permissions](docs/privacy-and-permissions.md) · [Troubleshooting](docs/build-and-troubleshooting.md) · [Full comparison](docs/comparison.md)

## 🙏 Credits

- [**Ice**](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird) — the app holzBar is built on: its design, its features and almost all of its code. Thank you, Jordan! 💙 If you like it, [sponsor Jordan](https://github.com/sponsors/jordanbaird) or [buy him a coffee](https://www.buymeacoffee.com/jordanbaird).
- [**RabenkoYevhenii**](https://github.com/RabenkoYevhenii) — the macOS 27 backend ([jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)).
- [**Barometer**](https://github.com/mackid1993/Barometer) by [mackid1993](https://github.com/mackid1993) and [**Thaw**](https://github.com/thaw-app/Thaw) by [thaw-app](https://github.com/thaw-app) — the macOS 27 assertion code holzBar's hiding is adapted from.

holzBar links no third-party package. The adapted projects and their licenses are listed in the app under **Settings → About → Acknowledgements**.

## 📄 License

holzBar is available under the [GPL-3.0 license](LICENSE), like Ice. See [NOTICE](NOTICE) for attribution and a summary of the changes made in this fork.
