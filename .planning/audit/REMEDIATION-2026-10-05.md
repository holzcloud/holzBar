<!-- generated-by: gsd-doc-writer -->
# holzBar audit remediation (2026-10-05)

## Scope

- **Audit:** [FULL-AUDIT-2026-10-05.md](FULL-AUDIT-2026-10-05.md), 112 findings: 3 high, 38 medium, 71 low, no critical; 66 auto-fixable, 46 manual-only.
- **Branch:** `audit/remediation-2026-10-05`, on top of `origin/main` (0.0.7-beta1 and its cask). The commit hashes below come from `git log --format="%h %s" origin/main..HEAD`.
- **Plans and summaries** of the manual chains (sync-alerts, xpc, events, ax-observers, mac27, appearance, release): [remediation/](remediation/).

## Result

- **Fixed: 93. Partly fixed: 1 (F-10). Open: 18.**
- The remediation fixed 92: the 66 auto-fixable findings, and 26 manual-only findings after the maintainer's 16 decisions (F-10 only partly). F-111 and F-112 were fixed along the way by the release chain ([below](#f-111-and-f-112-fixed-by-the-release-chain)).
- Every high and medium finding is fixed, F-10 partly. All 18 open findings are low and manual-only.
- What changed most:
  - The embedded XPC service `MenuBarItemService` is removed. holzBar ships a single executable with no nested code; on macOS 26 the source-PID lookup runs in the app, on a background queue, with time limits. `Scripts/check-signature.sh` (CI, release, `install.sh`) fails on any other Mach-O file.
  - Release builds no longer carry `com.apple.security.get-task-allow`; the published 0.0.7-beta1 did.
  - Releases run only for a `v*` tag on `main`, in separate jobs. They are signed with holzBar's own certificate, SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95` (unchanged, so permissions survive the update); the release fails without the signing secrets or with any other certificate.
  - Releases carry SLSA Build Level 3 provenance (slsa-github-generator) next to GitHub's artifact attestation.
  - OpenSSF Scorecard, CodeQL (weekly) and Dependabot for actions; every action is pinned by commit SHA, checked by `.github/scripts/workflow-check.py` and actionlint.
- **Repository settings:** secret scanning with push protection and private vulnerability reporting are on. The environment `release` (only `v*` tags) holds `CASK_DEPLOY_KEY`, the deploy key the cask job pushes with. After the merge, `main` requires pull requests with green checks, and a ruleset protects `v*` tags.

## Findings

Route: **auto** = auto-fixable, fixed by the automatic pipeline; **decision: \<cluster\>** = manual-only, fixed after the maintainer's decision ([below](#the-maintainers-16-decisions)); **manual-only** = not addressed. Commits are those whose subject names the finding (also as `F08-…`, `F26-…`, `F39-…`), or whose body does when the subject names none, oldest first.

