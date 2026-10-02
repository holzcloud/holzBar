<div align="center">

<img src="Resources/Logo/banner.png" alt="holzIce — the menu bar manager for macOS" width="100%">

<br>

[![Release](https://img.shields.io/github/v/release/holzcloud/holzIce?include_prereleases&style=for-the-badge&label=release&color=2A86E0)](https://github.com/holzcloud/holzIce/releases)
[![Homebrew](https://img.shields.io/badge/brew-holzice-D58C4A?style=for-the-badge&logo=homebrew&logoColor=white)](#-install)
[![macOS](https://img.shields.io/badge/macOS-14%20→%2027-111827?style=for-the-badge&logo=apple&logoColor=white)](#-macos-27)
[![License](https://img.shields.io/github/license/holzcloud/holzIce?style=for-the-badge&color=4B5563)](LICENSE)
[![Website](https://img.shields.io/badge/website-holzcloud.ch%2Fholzice-0E7C66?style=for-the-badge)](https://holzcloud.ch/holzice)
[![Sponsor](https://img.shields.io/badge/sponsor-%E2%99%A5-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/holzcloud)

**holzIce** keeps your menu bar tidy: hide what you don't need, reveal it when you do,<br>
and make the bar look the way you like — on the notch, on every display, on macOS 27.

**[🌐 holzcloud.ch/holzice](https://holzcloud.ch/holzice)**

[Install](#-install) · [macOS 27](#-macos-27) · [Features](#-features) · [Gallery](#-gallery) · [Credits](#-credits)

</div>

---

> [!IMPORTANT]
> ### 🧊 holzIce is a fork of the wonderful [Ice](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird)
> Ice is one of the best menu bar managers ever made for the Mac, and nearly everything you see here is Jordan's work.
> holzIce only keeps it going on macOS 27 while upstream development is slow. **If you enjoy holzIce, please ⭐ star
> [Ice](https://github.com/jordanbaird/Ice) and consider [sponsoring Jordan](https://github.com/sponsors/jordanbaird).**
> holzIce is independent and not affiliated with or endorsed by the Ice project.

## ✨ Why holzIce?

holzIce is a community fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird. Ice is a fantastic tool, but its development has slowed down — and macOS 27 broke it for most people. holzIce picks it up from there:

| | |
|---|---|
| 🧊 **Works on macOS 27** | New backend for the redesigned menu bar drawn by `MenuBarAgent`. |
| 🍺 **Homebrew first** | Install and update with one command. |
| 🔐 **No more permission loop** | A stale permission can be reset right from the permissions window. |
| 🌲 **Actively maintained** | Fixes land here instead of waiting upstream. |
| ✨ **More features** | Profiles, groups, spacers, a black menu bar, URL commands, settings sync — [see below](#-features). |

## 🚀 Install

### Homebrew <sub>(recommended)</sub>

```sh
brew tap holzcloud/holzice https://github.com/holzcloud/holzIce
brew trust --cask holzcloud/holzice/holzice
brew install --cask holzice
```

`brew trust` is needed once: Homebrew only installs casks from third-party taps that you have trusted.

Update with:

```sh
brew update && brew upgrade --cask holzice
```

### If macOS says holzIce "can't be opened"

holzIce is signed ad hoc, without an Apple Developer ID. The Homebrew cask removes the quarantine flag for you, but if you downloaded the zip yourself — or macOS still blocks the app — take it out of quarantine:

```sh
xattr -dr com.apple.quarantine /Applications/holzIce.app
```

Then open holzIce again. Alternatively: open it once, then go to **System Settings → Privacy & Security** and click **Open Anyway** next to the holzIce message.

> [!NOTE]
> holzIce replaces the original Ice — quit Ice and run `brew uninstall --cask jordanbaird-ice` first if you have it. Two menu bar managers must never run at the same time; holzIce offers to quit Ice, Bartender or Hidden Bar when it finds one running.
> Your Ice settings (layout, hotkeys, appearance) are imported automatically on the first launch.

### Build from source

Requires Xcode 27 on macOS 14 or later.

```sh
git clone https://github.com/holzcloud/holzIce
cd holzIce
Scripts/install.sh            # installs to ~/Applications
```

## 🧊 macOS 27

macOS 27 no longer draws menu bar items as separate windows — `MenuBarAgent` draws them all into one bar. holzIce ships a dedicated backend for it (from [jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)):

- **Hiding** via assessment-mode assertions, with per-app sections
- **Item discovery** through Accessibility instead of window lists
- **holzIce Bar** with real item images and even spacing
- **Layout editor** that assigns apps to sections — your old layout is carried over on first launch

**Known limitations on macOS 27**

- Items can't be reordered on the bar itself — only assigned to sections.
- Opening a system item (clock, battery, Wi-Fi) while hidden items are concealed adds ~150 ms.
- After an update, macOS may ask for Accessibility again. If holzIce is stuck on the permissions window, click **Reset and Grant Again**.

## 🧰 Features

<table>
<tr>
<td valign="top" width="50%">

#### Menu bar items
- ✅ Hide items in a hidden and an always-hidden section
- ✅ Show on hover, click or scroll (trackpad **and mouse wheel**)
- ✅ Automatic rehide
- ✅ Drag-and-drop layout editor
- ✅ **Layout profiles** — "Work", "Home", … one click or URL away
- ✅ **Groups** — several items behind an icon of their own
- ✅ **Spacers** — empty items of adjustable width
- ✅ **Choose where new items appear**
- ✅ Search menu bar items
- ✅ Item spacing <sub>BETA</sub>

</td>
<td valign="top" width="50%">

#### holzIce Bar
- ✅ Hidden items in a bar below the menu bar
- ✅ **Only on the built-in display or on displays with a notch**
- ✅ **Shows items the notch covers**

#### Appearance
- ✅ Tint, shadow, border, rounded and split shapes
- ✅ **Black menu bar that hides the notch**
- ✅ **Rounded screen corners**

</td>
</tr>
<tr>
<td valign="top" width="50%">

#### Automation
- ✅ **Show hidden items when the battery is low or the network drops**
- ✅ **`holzice://` URL commands** and [Raycast script commands](Integrations/Raycast)
- ✅ Hotkeys for sections, search, the holzIce Bar, app menus, **auto-rehide** and **a quick peek**

</td>
<td valign="top" width="50%">

#### Settings
- ✅ **Export and import** all settings
- ✅ **Sync between Macs** through iCloud Drive
- ✅ **Imports your Ice settings** on first launch
- ✅ Launch at login

</td>
</tr>
</table>

### holzIce vs. Ice

| | Ice 0.11.12 | holzIce |
|---|:---:|:---:|
| macOS 14 – 26 | ✅ | ✅ |
| **macOS 27** | ❌ | ✅ |
| Install and update with Homebrew | ✅ | ✅ |
| Updates | Sparkle (dialog can hang on macOS 26) | Homebrew |
| Hidden and always-hidden sections, Ice Bar, search, appearance | ✅ | ✅ |
| Layout profiles | ❌ | ✅ |
| Groups and spacers | ❌ | ✅ |
| Choose where new items appear | ❌ | ✅ |
| Bar only on some displays, notch overflow | ❌ | ✅ |
| Black menu bar, rounded screen corners | ❌ | ✅ |
| Show hidden items on low battery or when offline | ❌ | ✅ |
| URL commands and Raycast | ❌ | ✅ |
| Export, import and sync settings | ❌ | ✅ |
| Keep Live Activities visible | ❌ | ✅ <sub>experimental</sub> |
| Show on scroll with a mouse wheel | ❌ | ✅ |
| Fix for the permissions loop | ❌ | ✅ |
| Fixes from 280 open bug reports | — | [see the list](docs/upstream-bugs.md) |
| Signed with a Developer ID | ✅ | ❌ (ad hoc; the cask handles it) |

## 🖼 Gallery

<table>
<tr>
<td width="50%"><b>holzIce Bar</b> — hidden items below the menu bar<br><img src="https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b" alt="Ice Bar"></td>
<td width="50%"><b>Layout</b> — drag and drop your items<br><img src="https://github.com/user-attachments/assets/095442ba-f2d0-4bb4-9632-91e26ef8d45b" alt="Menu Bar Layout"></td>
</tr>
<tr>
<td width="50%"><b>Appearance</b> — tint, shadow, shapes<br><img src="https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3" alt="Menu Bar Appearance"></td>
<td width="50%"><b>Search</b> — find any item<br><img src="https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8" alt="Menu Bar Item Search"></td>
</tr>
</table>

<sub>Screenshots from the original Ice.</sub>

## 🙏 Credits

- [**Ice**](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird) — the app holzIce is built on: its design, its features and almost all of its code. Thank you, Jordan! 💙 If you like it, [sponsor Jordan](https://github.com/sponsors/jordanbaird) or [buy him a coffee](https://www.buymeacoffee.com/jordanbaird).
- [**RabenkoYevhenii**](https://github.com/RabenkoYevhenii) — the macOS 27 backend ([jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)).

## 📄 License

holzIce is available under the [GPL-3.0 license](LICENSE), like Ice. See [NOTICE](NOTICE) for attribution and a summary of the changes made in this fork.
