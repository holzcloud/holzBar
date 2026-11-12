# Build and troubleshooting

## Install, update and switch channel

Both Homebrew channels come from the same tap and install the same `holzBar.app`, so they conflict. `brew trust` is needed once per cask, because Homebrew only installs casks from third-party taps that you have trusted. Quit Ice, Thaw, Bartender or Hidden Bar first; your Ice settings are imported on the first launch.

**Update:** `brew update && brew upgrade --cask holzbar` (or `holzbar@beta`). Without `brew update` Homebrew may not have fetched the tap yet. Coming from 0.0.5? It was a different app and cask; the [0.0.6 release notes](release-notes/v0.0.6.md) list the steps.

**Switch channel:** uninstall one cask and install the other; your settings stay.

```sh
brew uninstall --cask holzbar
brew trust --cask holzcloud/holzbar/holzbar@beta
brew install --cask holzcloud/holzbar/holzbar@beta
```

The other way round: `brew uninstall --cask holzbar@beta`, then trust and install `holzcloud/holzbar/holzbar`.

**If macOS says holzBar "can't be opened":** `xattr -dr com.apple.quarantine /Applications/holzBar.app`, then open it again. The release is signed with holzBar's own certificate (SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`) rather than a Developer ID.

## Troubleshooting

**"The menu bar hides automatically."** holzBar can only arrange the items, and change the look of the bar, while the menu bar stays visible; Layout and Appearance then show this one sentence with **Open System Settings**. Open **System Settings → Control Center**, set **Automatically hide and show the menu bar** to **Never**, arrange your items in holzBar, then set the option back to what you had.

**New items end up in the always-hidden section.** macOS puts new menu bar items at the far left of the bar, which is where the always-hidden section is. Choose where they go in **Settings → Layout → New items go to**.

**holzBar is stuck on the permissions window.** After an update from 0.0.5 or earlier, or after replacing the app with a build signed by another key, macOS may no longer accept the old permission. Click **Reset and Grant Again** under the permission in the permissions window (it shows while the permission is missing) and grant the permission once more.

**Layout says "holzBar has not read the menu bar items yet."** Reading them takes a few seconds; after 15 seconds holzBar stops waiting and offers **Read Again**. If that does not help, quit and reopen holzBar.

**A layout change went wrong.** Every change of the layout can be taken back: **Undo** in the notice that shows for five seconds, **Undo** in Layout, or ⌘Z in the Settings window (the last 20 changes, until holzBar quits).

**An item is listed as "Menu Bar Item" (macOS 26).** On macOS 26 every item window belongs to Control Center, so holzBar asks the running apps, off the main thread and with time limits, which item is theirs. An app that does not answer in time is asked again at a later read. Apps signed by Apple are asked first, and the first of them to claim an item gets it. An item that two other apps claim stays "Menu Bar Item", and holzBar never moves it by itself.

## Build from source

Use Xcode 27 (macOS 27 SDK), as CI does; holzBar itself runs on macOS 14 or later. Every pull request that changes code launches the built app on macOS 26 and 27 and runs the unit tests there, so a crash at launch fails the build. Older macOS versions (14 and 15) are supported; CI runs macOS 26 and 27. CI builds with Xcode 27.1 for the SDK and the official Swift 6.4 toolchain from [swift.org](https://www.swift.org/install/macos/) as the compiler (both pinned in `.github/actions/select-xcode`).

```sh
git clone https://github.com/holzcloud/holzBar
cd holzBar
Scripts/install.sh            # installs to ~/Applications
```

`Scripts/install.sh` builds with Xcode's own Swift. To build with Swift 6.4 like CI (optional), install `swift-6.4.2-RELEASE-osx.pkg` from swift.org for your user only, then select it with `TOOLCHAINS`:

```sh
installer -pkg swift-6.4.2-RELEASE-osx.pkg -target CurrentUserHomeDirectory
TOOLCHAINS=$(plutil -extract CFBundleIdentifier raw -o - \
  ~/Library/Developer/Toolchains/swift-6.4.2-RELEASE.xctoolchain/Info.plist) Scripts/install.sh
```

`Scripts/install.sh` builds without the `get-task-allow` entitlement Xcode adds for debugging and installs nothing that fails `Scripts/check-signature.sh`, the check CI and the release run too: the app must carry the hardened runtime and no entitlement but `com.apple.security.personal-information.calendars` (Calendar access of the notch hub), and `Contents/MacOS/holzBar` must be its only code besides `Contents/Frameworks/NowPlayingRemote.framework`, the library of the optional Read all apps, which the same Xcode build produces and embeds. holzBar ships no XPC service or helper app; on macOS 26 it looks up each item's app itself.

If Read all apps in the Now Playing module says "Read all apps is not available on this Mac", macOS may have changed the private interface it uses; the Music and Spotify sources keep working.

Two hidden defaults show how holzBar recovers before macOS 27: `DebugDropsBarrierExitEvent` loses the whole round trip of every item move and click, so no event reaches the item and holzBar gives up after about two seconds; `DebugHangsItemImageCapture` makes every item image capture hang, so each is given up after two seconds and capture stops after three until holzBar is relaunched. Turn one on with `defaults write com.holzcloud.holzBar <name> -bool true` and off with `defaults delete com.holzcloud.holzBar <name>`.
