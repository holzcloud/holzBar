# Build and troubleshooting

## Troubleshooting

**"holzBar cannot arrange menu bar items in automatically hidden menu bars."** holzBar can only arrange the items while the menu bar stays visible. Open **System Settings → Control Center**, set **Automatically hide and show the menu bar** to **Never**, arrange your items in holzBar, then set the option back to what you had.

**New items end up in the always-hidden section.** macOS puts new menu bar items at the far left of the bar, which is where the always-hidden section is. Choose where they go in **Settings → Advanced → Place new menu bar items in**.

**holzBar is stuck on the permissions window.** After an update from 0.0.5 or earlier, or after replacing the app with a build signed by another key, macOS may no longer accept the old permission. Click **Reset and Grant Again** in the permissions window and grant the permission once more.

## Build from source

Use Xcode 27 (macOS 27 SDK), as CI does; holzBar itself runs on macOS 14 or later. Every pull request launches the built app on macOS 14, 15, 26 and 27 and runs the unit tests on each, so a missing symbol or a crash at launch on an older macOS fails the build. CI builds with Xcode 27.0 for the SDK and the official Swift 6.4 toolchain from [swift.org](https://www.swift.org/install/macos/) as the compiler (both pinned in `.github/actions/select-xcode`).

```sh
git clone https://github.com/holzcloud/holzBar
cd holzBar
Scripts/install.sh            # installs to ~/Applications
```

`Scripts/install.sh` builds with Xcode's own Swift. To build with Swift 6.4 like CI (optional), install `swift-6.4.0-RELEASE-osx.pkg` from swift.org for your user only, then select it with `TOOLCHAINS`:

```sh
installer -pkg swift-6.4.0-RELEASE-osx.pkg -target CurrentUserHomeDirectory
TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw -o - \
  ~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/Info.plist) Scripts/install.sh
```
