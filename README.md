<div align="center">

<img src="Resources/Logo/banner.png" alt="holzBar, the open source menu bar manager for macOS" width="100%">

<br>

[![Release](https://img.shields.io/github/v/release/holzcloud/holzBar?include_prereleases&style=for-the-badge&label=release&color=2A86E0)](https://github.com/holzcloud/holzBar/releases)
[![Homebrew](https://img.shields.io/badge/brew-holzbar-D58C4A?style=for-the-badge&logo=homebrew&logoColor=white)](#install)
[![macOS](https://img.shields.io/badge/macOS-26%20%C2%B7%2027-111827?style=for-the-badge&logo=apple&logoColor=white)](docs/macos27.md)
[![Privacy](https://img.shields.io/badge/privacy-no%20network%20connections-0E7C66?style=for-the-badge)](docs/privacy-and-permissions.md)
[![SLSA 3](https://slsa.dev/images/gh-badge-level3.svg)](docs/signing.md)
[![License](https://img.shields.io/github/license/holzcloud/holzBar?style=for-the-badge&color=4B5563)](LICENSE)

**holzBar** is a free, open source menu bar manager for macOS. It hides the icons you don't need,<br>
shows them again when you do, and works with the notch on macOS 26 and 27.

[Website](https://holzcloud.ch/holzbar) · [Install](#install) · [Features](docs/features.md) · [Comparison](#how-it-compares) · [Privacy](docs/privacy-and-permissions.md) · [Credits](#credits)

</div>

---

> [!IMPORTANT]
> ### holzBar is a fork of [Ice](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird)
> Ice is one of the best menu bar managers ever made for the Mac, and nearly everything you see here is Jordan's work.
> holzBar keeps it going on macOS 27 while upstream development is slow. **If you enjoy holzBar, please star
> [Ice](https://github.com/jordanbaird/Ice) and consider [sponsoring Jordan](https://github.com/sponsors/jordanbaird).**
> holzBar is independent and not affiliated with or endorsed by the Ice project.

<p align="center"><img src="Resources/Screenshots/shelf.png" alt="The macOS menu bar with the holzBar Shelf open below it, showing the hidden menu bar icons" width="560"></p>

## Why holzBar

If you looked for an Ice fork that runs on macOS 27, or a free Bartender alternative that is open source, this is it.

- **Works on macOS 26 and 27.** A dedicated backend for the redesigned macOS 27 menu bar. Every pull request that changes code launches the app on both and runs the unit tests there. It needs macOS 14 or later; CI runs macOS 26 and 27.
- **Never online.** No update checks, telemetry or analytics, and a CI check proves the app contains no network code.
- **No dependencies, modern Swift.** Swift 6 language mode, built with Swift 6.4 and Xcode 27, no third-party packages.
- **Least privilege.** Accessibility at first launch, Screen Recording optional, for pictures of your items, Location Services only when you add a Wi-Fi-name condition to a rule, Bluetooth only when you add a Bluetooth condition or switch on the Accessory alerts module. Calendar access only when you switch on the Calendar module of the notch hub, and access to your Downloads folder only when you switch on its downloads source in the Live activities module (the camera and microphone source needs no permission). Since 0.0.7-beta2 no XPC service or helper app, and from 0.0.14 one signed library for the optional Read all apps of Now Playing, used only while the hub is open and that switch is on; from 0.0.14 holzBar carries one entitlement, `com.apple.security.personal-information.calendars`, which only lets macOS ask you for Calendar access, and no `get-task-allow`.
- **Verifiable releases.** Signed with holzBar's own certificate, with GitHub build provenance and, since 0.0.7-beta2, SLSA Build Level 3 provenance.
- **More than Ice.** Rules, scripts and widgets, profiles, folders, spacers, Zen mode, Shortcuts actions, URL commands, a command palette and moods, a black menu bar, and a camera and microphone dot on macOS 27. Available in 11 languages: English, German, French, Italian, Romansh, Spanish, Brazilian Portuguese, Japanese, Simplified Chinese, Korean and Russian.

<table>
<tr>
<td width="50%" valign="top"><b>Layout</b>: drag items into sections<br><img src="Resources/Screenshots/settings-layout.png" alt="holzBar settings, Menu Bar Layout: drag menu bar icons into the visible, hidden and always-hidden sections"></td>
<td width="50%" valign="top"><b>Appearance</b>: moods, tint, border, shapes, a black bar<br><img src="Resources/Screenshots/settings-appearance.png" alt="holzBar settings, Menu Bar Appearance: tint, shadow, border, shapes and rounded screen corners"></td>
</tr>
</table>

More screenshots in the [gallery](docs/features.md#gallery).

## How it compares

Researched on 9 October 2026 from each project's own pages and repositories. A dash means the project does not state it.

| | Ice | Thaw | Bartender 7 | holzBar |
|---|:---:|:---:|:---:|:---:|
| Price, licence | free, GPL-3.0 | free, GPL-3.0 | paid, closed | free, GPL-3.0 |
| macOS 26 / 27 | dev builds / no | yes / yes | no (use Bartender 6) / yes | yes / yes |
| Hidden and always-hidden sections, separate bar | yes | yes | yes | yes |
| Layout profiles, groups, spacers | no | yes | yes | yes |
| Rules and scripts | no | yes | yes | yes |
| Network connections | Sparkle updates | Sparkle updates | vendor says none | none, enforced by CI |
| Dependencies, Swift | 5 packages, Swift 5 | 9 packages, Swift 6 | closed | none, Swift 6 |
| Build provenance | no | Cosign, SLSA | - | SLSA Build Level 3 |
| Developer ID, notarized | yes | yes | - | no (own certificate) |

Where holzBar loses: it has no Developer ID signature, fewer languages than Thaw, a slide of the bar's own items on macOS 26 only, a small AppleScript dictionary, and one maintainer. The [full comparison](docs/comparison.md) covers 14 apps, with sources and the cells we could not verify.

## Install

Two Homebrew channels from the same tap. **Stable** (`holzbar`) is the newest plain release, currently 0.0.13. **Beta** (`holzbar@beta`) is the newest alpha, beta or plain release, whichever is newest.

```sh
brew tap holzcloud/holzbar https://github.com/holzcloud/holzBar
brew trust --cask holzcloud/holzbar/holzbar
brew install --cask holzcloud/holzbar/holzbar
```

For the beta, use `holzbar@beta` in the last two commands. Quit Ice, Thaw, Bartender or Hidden Bar first; your Ice settings are imported on the first launch. Update with `brew update && brew upgrade --cask holzbar`.

If macOS says holzBar "can't be opened", run `xattr -dr com.apple.quarantine /Applications/holzBar.app` and open it again. The release certificate has the SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`; how to verify a download is in [docs/signing.md](docs/signing.md#for-users-verify-a-download). Switching channels, updating from 0.0.5 and building from source are in [Build and troubleshooting](docs/build-and-troubleshooting.md).

> [!WARNING]
> **macOS 27:** while holzBar hides menu bar items, Control Centre does not draw its camera, microphone and screen recording indicator. holzBar cannot prevent this, so it puts a dot on its own icon while the microphone (orange) or camera (green) is in use. [Details](docs/macos27.md#camera-and-microphone-indicator)

## What's next

**New in 0.0.14** (see [what is new](docs/features.md#new-in-0014)): a **count badge** on the holzBar icon, a small number that says how many items are hidden right now. It is off until you switch it on in Settings → General. The notch hub also has its first module, **Timers**: timers, countdowns to a moment and a stopwatch, with a sound when a timer ends and no permission. Its second module, **Calendar**, lists your next events with a Join button for meeting links; it asks for Calendar access only when you switch it on. Its third module, **Live activities**, hangs a small capsule below the notch while another app uses the camera or the microphone or a download is in progress in your Downloads folder, and lists them in the hub; it is not Apple's Live Activities from the iPhone. The downloads source asks for access to your Downloads folder only when you switch it on. Its fourth module, **File drop**, is a stash at the notch: drag files toward the notch, drop them in the hub, and drag them out later as copies. It needs no permission, keeps only where the files are, in memory, and forgets them when you quit. Its fifth module, **Display controls**, adds a volume slider with mute and a brightness slider to a tab of the hub; it needs no permission and costs nothing while it is off. Brightness has no public macOS API, so it uses a macOS call that Apple does not document, which may stop working in a later macOS; **Brightness** in the module's settings turns that call off. Its sixth module, **Accessory alerts**, hangs a capsule below the notch for five seconds when a paired accessory such as AirPods or headphones connects (and, if you want, when it disconnects) or runs low on battery, and lists the connected accessories with the battery levels macOS reports. It asks for Bluetooth only when you switch it on, and it never connects to, scans for or pairs with a device. The battery levels come from a macOS call that Apple does not document, so they may stop working in a later macOS; **Read battery levels** turns that call off. No device name is stored or logged. Its seventh module, **Notifications**, lists the banners and alerts that macOS shows, newest first, in a tab of the hub, with the Overview count and a pill beside the notch. macOS has no public way to read other apps' notifications, so holzBar reads the banners macOS draws, through the Accessibility access it already has, and asks for no Notifications permission; it has been measured on macOS 27.2 and follows a structure that a macOS update may change. It sees only banners and alerts that appear on screen (nothing a Focus holds back), cannot reply to or open a notification, keeps at most twenty in memory only, never stores, logs or sends them, and does not record while the screen is mirrored or shared; you can exclude an app. Its eighth module, **Now Playing**, shows what Music and Spotify play, with play, pause, next and previous, and the artwork of a song stored on your Mac. They announce what they play to every app, so it needs no permission; its buttons use the Accessibility access holzBar already has, only when you click one. With the switch **Read all apps** (off by default) it also shows what browsers and video apps play, through a private macOS interface that Apple does not document and a small library of holzBar's own that holzBar starts only while the hub is open; if macOS changes that interface, the switch turns itself off. It stores no song and sends nothing.

**0.0.11** (see the [release notes](docs/release-notes/v0.0.11.md) and [what is new](docs/features.md#new-in-0011)): the bar's hidden items slide in and out on macOS 26, under **Animate showing and hiding** in Settings → General (since 0.0.13 the **Animation** cards, see below; never with Reduce Motion on; macOS 27 animates its own bar, macOS 14 and 15 keep the instant change). The Search and Hints panels have a new glass look, and the type sizes and spacing in Settings come from one shared set of design tokens.

**0.0.12 is out** (see the [release notes](docs/release-notes/v0.0.12.md) and [what is new](docs/features.md#new-in-0012)): Apple Items, the Notch hub, Smart Categories, a floating Shelf and a glass command palette.

**0.0.9** (see the [release notes](docs/release-notes/v0.0.9.md) and [what is new](docs/features.md#new-in-009)): a new Settings window with a Modules pane, a command palette, an AppleScript dictionary, moods (saved looks), grid and column layouts and a fade for the holzBar Shelf, sound output and Bluetooth conditions for rules, opt-in usage suggestions, and a hint when a rule puts an item back.

**0.0.8** (see the [release notes](docs/release-notes/v0.0.8.md) and [what is new](docs/features.md#new-in-008)) brought rules, scripts, per-item conditions, widgets, layout snapshots, a Touch ID lock, menu bar styles, dragging items without ⌘ and support for macOS 27's own overflow button.

**0.0.13 is out** (see the [release notes](docs/release-notes/v0.0.13.md) and [what is new](docs/features.md#new-in-0013)): the Widgets module also offers **built-in items**: Focus, AirDrop (drop files on it to share them), media controls, fast user switching, a timer, and **app launchers**, a holzBar icon for any app you choose, each a menu bar item like any other, so it hides, moves and shows in the Shelf with the rest ([what they do](docs/features.md#built-in-items-and-app-launchers)). Four upgrades of the holzBar Shelf, with their settings in Settings → General. **Type to find** an item and open it with Return, the **always-hidden items behind one fold tile** ("+3"), apps that are **not running shown dimmed** so a click launches them, and **dragging** an item to put it in order, into another section or up onto the menu bar ([what they do](docs/features.md#new-in-0013)). Behaviour and the layout editor: the **Animation** setting shows Instant, Smooth and Fade as picture cards; on macOS 27 the **clock** opens Notification Center while items are hidden, and you can turn that off; each display can **always show everything** or **collapse**, and the display under the pointer decides; and the Menu Bar Layout pane **draws first and applies in one pass**, with a tile that shows where new items land ([what they do](docs/features.md#behaviour-and-the-layout-editor)). The search knows **short names** (`bt` finds Bluetooth, `wlan` Wi-Fi, `dnd` Focus) and puts the items you open from it first, with a **Forget** button; holzBar's own menu bar icon comes in more styles as **picture cards**, with a **No icon** card, and the Shelf's style and layout and the menu bar's shape are picture cards too ([what they do](docs/features.md#menu-bar-icon-search-and-design)). holzBar now speaks **11 languages**, with Spanish, Brazilian Portuguese, Japanese, Simplified Chinese, Korean and Russian new.

**New in 0.0.12:** on macOS 27 the **Apple Items** module hides the clock, Control Center, Wi-Fi or the battery and adds replacement icons that open an Apple item. **Smart Categories** add category buttons to the search (System, Network, Media and more), worked out from what holzBar can read about each app; nothing is recorded. The holzBar Shelf can also **float**: under **Style** in Settings → General it becomes a bar of its own a little below the menu bar, and under **Location** it opens at the holzBar icon, at the right edge of the screen or below the mouse pointer. The command palette has the new glass look. The **notch hub**, a panel at the notch for optional modules, is there with no module in it yet ([what it does](docs/features.md#new-in-0012)).

**Planned, not available yet:** settings sync and the other modules of the notch hub in 1.0.0. Every later module is optional, off until you switch it on, and never uses the network. The [roadmap](docs/features.md#planned-next) has the details.

## More

[Features and gallery](docs/features.md) · [macOS 27 notes](docs/macos27.md) · [Privacy and permissions](docs/privacy-and-permissions.md) · [Troubleshooting](docs/build-and-troubleshooting.md) · [Full comparison](docs/comparison.md) · [Notes on the comparison](docs/alternatives.md)

## Credits

- [**Ice**](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird): the app holzBar is built on, with its design, its features and almost all of its code. Thank you, Jordan! If you like it, [sponsor Jordan](https://github.com/sponsors/jordanbaird) or [buy him a coffee](https://www.buymeacoffee.com/jordanbaird).
- [**RabenkoYevhenii**](https://github.com/RabenkoYevhenii): the macOS 27 backend ([jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)).
- [**Barometer**](https://github.com/mackid1993/Barometer) by [mackid1993](https://github.com/mackid1993) and [**Thaw**](https://github.com/thaw-app/Thaw) by [thaw-app](https://github.com/thaw-app): the macOS 27 assertion code holzBar's hiding is adapted from.

holzBar links no third-party package. The adapted projects and their licenses are listed in the app under **Settings → About → Acknowledgements**.

## License

holzBar is available under the [GPL-3.0 license](LICENSE), like Ice. See [NOTICE](NOTICE) for attribution and a summary of the changes made in this fork. Like holzBar? [Sponsor holzcloud](https://github.com/sponsors/holzcloud).