| ID | Severity | Title | Status | Route | Commits | Note |
|---|---|---|---|---|---|---|
| F-01 | high | Timeouts never fire: a lost event round trip hangs every move and click (pointer hidden, input monitors off), and the Shelf's wait is unbounded | fixed | decision: event-timeouts | f14aed13, e8eff47e |  |
| F-02 | high | Settings sync overwrites other Macs' settings: push() never reads or compares the file (turning sync on, every launch, after "Later") | fixed | decision: sync | f2f8b9cc |  |
| F-03 | high | Applying a layout profile on macOS 27 replaces the whole saved layout, wiping it for profiles saved before macOS 27 | fixed | auto | 9e633177, 04e29a11, 5ae56d1c |  |
| F-04 | medium | macOS 26: the embedded XPC service runs with holzBar's TCC grants and is never checked, so swapping it hands those grants to other code | fixed | decision: xpc-trust | 8ea35478 |  |
| F-05 | medium | Release and install builds carry get-task-allow on the app and the XPC service, so a debugger can inject code that runs with holzBar's grants | fixed | decision: release | 108452a3, de59fe70, 5b2e1db2, f2117f4a |  |
| F-06 | medium | macOS 26: any app's Accessibility frames can claim a Control Center item window, making the camera and microphone indicator hideable | fixed | decision: indicators | a34ce29c, bc8a9e48 |  |
| F-07 | medium | holzbar://search and holzbar://settings bypass Zen mode and show hidden items during screen sharing (on macOS 27 also in the real menu bar) | fixed | auto | 44efea38 |  |
| F-08 | medium | macOS 27: while holzBar conceals items, Control Centre's microphone, camera and screen-recording indicator is suppressed, and nothing compensates | fixed | decision: indicators | 9c5a9098, a7590c75, e39b3d3f, 9224262a, 7bd3fc27 |  |
| F-09 | medium | The Shelf colour manager captures the screen on macOS 27 and while the Shelf is hidden | fixed | auto | 19de6e5e |  |
| F-10 | medium | The signing key and the signed-release pipeline can be reached from any branch or tag (repository-level secrets, no environment, no tag or branch protection) | partly fixed | decision: release | dc62108a, 092a1a3d, f2117f4a, 613ef3dd, c8bf65e5 | Deferred: the signing secrets stay repository secrets until the beta after 0.0.7-beta2 (see below). |
| F-11 | medium | Missing signing secrets fail open (an ad hoc release reaches every cask user), and the certificate fingerprint is never pinned | fixed | decision: release | f2117f4a |  |
| F-12 | medium | macOS 26 local fallback: the main-thread running-apps observer blocks on the lookup lock while a scan waits for holzBar's own Accessibility replies | fixed | decision: xpc-trust | 8ea35478 |  |
| F-13 | medium | One stuck window capture wedges the serial capture queue for the session: images stop updating and search and Shelf stop opening | fixed | decision: capture-queue | 84de2f53, d6291797 |  |
| F-14 | medium | NSAlert.runModal() inside main-actor Tasks blocks all main-actor work while the alert is open (macOS 27 system-item clicks are swallowed) | fixed | decision: modal-alerts | 570b6e5e, b595e8c1 |  |
| F-15 | medium | Settings sync does coordinated file I/O on the main thread, so a dataless file, a hung file provider or a stalled volume blocks launch and the UI | fixed | decision: sync | f2f8b9cc |  |
| F-16 | medium | Accessibility observer registration runs on the main thread with no messaging timeout, stalling holzBar and, on macOS 27, every click | fixed | decision: ax-observers | 3834cb6a |  |
| F-17 | medium | Launches and quits of menu bar agents go unnoticed: automatic Zen misses Screen Sharing, and macOS 27 concealment keeps newly launched Visible agents hidden | fixed | decision: agent-launches | 3a0c23be |  |
| F-18 | medium | The sync-folder bookmark is resolved without .withoutMounting on every access, so holzBar mounts network shares itself and blocks while the mount times out | fixed | auto | 2eabb385, c31dfd88, 22aebd79, 3e6935c2 |  |
| F-19 | medium | CGSSpaceGetType is declared with a Swift enum return type, so fullscreen spaces are never detected on macOS 26 and 27 | fixed | auto | cd3df1db |  |
| F-20 | medium | Smart rehide (the default) never fires without Screen Recording, because it only considers windows that have a title | fixed | auto | 11927c0b, 48c4cfa0 |  |
| F-21 | medium | With Caps Lock on, every item move and click on macOS 26 waits indefinitely and replays later | fixed | auto | 32065b86, f4cc7583, 54237c97, 4e62a66b |  |
| F-22 | medium | Rehiding a temporarily shown item targets a stored neighbour snapshot; if that window is gone, rehide fails forever and keeps tripping MoveBackoff | fixed | auto | c62d918e, 2b973387, af8eafcb |  |
| F-23 | medium | Stored identity keys of the second and later untitled items of an app never match their current key | fixed | auto | 279b0248, 9448b6f8 |  |
| F-24 | medium | Stale saved-section keys are never pruned and collide with current keys, so restore can move items back into old sections | fixed | auto | 9df196f2 |  |
| F-25 | medium | A pending profile reconciliation is replaced by a later restore request, so the profile is silently not applied | fixed | auto | cc250fc3 |  |
| F-26 | medium | macOS 27 click bridge: stale panel state plus banner windows make a clock click post a synthetic Escape and swallow the click | fixed | decision: mac27-clicks | b8e10631, e346da40, f47c57f4 |  |
| F-27 | medium | macOS 27: clicks and photos of a temporarily shown app use fixed sleeps and stale Accessibility frames, so they can hit another item | fixed | decision: mac27-clicks | 4dddd7c5 |  |
| F-28 | medium | macOS 27: Visible apps concealed for the notch stay concealed after the reveal that crowded the bar ends | fixed | auto | 02678651, 19da231c |  |
| F-29 | medium | A hotkey stays unregistered when its recorder disappears while recording | fixed | auto | 5e87caca |  |
| F-30 | medium | A combination another holzBar hotkey already uses is saved but never registered, and the row then offers no way to clear it | fixed | decision: hotkey-conflicts | a10fbdce |  |
| F-31 | medium | Backspace or Escape anywhere in holzBar deletes or deselects the selected gradient stop and is swallowed | fixed | auto | cc497ae0, 08232feb, 7e7ed6bf |  |
| F-32 | medium | Menu Bar Layout pane: the source row of a drag stops updating after a drop into another row or a cancelled drag | fixed | auto | 45d246c4 |  |
| F-33 | medium | Keyboard and VoiceOver moves in the Layout pane lose focus after one step | fixed | auto | b5d2c68e |  |
| F-34 | medium | The "Focused app" rehide strategy fires even when "Automatically rehide" is off | fixed | auto | af525bae, 7dedb949 |  |
| F-35 | medium | The Shelf jumps after it opens, because every resize recomputes its position from the current mouse location | fixed | auto | 2546ae7c |  |
| F-36 | medium | Opening a hidden item without showing it treats a menu-opening AXPress as a failure and clicks the item again | fixed | decision: axpress | 914ee0d4, 0aeafbf4 |  |
| F-37 | medium | macOS 26 source-PID lookups have no overall time limit, so one slow app stalls every item read | fixed | decision: xpc-trust | 62dd5816 |  |
| F-38 | medium | The sync device ID lives in the preferences file, so Macs set up by Migration Assistant, restore or clone ignore each other's changes | fixed | decision: sync | ec55d265 |  |
| F-39 | medium | The Split menu bar shape always degrades to the full shape on macOS 27 | fixed | decision: split-shape | 6645b8e0, 768f40f0, 25a1a938, bdaa6ab4, cdab120b, 3102c6fc, 5e8cb6f0, f1117f9f, 8d1d0df4 |  |
| F-40 | medium | install.sh skips the TCC reset for ad hoc builds most of the time (SIGPIPE under pipefail) | fixed | auto | fc73e170 |  |
| F-41 | medium | verify-layout.sh restores MacOS27Layout with string values, wiping the real macOS 27 layout while printing PASS | fixed | auto | 17586778, eb366154 |  |
| F-42 | low | Any app can crash holzBar on macOS 27 by reporting a non-finite or huge Accessibility frame | fixed | auto | d13ef9f7, 69b8d0b8 |  |
| F-43 | low | Any local process can freeze concealment, Zen mode and item placement with a spoofed com.apple.screenIsLocked notification | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-44 | low | macOS 26: a process named like holzBar or Control Center gets their item tags, and a fake divider becomes the section divider | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-45 | low | macOS 27: a second process with bundle ID com.apple.MenuBarAgent overwrites the system-item frames the click bridge uses | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-46 | low | macOS 27: a spoofed theme-change notification discards all item images and resets the photo schedule, so concealed apps flash into the bar | fixed | auto | 6d0bcbe5, a95eef60 |  |
| F-47 | low | Item groups read from settings are not capped; a crafted import or sync file floods the menu bar with status items | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-48 | low | The app never verifies the XPC service's code, and the comment's reasons for skipping it are wrong | fixed | decision: xpc-trust | 8ea35478 |  |
| F-49 | low | docs/signing.md and SECURITY.md (T-06-M4) present the trojanized-app threat as mitigated, but a swapped nested service keeps the grants | fixed | decision: xpc-trust | — | Code side: the XPC service is gone (8ea35478). docs/signing.md and SECURITY.md are corrected in this branch's documentation update. |
| F-50 | low | The 0.0.6 release notes verify the certificate SHA-256 with a command that never prints it | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-51 | low | macOS 27: the menu bar capture does not check that the bar is on screen, so fragments of the window underneath become item icons | fixed | auto | ebfffd02, 241a4d0d |  |
| F-52 | low | An unpinned, unsandboxed SwiftLint build phase runs in every build, including the release job with contents:write and id-token:write | fixed | decision: release | 1694b9d6, f2117f4a, c9bd6213 |  |
| F-53 | low | The documented `gh attestation verify -R holzcloud/holzBar` accepts an attestation from any workflow on any ref | fixed | decision: release | f2117f4a, c8bf65e5 |  |
| F-54 | low | The "no Swift packages" CI gate is bypassed by omitting Package.resolved; project.pbxproj package references are never checked | fixed | auto | 6b1176fc, 04596d0f |  |
| F-55 | low | Debouncer runs a superseded or cancelled action when its sleep had already finished | fixed | auto | 1d7934e4 |  |
| F-56 | low | A superseded item-cache refresh keeps running after cancellation and can overwrite the newer result | fixed | auto | 7f4426c6, 11208e46 |  |
| F-57 | low | macOS 27 item scan sets a short messaging timeout only on the application element; per-item reads wait up to 6 s | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-58 | low | macOS 27: image-store deletes and writes run in unordered detached tasks, so old-appearance glyphs can survive a theme switch | fixed | auto | 786dc6d9 |  |
| F-59 | low | One bad entry in a dictionary- or JSON-valued setting empties the whole setting, and the next save writes the loss back | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-60 | low | Applying synced settings deletes local keys the sending Mac never had, wiping the per-OS layout between macOS 26 and 27 Macs | fixed | decision: sync | 88921465 |  |
| F-61 | low | A custom icon of a few hundred KB pushes the sync file over the 1 MiB read limit, and other Macs silently ignore all synced settings | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-62 | low | A stored custom icon that ImageIO refuses leaves holzBar's own menu bar icon blank, with no fallback | fixed | auto | 1622fecf |  |
| F-63 | low | An unknown shape kind, end cap or black-background value fails the whole appearance decode, and the next edit overwrites it | fixed | auto | f65e7bfc |  |
| F-64 | low | New items are marked known before they are placed, so a failed or paused placement is never retried | fixed | auto | 061e3a97, fb8cff2a |  |
| F-65 | low | "Keep Live Activities visible" and the new-items placement fight over the same item in every reconciliation | fixed | auto | e42b4da9 |  |
| F-66 | low | A running restore keeps moving items after the user starts dragging, and the reverted arrangement is saved | fixed | auto | 109649e0, 864d9579 |  |
| F-67 | low | Position-based identity keys swap between items of one app, so restore can put each item in the other's section | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-68 | low | On macOS 27 identity keys are never disambiguated, so all items of a learned title-changing app share one key | fixed | auto | efd0ef69 |  |
| F-69 | low | Learned title-changing owners are never unlearned and can be poisoned by a process presenting another app's namespace | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-70 | low | Any app keeps its item out of the hidden section by putting "LiveActivit" in its title | fixed | auto | 483bf4d4 |  |
| F-71 | low | "Show When It Changes" never starts watching an item whose Accessibility element was not found the first time | fixed | auto, then ax-observers | d4f1cd05, bd9471da, 3834cb6a |  |
| F-72 | low | The negative lookup cache stores lookups that never scanned for 30 s, giving new items a temporary UUID namespace | fixed | auto | 4466fcf2 |  |
| F-73 | low | macOS 27: continuous AX created/destroyed notifications from one owner keep postponing item-list refreshes, including the 60 s fallback | fixed | auto | 3b1293c3 |  |
| F-74 | low | macOS 27: the theme observer is not installed when the image store's version check fails, so theme switches keep old glyphs | fixed | auto | 77da3ee6, a95eef60 |  |
| F-75 | low | macOS 27: item images keyed by identifiers other apps choose are never pruned | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-76 | low | macOS 27: system items on the inactive display are guessed with a "widest frame over 80 pt is the clock" rule that misfires | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-77 | low | macOS 27: a failed concealment apply leaves holzBar claiming concealment, with no retry | fixed | auto | 0ea4b9a8, ea01023d |  |
| F-78 | low | macOS 27: an earlier suspension timer ends a later, longer suspension early | fixed | auto | 95fa7a10, b77a6ed8 |  |
| F-79 | low | macOS 27: a drag within one row shows an order macOS does not keep and registers a no-op undo | fixed | auto | 3d77ff6d |  |
| F-80 | low | holzBar's own activation (to hide application menus) counts as a focus change and rehides the section it just showed | fixed | auto | 2d1f3763, 7dedb949 |  |
| F-81 | low | Application menus can be hidden after the section was already hidden again (stale async result) | fixed | auto | b4fe174d, 1b490f16 |  |
| F-82 | low | Opening Settings or closing its window while application menus are hidden leaves the hiding flag stale | fixed | auto | 602fd9a5 |  |
| F-83 | low | Closing the Shelf while it waits for the cache leaves it on screen with no section, and Escape does not close it | fixed | auto | b6b6e371, 1b427190 |  |
| F-84 | low | The search panel still opens after it was closed while waiting for the image cache | fixed | auto | 997f0200, b2b31185 |  |
| F-85 | low | "Show the hidden section for a moment" hides early on repeated presses and overrides a later manual show | fixed | auto | eec8c07c, 3069191c |  |
| F-86 | low | With Caps Lock on, Option-click and Control-click on the holzBar icon and on empty menu bar space do the wrong thing | fixed | auto | 8a510c85 |  |
| F-87 | low | Section dividers keep the drag marker and 3 pt width after a Command-drag ends | fixed | auto | af93a974 |  |
| F-88 | low | NSScreen.screenWithMouse returns nil at the top pixel row, so hit tests can use the wrong display | fixed | auto | d37cb2cf |  |
| F-89 | low | Permissions are never re-checked after setup: a revoked Accessibility still shows "Permission Granted" | fixed | auto | 751d4ae5 |  |
| F-90 | low | On macOS 26 the Layout pane checks Control Center's responsiveness instead of the item's own app | fixed | auto | 71aea0ea |  |
| F-91 | low | With a dynamic appearance, overlay panels exist only for the current mode, so the other mode's style and Hold to Preview never show | fixed | auto | 0488f31b |  |
| F-92 | low | The System Glass view is not added or removed when light/dark mode switches under a dynamic appearance | fixed | auto | 32d60b8d |  |
| F-93 | low | Several hotkey recorders can record at once; a forgotten one swallows key presses in all of holzBar's windows | fixed | auto | 9b26771d |  |
| F-94 | low | While a hotkey problem alert is shown, recording swallows the keyboard, so Return cannot dismiss the alert | fixed | auto | 93d48b39 |  |
| F-95 | low | Activating another colour well while a gradient stop is selected overwrites the stop's colour | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-96 | low | Distributing gradient stops re-sorts them under an index-based selection, so the panel edits a different stop | fixed | auto | 9914f3f9, df67f094 |  |
| F-97 | low | Gradient stop handles cannot get keyboard focus and expose nothing to VoiceOver | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-98 | low | The search list's app-wide arrow and Return monitors break input-method composition in the search field | fixed | auto | 03525582, 7e7ed6bf |  |
| F-99 | low | Profile names are unique case-sensitively but looked up case-insensitively, so the wrong profile can be applied | fixed | auto | a6acf917 |  |
| F-100 | low | Deleting a group leaves its custom image file in ItemIcons | fixed | auto | 6d7fe645 |  |
| F-101 | low | Applying a new item spacing on macOS 26 silently skips apps whose source PID could not be resolved | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-102 | low | The spacing relaunch can leave an app quit and not restarted while the error says it did not quit | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-103 | low | Shortcuts actions run before setup and do nothing or fail misleadingly; the notReady error is never thrown | fixed | auto | 48e45d21 |  |
| F-104 | low | The Settings window opened before setup shows defaults instead of stored values and drops hotkey edits | fixed | auto | f4d44cc2, d80c0048 |  |
| F-105 | low | The conflicting-app check matches any app by display name and force-terminates it after 3 s | fixed | auto | abbb90db |  |
| F-106 | low | The Raycast profile script does not encode "/" and needs python3, so some profiles apply wrongly or not at all | fixed | auto | d0dba9c4, b34e371f |  |
| F-107 | low | install.sh's TCC reset by bundle ID also revokes the Homebrew release's permissions | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-108 | low | verify-conceal.sh leaves a screencapture loop running when interrupted | fixed | auto | 7a2a96cd, 9488c024 |  |
| F-109 | low | The clock-restore and reveal-window probes leave a MacOS27ClickRestoreDelay override behind when interrupted | fixed | auto | f80e21d5 |  |
| F-110 | low | The project's MARKETING_VERSION is stale (0.0.5), so source builds report the wrong version | open | manual-only | — | Not in the chosen scope (manual-only, no decision asked). |
| F-111 | low | Dispatching the release for an existing tag publishes a binary built from a different commit than the tag | fixed | release chain, incidentally | f2117f4a | Fixed by the release restructure (see below). |
| F-112 | low | The release job cannot be re-run after a failed cask update and has no concurrency guard | fixed | release chain, incidentally | f2117f4a, 54a91ff5, 2fe22323 | Fixed by the release restructure (see below). |

