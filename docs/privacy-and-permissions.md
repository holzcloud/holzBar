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
| **Accessibility** <sub>required</sub> | Reading where menu bar items are; moving, showing and clicking them for you; noticing clicks, scrolls and hovers in the menu bar for show on click, scroll and hover; on macOS 27, an Escape key press sent to Notification Center or Control Centre to close a panel holzBar opened | Asked on the first launch |
| **Screen Recording** <sub>optional</sub> | Pictures of menu bar items in the holzBar Shelf, the search and the Menu Bar Layout pane (on macOS 27 taken once per item), and a moving wallpaper beside a menu bar shape (before macOS 27; other wallpapers are read from their file) | Asked the first time you open the holzBar Shelf, the search or the Menu Bar Layout pane, or choose a menu bar shape with a moving wallpaper — never at launch. Without it, everything else works, the holzBar Shelf and the search show app icons, and nothing captures the screen |
| **Login item** | Starting holzBar when you log in | Only when you turn on "Launch at login" |
| **Microphone and camera use** <sub>macOS 27, no permission</sub> | The dot on holzBar's icon while another app uses the microphone or a camera. holzBar reads only whether a process records audio (Core Audio) and whether a camera is running (CoreMediaIO), on a background queue; it opens no audio or video, and records and stores nothing | Only while "Show a dot on the holzBar icon…" is on (Settings → General, on by default) |
| **Entitlements** | None, not even `get-task-allow`, which would let a debugger attach. holzBar runs without the App Sandbox, because Accessibility event taps and the menu bar's private WindowServer calls do not work in it, and it has no network entitlement | — |
| **Location Services** <sub>Preview</sub> | Only for the automation condition "Wi-Fi network named …": since macOS 14 the system gives the network name only to apps that may use Location Services. holzBar reads that name and requests no location updates, and stores no location. Without it the condition is never true | Only when you add that condition: holzBar explains why first, then macOS asks |
| **Info.plist usage strings** | The one for Location Services above. Accessibility and Screen Recording need none | — |
| **Reset and Grant Again** | Runs `tccutil reset` for holzBar's own entry only, when a stale permission keeps the permissions window open | Only when you click it |

holzBar is a single executable with no helper process or other nested code, so nothing else runs with these permissions. Accessibility calls into other apps, such as finding the app behind each menu bar item on macOS 26 and registering the observers that notice new and changed items, run off the main thread with time limits, so a slow app does not stall holzBar or your clicks.

Without any permission, holzBar also reads, on your Mac only:

- **Code signatures of running apps** (macOS 26), to tell macOS's own processes from other apps when it works out which app a menu bar item belongs to.

<p align="center"><img src="../Resources/Screenshots/settings-layout-screen-recording.png" alt="holzBar settings, Menu Bar Layout pane without Screen Recording: it explains that the pane shows pictures of the menu bar items, which macOS lets an app take only with Screen Recording, with an Allow Screen Recording… button" width="560"><br><sub>Screen Recording is asked only when a feature needs it, and holzBar says why.</sub></p>

> [!WARNING]
> **macOS 27: the camera, microphone and screen recording indicator.** While holzBar hides menu bar items on macOS 27, Control Centre does not show its privacy indicator — green for the camera, orange for the microphone, indigo for screen sharing or recording. The small green dot beside the clock still appears while the camera is on. The indicator comes back while holzBar hides no item. holzBar cannot prevent this: macOS removes the indicator whenever an app hides items the way holzBar must on macOS 27. Instead, holzBar puts a dot on its own icon while it hides items and another app uses the microphone (orange) or a camera (green), and shows its icon for that even when "Show holzBar icon" is off. Screen recording is not covered: no public API reports it. The setting is in **Settings → General**, on by default, and needs no permission.
