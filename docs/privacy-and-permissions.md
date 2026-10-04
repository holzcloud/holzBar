# Privacy and permissions

## Principles

Every change to holzBar follows four rules — without taking a feature away:

- **Modern** — written the way a macOS app is written in 2026: current Swift, Swift concurrency and current SwiftUI and AppKit APIs. Outdated APIs are replaced as the code is touched.
- **Lean and fast** — as little CPU, energy, memory and disk as possible; no polling where macOS sends an event; a small app that launches fast.
- **Private** — holzBar never connects to the network: no telemetry, no analytics, no crash reports, no update checks, no remote content. The only exception is a link you click, which opens in your browser. Your data stays on your Mac and out of the logs. To show hidden items when the network drops, holzBar only watches whether a network path is available (Apple's NWPathMonitor); it never opens a connection. The `no-network` check fails every pull request that adds networking code or a third-party package, and every build checks the app's binaries and entitlements for network access.
- **Least privilege** — holzBar asks only for the permissions a feature really needs, when it needs them, and says why.

Where holzBar doesn't meet a rule yet, that is a bug to fix.

## Permissions

Everything holzBar asks macOS for, the feature that needs it and when it is asked:

| Permission or entitlement | Needed for | When |
|---|---|---|
| **Accessibility** <sub>required</sub> | Reading where menu bar items are; moving, showing and clicking them for you; noticing clicks, scrolls and hovers in the menu bar for show on click, scroll and hover | Asked on the first launch |
| **Screen Recording** <sub>optional</sub> | Pictures of menu bar items in the holzBar Shelf, the search and the Menu Bar Layout pane (on macOS 27 taken once per item), and a moving wallpaper beside a menu bar shape (before macOS 27; other wallpapers are read from their file) | Asked the first time you open the holzBar Shelf, the search or the Menu Bar Layout pane, or choose a menu bar shape with a moving wallpaper — never at launch. Without it, everything else works, the holzBar Shelf and the search show app icons, and nothing captures the screen |
| **Login item** | Starting holzBar when you log in | Only when you turn on "Launch at login" |
| **A folder you choose** | Settings sync between your Macs (`holzBar/Settings.plist` in iCloud Drive or any folder your Macs sync, such as Nextcloud, Dropbox, OneDrive, Syncthing or a network share), read and written with file coordination; holzBar keeps a bookmark of the folder, the folder's own app does the syncing | Only while settings sync is on; with sync off, holzBar neither watches the folder nor writes to it |
| **Entitlements** | None. holzBar runs without the App Sandbox, because Accessibility event taps and the menu bar's private WindowServer calls do not work in it, and it has no network entitlement | — |
| **Info.plist usage strings** | None: macOS does not use them for Accessibility and Screen Recording | — |
| **Reset and Grant Again** | Runs `tccutil reset` for holzBar's own entry only, when a stale permission keeps the permissions window open | Only when you click it |

<p align="center"><img src="../Resources/Screenshots/settings-layout-screen-recording.png" alt="holzBar settings, Menu Bar Layout pane without Screen Recording: it explains that the pane shows pictures of the menu bar items, which macOS lets an app take only with Screen Recording, with an Allow Screen Recording… button" width="560"><br><sub>Screen Recording is asked only when a feature needs it, and holzBar says why.</sub></p>

> [!WARNING]
> **macOS 27: the camera, microphone and screen recording indicator.** While holzBar hides menu bar items on macOS 27, Control Centre does not show its privacy indicator — green for the camera, orange for the microphone, indigo for screen sharing or recording. The small green dot beside the clock still appears while the camera is on. The indicator comes back while holzBar hides no item. holzBar needs no permission for this and cannot prevent it: macOS removes the indicator whenever an app hides items the way holzBar must on macOS 27. **Settings → General** says so too.