Review fix-ups that name no finding ID:

- sync-alerts: `e92c3aab` (SA-04), `58461af9` (SA-06), `b50fd7b4` (SA-07), `07e3b78b` (SA-08).
- xpc: `1d359ef7` (XPC-01), `b0ae6887` (XPC-06), `13223d12` (XPC-07).
- events: `dc3f9bdb` (EV-01), `747bad6e` (EV-02), `784338f5` (EV-04).
- ax-observers: `e9474da8` (AXO-2), `780ca8f5` (AXO-R1), `a61458c9` (AXO-R2), `02fb2d2e` (AXO-R3).
- release: `8b85d460` (R-01), `b74d6473` (R-02), `54a91ff5` (R-03), `7221c342` (R-04), `2fe22323` (R-06).
- layoutbar (auto fixes F-32, F-33, F-79, F-90): `2e394858` (LB-1), `b895d70f` (LB-2), `f0004bfc` (LB-3), `f035cb10` (LB-4), `ed2a1d14` (LB-5).

Merges: the auto fixes in 13 merges (`a06635b7` scripts … `957a697f` ui), the chains in `aa52235f` (appearance-split), `1539b876` (ax-observers), `20447b2b` (events), `0c9840e8` (mac27-clicks), `bf8d705c` (sync-alerts), `8850f7a6` (xpc-attribution) and `6ee9dce5` (release).

