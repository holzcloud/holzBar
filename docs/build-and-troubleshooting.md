# Build and troubleshooting

## Troubleshooting

**"holzBar cannot arrange menu bar items in automatically hidden menu bars."** holzBar can only arrange the items while the menu bar stays visible. Open **System Settings → Control Center**, set **Automatically hide and show the menu bar** to **Never**, arrange your items in holzBar, then set the option back to what you had.

**New items end up in the always-hidden section.** macOS puts new menu bar items at the far left of the bar, which is where the always-hidden section is. Choose where they go in **Settings → Advanced → Place new menu bar items in**.

**holzBar is stuck on the permissions window.** After an update from 0.0.5 or earlier, or after replacing the app with a build signed by another key, macOS may no longer accept the old permission. Click **Reset and Grant Again** in the permissions window and grant the permission once more.

**An item is listed as "Menu Bar Item" (macOS 26).** On macOS 26 every item window belongs to Control Center, so holzBar asks the running apps, off the main thread and with time limits, which item is theirs. An app that does not answer in time is asked again at a later read. Apps signed by Apple are asked first, and the first of them to claim an item gets it. An item that two other apps claim stays "Menu Bar Item", and holzBar never moves it by itself.

**"The sync folder cannot be found."** If the sync folder is on a network share, holzBar uses it only while the share is mounted and never mounts it itself. Mount the share (for example in the Finder) and syncing picks up again by itself; otherwise click **Change…** and choose the folder again. In 0.0.7-beta2 settings sync is paused, so this message does not appear and **Change…** is greyed out; see [Settings sync](features.md#settings-sync).

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

`Scripts/install.sh` builds without the `get-task-allow` entitlement Xcode adds for debugging and installs nothing that fails `Scripts/check-signature.sh`, the check CI and the release run too: the app must carry the hardened runtime and no entitlement, and `Contents/MacOS/holzBar` must be its only code. holzBar ships no XPC service, helper or other nested code; on macOS 26 it looks up each item's app itself.

Two hidden defaults show how holzBar recovers before macOS 27: `DebugDropsBarrierExitEvent` loses the whole round trip of every item move and click, so no event reaches the item and holzBar gives up after about two seconds; `DebugHangsItemImageCapture` makes every item image capture hang, so each is given up after two seconds and capture stops after three until holzBar is relaunched. Turn one on with `defaults write com.holzcloud.holzBar <name> -bool true` and off with `defaults delete com.holzcloud.holzBar <name>`.
