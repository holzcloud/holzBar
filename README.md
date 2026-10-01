<div align="center">

<img src="Resources/Logo/banner.png" alt="holzIce — the menu bar manager for macOS" width="100%">

<br>

[![Release](https://img.shields.io/github/v/release/holzcloud/holzIce?style=for-the-badge&label=release&color=2A86E0)](https://github.com/holzcloud/holzIce/releases/latest)
[![Homebrew](https://img.shields.io/badge/brew-holzice-D58C4A?style=for-the-badge&logo=homebrew&logoColor=white)](#-install)
[![macOS](https://img.shields.io/badge/macOS-14%20→%2027-111827?style=for-the-badge&logo=apple&logoColor=white)](#-macos-27)
[![License](https://img.shields.io/github/license/holzcloud/holzIce?style=for-the-badge&color=4B5563)](LICENSE)

**holzIce** keeps your menu bar tidy: hide what you don't need, reveal it when you do,<br>
and make the bar look the way you like — on the notch, on every display, on macOS 27.

[Install](#-install) · [macOS 27](#-macos-27) · [Features](#-features) · [Gallery](#-gallery) · [Credits](#-credits)

</div>

---

## ✨ Why holzIce?

holzIce is a community fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird. Ice is a fantastic tool, but its development has slowed down — and macOS 27 broke it for most people. holzIce picks it up from there:

| | |
|---|---|
| 🧊 **Works on macOS 27** | New backend for the redesigned menu bar drawn by `MenuBarAgent`. |
| 🍺 **Homebrew first** | Install and update with one command. |
| 🔐 **No more permission loop** | A stale permission can be reset right from the permissions window. |
| 🌲 **Actively maintained** | Fixes land here instead of waiting upstream. |

## 🚀 Install

### Homebrew <sub>(recommended)</sub>

```sh
brew tap holzcloud/holzice https://github.com/holzcloud/holzIce
brew install --cask holzice
```

Update with:

```sh
brew upgrade --cask holzice
```

> [!NOTE]
> holzIce replaces the original Ice — run `brew uninstall --cask jordanbaird-ice` first if you have it.
> The app is signed ad hoc (there is no Developer ID); the cask removes the quarantine flag so it opens normally.

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
- **Ice Bar** with real item images and even spacing
- **Layout editor** that assigns apps to sections — your old layout is carried over on first launch

**Known limitations on macOS 27**

- Items can't be reordered on the bar itself — only assigned to sections.
- Opening a system item (clock, battery, Wi-Fi) while hidden items are concealed adds ~150 ms.
- After an update, macOS may ask for Accessibility again. If Ice is stuck on the permissions window, click **Reset and Grant Again**.

## 🧰 Features

<table>
<tr>
<td valign="top" width="50%">

#### Menu bar items
- ✅ Hide menu bar items
- ✅ "Always-hidden" section
- ✅ Show on hover, click or scroll
- ✅ Automatically rehide
- ✅ Hide app menus when they overlap
- ✅ Drag-and-drop layout
- ✅ Ice Bar (great with the notch)
- ✅ Search menu bar items
- ✅ Item spacing <sub>BETA</sub>
- ⬜ Layout profiles
- ⬜ Spacer items & groups

</td>
<td valign="top" width="50%">

#### Appearance
- ✅ Tint (solid and gradient)
- ✅ Shadow and border
- ✅ Rounded and split shapes
- ⬜ Remove the bar's background
- ⬜ Separate light/dark settings

#### Hotkeys
- ✅ Toggle sections
- ✅ Search panel
- ✅ Ice Bar on/off
- ✅ Toggle app menus
- ⬜ Toggle auto rehide

</td>
</tr>
</table>

## 🖼 Gallery

<table>
<tr>
<td width="50%"><b>Ice Bar</b> — hidden items below the menu bar<br><img src="https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b" alt="Ice Bar"></td>
<td width="50%"><b>Layout</b> — drag and drop your items<br><img src="https://github.com/user-attachments/assets/095442ba-f2d0-4bb4-9632-91e26ef8d45b" alt="Menu Bar Layout"></td>
</tr>
<tr>
<td width="50%"><b>Appearance</b> — tint, shadow, shapes<br><img src="https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3" alt="Menu Bar Appearance"></td>
<td width="50%"><b>Search</b> — find any item<br><img src="https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8" alt="Menu Bar Item Search"></td>
</tr>
</table>

<sub>Screenshots from the original Ice.</sub>

## 📦 Releasing

Push a tag `v<version>` — or run the **Release** workflow by hand. It builds the app, publishes a GitHub release and updates [`Casks/holzice.rb`](Casks/holzice.rb) on `main`.

```sh
git tag v0.11.13-holz.1 && git push origin v0.11.13-holz.1
```

## 🙏 Credits

- [**Ice**](https://github.com/jordanbaird/Ice) by [Jordan Baird](https://github.com/jordanbaird) — the app holzIce is built on. If you like it, consider [sponsoring Jordan](https://github.com/sponsors/jordanbaird).
- [**RabenkoYevhenii**](https://github.com/RabenkoYevhenii) — the macOS 27 backend ([jordanbaird/Ice#995](https://github.com/jordanbaird/Ice/pull/995)).

## 📄 License

holzIce is available under the [GPL-3.0 license](LICENSE), like Ice.