## The maintainer's 16 decisions

Asked as multiple choice for the 13 manual-only clusters; the recommended option was chosen in 15 of 16.

| # | Cluster | Findings | Chosen | Rejected | What it does |
|---|---|---|---|---|---|
| 1 | sync | F-02, F-15, F-38, F-60 | Ask on conflict (recommended) | The folder always wins; merge setting by setting | holzBar asks which settings to use when a Mac joins a folder with different settings, or when both Macs changed. It never overwrites unasked, keeps settings a Mac lacks, does sync file I/O off the main thread (the launch read waits at most 1 s), and ties the sync id to the Mac with a salted hash of its hardware UUID. |
| 2 | event-timeouts | F-01 | Safety net, timing unchanged (recommended) | Tight deadlines as planned | Timeouts really fire: a lost event round trip is given up after about 2 s and the pointer and input monitors come back; the tuned timing stays. |
| 3 | event-timeouts | F-01 | Wait at most 1 s (recommended) | Open at once, load images afterwards | On macOS 26 the Shelf waits at most 1 s for its refresh. |
| 4 | xpc-trust | F-04, F-12, F-37, F-48, F-49 | Remove the helper service (recommended) | Keep the service and verify it; buy an Apple Developer ID; only fix the hangs for now | No XPC service; source-PID lookups run in the app on a background queue with time limits, and a scan that runs out of time is continued later. |
| 5 | indicators | F-06 | Protection plus safe attribution (recommended) | Protect only the indicator | The camera, microphone and FaceTime items never hide; Apple-signed apps are asked first, and a window two apps claim belongs to none. |
| 6 | indicators | F-08 | Dot in holzBar's icon (recommended) | Pause hiding during recording; dot plus a pause option; only a note for now | On macOS 27 holzBar's icon carries a dot while another app uses the microphone (orange) or a camera (green); a General setting, on by default. Screen recording is not covered. |
| 7 | capture-queue | F-13 | Watchdog and avoid triggers (recommended) | Avoid triggers without a watchdog; only safeguard search and Shelf | A capture that does not return is given up after about 2 s and later captures run on a new queue; after three stuck captures in a session, item capture stops. |
| 8 | modal-alerts | F-14 | Sheets and a quiet hint | Keep the alerts as they are (recommended); sheets in Settings only; quiet sync hint only | Alerts in Settings are sheets; a sync change from another Mac shows a quiet hint with Restart instead of a dialog. |
| 9 | ax-observers | F-16 | Register in the background (recommended) | Only short timeouts | Accessibility observers are registered off the main thread, with a messaging timeout. |
| 10 | agent-launches | F-17 | Known and standalone apps (recommended) | Only known apps; all app processes; only the Zen part now | holzBar follows changes of the running applications, so automatic Zen notices Screen Sharing and macOS 27 concealment notices menu bar agents that start later. |
| 11 | mac27-clicks | F-26 | Escape only to the panel (recommended) | Only the audit's proposal; drop the Escape shortcut | Escape goes only to the owner of a panel holzBar saw open. |
| 12 | mac27-clicks | F-27 | Wait for the real reveal (recommended) | Only the audit's proposal; change nothing for now | A click on or photo of a shown app waits until its concealment change has landed. |
| 13 | hotkey-conflicts | F-30 | Ask and replace (recommended) | Refuse with a note; only a beep | The recorder asks before moving a combination another hotkey uses (Replace or Cancel). |
| 14 | axpress | F-36 | Count the timeout as success (recommended) | Wait for the menu window | A press blocked by the item's open menu counts as taken; the item is not clicked again. |
| 15 | split-shape | F-39 | Recompute the right half (recommended) | Hide "Split" on macOS 27; only show a note | On macOS 27 the Split shape's trailing half follows the items area. |
| 16 | release | F-05, F-10, F-11, F-52, F-53, F-54 | Required pull requests plus a deploy key (recommended) | A separate tap repository; cask pull requests without required CI; `main` stays as it is | `main` takes only pull requests with green checks; the cask job pushes with a deploy key from the environment `release`; the release is tag-only, signed in its own job, fails closed and pins the certificate. The signing secrets stay repository secrets for now (F-10). F-54 was fixed by the auto pipeline. |

