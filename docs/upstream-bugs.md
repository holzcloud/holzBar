# Upstream bug reports

In October 2026, [Ice](https://github.com/jordanbaird/Ice) had 282 open bug reports. This page groups them and records where each group stands in holzBar. Reports were read through their issue pages; most have no logs, so groups marked **open** need someone to reproduce them on a Mac.

Issue numbers below refer to [jordanbaird/Ice](https://github.com/jordanbaird/Ice/issues).

## Fixed in holzBar

| Group | Issues | Fix |
|---|---|---|
| macOS 27: nothing hides, "Loading menu bar items", layout editor spins | #954, #965, #970, #991, #992, #996, #999, #1003, #1006 | macOS 27 backend from [#995](https://github.com/jordanbaird/Ice/pull/995) |
| Stuck on the permissions window although permissions are granted | #1004, #834 | "Reset and Grant Again" in the permissions window; `Scripts/install.sh` resets them for ad hoc builds |
| Crash on clicking the icon or with the Ice Bar on macOS 26 (`EXC_BREAKPOINT`, `NSStatusBarWindow.windowNumber`) | #786, #796, #810, #821, #855, #867, #880, #905, #925, #947, #977, #779, #742, #669 | The `macos-26` base no longer casts window numbers with `CGWindowID(_:)`; see also [#989](https://github.com/jordanbaird/Ice/pull/989) |
| "Check for updates automatically?" dialog that cannot be closed | #681, #688, #699, #837, #882, #912, #926, #931, #932, #937, #957, #969 | Sparkle is not started; holzBar updates through Homebrew |
| Outdated Sparkle | #785 | Sparkle is removed |
| Main thread hangs in screen capture | #777 | Captures run on their own queue (`macos-26` base) |
| Ice Bar images too small or too large on another display | #825, #829, #929, #955, #987 | Scale derived from the capture (#995) |
| Show on scroll ignores a mouse wheel | #717 | Wheel deltas are scaled from lines to points |
| Hidden section's divider gone after Command-dragging it out | #619 | The divider is put back |
| "Hide application menus" only works with the always-hidden section on | #434, #620, #879 | Shown hidden items are no longer dropped from the check |
| Menu bar behaviour on displays without a menu bar ("Displays have separate Spaces" off) | #383, #456, #646 | Only the primary display counts as having a menu bar |
| Layout editor or Ice Bar stuck on "Loading menu bar items…" on macOS 26 | #687, #710, #711, #677, #679, #762 and others | The menu bar item service failed to start (`XPCRichError` code 1, seen on 26.7.1). holzBar recognises its own dividers directly and looks up the other items in the app when the service fails; the service also accepts holzBar's own ad hoc builds, which have no team identifier, by requiring the exact code of the app it is embedded in (signing identifier and code directory hashes) |

## Open

| Group | Issues | Notes |
|---|---|---|
| Layout editor or Ice Bar empty/white on macOS 26 ("Unable to display menu bar items") | #635, #664, #673, #677, #679, #682, #685, #687, #696, #710, #711, #716, #730, #741, #743, #744, #753, #758, #762, #773, #818, #833, #846, #891, #913, #916, #921, #973 | Item discovery or capture fails; #710 says 0.11.13-dev.1 mostly worked. Needs logs from an affected Mac |
| Items lose their section after a restart, an app update or a width change | #661, #666, #675, #702, #723, #732, #748, #769, #771, #806, #844, #853, #887, #909 | Item identity is not stable across launches |
| Several items of one app (OneDrive, …) are mixed up | #300, #404, #739, #857 | Same root as above |
| Moving an item times out (Live Activities, iPhone items) | #656, #704, #729, #746, #861, #918 | |
| Pointer gone or stuck after clicking an item in the Ice Bar | #640, #751, #757 | Hide and show calls are balanced; may be the enlarged accessibility pointer (#757) |
| Auto-rehide fires while a menu is open or a control is in use | #403, #452, #526, #621, #914 | |
| Bar, tint or shape drawn in the wrong place (middle of the screen, rotated or secondary displays, fullscreen) | #445, #517, #550, #609, #750, #780, #858, #863, #986 | |
| Split shape on ultrawide and external displays | #94, #529, #573, #608 | |
| Styling lost after sleep or launch at login | #53, #409, #525 | Appearance is not re-applied |
| Volume and brightness HUD hidden with its item on macOS 26 | #701, #719 | macOS attaches the HUD to the item; may be unfixable |
| High CPU, energy or memory | #334, #479, #530, #578, #819 | holzBar keeps one hover task instead of one per mouse move, stops permission polling once granted and reacts to power events instead of a 60 s timer; needs profiling on an affected Mac |
| Dock icon appears while showing items | #397, #590, #768, #808, #906 | Activation policy switching |

Not bugs, or not in the app: #745 (thanks), #752, #774, #935 (website), #939 (project status), #966 (another fork).