## F-111 and F-112: fixed by the release chain

The release restructure (`f2117f4a`, then `54a91ff5` and `2fe22323`) fixes both, checked against `.github/workflows/release.yml`:

- **F-111** (a dispatched release builds a different commit than the tag): `workflow_dispatch` is gone; the workflow runs only `on: push: tags: [ "v*" ]` (lines 6-8). "Determine version" fails unless the ref is a tag (line 44), "Check that the tag is on main" requires the tagged commit on `main` (line 61), and `gh release create --verify-tag` never creates a tag (line 433). The zip is always built from the tagged commit.
- **F-112** (no re-run after a failed cask update, no concurrency guard):
  - `concurrency: group: release-${{ github.ref }}`, `cancel-in-progress: false` (lines 15-17): one run per tag at a time.
  - Publish completes an existing release and never replaces a published zip (lines 419-433).
  - The cask job retries the push three times on the newest `main` (line 521), exits successfully when the cask is already at the version (line 525), and moves the cask only forward (line 535).
  - The ad hoc build is kept 7 days, so "Re-run failed jobs" can re-run the sign job (line 115).
  - The concurrency group is per tag, so two different tags can still run at once; the forward-only rule keeps the cask at the newer version, and the older run's cask job fails on purpose.

## Deferred: F-10

- **Done:** the sign and cask jobs run in the environment `release`, which only `v*` tags may use (`b74d6473`); the build job has no secrets, OIDC or write token; the signing job has no token permissions and runs no repository code; the cask is pushed with the deploy key `CASK_DEPLOY_KEY`; `main` and `v*` tags get rulesets after the merge.
- **Open:** `SIGNING_CERTIFICATE_P12` and `SIGNING_CERTIFICATE_PASSWORD` are still repository secrets, so a workflow pushed to any branch by a credential with the workflow scope can read them. The maintainer accepted this until the beta after 0.0.7-beta2, because the secrets have to be re-entered and the `.p12` and its password are not at hand.
- **Todo:** [2026-10-05-move-the-signing-secrets-into-the-release-environment-f-10.md](../todos/pending/2026-10-05-move-the-signing-secrets-into-the-release-environment-f-10.md). Its step 2 (`environment: release` on the sign job) is already done, so only settings remain: set both secrets with `--env release` (a fresh `.p12` exported from Keychain Access with a new password works too), release one beta, then delete the repository copies and the residual-risk notes.

## Open question: SA-05

Found in the review of the sync chain, not an audit finding; it needs the maintainer's decision. holzBar's own automatic layout writes (`ItemSections`, `MacOS27Layout`) count as user changes for conflict detection: `SettingsSyncPolicy.learnedKeys` (`holzBar/Core/SettingsSyncPolicy.swift`) leaves them out, so they enter the user digest. A Mac whose layout holzBar rearranged on its own can therefore ask the sync conflict question. The implementer advised against simply leaving the other OS's layout key out of the digest.

## Still open

The 18 open findings are all low and manual-only, and were not in the chosen scope: F-43, F-44, F-45, F-47, F-50, F-57, F-59, F-61, F-67, F-69, F-75, F-76, F-95, F-97, F-101, F-102, F-107, F-110. Two consequences to keep in mind:

- **F-107:** since F-40, `Scripts/install.sh` runs its TCC reset every time, which also revokes the Homebrew release's permissions on every source install.
- **F-50:** besides `docs/release-notes/v0.0.6.md`, the published 0.0.6 release body needs the same correction.
