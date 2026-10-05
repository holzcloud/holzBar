# holzBar full bug and security audit (2026-10-05)

## Scope and method

- **Repository:** `/Users/cheidenreich/privat/holzBar` (holzBar, a macOS menu bar manager forked from Ice by Jordan Baird). Branch `fix/macos26-own-control-items`, HEAD `3d2f1bb`. The current working-tree files were audited.
- **What the product is:** a non-App-Store app with Accessibility and Screen Recording permissions. It has an embedded XPC service (`MenuBarItemService`), the `holzbar://` URL scheme, App Intents, settings import, backup and sync, Homebrew cask distribution, and release signing in GitHub Actions. It builds in Swift 6 language mode with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Platforms:** the deployment target is macOS 14, but only macOS 26 and macOS 27 matter, so a finding that only affects 14 or 15 is rated low at most. The three backends:
  - `WindowListBackend` (macOS 14 and 15)
  - `ServiceBackend26` (macOS 26: Control Center owns every item window, and the XPC service resolves source PIDs through Accessibility)
  - `AccessibilityBackend27` (macOS 27)
- **Rules checked:** the project's own rules in `CLAUDE.md` (the app never uses the network except to open links in the browser, least privilege, modern Apple APIs) and general correctness and security.
- **Slices:** 16 audit slices.
  - 11 region slices: R01 core, R02 macOS 27, R03 menu bar items, R04 backends and control items, R05 other menu bar code, R06 appearance and layout bar, R07 utilities, permissions and events, R08 UI, R09 settings, main and hotkeys, R10 shared code and XPC, R11 scripts and build.
  - 5 lens slices: L1 attack surface, L2 untrusted data, L3 supply chain, L4 privacy and permissions, L5 concurrency.
- **Coverage check and gap round:** a critic compared the reviewed files with `git ls-files`. A gap round then added three slices: G1 data that hostile apps feed in, G2 bundle integrity, G3 layout faults.
- **Verification:** a separate skeptic re-read the code behind every finding, often with probes built using the project's concurrency settings. Only findings that survived are included. Each high or critical finding also got an independent second vote, recorded under the finding's verification notes.
- **Synthesis (this document):**
  - Duplicates with the same root cause are merged, and their source slice findings are listed under "Merged from". The 151 verified slice findings became **112 findings**.
  - Findings are ordered by severity, then by category (security, privacy, supply-chain, concurrency, bug), then by impact.
  - Each finding is classified the GSD audit-fix way, as described below.
  - One disputed sub-claim was settled with a probe: `scratchpad/audit-synth/modal.swift` (see F-02 and F-14).
- **Results:** no critical findings. 3 high, 38 medium, 71 low. By category: 12 security, 4 privacy, 5 supply-chain, 10 concurrency, 81 bug. **66 auto-fixable, 46 manual-only.**

### Classification rules

**Auto-fixable** means all of the following hold:

- The fix has a specific file and line and a concrete minimal change.
- It stays within one subsystem.
- It needs no product, UX or policy decision. This includes no new user-facing text: CI's `strings-check.py` requires every new string in English, German, French, Italian and Romansh.
- It does not touch release, signing, CI-release or repository settings.
- It does not restructure OS interaction whose timing was tuned on a device: event-tap barriers, click replay, concealment apply sequencing.

Everything else is **manual-only**. When in doubt, a finding is manual-only.

What the test gate can check: `swift test` compiles only `holzBar/Core`, `holzBar/MenuBar/MacOS27/Core` and `Shared/CodeSigning`. This Mac has only the Command Line Tools and no Xcode, so changes to the app target are compile-checked only by CI's build job or on a Mac with Xcode 27. Behaviour on macOS 27 could not be run here, because the host runs macOS 26.7.1.

### Dependencies for the fix pipeline

- F-01 and F-21 both edit `MenuBarItemEventPoster.swift`. F-21 and F-86 should share one helper for user-held modifier flags.
- F-02, F-15, F-38 and F-60 belong to one settings-sync redesign. F-18 is independent and safe to do first.
- F-19 makes fullscreen detection work for the first time, which affects F-51 and every fullscreen path in the app. Test fullscreen afterwards.
- F-40 makes the TCC reset in `install.sh` run every time, so F-107 then happens on every source install.
- F-46, F-58 and F-74 touch the same appearance-discard path in `ItemImageStore27.swift`.
- F-31 and F-98 need the same `onKeyDown` overload that passes the event.
- F-12 must be fixed before F-04's preferred fix (moving the lookup into the app).

## Summary

| ID | Severity | Category | Title | File | Classification |
|---|---|---|---|---|---|
| F-01 | high | concurrency | Timeouts never fire: a lost event round trip hangs every move and click (pointer hidden, input monitors off), and the Shelf's wait is unbounded | `holzBar/Utilities/ConcurrencyHelpers.swift:39` | manual-only |
| F-02 | high | bug | Settings sync overwrites other Macs' settings: push() never reads or compares the file (turning sync on, every launch, after "Later") | `holzBar/Utilities/SettingsSync.swift:146` | manual-only |
| F-03 | high | bug | Applying a layout profile on macOS 27 replaces the whole saved layout, wiping it for profiles saved before macOS 27 | `holzBar/MenuBar/Profiles/LayoutProfiles.swift:172` | auto-fixable |
| F-04 | medium | security | macOS 26: the embedded XPC service runs with holzBar's TCC grants and is never checked, so swapping it hands those grants to other code | `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:150` | manual-only |
| F-05 | medium | security | Release and install builds carry get-task-allow on the app and the XPC service, so a debugger can inject code that runs with holzBar's grants | `.github/workflows/release.yml:67` | manual-only |
| F-06 | medium | security | macOS 26: any app's Accessibility frames can claim a Control Center item window, making the camera and microphone indicator hideable | `Shared/Services/SourcePIDCache.swift:146` | manual-only |
| F-07 | medium | privacy | holzbar://search and holzbar://settings bypass Zen mode and show hidden items during screen sharing (on macOS 27 also in the real menu bar) | `holzBar/Core/URLCommand.swift:50` | auto-fixable |
| F-08 | medium | privacy | macOS 27: while holzBar conceals items, Control Centre's microphone, camera and screen-recording indicator is suppressed, and nothing compensates | `holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:59` | manual-only |
| F-09 | medium | privacy | The Shelf colour manager captures the screen on macOS 27 and while the Shelf is hidden | `holzBar/MenuBar/Shelf/HolzBarShelfColorManager.swift:122` | auto-fixable |
| F-10 | medium | supply-chain | The signing key and the signed-release pipeline can be reached from any branch or tag (repository-level secrets, no environment, no tag or branch protection) | `.github/workflows/release.yml:81` | manual-only |
| F-11 | medium | supply-chain | Missing signing secrets fail open (an ad hoc release reaches every cask user), and the certificate fingerprint is never pinned | `.github/workflows/release.yml:87` | manual-only |
| F-12 | medium | concurrency | macOS 26 local fallback: the main-thread running-apps observer blocks on the lookup lock while a scan waits for holzBar's own Accessibility replies | `Shared/Services/SourcePIDCache.swift:192` | manual-only |
| F-13 | medium | concurrency | One stuck window capture wedges the serial capture queue for the session: images stop updating and search and Shelf stop opening | `holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:71` | manual-only |
| F-14 | medium | concurrency | NSAlert.runModal() inside main-actor Tasks blocks all main-actor work while the alert is open (macOS 27 system-item clicks are swallowed) | `holzBar/Utilities/SettingsSync.swift:452` | manual-only |
| F-15 | medium | concurrency | Settings sync does coordinated file I/O on the main thread, so a dataless file, a hung file provider or a stalled volume blocks launch and the UI | `holzBar/Utilities/SettingsSync.swift:336` | manual-only |
| F-16 | medium | concurrency | Accessibility observer registration runs on the main thread with no messaging timeout, stalling holzBar and, on macOS 27, every click | `holzBar/MenuBar/MacOS27/ItemChangeObserver27.swift:59` | manual-only |
| F-17 | medium | bug | Launches and quits of menu bar agents go unnoticed: automatic Zen misses Screen Sharing, and macOS 27 concealment keeps newly launched Visible agents hidden | `holzBar/MenuBar/PresentationMonitor.swift:64` | manual-only |
| F-18 | medium | bug | The sync-folder bookmark is resolved without .withoutMounting on every access, so holzBar mounts network shares itself and blocks while the mount times out | `holzBar/Utilities/SettingsSync.swift:85` | auto-fixable |
| F-19 | medium | bug | CGSSpaceGetType is declared with a Swift enum return type, so fullscreen spaces are never detected on macOS 26 and 27 | `Shared/Bridging/Shims.swift:101` | auto-fixable |
| F-20 | medium | bug | Smart rehide (the default) never fires without Screen Recording, because it only considers windows that have a title | `holzBar/Events/HIDEventManager.swift:434` | auto-fixable |
| F-21 | medium | bug | With Caps Lock on, every item move and click on macOS 26 waits indefinitely and replays later | `holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift:39` | auto-fixable |
| F-22 | medium | bug | Rehiding a temporarily shown item targets a stored neighbour snapshot; if that window is gone, rehide fails forever and keeps tripping MoveBackoff | `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1030` | auto-fixable |
| F-23 | medium | bug | Stored identity keys of the second and later untitled items of an app never match their current key | `holzBar/Core/ItemIdentity.swift:98` | auto-fixable |
| F-24 | medium | bug | Stale saved-section keys are never pruned and collide with current keys, so restore can move items back into old sections | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:97` | auto-fixable |
| F-25 | medium | bug | A pending profile reconciliation is replaced by a later restore request, so the profile is silently not applied | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:153` | auto-fixable |
| F-26 | medium | bug | macOS 27 click bridge: stale panel state plus banner windows make a clock click post a synthetic Escape and swallow the click | `holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift:136` | manual-only |
| F-27 | medium | bug | macOS 27: clicks and photos of a temporarily shown app use fixed sleeps and stale Accessibility frames, so they can hit another item | `holzBar/MenuBar/MacOS27/ItemClicker27.swift:41` | manual-only |
| F-28 | medium | bug | macOS 27: Visible apps concealed for the notch stay concealed after the reveal that crowded the bar ends | `holzBar/MenuBar/MacOS27/Concealer27.swift:357` | auto-fixable |
| F-29 | medium | bug | A hotkey stays unregistered when its recorder disappears while recording | `holzBar/UI/Views/HotkeyRecorder.swift:189` | auto-fixable |
| F-30 | medium | bug | A combination another holzBar hotkey already uses is saved but never registered, and the row then offers no way to clear it | `holzBar/UI/Views/HotkeyRecorder.swift:228` | manual-only |
| F-31 | medium | bug | Backspace or Escape anywhere in holzBar deletes or deselects the selected gradient stop and is swallowed | `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:112` | auto-fixable |
| F-32 | medium | bug | Menu Bar Layout pane: the source row of a drag stops updating after a drop into another row or a cancelled drag | `holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift:497` | auto-fixable |
| F-33 | medium | bug | Keyboard and VoiceOver moves in the Layout pane lose focus after one step | `holzBar/MenuBar/LayoutBar/LayoutBarContainer.swift:188` | auto-fixable |
| F-34 | medium | bug | The "Focused app" rehide strategy fires even when "Automatically rehide" is off | `holzBar/MenuBar/MenuBarManager.swift:192` | auto-fixable |
| F-35 | medium | bug | The Shelf jumps after it opens, because every resize recomputes its position from the current mouse location | `holzBar/MenuBar/Shelf/HolzBarShelf.swift:119` | auto-fixable |
| F-36 | medium | bug | Opening a hidden item without showing it treats a menu-opening AXPress as a failure and clicks the item again | `holzBar/MenuBar/MenuBarItems/ItemOpener.swift:85` | manual-only |
| F-37 | medium | bug | macOS 26 source-PID lookups have no overall time limit, so one slow app stalls every item read | `Shared/Services/SourcePIDCache.swift:148` | manual-only |
| F-38 | medium | bug | The sync device ID lives in the preferences file, so Macs set up by Migration Assistant, restore or clone ignore each other's changes | `holzBar/Utilities/SettingsSync.swift:50` | manual-only |
| F-39 | medium | bug | The Split menu bar shape always degrades to the full shape on macOS 27 | `holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift:832` | manual-only |
| F-40 | medium | bug | install.sh skips the TCC reset for ad hoc builds most of the time (SIGPIPE under pipefail) | `Scripts/install.sh:73` | auto-fixable |
| F-41 | medium | bug | verify-layout.sh restores MacOS27Layout with string values, wiping the real macOS 27 layout while printing PASS | `Scripts/macos27/verify-layout.sh:49` | auto-fixable |
| F-42 | low | security | Any app can crash holzBar on macOS 27 by reporting a non-finite or huge Accessibility frame | `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:411` | auto-fixable |
| F-43 | low | security | Any local process can freeze concealment, Zen mode and item placement with a spoofed com.apple.screenIsLocked notification | `holzBar/Events/SystemActivityMonitor.swift:61` | manual-only |
| F-44 | low | security | macOS 26: a process named like holzBar or Control Center gets their item tags, and a fake divider becomes the section divider | `holzBar/MenuBar/MenuBarItems/MenuBarItem.swift:375` | manual-only |
| F-45 | low | security | macOS 27: a second process with bundle ID com.apple.MenuBarAgent overwrites the system-item frames the click bridge uses | `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:278` | manual-only |
| F-46 | low | security | macOS 27: a spoofed theme-change notification discards all item images and resets the photo schedule, so concealed apps flash into the bar | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:94` | auto-fixable |
| F-47 | low | security | Item groups read from settings are not capped; a crafted import or sync file floods the menu bar with status items | `holzBar/MenuBar/Groups/MenuBarItemGroups.swift:74` | manual-only |
| F-48 | low | security | The app never verifies the XPC service's code, and the comment's reasons for skipping it are wrong | `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:157` | manual-only |
| F-49 | low | security | docs/signing.md and SECURITY.md (T-06-M4) present the trojanized-app threat as mitigated, but a swapped nested service keeps the grants | `docs/signing.md:7` | manual-only |
| F-50 | low | security | The 0.0.6 release notes verify the certificate SHA-256 with a command that never prints it | `docs/release-notes/v0.0.6.md:120` | manual-only |
| F-51 | low | privacy | macOS 27: the menu bar capture does not check that the bar is on screen, so fragments of the window underneath become item icons | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:189` | auto-fixable |
| F-52 | low | supply-chain | An unpinned, unsandboxed SwiftLint build phase runs in every build, including the release job with contents:write and id-token:write | `holzBar.xcodeproj/project.pbxproj:232` | manual-only |
| F-53 | low | supply-chain | The documented `gh attestation verify -R holzcloud/holzBar` accepts an attestation from any workflow on any ref | `docs/signing.md:118` | manual-only |
| F-54 | low | supply-chain | The "no Swift packages" CI gate is bypassed by omitting Package.resolved; project.pbxproj package references are never checked | `.github/scripts/privacy-check.py:166` | auto-fixable |
| F-55 | low | concurrency | Debouncer runs a superseded or cancelled action when its sleep had already finished | `holzBar/Core/Debouncer.swift:48` | auto-fixable |
| F-56 | low | concurrency | A superseded item-cache refresh keeps running after cancellation and can overwrite the newer result | `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:236` | auto-fixable |
| F-57 | low | concurrency | macOS 27 item scan sets a short messaging timeout only on the application element; per-item reads wait up to 6 s | `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:235` | manual-only |
| F-58 | low | concurrency | macOS 27: image-store deletes and writes run in unordered detached tasks, so old-appearance glyphs can survive a theme switch | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:110` | auto-fixable |
| F-59 | low | bug | One bad entry in a dictionary- or JSON-valued setting empties the whole setting, and the next save writes the loss back | `holzBar/MenuBar/MenuBarItems/ItemIconStore.swift:46` | manual-only |
| F-60 | low | bug | Applying synced settings deletes local keys the sending Mac never had, wiping the per-OS layout between macOS 26 and 27 Macs | `holzBar/Utilities/SettingsBackup.swift:66` | manual-only |
| F-61 | low | bug | A custom icon of a few hundred KB pushes the sync file over the 1 MiB read limit, and other Macs silently ignore all synced settings | `holzBar/Core/SettingsSyncFile.swift:27` | manual-only |
| F-62 | low | bug | A stored custom icon that ImageIO refuses leaves holzBar's own menu bar icon blank, with no fallback | `holzBar/MenuBar/ControlItem/ControlItem.swift:400` | auto-fixable |
| F-63 | low | bug | An unknown shape kind, end cap or black-background value fails the whole appearance decode, and the next edit overwrites it | `holzBar/MenuBar/Appearance/Configurations/MenuBarAppearanceConfigurationV2.swift:82` | auto-fixable |
| F-64 | low | bug | New items are marked known before they are placed, so a failed or paused placement is never retried | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:250` | auto-fixable |
| F-65 | low | bug | "Keep Live Activities visible" and the new-items placement fight over the same item in every reconciliation | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:233` | auto-fixable |
| F-66 | low | bug | A running restore keeps moving items after the user starts dragging, and the reverted arrangement is saved | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:256` | auto-fixable |
| F-67 | low | bug | Position-based identity keys swap between items of one app, so restore can put each item in the other's section | `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:209` | manual-only |
| F-68 | low | bug | On macOS 27 identity keys are never disambiguated, so all items of a learned title-changing app share one key | `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1166` | auto-fixable |
| F-69 | low | bug | Learned title-changing owners are never unlearned and can be poisoned by a process presenting another app's namespace | `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1185` | manual-only |
| F-70 | low | bug | Any app keeps its item out of the hidden section by putting "LiveActivit" in its title | `holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift:72` | auto-fixable |
| F-71 | low | bug | "Show When It Changes" never starts watching an item whose Accessibility element was not found the first time | `holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift:110` | auto-fixable |
| F-72 | low | bug | The negative lookup cache stores lookups that never scanned for 30 s, giving new items a temporary UUID namespace | `Shared/Services/SourcePIDCache.swift:248` | auto-fixable |
| F-73 | low | bug | macOS 27: continuous AX created/destroyed notifications from one owner keep postponing item-list refreshes, including the 60 s fallback | `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:186` | auto-fixable |
| F-74 | low | bug | macOS 27: the theme observer is not installed when the image store's version check fails, so theme switches keep old glyphs | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:80` | auto-fixable |
| F-75 | low | bug | macOS 27: item images keyed by identifiers other apps choose are never pruned | `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:425` | manual-only |
| F-76 | low | bug | macOS 27: system items on the inactive display are guessed with a "widest frame over 80 pt is the clock" rule that misfires | `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:302` | manual-only |
| F-77 | low | bug | macOS 27: a failed concealment apply leaves holzBar claiming concealment, with no retry | `holzBar/MenuBar/MacOS27/Concealer27.swift:232` | auto-fixable |
| F-78 | low | bug | macOS 27: an earlier suspension timer ends a later, longer suspension early | `holzBar/MenuBar/MacOS27/Concealer27.swift:418` | auto-fixable |
| F-79 | low | bug | macOS 27: a drag within one row shows an order macOS does not keep and registers a no-op undo | `holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift:78` | auto-fixable |
| F-80 | low | bug | holzBar's own activation (to hide application menus) counts as a focus change and rehides the section it just showed | `holzBar/MenuBar/MenuBarManager.swift:189` | auto-fixable |
| F-81 | low | bug | Application menus can be hidden after the section was already hidden again (stale async result) | `holzBar/MenuBar/MenuBarManager.swift:258` | auto-fixable |
| F-82 | low | bug | Opening Settings or closing its window while application menus are hidden leaves the hiding flag stale | `holzBar/Main/AppState.swift:377` | auto-fixable |
| F-83 | low | bug | Closing the Shelf while it waits for the cache leaves it on screen with no section, and Escape does not close it | `holzBar/MenuBar/Shelf/HolzBarShelf.swift:206` | auto-fixable |
| F-84 | low | bug | The search panel still opens after it was closed while waiting for the image cache | `holzBar/MenuBar/Search/MenuBarSearchPanel.swift:122` | auto-fixable |
| F-85 | low | bug | "Show the hidden section for a moment" hides early on repeated presses and overrides a later manual show | `holzBar/Hotkeys/HotkeyActionPerform.swift:69` | auto-fixable |
| F-86 | low | bug | With Caps Lock on, Option-click and Control-click on the holzBar icon and on empty menu bar space do the wrong thing | `holzBar/MenuBar/ControlItem/ControlItem.swift:524` | auto-fixable |
| F-87 | low | bug | Section dividers keep the drag marker and 3 pt width after a Command-drag ends | `holzBar/MenuBar/ControlItem/ControlItem.swift:221` | auto-fixable |
| F-88 | low | bug | NSScreen.screenWithMouse returns nil at the top pixel row, so hit tests can use the wrong display | `holzBar/Utilities/Extensions.swift:506` | auto-fixable |
| F-89 | low | bug | Permissions are never re-checked after setup: a revoked Accessibility still shows "Permission Granted" | `holzBar/Permissions/Permission.swift:108` | auto-fixable |
| F-90 | low | bug | On macOS 26 the Layout pane checks Control Center's responsiveness instead of the item's own app | `holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift:133` | auto-fixable |
| F-91 | low | bug | With a dynamic appearance, overlay panels exist only for the current mode, so the other mode's style and Hold to Preview never show | `holzBar/MenuBar/Appearance/MenuBarAppearanceManager.swift:166` | auto-fixable |
| F-92 | low | bug | The System Glass view is not added or removed when light/dark mode switches under a dynamic appearance | `holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift:608` | auto-fixable |
| F-93 | low | bug | Several hotkey recorders can record at once; a forgotten one swallows key presses in all of holzBar's windows | `holzBar/UI/Views/HotkeyRecorder.swift:177` | auto-fixable |
| F-94 | low | bug | While a hotkey problem alert is shown, recording swallows the keyboard, so Return cannot dismiss the alert | `holzBar/UI/Views/HotkeyRecorder.swift:221` | auto-fixable |
| F-95 | low | bug | Activating another colour well while a gradient stop is selected overwrites the stop's colour | `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:132` | manual-only |
| F-96 | low | bug | Distributing gradient stops re-sorts them under an index-based selection, so the panel edits a different stop | `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:284` | auto-fixable |
| F-97 | low | bug | Gradient stop handles cannot get keyboard focus and expose nothing to VoiceOver | `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:345` | manual-only |
| F-98 | low | bug | The search list's app-wide arrow and Return monitors break input-method composition in the search field | `holzBar/UI/Views/SectionedList.swift:74` | auto-fixable |
| F-99 | low | bug | Profile names are unique case-sensitively but looked up case-insensitively, so the wrong profile can be applied | `holzBar/MenuBar/Profiles/LayoutProfiles.swift:151` | auto-fixable |
| F-100 | low | bug | Deleting a group leaves its custom image file in ItemIcons | `holzBar/MenuBar/Groups/MenuBarItemGroups.swift:110` | auto-fixable |
| F-101 | low | bug | Applying a new item spacing on macOS 26 silently skips apps whose source PID could not be resolved | `holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift:191` | manual-only |
| F-102 | low | bug | The spacing relaunch can leave an app quit and not restarted while the error says it did not quit | `holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift:144` | manual-only |
| F-103 | low | bug | Shortcuts actions run before setup and do nothing or fail misleadingly; the notReady error is never thrown | `holzBar/Main/HolzBarIntents.swift:38` | auto-fixable |
| F-104 | low | bug | The Settings window opened before setup shows defaults instead of stored values and drops hotkey edits | `holzBar/Main/AppDelegate.swift:126` | auto-fixable |
| F-105 | low | bug | The conflicting-app check matches any app by display name and force-terminates it after 3 s | `holzBar/Main/ConflictingApps.swift:28` | auto-fixable |
| F-106 | low | bug | The Raycast profile script does not encode "/" and needs python3, so some profiles apply wrongly or not at all | `Integrations/Raycast/holzbar-profile.sh:14` | auto-fixable |
| F-107 | low | bug | install.sh's TCC reset by bundle ID also revokes the Homebrew release's permissions | `Scripts/install.sh:76` | manual-only |
| F-108 | low | bug | verify-conceal.sh leaves a screencapture loop running when interrupted | `Scripts/macos27/verify-conceal.sh:77` | auto-fixable |
| F-109 | low | bug | The clock-restore and reveal-window probes leave a MacOS27ClickRestoreDelay override behind when interrupted | `Scripts/macos27/clock-restore.swift:99` | auto-fixable |
| F-110 | low | bug | The project's MARKETING_VERSION is stale (0.0.5), so source builds report the wrong version | `holzBar.xcodeproj/project.pbxproj:444` | manual-only |
| F-111 | low | bug | Dispatching the release for an existing tag publishes a binary built from a different commit than the tag | `.github/workflows/release.yml:183` | manual-only |
| F-112 | low | bug | The release job cannot be re-run after a failed cask update and has no concurrency guard | `.github/workflows/release.yml:186` | manual-only |

## Findings

### High

#### F-01 — Timeouts never fire: a lost event round trip hangs every move and click (pointer hidden, input monitors off), and the Shelf's wait is unbounded

- **Severity:** high · **Category:** concurrency · **Affects:** macOS 26 (the Shelf part also on macOS 27 when `macOS27ShelfWaitsForRefresh` is set)
- **Location:** `holzBar/Utilities/ConcurrencyHelpers.swift:39`; `holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift:188`, `:310`
- **Classification:** manual-only. Two interdependent concurrency changes, the shared timeout helper and the event-poster continuations with tap cleanup, on the core macOS 26 move/click path. Correct behaviour depends on event-tap timing and must be verified on a macOS 26 Mac. `holzBar/Utilities` is not compiled by `swift test`.
- **Merged from:** R04-backends-controlitem: "Event barrier timeout never fires: a missing event round trip hangs every move and click with the cursor hidden and HID monitors stopped"; R07-utilities-permissions-events: "Task(timeout:) cannot time out an operation that ignores cancellation, so a stuck event round trip hangs moves and clicks forever and leaves the HID monitors disabled"; L5-concurrency: "Task(timeout:) never times out an operation that is not cancellation-aware, so the Shelf's 1-second wait on macOS 26 has no limit"; L5-concurrency: "Event-barrier continuations in MenuBarItemEventPoster are never resumed on timeout; a lost barrier hangs moves and clicks for good, with the cursor hidden and holzBar's input monitors off".

**Summary.** Two defects combine.

1. `Task.value(of:timeout:)` races the operation against a sleep inside `withThrowingTaskGroup`. When the sleep wins, the error leaves the group body, but a task group always waits for its remaining children. The remaining child awaits `operationTask.value`, which does not react to cancellation. So the timeout error only arrives once the operation has finished anyway.
2. `postEventWithBarrier` and `scrombleEvent` wait in a bare `withCheckedThrowingContinuation`. Their only cancellation handler sits in a separate unstructured `Task { await withTaskCancellationHandler { … } onCancel: { … } }`. That task finishes right after posting the entry event and is never cancelled, so its `onCancel` is dead code. The only thing that resumes the continuation is EventTap 1 seeing the exit event.

On macOS 26 every move and click goes through this code (ServiceBackend26 → WindowListBackend → MenuBarItemEventPoster). For a lost event, the adaptive 25–150 ms timeouts and the `catch is TaskTimeoutError` handling are never reached. The same helper turns the Shelf's `Task(timeout: .seconds(1))` refresh wait into a wait for the whole refresh; this is the default Shelf path on macOS 26.

**Evidence.**
- Helper: `ConcurrencyHelpers.swift:39-56`, with `withTaskCancellationHandler { try await operationTask.value } onCancel: { operationTask.cancel() }` inside the group.
- Event poster: `MenuBarItemEventPoster.swift:188-261` and `310-407`. The inner unstructured Task is at 246-259 and 390-405, and `try await timeoutTask.value` has no cancellation handler.
- State the callers never restore when the wait hangs:
  - `eventLock` at 563-566 and 729
  - `hidEventManager.stopAll()` / `defer { startAll() }` at 658-661 and 812-814
  - `hideCursor()` / `defer { showCursor() }` at 167-170 and 290-293
- Shelf: `HolzBarShelf.swift:206-216`.
- All `Task(timeout:)` call sites: EventPoster 188, 310 and 531, and HolzBarShelf 206. Line 531 (`waitForMoveEventResponse`) works, because its operation polls with `checkCancellation`.

**Failure scenario.** On macOS 26 holzBar moves or clicks an item: a Shelf or search click, a rehide, a section restore or a divider order. The entry or exit null event never comes back. Possible causes:
- the item's app quit between the item read and the move;
- `CGEvent.tapCreateForPid` failed, so `EventTap.enable()` silently does nothing;
- the tap was disabled by `tapDisabledByTimeout` during a main-thread stall;
- another session tap dropped the synthetic event.

The await never returns, with these effects until holzBar is quit:
- `eventLock` stays held, so every later move and click queues forever.
- `CGDisplayHideCursor` is never balanced, so the pointer stays hidden system-wide.
- `stopAll()` is never undone, so show on hover, click and scroll and smart rehide stop working.
- A synthetic mouse-down may be left without its mouse-up.

Separately, a CGWindowList capture that blocks on the serial capture queue makes every later Shelf open wait forever. The code documents such blocking for off-edge items on macOS 26 (`MenuBarItemImageCache.swift:50-60`).

**Fix.**
1. In both event-poster functions:
   - remove the inner unstructured Task, and put `withTaskCancellationHandler` directly around `withCheckedThrowingContinuation`;
   - keep the continuation in an `OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>`, which the exit-tap path and `onCancel` take and resume exactly once;
   - disable all taps on the main actor in a `defer`;
   - wrap `try await timeoutTask.value` in a cancellation handler that cancels `timeoutTask`.
2. Make `Task.value(of:timeout:)` return on timeout without awaiting the operation: two unstructured tasks race to resume one continuation behind a resume-once flag, and the timeout path cancels the operation. Correct the doc comment.
3. In `HolzBarShelfPanel.show`, show the panel first and refresh alongside it, as the macOS 27 path does.
4. Add a regression test for the helper with an operation that ignores cancellation. The helper is not in a package target today.

**Verification.**
- R04-1 and R07-1 were confirmed high, each with a second vote (high). Their probes, built with the project's concurrency settings, were still suspended 3.07–3.14 s after a 100–200 ms timeout and reported a leaked continuation.
- L5-1 was confirmed high with a second vote (high). The second voter's own probe got the timeout error 1.8 s late, exactly when the operation finished.
- L5-2's verifier rated the continuation defect medium. The merged finding is high because the two defects together hang the core path for the whole session.
- Not one of K1–K4. The symptom matches upstream reports that `docs/upstream-bugs.md` lists as solved ("Pointer gone or stuck after clicking an item in the Shelf", #640/#751/#757).
- Related: F-13 (the capture wedge behind the Shelf hang) and F-21 (the unbounded user-input wait in the same move path).

#### F-02 — Settings sync overwrites other Macs' settings: push() never reads or compares the file (turning sync on, every launch, after "Later")

- **Severity:** high · **Category:** bug · **Affects:** all versions (the code does not depend on the backend)
- **Location:** `holzBar/Utilities/SettingsSync.swift:146`
- **Classification:** manual-only. Needs a user-facing conflict choice, with new strings in five languages, and a design for persisted sync state across enabling sync, launch, push and the prompt. It is one file, but it redesigns a policy.
- **Merged from:** R07-utilities-permissions-events: "Turning on sync on a second Mac overwrites the existing sync file with that Mac's settings before reading it"; L2-untrusted-data: "Turning sync on (or choosing a folder) overwrites the other Mac's settings file before reading it"; R07-utilities-permissions-events: "Every launch re-pushes the settings unconditionally: other Macs get endless restart prompts, and a Mac that has not received the latest file yet overwrites it"; L2-untrusted-data: "Every launch rewrites the sync file with a fresh timestamp, so every other Mac gets a restart prompt and Macs keep re-prompting each other"; L1-attack-surface: "Settings sync overwrites another Mac's newer settings: an unconditional push at every launch, and pushes after \"Later\" or while the restart question is open"; L2-untrusted-data: "An unapplied change from another Mac is discarded when this Mac pushes, for example after \"Later\" or while the restart alert is open".

**Summary.** `push()` replaces the file with this Mac's settings, stamped with `modified = now` and this Mac's device ID. It never reads the existing file first and never compares content. Receivers decide only by date and device. Three paths lose data:

- **(a) Joining.** "Turn On…" and "Change…" call `chooseFolder()`, which clears `lastPushedData` and then sets `isEnabled = true` (or pushes directly), and `isEnabled.didSet` pushes. The joining Mac's settings, often defaults, replace the existing file. The other Mac then adopts them, through the restart prompt or silently at its next launch via `pullIfNeeded`, and `SettingsBackup.apply` removes every key the file lacks. The joining Mac never receives the existing settings.
- **(b) Every launch.** `performSetup` assigns `isEnabled` from false to true, so `didSet` pushes. `lastPushedData` is nil at launch, so the file is rewritten with a fresh date even when nothing changed.
  - Every other Mac then shows "Settings changed on another Mac". Restarting it pushes again, which prompts the first Mac, and so on (ping-pong).
  - A Mac whose sync client has not yet downloaded the newest file pushes its stale settings over it with a newer date (lost update).
- **(c) After "Later".** Nothing records the pending remote version. The next debounced or direct push overwrites it and sets `lastSynced = now`, so the change is never applied. Such pushes include holzBar's own writes of `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners` and `ItemSections`.

**Evidence.** `SettingsSync.swift`:
- 146-153: `if isEnabled, !oldValue { push() }`
- 175-178: `isEnabled = Defaults.bool(forKey: .syncsSettingsWithICloud)`
- 247-270: `chooseFolder` sets `lastPushedData = nil`, then pushes or sets `isEnabled = true`
- 292-348: `push`, whose only guard is `settingsData != lastPushedData`; it writes `Date.now` and the device ID and sets the last-synced date
- 417-429: `pullIfNeeded`, which runs only at launch and only when sync was already on
- 434-455: the restart prompt

Elsewhere:
- `SettingsSyncFile.swift:54-63`: `newerSettings` checks only device, date and clock skew.
- `SettingsBackup.swift:62-71`: `apply` removes keys that are missing from the file.

**Failure scenario.** Mac A has synced its layout, profiles and hotkeys for weeks. The user installs holzBar on Mac B and clicks Settings › Advanced › Sync › Turn On… with the same iCloud Drive folder.
- B writes its defaults over `holzBar/Settings.plist`.
- A offers a restart, or applies the file silently at its next launch.
- A's configuration is replaced by B's defaults on both Macs, and no copy is left in the folder.

Separately, with two Macs syncing, every login on one Mac prompts the other to restart for identical settings. A "Later" on one Mac, followed by any app launch there, discards the other Mac's change.

**Fix.**
1. Remove the unconditional `push()` from `isEnabled.didSet`.
2. When the user turns sync on or changes the folder, read the existing file first. If another Mac wrote it, ask "Use the settings in the sync folder (restart)" or "Replace them with this Mac's". Push only on "replace", or when there is no file or the file is this Mac's own.
3. Persist a hash of the last pushed or applied settings in a local `SettingsSync*` key. Skip pushes whose content is unchanged. Skip the restart prompt when the remote settings, with local keys removed, equal this Mac's.
4. Before every push, read the file. While `newerSettings(from:)` reports another Mac's newer, unapplied version, do not overwrite it: keep it pending and ask again.
5. Put the decision logic into `holzBar/Core` next to `SettingsSyncFile` and cover it with tests.

**Verification.**
- R07-2 and L2-1 were confirmed high, each with a second vote (high). The second votes traced the path end to end, including "Later" (the file is applied silently at the next launch) and `apply` removing missing keys.
- R07-3 and L2-2 were confirmed medium; the second vote on L2-2 was medium.
- L1-3 and L2-3 also claim that the debounced push can run while the restart alert is open. That sub-claim does not hold. The alert runs `runModal()` inside a main-actor Task, and no other main-actor job runs until it returns. This is shown by L5-5's probe and re-checked by the synthesizer with `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/audit-synth/modal.swift`. The "after Later" path stands.
- Related: F-15, F-38, F-60, F-61.

#### F-03 — Applying a layout profile on macOS 27 replaces the whole saved layout, wiping it for profiles saved before macOS 27

- **Severity:** high · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/Profiles/LayoutProfiles.swift:172`
- **Classification:** auto-fixable. One function in one file. The type's documented contract ("items the profile does not know stay where they are") defines the behaviour: merge, and skip an empty layout. No UI or policy choice. Compile-check with an Xcode build.
- **Merged from:** R05-menubar-other: "Applying a layout profile on macOS 27 replaces the whole saved layout, wiping it when the profile was saved before macOS 27 or doesn't know an app".

**Summary.** On macOS 27, `apply(_:)` overwrites `Defaults .macOS27Layout` with `profile.applicationSections`. That contradicts the type's own contract.
- `saveCurrentLayout` fills `applicationSections` from `.macOS27Layout`, which only Concealer27 writes. So every profile saved on macOS 14–26, or synced from such a Mac, holds an empty dictionary.
- Concealer27 treats an app that is missing from the layout as visible, and `macOS27LayoutSeeded` prevents reseeding.
- Apps first seen after a profile was saved on 27 are dropped from the layout as well.
- `registerUndo` only restores the profile list, not the layout.

**Evidence.**
- `LayoutProfiles.swift:120`: `Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]`
- `LayoutProfiles.swift:171-173`: `Defaults.set(profile.applicationSections, forKey: .macOS27Layout)`
- `Concealer27.swift:73-77`: apps missing from the layout are visible.
- `AccessibilityBackend27.seedLayoutIfNeeded`: guarded by `macOS27LayoutSeeded`.
- Callers that apply a profile: the profile menu, a hotkey (`HotkeyActionPerform.swift:19`), the App Intent (`HolzBarIntents.swift:160`), `holzbar://profile` (`URLCommands.swift:164`), and `applyBoundProfile` on Space switches and display connects.

**Failure scenario.** A user saves "Work" (bound to Space 1) and "Home" (Space 2) on macOS 26, then upgrades to macOS 27. The first Space switch applies the other profile, writes an empty layout, and every hidden and always-hidden item appears in the menu bar. Rebuilding the layout by hand is undone at the next switch, until every profile is saved again on 27.

**Fix.** In the macOS 27 branch of `apply(_:)`:
1. If `profile.applicationSections` is empty, skip the layout write and log it.
2. Otherwise merge: `var layout = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]; layout.merge(profile.applicationSections) { _, new in new }; Defaults.set(layout, forKey: .macOS27Layout)`.
3. Then call `concealer27.update()`.

Optionally, translate the profile's `itemSections` namespaces to bundle IDs for profiles saved before 27.

**Verification.** Confirmed high with a second vote (high). The second vote notes that `ProfileBinding.profileToApply` never re-applies the current profile, so a single bound profile does not fire on its own. Two bound profiles, or any manual apply, do. Not one of K1–K4.

### Medium

#### F-04 — macOS 26: the embedded XPC service runs with holzBar's TCC grants and is never checked, so swapping it hands those grants to other code

- **Severity:** medium · **Category:** security · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:150`
- **Classification:** manual-only. Architecture decision: move the source-PID lookup into the app (after F-12), stop starting the service, or ship with a Developer ID and notarization.
- **Merged from:** G2-bundle-integrity: "On macOS 26 the XPC service runs with holzBar's Accessibility and Screen Recording grants, and nothing checks it before launchd starts it, so replacing the service executable gives that code holzBar's permissions".

**Summary.**
- **How the grants reach the service.** TCC charges the embedded service's requests to its responsible process, holzBar. That is why the service's own Accessibility calls work. TCC checks the stored code requirement against the responsible app's main executable, not against the helper.
- **Nothing checks the service.** The service is a plain file inside a user-writable, quarantine-stripped bundle without a team identifier. Before launchd starts it:
  - the app does no static check;
  - for team-less builds, the app sets no peer requirement, and a peer requirement would only act after the code has run anyway;
  - the service's own check (`Listener.swift:76-97`) only limits who may connect to it.
- **Two routes:**
  1. Replace the file in place. Whether App Management protects this team-less bundle is untested.
  2. Copy the bundle, swap only the service, and launch the copy. TCC accepts the copy, because its main binary is genuine and the requirement is the identifier plus the certificate leaf, with no path.
- **Scope:** macOS 26 starts the service at launch; macOS 27 never starts it.

**Evidence.**
- `MenuBarItemServiceConnection.swift:150-166`: session creation, with a peer requirement only `if CodeSignature.currentTeamIdentifier != nil`.
- `ServiceBackend26.swift:31-33`: the service is started at launch.
- `SourcePIDCache.swift:139-140`: the service itself calls `AXHelpers.isProcessTrusted()`.
- The installed app, checked read-only:
  - the service executable is owned by the user;
  - `TeamIdentifier=not set`;
  - the designated requirement is `identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc…"`;
  - `spctl` rejects the app.
- `Casks/holzbar.rb:25-31`: the cask strips the quarantine attribute.

**Failure scenario.** A same-user process without any TCC grants, such as a malicious npm or pip install script in Terminal, does the following:
1. runs `ditto /Applications/holzBar.app ~/Library/Caches/x/holzBar.app`;
2. replaces the copy's `MenuBarItemService` executable with its own ad hoc-signed binary;
3. opens the copy.

On macOS 26 the copy starts the service. The attacker's code then runs with holzBar's Accessibility (synthetic input, reading other apps' UI) and Screen Recording, without a prompt.

**Fix.** Design decision. Two ways to remove the route:
- Do not run Accessibility work in separately launched nested code for team-less builds. Do the source-PID lookup in the app (the local SourcePIDCache fallback exists; fix F-12 first) and stop starting the service on macOS 26.
- Or ship with a Developer ID and notarization, so that App Management and Gatekeeper cover the bundle.

F-48 is a partial gate in the meantime: a nested-code check before each session plus a cdhash peer requirement.

**Verification.** Confirmed medium by reading the code. It was not tested end to end, which would need a TCC grant for a test bundle or a write to the installed bundle. Medium rather than high, because:
- it needs local code execution first;
- it is a general macOS weakness of nested helpers, and a Team ID or notarization does not close the copy route either;
- it is unverified end to end.

Not one of K1–K4. It remains after F-05 is fixed.

#### F-05 — Release and install builds carry get-task-allow on the app and the XPC service, so a debugger can inject code that runs with holzBar's grants

- **Severity:** medium · **Category:** security · **Affects:** build, CI and release
- **Location:** `.github/workflows/release.yml:67` (also `:120`, `Scripts/install.sh:40`)
- **Classification:** manual-only. Release, signing and install infrastructure.
- **Merged from:** R10-shared-xpc: "Release and install builds ship com.apple.security.get-task-allow on the app and the XPC service, so debuggers can inject code that runs with holzBar's Accessibility and Screen Recording grants".

**Summary.**
- The release workflow and `Scripts/install.sh` build the Release configuration with `CODE_SIGN_IDENTITY=-` (Sign to Run Locally).
- Xcode then injects `com.apple.security.get-task-allow`, because `CODE_SIGN_INJECT_BASE_ENTITLEMENTS` is not disabled.
- The certificate re-signing step keeps it, because it uses `--preserve-metadata=identifier,entitlements,flags,runtime`.
- `docs/signing.md` and the workflow comment say the entitlements are empty.

With get-task-allow, the hardened runtime lets an authorised debugger take the task port. Injected code then runs with holzBar's TCC grants. The XPC service is attributed to the app, so the same holds for it.

**Evidence.**
- `codesign -d --entitlements -` on `/Applications/holzBar.app` and on its `MenuBarItemService.xpc` prints `com.apple.security.get-task-allow = true`. This is the cask 0.0.7-beta1, build 9, Authority "holzBar Release Signing".
- `release.yml:63-67`: `CODE_SIGN_IDENTITY=-`.
- `release.yml:118-120`: `--preserve-metadata=…entitlements…`.
- `Scripts/install.sh:38-40`.
- `docs/signing.md:10`.

**Failure scenario.** A malicious same-user process on a Mac with Developer Tools access enabled runs `lldb -p $(pgrep MenuBarItemService)` (or attaches to holzBar). It loads a dylib and uses holzBar's Accessibility and Screen Recording without a prompt. Without get-task-allow, the hardened runtime refuses the attach.

**Fix.**
1. Pass `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to both xcodebuild calls, or set it for Release in both targets.
2. Drop `entitlements` from `--preserve-metadata`.
3. Add a CI check that fails when `codesign -d --entitlements - --xml` on either bundle lists any key.
4. Correct `docs/signing.md` once the build matches it.

**Verification.** Confirmed medium on the installed Homebrew release. Exploiting it needs same-user code and Developer Tools access; that access is common on developer Macs, and otherwise macOS shows an admin prompt. The slice anchored the finding at `MenuBarItemService/Resources/Info.plist:1`, but the defect lives in `release.yml` and `install.sh`.

#### F-06 — macOS 26: any app's Accessibility frames can claim a Control Center item window, making the camera and microphone indicator hideable

- **Severity:** medium · **Category:** security · **Affects:** macOS 26
- **Location:** `Shared/Services/SourcePIDCache.swift:146`
- **Classification:** manual-only. Needs an attribution policy: window owner versus AX-resolved source, scan order, and ambiguous matches. That policy spans the shared XPC service code and `MenuBarItemTag`. The quick mitigation (never hide AudioVideoModule) still needs that decision for `Item-0`.
- **Merged from:** G1-hostile-items: "macOS 26: any app's Accessibility frames can claim a Control Center item window, which makes the camera/microphone indicator hideable".

**Summary.** `updatePID(for:)` gives a window to the first app in scan order with an enabled extras-menu-bar child whose AX frame centre lies within 1 pt of the window centre.
- Nothing checks ownership, and the frames are reported by the other process itself.
- Scan order is `runningApplications` order with already-cached apps first. So login items come before Control Center, and processes started on demand (screencaptureui, or a restarted Control Center) come last.
- A misattributed AudioVideoModule window gets the claiming app's namespace.
- `canBeHidden` only protects `controlCenter:AudioVideoModule`, `screencaptureui:Item-0`, FaceTime, and AudioVideoModule in a UUID namespace. So `<app>:AudioVideoModule` passes `isValidForCaching` and the SectionRestore candidate filter.

**Evidence.**
- `SourcePIDCache.swift:146-165`: the first match within 1 pt wins.
- `MenuBarItemTag.swift:27-34`: `canBeHidden`.
- `MenuBarItemManager.swift:369` and `SectionRestore.swift:210-217`: the filters it passes.
- A probe listed login items (indices 4–7) before Control Center (11).

**Failure scenario.**
1. An app that launches at login has a status item and reports AX frames centred on Control Center's item windows.
2. When capture starts, it claims the AudioVideoModule window.
3. The next reconcile moves the privacy indicator into a hidden section if either holds:
   - "Place new items in" is set to Hidden;
   - a saved ItemSections entry exists for that key. Any same-user process can write holzBar's defaults.

**Fix.**
1. Never hide the privacy-indicator items, whatever the resolved namespace: the title AudioVideoModule, and `Item-0` and similar when the window owner is Control Center and the resolved app is not an Apple system process. Or, on macOS 26, decide `canBeHidden` for these items from the window owner.
2. In SourcePIDCache, scan Control Center and other Apple system processes first, and refuse a match when two apps claim the same centre.

**Verification.** Confirmed medium. Not high, because the attacker needs:
- crafted AX frames that track Control Center's windows;
- to win the scan ordering;
- either a Hidden new-items setting or a write to holzBar's defaults.

Whether macOS lets the indicator be pushed fully off screen was not confirmed.

#### F-07 — holzbar://search and holzbar://settings bypass Zen mode and show hidden items during screen sharing (on macOS 27 also in the real menu bar)

- **Severity:** medium · **Category:** privacy · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Core/URLCommand.swift:50`
- **Classification:** auto-fixable. The decision table lives in `holzBar/Core` and is covered by `swift test` (URLCommandTests). The fix is one function plus test cases, and it aligns the code with the documented guarantee. The defence-in-depth guards and the doc edits are optional follow-ups.
- **Merged from:** R01-core: "holzbar://search (and holzbar://settings) reveals hidden items while Zen mode is on, including automatic Zen during screen sharing"; R09-settings-main-hotkeys: "holzbar://search and holzbar://settings bypass Zen mode and put hidden items on a shared screen"; R11-scripts-build: "holzbar://search and holzbar://settings bypass Zen mode and show hidden items during screen sharing (T-06-M1 mitigation incomplete; README and SECURITY.md overstate it)"; L1-attack-surface: "holzbar://search and holzbar://settings show every hidden item while Zen mode is on (including automatic Zen during screen sharing)"; L4-privacy-permissions: "Zen mode does not cover holzbar://search and holzbar://settings: any app can show hidden and always-hidden items during screen sharing, and on macOS 27 the search also reveals concealed apps in the real menu bar".

**Summary.** `decision(zenMode:)` returns `.perform` for `.search` and `.settings` in every Zen state. `URLCommands.perform` then opens the search panel or Settings with no Zen check; only toggle and show of a hidden section are refused.
- **Search:** the panel lists every enabled section, Hidden and Always Hidden included, with names and pictures. On macOS 27, opening it runs `ItemImageStore27.photographMissing`. That calls `concealer27.showTemporarily` for up to six concealed apps, 600 ms each, and repeats while the panel stays open (within PhotoSchedule27's backoff).
- **Settings:** `holzbar://settings` reopens the pane used last. On macOS 27, `Concealer27.revealState` returns `.allRevealed` whenever Settings shows Menu Bar Layout, so every concealed item appears in the real menu bar.

This contradicts `URLCommands.swift:29` ("While Zen mode is on, no URL reveals hidden items"), SECURITY.md T-06-M1 and `Integrations/Raycast/README.md:25`. The comment at `URLCommand.swift:40` shows that letting search run was deliberate, on the reasoning that it "changes nothing lasting".

**Evidence.**
- `URLCommand.swift:40-51`: the decision table and its comment.
- `URLCommands.swift:29`, `:100-117` and `:122-126`: the guarantee and the perform paths.
- `MenuBarSearchPanel.swift:120-123` and `:316-343`: the panel and its sections.
- `MenuBarItemImageCache.swift:406-407` and `ItemImageStore27.swift:242-266`: the macOS 27 photographing.
- `Concealer27.swift:645-647`: the layout-window reveal.
- `AppNavigationState.swift:19`: `settingsNavigationIdentifier` is never reset.
- `ZenMode.swift:74`.

**Failure scenario.** The user shares their screen, so automatic Zen mode is on. Another app, or a web page the user once allowed to open holzbar:// links, opens `holzbar://search`.
- The panel appears on the shared screen with every hidden item's name and picture.
- On macOS 27, concealed apps flash into the real menu bar while the panel is open.
- If the user visited the Menu Bar Layout pane earlier, `holzbar://settings` on macOS 27 reveals every concealed item in the menu bar for the rest of the share.

**Fix.**
1. In `URLCommand.Action.decision(zenMode:)`, return `zenMode.isActive ? .refuse : .perform` for `.search` and `.settings`.
2. Add URLCommandTests cases for both with Zen active.

Defence in depth, as separate changes:
- skip `photographMissing` while Zen is active;
- let `Concealer27.revealState` ignore the layout-window reveal while Zen is active;
- set `sharingType = .none` on the search panel.

Re-check SECURITY.md T-06-M1 and the Raycast README afterwards.

**Verification.** Five slices reported this. R11-2 and L1-2 rated it medium. R01-2, R09-3 and L4-3 rated it low, because the sender must be a local app or a browser page the user already allowed. Merged at medium, because a documented privacy guarantee is broken and, on macOS 27, items are revealed in the real menu bar. The `.settings` half depends on which pane was shown last.

#### F-08 — macOS 27: while holzBar conceals items, Control Centre's microphone, camera and screen-recording indicator is suppressed, and nothing compensates

- **Severity:** medium · **Category:** privacy · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift:59`
- **Classification:** manual-only. A product and privacy design decision about a documented trade-off of macOS 27 concealment. It needs new monitoring of capture state and a setting.
- **Merged from:** L1-attack-surface: "macOS 27: while holzBar conceals any item, the camera, microphone and screen-recording indicator is suppressed, and no mitigation is attempted"; L4-privacy-permissions: "macOS 27: while anything is concealed, the camera, microphone and screen-recording privacy indicator is suppressed, and nothing compensates".

**Summary.**
- Concealment on macOS 27 uses an MBAssessmentMode assertion.
- holzBar's own measurements state that Control Centre's capture indicator (orange for the microphone, indigo for screen sharing, the green camera button) is not drawn while any assertion is live. Only the small green camera dot remains.
- Concealment is holzBar's normal state, since the hidden section is hidden by default. So for most macOS 27 users the main visible cue for microphone and screen recording is gone, including for holzBar's own ScreenCaptureKit captures.
- The limitation is disclosed in Settings and in the docs, but nothing restores the cue while capture is active.

**Evidence.**
- `MenuBarAssessmentAssertion27.swift:59-65`: the measurement.
- `GeneralSettingsPane.swift:371-395`: PrivacyIndicatorNote.
- `docs/privacy-and-permissions.md:31` and `docs/features.md:84`: the disclosure.

**Failure scenario.** On macOS 27 with hidden items concealed, a background app or a forgotten browser tab starts recording the microphone, or a process starts capturing the screen. No orange or indigo indicator appears, so the user has no visible sign of it.

**Fix.** Design decision. A mitigation without new permissions:
1. Watch capture state with property listeners: `kAudioDevicePropertyDeviceIsRunningSomewhere` on input devices, and `kCMIODevicePropertyDeviceIsRunningSomewhere` (or `AVCaptureDevice.isInUseByAnotherApplication`) on cameras.
2. While any capture runs and automatic Zen is not active, release the assertion so that Control Centre draws its indicator.
3. Conceal again when capture ends.
4. Offer this as a setting that is on by default.

**Verification.** L1-5 rated it medium. L4-4 rated it low, as a disclosed design trade-off: microphone, camera and screen capture still need per-app TCC grants. Merged at medium, given the privacy-first principle and that it affects most macOS 27 users by default. Releasing concealment during capture must respect Zen, or hidden items would be revealed during calls.

#### F-09 — The Shelf colour manager captures the screen on macOS 27 and while the Shelf is hidden

- **Severity:** medium · **Category:** privacy · **Affects:** macOS 26 and 27 (the missing macOS 27 guard is 27 only; capturing while hidden happens on both)
- **Location:** `holzBar/MenuBar/Shelf/HolzBarShelfColorManager.swift:122`
- **Classification:** auto-fixable. Guards in two files of the Shelf (`HolzBarShelfColorManager`, `HolzBarShelf.show`) that follow the approach the rest of the macOS 27 code already takes. No UI or policy choice. Needs an Xcode build and a check on macOS 27.
- **Merged from:** R05-menubar-other: "Shelf colour manager still captures the screen on macOS 27 (on every Space, screen or theme change and every 5 s while visible), overwriting the flat colour and lighting the recording indicator"; G1-hostile-items: "Shelf colour manager captures the screen on every theme or space notification without a throttle, even while the Shelf is hidden".

**Summary.** The rest of the macOS 27 code avoids screen captures for the bar colour: MenuBarManager uses `flatColor27()`, and MenuBarSearchModel's comment says "On macOS 27 a capture lights the recording indicator". HolzBarShelfColorManager has no macOS 27 guard:
- `show` calls `updateAllProperties`, which captures, before `setColor27()`.
- The 5 s timer, the frame and screen KVO, and the Space, screen-parameter and AppleInterfaceThemeChanged notifications all call `refresh()`, which captures the Menubar and wallpaper windows.
- `refresh()` captures whenever the panel's screen is the main screen, even while the Shelf is hidden. The comment at line 27 says captures happen only while the Shelf is visible.
- The manager is created at the first Shelf show and lives for the session.
- On macOS 27 the averaged capture colour also replaces the flat colour the glyphs were cut for.
- Any process can post AppleInterfaceThemeChanged, and nothing throttles it.

**Evidence.**
- `HolzBarShelfColorManager.swift:27`: the comment.
- `HolzBarShelfColorManager.swift:49-95`: the timer, KVO and notification triggers.
- `HolzBarShelfColorManager.swift:122-136` (`refresh()`) and `:138`.
- `HolzBarShelf.swift:234-237` and `:393-394`.
- `MenuBarSearchModel.swift:46`.

**Failure scenario.** On macOS 27, with Screen Recording granted, the user opens the Shelf once.
- From then on, every Space switch, display change or light/dark switch captures the screen even with the Shelf closed. That lights the recording indicator and is needless work.
- While the Shelf is open, the 5 s timer replaces the flat colour, so the panel and the glyphs no longer match.

On macOS 26, every Space switch also captures a strip while the Shelf is hidden.

**Fix.**
1. At the top of `refresh()`, add `guard shelfPanel.isVisible else { return }`.
2. On macOS 27:
   - return early from `refresh()` and from `updateAllProperties(with:screen:)`;
   - do not start the timer, the frame throttle or the notification tasks, or let them only call `setColor27()`.
3. In `HolzBarShelfPanel.show`, call `updateAllProperties` only before macOS 27, and `setColor27()` on 27.

**Verification.** R05-1 was confirmed medium. G1-6 was confirmed low: each capture is a 1 pt strip, and a tight-loop spoof is contrived. Merged at medium. Not run on macOS 27, because the host runs 26.7.1.

#### F-10 — The signing key and the signed-release pipeline can be reached from any branch or tag (repository-level secrets, no environment, no tag or branch protection)

- **Severity:** medium · **Category:** supply-chain · **Affects:** build, CI and release
- **Location:** `.github/workflows/release.yml:81`
- **Classification:** manual-only. Needs repository settings (environments, rulesets, allowed actions) and release workflow changes, which is release and signing infrastructure.
- **Merged from:** L3-supply-chain: "Release signing key and the signed-release pipeline can be reached from any branch push or tag (repo-level secrets, no environment, no tag/branch protection)"; L1-attack-surface: "Release workflow signs and ships whatever ref it is dispatched on, using actions pinned only by mutable tags".

**Summary.**
- `SIGNING_CERTIFICATE_P12` and its password are repository-level secrets. The release job has no `environment:`, so a workflow pushed to any branch can read them.
- Any `v*` tag on any commit, or a `workflow_dispatch` from any ref, builds that ref and signs it with the persistent certificate. That certificate's designated requirement keeps users' Accessibility grants. The job then publishes the build and force-updates the cask on main.
- Read-only API calls show:
  - no environments;
  - only a "No force push" ruleset for branches, and nothing for tags;
  - main is unprotected;
  - `allowed_actions: all`, with no SHA pinning.
- `actions/checkout@v7` and `actions/attest-build-provenance@v4` are pinned by tag.
- A tag release also skips build.yml's checks.
- Agent sessions already push branch workflows that run (`xcode-probe.yml` on `claude/ice-fork-development-hzdl1d`).
- `docs/signing.md:91` says a leaked certificate cannot be revoked.

**Evidence.**
- `release.yml:2-9`: the triggers.
- `release.yml:16-25`: no `environment:`.
- `release.yml:82-84`: the secrets in `env`.
- `release.yml:183-197`: the release at `$GITHUB_SHA` and the push to main.
- The read-only GitHub API results above.
- `SECURITY.md:36`: T-06-L7, Low, Open.

**Failure scenario.**
- A prompt-injected agent session or a leaked maintainer token pushes a branch with a workflow that sends the p12 and its password to an external host. The attacker then signs a trojan holzBar.app that satisfies the TCC designated requirement and inherits users' existing Accessibility grants. The key cannot be revoked.
- Or it pushes tag v0.0.8 on an unreviewed commit, and every `brew upgrade` user installs that build.

**Fix.**
1. Create an environment `release` whose deployment policy allows only `v*` tags, optionally with a required reviewer.
2. Move both signing secrets (and `CMS_TOKEN`) into that environment, and add `environment: release` to the release job.
3. Add a tag ruleset on `refs/tags/v*` that limits creation, update and deletion to the admin.
4. Protect main with pull requests and required checks. Limit the github-actions bypass to the cask commit, or bump the cask through a pull request.
5. Guard the job with `if: startsWith(github.ref, 'refs/tags/v')`, or drop `workflow_dispatch`.
6. Check `git merge-base --is-ancestor "$GITHUB_SHA" origin/main`.
7. Set allowed actions to selected, and pin actions by commit SHA.

**Verification.** L3-1 was confirmed medium. Exploiting it needs the sole maintainer's write credential or an agent session with push rights; pull requests from forks get no secrets. L1-8 was confirmed low. This extends SECURITY.md T-06-L7 with a worse consequence: a permanent signing key that cannot be revoked.

#### F-11 — Missing signing secrets fail open (an ad hoc release reaches every cask user), and the certificate fingerprint is never pinned

- **Severity:** medium · **Category:** supply-chain · **Affects:** build, CI and release
- **Location:** `.github/workflows/release.yml:87`
- **Classification:** manual-only. Release and signing infrastructure.
- **Merged from:** L3-supply-chain: "Missing signing secrets fail open: the release is published ad hoc and pushed to every cask user; the certificate identity is never pinned".

**Summary.**
- When either secret is empty, the signing step prints a warning and runs `exit 0`. Packaging, attestation, `gh release create` and the cask bump still run.
- `docs/signing.md:85` recommends moving the secrets into an environment, but the job has no `environment:` key. Following that advice therefore makes every later release ad hoc.
- The leaf fingerprint is only printed (`release.yml:142-146`), never compared with the published e55f0df1…. A replaced p12 therefore changes holzBar's identity without failing anything.

**Evidence.** `release.yml:87-91` and `:142-146`; `docs/signing.md:85`.

**Failure scenario.**
1. The maintainer moves the secrets into environment `release`, as documented, and tags v0.0.7.
2. The job sees empty secrets, publishes an ad hoc zip and bumps the cask.
3. Every `brew upgrade` user loses Accessibility and Screen Recording, because the designated requirement becomes a cdhash.
4. Everyone has to grant them again, which is the habit T-06-M4 was meant to stop.

**Fix.**
1. Fail the step (`exit 1`) when the secrets are missing in holzcloud/holzBar.
2. Add `EXPECTED_CERT_SHA256: e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`, and fail when the fingerprint differs.
3. Add `environment: release` together with the docs change (see F-10).

**Verification.** Confirmed medium. The fail-open branch predates the certificate. Now that 0.0.6 is signed, it is a regression hazard.

#### F-12 — macOS 26 local fallback: the main-thread running-apps observer blocks on the lookup lock while a scan waits for holzBar's own Accessibility replies

- **Severity:** medium · **Category:** concurrency · **Affects:** macOS 26
- **Location:** `Shared/Services/SourcePIDCache.swift:192`
- **Classification:** manual-only. The code is shared by the app and the XPC service and has no test coverage. Skipping holzBar's own process would break attribution of its group and spacer items in the fallback, because OwnStatusItemWindows only covers control items. So the fix needs a design choice, and it is a concurrency change in the fallback path.
- **Merged from:** R10-shared-xpc: "In the app's local fallback (macOS 26), the main-thread runningApplications observer waits on the lock held by an Accessibility scan that is waiting for holzBar's own main thread, freezing the UI for about 6 s"; L4-privacy-permissions: "macOS 26 fallback lookup can freeze the main thread: the running-apps KVO handler waits on a lock that a background thread holds while it sends Accessibility requests to holzBar itself"; L5-concurrency: "SourcePIDCache keeps its lock through whole Accessibility scans; in the app's fallback mode the main-thread KVO handler then deadlocks against holzBar's own Accessibility replies".

**Summary.**
- When the XPC service cannot be reached, `MenuBarItemService.Connection` runs SourcePIDCache inside holzBar on `localQueue`.
- `pid(for:)` holds the cache's unfair lock for a whole `updatePID` scan. A scan includes up to 150 ms of `Thread.sleep` in `stableBounds` and AX reads of every app with an extras menu bar, with the default 6 s timeout.
- NSWorkspace delivers `runningApplications` KVO on the main thread, and `update(runningApps:)` takes the same lock.
- holzBar is an accessory app with status items, and `partitionApps` puts it first. So scans ask holzBar's own process, and AppKit answers those requests on the main thread.
- If an app launches or quits during such a scan, the main thread waits for the lock while the scan waits for the main thread, until each request times out.

K1's fix moved the XPC wait off the main thread, but it left this lock shared with a main-thread handler.

**Evidence.**
- `SourcePIDCache.swift`:
  - 114: the sleep inside the lock
  - 126 and 148-165: the scan
  - 192-195: the KVO handler
  - 204: `update` takes the lock
  - 239-256: `pid(for:)` holds it
- `MenuBarItemServiceConnection.swift:105-123`: `switchToLocalCache` and `BlockingWork.run(on: localQueue)`.
- `AXHelpers.swift:66-76`: no messaging timeout.
- `BlockingWork.swift:13-17`: describes the same self-Accessibility deadlock for the XPC path.

**Failure scenario.**
1. On macOS 26.7.1 the service is not reachable (the documented case), so holzBar uses the local cache.
2. The user opens the Shelf, which triggers lookups, and an app launches at the same moment.
3. The main thread blocks in `update(runningApps:)` while the scan is inside `AXHelpers.children(for:)` on holzBar's own extras menu bar.
4. holzBar freezes for several seconds, and freezes again whenever the app list changes during a scan.

**Fix.**
1. Do not take the lock on the main thread: hand `update(runningApps:)` to a private serial queue, or to the queue that runs lookups.
2. Scan without holding the lock: take a snapshot of the apps, scan, then commit `pids` and `failedLookups` under the lock.
3. Give the per-app elements a short messaging timeout.

Skipping holzBar's own process in the scan would also remove the self-request. That is only safe once all of holzBar's own status items are matched before the lookup: groups and spacers too, not only the control items OwnStatusItemWindows recognises.

**Verification.** L4-1 and L5-7 rated it medium. R10-4 rated it low: fallback mode only, plus a timing overlap, and the freeze is bounded rather than a permanent deadlock. Merged at medium. The synthesizer checked that OwnStatusItemWindows covers only ControlItem identifiers, so the slices' "skip the own process" fix would misattribute group and spacer items in the fallback. Not K1 or K3: a different lock in a different type.

#### F-13 — One stuck window capture wedges the serial capture queue for the session: images stop updating and search and Shelf stop opening

- **Severity:** medium · **Category:** concurrency · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:71`
- **Classification:** manual-only. How to recover from a wedged OS capture call (a watchdog, replacing the queue, abandoning the stuck thread) is a design decision, and the hang can only be reproduced on macOS 26.
- **Merged from:** R03-menubaritems: "A capture that never returns stalls the serial capture queue for the rest of the session"; L5-concurrency: "One stuck capture wedges the serial image-capture queue for the rest of the session; waiters pile up and the search panel never appears".

**Summary.**
- All CGWindowList captures run on one serial DispatchQueue, through a `withCheckedContinuation` that cannot be cancelled.
- The code itself documents that on macOS 26 a capture of an item off the edge of the bar can block forever. It chose a serial queue so that a stuck capture costs only one thread, but it does not account for every later capture queueing behind the stuck one.
- Nothing limits pending requests. The 3 s refresh loop and each throttled `requestUpdate` start another `Task { await self?.updateCache() }`, which then suspends forever.
- Individual captures, used for composite-excluded items and for 2 s after any move, capture off-screen hidden items one by one.
- MenuBarSearchPanel installs its content only after `await updateCache()`, and the Shelf's wait cannot time out (F-01).

**Evidence.**
- `MenuBarItemImageCache.swift:49-79`: the comment and the queue.
- `MenuBarItemImageCache.swift:207-216`: the 3 s loop.
- `MenuBarItemImageCache.swift:220-225`: the throttled update.
- `MenuBarItemImageCache.swift:341-343`: the individual path after moves.
- `MenuBarSearchPanel.swift:122-128`.

**Failure scenario.** On macOS 26 the user opens the Shelf right after an item move. The individual-capture path captures a hidden item, and the call never returns. From then on, until relaunch:
- no item image updates;
- the search panel opens empty or not at all;
- the Shelf no longer opens;
- a suspended task leaks every 3 s while a panel is shown.

**Fix.**
1. Allow one capture in flight: while one is pending, return the cached images instead of queueing another.
2. Add a watchdog. When a capture has not returned after about 2 s, resume its waiter with an empty result (behind a resume-once guard), and send later captures to a fresh serial queue.
3. Do not individually capture items whose live bounds lie outside every display.
4. In `MenuBarSearchPanel.show`, install the hosting view before awaiting the cache.

**Verification.** R03-8 rated it low: how often captures hang is unproven, and the composite capture uses the same API on the same windows. L5-9 rated it medium. Merged at medium, because one hang disables images, search and the Shelf for the session.

#### F-14 — NSAlert.runModal() inside main-actor Tasks blocks all main-actor work while the alert is open (macOS 27 system-item clicks are swallowed)

- **Severity:** medium · **Category:** concurrency · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Utilities/SettingsSync.swift:452`
- **Classification:** manual-only. Cross-cutting: it changes how alerts are presented at about six call sites in several subsystems.
- **Merged from:** L5-concurrency: "NSAlert.runModal inside main-actor Tasks blocks all main-actor work while the alert is open (macOS 27 system-item clicks are swallowed)".

**Summary.** A nested run loop started inside a main-queue job does not drain the main dispatch queue, because CFRunLoop does not service it re-entrantly. So every other main-actor job waits until the modal ends: Tasks, continuation resumptions, ObservationLoop callbacks, debouncers.

Several alerts run from async main-actor code:
- `SettingsSync.checkForNewerSettings`, triggered remotely when another Mac writes the sync file and brought up with `NSApp.activate()`;
- `MenuBarItemManager.temporarilyShow` ("Not enough room…", line 901);
- `LayoutBarPaddingView.swift:161`;
- `LayoutBarItemView.swift:466` and `:472`;
- `GeneralSettingsPane.swift:360`;
- `SettingsBackup.swift:130` and `:170`.

Event taps still fire while the modal runs. So SystemItemClickBridge27 keeps holding clicks back, but the Task that lifts concealment and replays them cannot run.

**Evidence.**
- `SettingsSync.swift:383-392` and `:432-455`.
- `SystemItemClickBridge27.swift:123-176`.
- The call sites listed above.
- Probes: L5-5's own, and the synthesizer's `scratchpad/audit-synth/modal.swift`. A 1.5 s modal-panel run loop started from a main-actor Task let no other main-actor task or main-queue block run until it ended. The same loop started from `RunLoop.main.perform` let them run.

**Failure scenario.** Another Mac writes a newer `Settings.plist`. holzBar shows "Settings changed on another Mac", and the user leaves the alert open.
- On macOS 27, clicks on the clock, battery, Wi-Fi or Control Centre while items are concealed are swallowed and replayed only after the alert closes.
- Meanwhile hover, click-to-show, ItemClicker27 and concealment updates freeze.
- On macOS 26, the image cache, item refreshes and Shelf actions freeze too.

**Fix.** Do not call `runModal()` from async or Task contexts. Instead:
- present alerts as sheets (`beginSheetModal(for:)`), or as non-modal panels whose buttons continue the work; or
- start the modal from a run-loop source (`RunLoop.main.perform(inModes: [.default]) { … runModal() … }`). The synthesizer's probe showed that main-actor work keeps running in that case.

Start with the remotely triggered sync alert.

**Verification.** Confirmed medium. The remote trigger (the sync file) is what makes this matter; the other call sites are started by the user.

#### F-15 — Settings sync does coordinated file I/O on the main thread, so a dataless file, a hung file provider or a stalled volume blocks launch and the UI

- **Severity:** medium · **Category:** concurrency · **Affects:** all versions
- **Location:** `holzBar/Utilities/SettingsSync.swift:336`
- **Classification:** manual-only. The launch pull is deliberately synchronous, so that nothing reads settings before they are applied. Skipping, deferring or bounding it is a design decision, and it interacts with the sync redesign in F-02.
- **Merged from:** L5-concurrency: "Settings sync does coordinated file I/O and bookmark resolution synchronously on the main thread, including for network shares"; R09-settings-main-hotkeys: "Launch reads the sync file synchronously on the main thread, which hangs while an online-only file downloads".

**Summary.**
- **Launch.** `pullIfNeeded()` runs in `AppDelegate.init`, before any scene exists. It does an `NSFileCoordinator` read plus open and read on the main thread. Its comment says the size limit keeps the read short, which assumes a local file.
- **Push.** `push()` runs on the main actor 5 s after any defaults change, and when sync is turned on. It runs `lstat`, `createDirectory` and a coordinated `.forReplacing` write synchronously.
- **Why that blocks.** The type explicitly supports:
  - iCloud Drive with Optimize Storage;
  - File Provider folders (Nextcloud, Dropbox, OneDrive);
  - network shares.

  In these, a file written by another Mac is often dataless, and a coordinated read waits for its download. A hung provider or volume stalls the write.

Bookmark resolution and mounting are covered separately in F-18.

**Evidence.**
- `AppDelegate.swift:18`: the launch pull.
- `SettingsSync.swift:292-366`: push, with the coordinated write at 336-366.
- `SettingsSync.swift:380-404`: `readFileContents`.
- `SettingsSync.swift:412-429`: `pullIfNeeded` and its comment.

**Failure scenario.** Sync uses a OneDrive folder, and another Mac updated `Settings.plist`, which arrives online-only.
- At login without network, holzBar blocks in `AppDelegate.init` on the coordinated read and shows no menu bar icon until the provider gives up.
- Later, with a hung provider, toggling any setting stalls the main thread for the coordination timeout. On macOS 27, every click on the Mac waits behind holzBar's HID tap meanwhile.

**Fix.**
1. Build the plist on the main actor, but do the folder check, `createDirectory` and the coordinated write in a `@concurrent nonisolated` function, as `readFileContentsInBackground` already does. Publish `lastPushedData` and the last-synced date back on the main actor.
2. At launch, skip the pull when the file is not local, and leave it to the background check. Not local means `ubiquitousItemDownloadingStatus` is not `.current`, or `SF_DATALESS` is set, or the volume is not `volumeIsLocal`. Alternatively, bound the launch pull with a short timeout.
3. Design this together with F-02.

**Verification.** L5-6 rated it medium. R09-7 rated it low: the file is small, and an offline provider usually fails rather than waits. Merged at medium.

#### F-16 — Accessibility observer registration runs on the main thread with no messaging timeout, stalling holzBar and, on macOS 27, every click

- **Severity:** medium · **Category:** concurrency · **Affects:** macOS 26 and 27 (mainly 27)
- **Location:** `holzBar/MenuBar/MacOS27/ItemChangeObserver27.swift:59`
- **Classification:** manual-only. The fix spans the macOS 27 observer and the shared ItemChangeWatcher. Shortening the timeout on the provider's shared element conflicts with a deliberate choice for presses (see F-57), and the retry backoff needs a policy.
- **Merged from:** L5-concurrency: "Accessibility calls to other apps on the main thread with no messaging timeout (ItemChangeObserver27, ItemChangeWatcher) stall the macOS 27 click tap".

**Summary.**
- `ItemChangeObserver27.addObserver` runs on the main actor on every cache refresh (`AccessibilityBackend27.swift:71`). It calls `AXObserverAddNotification` twice on a fresh `AXUIElementCreateApplication(pid)`, with the default timeout of about 6 s.
- When both calls fail, the observer is discarded and the registration is retried on the next refresh.
- On macOS 27, `ItemChangeWatcher.observe` registers on MenuBarItemProvider27's stored element, which also has no short timeout, although its comment says "Every call to the app waits 0.25 s at most".
- SystemItemClickBridge27's HID filter tap is serviced on the main run loop. So while the main thread waits, clicks everywhere on the Mac wait for holzBar.

This contradicts the project's own rule against Accessibility reads on the main thread (`MenuBarItemProvider27.swift:122-126`).

**Evidence.**
- `ItemChangeObserver27.swift:51-67`.
- `AccessibilityBackend27.swift:71`.
- `ItemChangeWatcher.swift:126`, `:133-135` and `:158-160`.
- `EventTap.swift:197`.
- `SystemItemClickBridge27.swift:45-49`.

**Failure scenario.** On macOS 27 an app adds its status item, then spends seconds finishing its launch. The launch refresh registers the observer and blocks holzBar's main thread for up to 2 × 6 s.
- Clicks lag system-wide.
- Hover and the Shelf freeze.
- If the registration fails, it is repeated on the next refresh.

**Fix.**
1. In `addObserver`, call `AXUIElementSetMessagingTimeout(application, 0.25)` before the registrations.
2. Remember PIDs whose registration failed and retry them with a backoff, instead of on every refresh.
3. In ItemChangeWatcher on macOS 27, register off the main thread, or set a short timeout on the shared element around the calls and reset it to `0` afterwards, so ItemClicker27's presses keep the default (see F-57).

**Verification.** Confirmed medium. Limits:
- The trigger needs an app that answered the off-main scan within 0.5 s but is busy at registration time; that is plausible during launch.
- ItemChangeWatcher only covers items marked to reveal on change.
- On macOS 26 its reads are bounded at 0.25 s.

#### F-17 — Launches and quits of menu bar agents go unnoticed: automatic Zen misses Screen Sharing, and macOS 27 concealment keeps newly launched Visible agents hidden

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/PresentationMonitor.swift:64`; `holzBar/MenuBar/MacOS27/Concealer27.swift:87`
- **Classification:** manual-only. Two subsystems. On macOS 27 every launch of a background agent would now reach the concealer (allowlist rebuilds, launch grace), which needs a filtering decision and verification on macOS 27. The PresentationMonitor half is small and can be done first.
- **Merged from:** R05-menubar-other: "Automatic Zen mode misses the start and end of screen sharing: the launch/terminate notifications are not posted for background agents"; R02-macos27: "Concealment allowlist misses menu bar agents (LSUIElement apps) that launch while concealing, so they stay hidden".

**Summary.** NSWorkspace posts `didLaunch`/`didTerminateApplicationNotification` only for regular apps. For LSUIElement and background apps, only the KVO on `runningApplications` changes. Probes on this Mac confirmed this for both launch and quit.
- **PresentationMonitor** checks for `com.apple.screensharing.agent` (which has LSUIElement = 1) only on those notifications or on screen changes. So the start and end of a Screen Sharing session are noticed only when some unrelated regular app launches or quits.
- **Concealer27** rebuilds its allowlist (running apps minus concealed apps, a snapshot of `runningApplications` taken at update) only on the same notifications plus section, settings, fullscreen and settle events.
  - MenuBarItemManager's KVO reaches `update()` only for brand-new bundle IDs placed in a non-Visible section.
  - LaunchGrace27 never starts for agents either.

**Evidence.**
- `PresentationMonitor.swift:56-74`.
- `Concealer27.swift:87-99` and `:204-206`.
- `ConcealmentPlanner27.swift:46-47`.
- `MenuBarAssessmentAssertion27.swift:17`.
- Probe output: an LSUIElement app produced only the KVO change and no notifications; a regular app produced both.

**Failure scenario.**
- With "Turn on Zen mode while the screen is mirrored or shared" on, someone connects with Screen Sharing. Zen stays off, so hover, scroll, reveal rules or a change reveal can show hidden items to the viewer. Afterwards, Zen can stay on until another app launches or quits.
- On macOS 27, a Visible menu bar agent that starts after holzBar (a login item) or relaunches stays hidden, and is squashed to 3 pt, until some other event calls `update()`.

**Fix.** In both places, observe `NSWorkspace.shared.runningApplications` with KVO (`[.old, .new]`); this is event-driven.
- **PresentationMonitor:** call `evaluate()` on every change while the setting is on. This part is small and can go first.
- **Concealer27:**
  - diff the bundle-ID sets;
  - call `applicationDidLaunch(bundleID:)` for each added ID;
  - run the terminate handling (clear `notchConcealed`, call `update()`) for removed IDs;
  - drop or deduplicate the notification observers;
  - decide how to filter background helpers that never own a status item, so the concealer is not rebuilt for every helper launch.

**Verification.** Both were confirmed medium. R05-10's verifier reproduced the notification behaviour with a probe on macOS 26. The concealer effect is temporary, because any regular app launch, section toggle, fullscreen change or settle rebuilds the allowlist, but it can last a long time.

#### F-18 — The sync-folder bookmark is resolved without .withoutMounting on every access, so holzBar mounts network shares itself and blocks while the mount times out

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Utilities/SettingsSync.swift:85`
- **Classification:** auto-fixable. One option at one call site (add `.withoutMounting`), plus caching the resolved URL, all in one file. The failure path (`.failed`) already exists. Needs an Xcode build.
- **Merged from:** R07-utilities-permissions-events: "Resolving the sync-folder bookmark without .withoutMounting can mount a network share and block the main thread at launch and in a SwiftUI body"; L2-untrusted-data: "The sync folder bookmark is resolved on the main thread, at launch and in a SwiftUI body, without .withoutMounting, so network shares are mounted and can hang the app"; L4-privacy-permissions: "Sync folder bookmark is resolved without .withoutMounting on the main thread, so holzBar itself mounts network shares and blocks launch and UI".

**Summary.**
- `syncFolderURL` is a computed static property that resolves the stored bookmark on every access, with only `[.withoutUI]`.
- Without `.withoutMounting`, resolution mounts the bookmark's volume when it is not mounted.
- It runs on the main thread from:
  - `AppDelegate.init` (through `pullIfNeeded`);
  - every push and check;
  - `updateObservers` and `chooseFolder`;
  - `folderDisplayName`, which the Advanced pane reads in its view body.
- Network shares are an advertised sync target. holzBar then opens SMB, AFP or NFS connections on its own, which goes against the "never connects to the network" principle, and the main thread waits for the mount attempt.
- The code already expects resolution to fail when a volume is not mounted (`SettingsSyncLocation.Resolution.failed`).

**Evidence.**
- `SettingsSync.swift`:
  - 80-107: the resolution
  - 112: `storeBookmark`
  - 120-140: `folderURL`, `fileURL` and `folderDisplayName`
  - 417-421: `pullIfNeeded`
- `AdvancedSettingsPane.swift:316` and `:329`.
- `docs/features.md:59` and `docs/privacy-and-permissions.md:23`: network shares are advertised.

**Failure scenario.** A laptop user syncs through `smb://nas/home` and logs in away from home. `AppDelegate.init` resolves the bookmark, NetFS tries to mount the unreachable server, and holzBar shows nothing until that times out. Every redraw of Settings › Advanced and every push repeats it.

**Fix.**
1. Resolve with `[.withoutUI, .withoutMounting]`. Treat a failure as "folder not available" (the existing `.failed` path), and do not rewrite the bookmark.
2. Resolve once and cache the URL in the instance. Refresh it in `chooseFolder()` and on `NSWorkspace.didMountNotification` and `didUnmountNotification`, never in a view body.

**Verification.** All three slices confirmed it medium. Only users who chose a network-share folder are affected. One sentence cited as evidence (that the NSOpenPanel message names network shares) is wrong, but the share is advertised elsewhere.

#### F-19 — CGSSpaceGetType is declared with a Swift enum return type, so fullscreen spaces are never detected on macOS 26 and 27

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `Shared/Bridging/Shims.swift:101`
- **Classification:** auto-fixable. An ABI fix in two files of `Shared/Bridging`: declare `UInt32`, then map with `rawValue`. Verify fullscreen handling on macOS 26 afterwards, because those paths have effectively never run.
- **Merged from:** R10-shared-xpc: "CGSSpaceGetType is declared to return a Swift raw-value enum, so fullscreen spaces are never detected and system spaces are reported as fullscreen".

**Summary.**
- The private C function returns a 32-bit integer: 0 user, 2 system, 4 fullscreen.
- The shim binds it with `@_silgen_name` and declares the return type as the Swift enum `CGSSpaceType: UInt32`. Swift passes that enum as a one-byte case index, not as its raw value.
- So C value 2 becomes `.fullscreen`, and C value 4 matches no case (undefined behaviour).
- `Bridging.isSpaceFullscreen` therefore returns false for real fullscreen spaces.

Every consumer of `activeSpace.isFullscreen` is affected:
- Concealer27: holzBar's own item goes missing from the fullscreen bar, by its own comment;
- MenuBarOverlayPanel's validate step;
- MenuBarItemContainer;
- InputMonitors;
- SystemItemClickBridge27's visible-bar rectangle, on Macs with a notch;
- partly MenuBarOverlayPanel:343, HIDEventManager:284 and MenuBarManager:242, which the presentation-options signal covers.

**Evidence.**
- `Shims.swift:14-18` and `:101-105`: the enum and the binding.
- `Bridging.swift:252-255`: `isSpaceFullscreen`.
- `SpaceInfo.swift:21`, plus the consumers listed above.
- Two independent probes: C values 0, 2 and 4 compare as `.user`, `.fullscreen` and no case.

**Failure scenario.** On macOS 26 or 27 the user makes an app fullscreen.
- The overlay keeps tinting the bar.
- Concealer27 does not run again on the transition.
- The container draws no black fullscreen background.
- The click bridge computes the bar from `visibleFrame` and misses part of a bar with a notch.

**Fix.**
1. Declare `@_silgen_name("CGSSpaceGetType") nonisolated func CGSSpaceGetType(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> UInt32`.
2. Map the result in Bridging with `CGSSpaceType(rawValue: …) == .fullscreen`.
3. As a rule, never use a Swift enum in an `@_silgen_name` C signature.
4. Then test fullscreen handling on macOS 26, because these paths have effectively never run.

**Verification.** Confirmed with a second vote (medium). The second vote downgraded it from high, because the presentation-options signal covers the most visible consumers. Normal spaces return 0 on this Mac. A fullscreen space was not created, to avoid changing the user's session.

#### F-20 — Smart rehide (the default) never fires without Screen Recording, because it only considers windows that have a title

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Events/HIDEventManager.swift:434`
- **Classification:** auto-fixable. One guard in one function. Window bounds, layer and owner are available without Screen Recording.
- **Merged from:** R07-utilities-permissions-events: "Smart rehide needs window titles, which macOS gives only with Screen Recording, so the default rehide never fires without that optional permission".

**Summary.**
- The smart strategy finds the clicked window with `$0.title?.isEmpty == false`.
- `WindowInfo.title` is `kCGWindowName`, which macOS withholds for other apps' windows when the app lacks Screen Recording.
- Screen Recording is optional in holzBar (`isRequired: false`), and ScreenRecordingFeature does not list smart rehide.
- With only Accessibility, no window matches, the guard returns, and the sections never hide after a click outside.
- No other code path implements `.smart`.

**Evidence.**
- `HIDEventManager.swift:432-440`: the guard.
- `Shared/Utilities/WindowInfo.swift:61`: `title` comes from `kCGWindowName`.
- GeneralSettings defaults: `autoRehide = true`, `rehideStrategy = .smart`.
- `Permission.swift:269` and `ScreenRecordingFeature.swift`.

**Failure scenario.** A fresh install with default settings and only Accessibility granted, as the permissions window suggests. The user shows the hidden items and clicks into Safari. The items stay visible indefinitely.

**Fix.**
1. Drop the title requirement.
2. Take the topmost on-screen window at the click point with `layer == 0`, or one owned by `com.apple.dock`.
3. Keep the existing owner, `isActive` and activation-policy checks.

Bounds, layer and owner PID are available without Screen Recording.

**Verification.** Confirmed medium. This affects the default setup on macOS 26 and 27.

#### F-21 — With Caps Lock on, every item move and click on macOS 26 waits indefinitely and replays later

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift:39`
- **Classification:** auto-fixable. Masking the modifier flags is mechanical, and bounding the wait is a contained change in one file. The only choice is the deadline value. The same file is edited by F-01, so coordinate the two fixes.
- **Merged from:** R04-backends-controlitem: "Caps Lock (or any latched modifier) blocks all item moves and clicks indefinitely, then replays them later".

**Summary.**
- `hasUserPausedInput` requires `NSEvent.modifierFlags.isEmpty`. That class property includes `.capsLock` while Caps Lock is engaged.
- `waitForUserToPauseInput` polls in an unstructured Task with no deadline. The caller awaits `waitTask.value` without a cancellation handler, so the wait can neither time out nor be cancelled.
- Every `move()` and `click()` waits here, and `rehideTemporarilyShownItems` uses the same check.

**Evidence.**
- `MenuBarItemEventPoster.swift:39-44` and `:47-62`: the check and the polling wait.
- `MenuBarItemEventPoster.swift:656` and `:803`: `move()` and `click()` wait here.
- `MenuBarItemManager.swift:993`: the rehide check.

**Failure scenario.** On macOS 26 with Caps Lock on, the user clicks a hidden item in the Shelf or in search.
- Nothing happens, and each further click adds another endless polling task.
- Temporarily shown items are never rehidden.
- When Caps Lock goes off, all queued moves and clicks run, and menus open long after the user gave up.

**Fix.**
1. Compare only the modifiers the user holds: `NSEvent.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty`. Ideally make this one shared helper, also used by F-86.
2. Loop directly in the calling task instead of an inner unstructured Task.
3. Bound the wait, for example by throwing `EventError.cannotComplete` after about 5 s.

**Verification.** Confirmed medium by reading the code. The Caps Lock state of `NSEvent.modifierFlags` was not toggled at runtime here.

#### F-22 — Rehiding a temporarily shown item targets a stored neighbour snapshot; if that window is gone, rehide fails forever and keeps tripping MoveBackoff

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1030`
- **Classification:** auto-fixable. One file. Resolve the neighbour again from the fresh item list, with the section-based fallback the code already uses elsewhere. Needs an Xcode build and a check on macOS 26.
- **Merged from:** R03-menubaritems: "Rehide never refreshes the return destination; a vanished neighbour makes the item undismissable and trips MoveBackoff forever".

**Summary.**
- `temporarilyShow` stores `returnDestination = .leftOfItem(items[index + 1])`, a MenuBarItem snapshot of the right neighbour.
- `rehideTemporarilyShownItems` finds the shown item again, but always moves it to that stored destination.
- `MenuBarItemEventPoster.move` first calls `itemHasCorrectPosition`, which throws `missingItemBounds` for a window that has vanished. That throw happens outside the retry loop.
- The context then cycles through immediate retries, failedContexts and the 3 s rehide timer indefinitely. Each attempt is counted by `checkAutomaticMove` and `recordFailure`.
- So MoveBackoff pauses all automatic moves for 60 s, doubling up to 600 s, again and again.
- `ItemCache.insert` also drops the item silently when its target has no address.

**Evidence.**
- `MenuBarItemManager.swift:292-315`: `ItemCache.insert`.
- `MenuBarItemManager.swift:812-823`: `getReturnDestination`.
- `MenuBarItemManager.swift:960-1054`: the rehide.
- `MenuBarItemEventPoster.swift:672`: the throw.

**Failure scenario.** The user opens a hidden item from the Shelf. Before the rehide, its right neighbour's app quits, relaunches, updates or re-creates its status item. For the rest of the session:
- the item stays in the visible section;
- it disappears from the Layout pane and the Shelf;
- new-item placement, section restore, divider ordering and profile moves stay paused most of the time.

**Fix.**
1. Store the neighbour's windowID, tag or identity key, and the original section, in the context.
2. At rehide, resolve the neighbour again from the fresh items: by windowID, then tag, then identity key.
3. If it is gone, use a section destination: `.leftOfItem(hidden control item)` for Hidden, and the always-hidden control item for Always Hidden.
4. Use the same fallback in `ItemCache.insert`.
5. Optionally, drop the context after N failed cycles.

**Verification.** Confirmed medium. The trigger is narrow, but the effect lasts the whole session.

#### F-23 — Stored identity keys of the second and later untitled items of an app never match their current key

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 (also 14 and 15)
- **Location:** `holzBar/Core/ItemIdentity.swift:98`
- **Classification:** auto-fixable. `holzBar/Core`, with existing ItemIdentity tests. The round-trip property is directly testable.
- **Merged from:** R01-core: "Stored identity keys of the 2nd and later untitled items of one app never match their current key".

**Summary.**
- With an empty canonical title, `keys(for:)` keys the second item of a namespace `ns:2`.
- `storedKey` cannot turn that key back into itself:
  1. it splits at the first colon, giving the title "2";
  2. the `/(.*):(\d+)/` occurrence pattern does not match;
  3. it falls through to `ns:#`.
- Every stored key goes through `storedIdentityKey`, so the stored and the current key never match.
- On macOS 26, titles are empty for every item when Screen Recording is not granted, because Control Center owns the windows and macOS hides their names. That is a supported setup.
- macOS 27 is not affected.

**Evidence.**
- `ItemIdentity.swift:83-112`: `keys(for:)` and `storedKey`.
- `SectionRestore.swift:97` and `:220`, `LayoutProfiles.swift:184`: stored keys.
- `MenuBarItem.swift:323`: the title source.
- A probe on the real file mapped the keys `["com.example", "com.example:2"]` back to `["com.example", "com.example:#"]`.

**Failure scenario.** A macOS 26 user without Screen Recording. Every second and later item of a namespace, such as Control Center's items or an app with several items:
- counts as new on each read and is moved to the new-items section;
- causes `knownItemTags` to be rewritten on each read;
- is never found by profiles, groups, custom icons and Open-Item hotkeys.

The moves repeat until MoveBackoff trips.

**Fix.**
1. In `storedKey`, return `stored` unchanged when the title part is all digits: `if title.wholeMatch(of: /\d+/) != nil { return stored }`. Alternatively, give empty-titled occurrences their own form in `keys(for:)` (for example `ns::2`) and recognise it.
2. Add a HolzBarCore test asserting `storedKey(k) == k` for every key `keys(for:)` produces for empty titles.

**Verification.** Confirmed medium with a probe built from the real file. The existing tests cover only non-empty titles.

#### F-24 — Stale saved-section keys are never pruned and collide with current keys, so restore can move items back into old sections

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:97`
- **Classification:** auto-fixable. One file: normalise the keys on save and make the read deterministic.
- **Merged from:** R03-menubaritems: "Stale saved-section keys are never pruned and collide with new keys; a random one wins on each launch".

**Summary.**
- `saveSections` and `storeSections` only add or overwrite entries; nothing is ever removed.
- `savedSections()` maps every stored key through `storedIdentityKey` into a new dictionary. When several stored keys map to the same current key, the last one iterated wins, and Swift dictionary order is seeded per process.
- Typical case:
  1. the first run stores `ns:<canonical title>`;
  2. the app is later learned as title-changing and keyed `ns:#1`;
  3. the old key also maps to `ns:#1`.
- Old raw-title keys from earlier versions or from Ice collide the same way.

**Evidence.**
- `SectionRestore.swift:46-68` and `:93-102`.
- `ItemIdentity.swift:107-112`.
- `MenuBarItemManager.swift:529`.

**Failure scenario.**
1. After the first save, a clock or monitor item is learned as title-changing.
2. The user drags it from Hidden to Visible, so `ns:#1` says visible while the stale entry still says hidden.
3. On some launches, app launches or settles, the stale value wins, and reconcileSections moves the item back into Hidden.

**Fix.**
1. In save, first normalise the stored dictionary with `Dictionary(stored.map { (storedIdentityKey($0.key), $0.value) }, uniquingKeysWith:)`, preferring an entry whose raw key already equals the canonical key. Write only canonical keys.
2. In `savedSections()`, let an exact canonical key win over keys that only map to it.

**Verification.** Confirmed medium. Within one process the winner is fairly stable, so the arrangement is undone on some launches rather than on every trigger.

#### F-25 — A pending profile reconciliation is replaced by a later restore request, so the profile is silently not applied

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:153`
- **Classification:** auto-fixable. One condition in one function.
- **Merged from:** R03-menubaritems: "A pending profile reconciliation is overwritten by a later restore trigger, so the profile is silently lost".

**Summary.**
- While a reconciliation runs, a new request replaces `pendingReconciliation` when `wanted != nil || trigger.restoresSavedSections || pendingReconciliation == nil`.
- So a later `.settle`, `.applicationLaunch` or `.launch` request, which has `wanted == nil`, replaces a pending profile.
- The profile's sections are only stored inside `performReconciliation`, so they are never applied or stored.
- Meanwhile `LayoutProfiles.apply` has already set and saved `currentProfileName`.

**Evidence.** `SectionRestore.swift:153-158`; `LayoutProfiles.swift:170-171`.

**Failure scenario.**
1. Connecting a display applies a bound profile while an item-list reconciliation is running on macOS 26, where moves take seconds.
2. The profile becomes pending.
3. The display-change settle then calls `reconcileSections(.settle)`, which replaces it.
4. The layout is never applied, while the UI shows it as the current profile.

**Fix.** Never let a request without `wanted` replace a pending profile: `if wanted != nil || (pendingReconciliation?.wanted == nil && (trigger.restoresSavedSections || pendingReconciliation == nil)) { pendingReconciliation = (wanted, trigger) }`.

**Verification.** Confirmed medium.

#### F-26 — macOS 27 click bridge: stale panel state plus banner windows make a clock click post a synthetic Escape and swallow the click

- **Severity:** medium · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/SystemItemClickBridge27.swift:136`
- **Classification:** manual-only. Timing-sensitive click replay on macOS 27 (detecting the panel after the replayed click). It must be verified on macOS 27 with notification banners.
- **Merged from:** R02-macos27: "Stale itemShowingPanel plus banner detection makes the click bridge post a stray Escape and swallow the clock click"; L1-attack-surface: "macOS 27 click bridge posts a synthetic Escape to the frontmost app and swallows the clock click when its remembered panel state is stale".

**Summary.**
- `itemShowingPanel` is set after every replayed system-item click (line 172), whether or not a panel opened.
- It is cleared only when the same item is clicked again while a panel-sized window is on screen. Closing Notification Center or a Control Centre menu any other way leaves it stale.
- `openPanelWindow()` counts any notificationcenterui or controlcenter window at layer 20 or higher that is taller than 150 pt. The code's own comment says a notification banner is exactly such a window.
- With a stale value and a banner on screen, the next click on that item:
  - posts Escape through the HID tap, which reaches the frontmost app's key window, not the banner;
  - then, because the identifiers match, returns without replaying the click it held back.

**Evidence.**
- `SystemItemClickBridge27.swift:129-142`: the dismiss check.
- `SystemItemClickBridge27.swift:172`: the unconditional assignment.
- `SystemItemClickBridge27.swift:176-177`: the held-back click.
- `SystemItemClickBridge27.swift:233-237`: the Escape.
- `ItemClick27.swift:27-30`: `openPanelWindow()`.

**Failure scenario.**
1. The user opens Notification Center from the clock through holzBar, then closes it by clicking the desktop.
2. Later, with a banner on screen, the user clicks the clock while a dialog, a sheet or a fullscreen video is frontmost.
3. The Escape cancels the dialog or leaves fullscreen.
4. Notification Center does not open until a second click.

**Fix.**
1. Set `itemShowingPanel` only after a short `waitForPanel` confirms that a new panel window opened, and store that window's number.
2. Treat a click as a dismiss only while `ItemClick27.panelIsOnScreen(window: stored, …)` is true.
3. Otherwise, clear the state and do not post Escape.

**Verification.** Both were confirmed medium. It needs macOS 27, active concealment, and a banner on screen at that moment.

#### F-27 — macOS 27: clicks and photos of a temporarily shown app use fixed sleeps and stale Accessibility frames, so they can hit another item

- **Severity:** medium · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemClicker27.swift:41`
- **Classification:** manual-only. Changes the timing contract between Concealer27, ItemClicker27 and ItemImageStore27 (when an item counts as settled). The delays were set by measurement on a macOS 27 device.
- **Merged from:** R02-macos27: "Clicks and photos of a temporarily shown app use fixed sleeps and stale Accessibility frames, so they can hit another item".

**Summary.**
- `showTemporarily()` only queues an apply behind the previous one, and each activation may wait up to 3 s for MenuBarAgent.
- ItemClicker27 and `ItemImageStore27.photographMissing` wait a fixed 600 ms from the call, then trust the item's AX frame.
- On macOS 27 that frame stays where a concealed app was last drawn. `isOnScreen` ignores concealment, and `update()` has already removed the app from `concealedPIDs`.
- Both guards pass on the stale frame:
  - the settle guard is measured from `update()`, because `lastChangeAt` is set before the apply runs;
  - `settledTags` compares two reads of the same stale frame.
- Queued applies are likely exactly while the Shelf is open, because photographMissing chains applies for up to six apps.
- A wrong glyph is never replaced.

**Evidence.**
- `ItemClicker27.swift:41-49`.
- `Concealer27.swift:230-240`.
- `ItemImageStore27.swift:264-269`.
- `MenuBarItemProvider27.swift:60-61`.

**Failure scenario.** A concealment change is still queued when the user clicks a hidden item in the Shelf.
- After 600 ms holzBar clicks at the old frame, where another item or the clock now sits. The wrong menu opens, or the click bridge fires.
- Or photographMissing stores another item's glyph as this app's Shelf icon.

**Fix.**
1. Let `showTemporarily` return (or expose) the apply task, and await it before the 0.4–0.6 s draw delay.
2. Set `lastChangeAt` when the apply finishes, not when `update()` is called.
3. Alternatively, wait until the app's items appear at a frame that differs from the one recorded while they were concealed.

**Verification.** Confirmed medium. The timing on macOS 27 was set by measurement on a device and could not be re-checked here.

#### F-28 — macOS 27: Visible apps concealed for the notch stay concealed after the reveal that crowded the bar ends

- **Severity:** medium · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/Concealer27.swift:357`
- **Classification:** auto-fixable. State invalidation in one function of Concealer27. Check on a Mac with a notch running macOS 27.
- **Merged from:** R02-macos27: "Visible apps concealed for the notch stay hidden after the reveal that crowded the bar ends".

**Summary.**
- While holzBar's icon is under the notch, `checkNotchCover` conceals Visible apps, one per settled read, and adds them to `notchConcealed`.
- `notchConcealed` is cleared only on an app launch or quit, a screen-parameter change, or an active-display change. It is not cleared when the reveal state shrinks the bar again.
- `update()` always adds `notchConcealed` to the target, and creates an assertion even when nothing else is concealed. So those apps stay concealed and `isConcealing` stays true.
- Because launches and quits of agents go unnoticed (F-17), this can last a long time.

**Evidence.**
- `Concealer27.swift:96`, `:106`, `:149`, `:310` and `:334`: the only places that clear `notchConcealed`.
- `Concealer27.swift:208-215`: `update()` adds it to the target.
- `Concealer27.swift:357`: where apps are added.
- `NotchCover27.adding`.

**Failure scenario.**
1. On a crowded MacBook with a notch, the user reveals the Hidden section (or opens the Menu Bar Layout pane).
2. holzBar's icon lands under the notch, so Visible apps are concealed.
3. The user hides the section again. The bar now has room, but those Visible apps stay off the bar until some app launches or quits or the displays change.

**Fix.**
1. In `update()`, keep the last reveal state.
2. Clear `notchConcealed` when `revealState(appState)` or the layout-derived concealed sets change.
3. The next settled read adds entries again if the icon is still covered.

**Verification.** Confirmed medium. Not run on a Mac with a notch on macOS 27.

#### F-29 — A hotkey stays unregistered when its recorder disappears while recording

- **Severity:** medium · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/UI/Views/HotkeyRecorder.swift:189`
- **Classification:** auto-fixable. One modifier (`.onDisappear`) on one view.
- **Merged from:** R08-ui: "HotkeyRecorder leaves the hotkey unregistered when the view goes away during recording"; R09-settings-main-hotkeys: "Hotkey stays unregistered when the recorder disappears while recording".

**Summary.**
- `startRecording()` unregisters the global hotkey with `hotkey.disable()`. Only `stopRecording()`, or a new combination, registers it again.
- Nothing calls `stopRecording()` when the view goes away: HotkeyRecorder has no `onDisappear`, and the model has no deinit handling.
- The view can go away while recording:
  - switching Settings panes destroys the pane, because SettingsView switches on the navigation identifier;
  - the item hotkey popover is `.transient`;
  - the monitor only watches keyDown, so a mouse click elsewhere does not stop recording.
- The EventMonitor removes itself in deinit. But the Hotkey, owned by HotkeysSettings, stays disabled while its combination is still stored.

**Evidence.**
- `HotkeyRecorder.swift:21-37` and `:189-205`.
- `SettingsView.swift:145`.
- `LayoutBarItemView.swift:453-458` and `:551`.

**Failure scenario.**
1. The user clicks "Record Hotkey" for "Toggle the hidden section".
2. They change their mind and click "General" in the sidebar.
3. ⌃⌥H no longer works until holzBar restarts, and the Hotkeys pane shows "Record Hotkey" although the combination is stored.

**Fix.**
1. Add `.onDisappear { model.stopRecording() }` to `HotkeyRecorder.body`.
2. As a backstop, give the model an isolated deinit that calls `hotkey.enable()` while recording.

**Verification.** Both slices confirmed it medium.

#### F-30 — A combination another holzBar hotkey already uses is saved but never registered, and the row then offers no way to clear it

- **Severity:** medium · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/UI/Views/HotkeyRecorder.swift:228`
- **Classification:** manual-only. Needs a new problem alert (strings in five languages) and a decision whether a duplicate is refused or reassigned.
- **Merged from:** R08-ui: "A combination that another holzBar hotkey already uses is saved but silently not registered, and the recorder shows \"Record Hotkey\" without a way to clear it"; R09-settings-main-hotkeys: "A hotkey that duplicates another holzBar hotkey is saved but never registered, and the UI shows it as unset".

**Summary.**
- The recorder rejects only system-reserved and Option-only combinations. Nothing checks holzBar's other hotkeys.
- A second `RegisterEventHotKey` of the same combination in one process returns -9878 (eventHotKeyExistsErr). `Listener.init` then returns nil and `isEnabled` is false, while `keyCombination` stays set and HotkeysSettings saves it.
- The recorder's label and trailing button key off `isEnabled`. So the row shows "Record Hotkey", hides the stored combination, and its Clear button starts recording instead of clearing.
- Freeing the other hotkey does not register this one again. At the next launch, load order decides which hotkey wins.

**Evidence.**
- `HotkeyRecorder.swift:72`, `:93` and `:108`: the label and button logic.
- `HotkeyRecorder.swift:221-233`: the only checks.
- `HotkeyRegistry.swift` (about line 175): the registration.
- `HotkeysSettings.swift:118-142`: the save.
- A probe: the first registration returned 0, the second -9878.

**Failure scenario.** "Search menu bar items" uses ⌃⌥⌘K, and the user records ⌃⌥⌘K for a layout profile. The row goes back to "Record Hotkey" with no alert. The profile hotkey never fires, and the row cannot clear the stored combination.

**Fix.**
1. Before assigning, check the other hotkeys (action and dynamic). Either refuse a combination that is already used and show a new problem ("Already used by …", strings needed in all five languages), or decide to reassign it.
2. Base the label and the Clear button on `hotkey.keyCombination != nil`.
3. If registration fails after the assignment, revert it and tell the user.

**Verification.** R08-5 rated it medium: the row cannot clear it, and the winner after a relaunch depends on order. R09-2 rated it low: the row visibly reverts, and nothing is lost. Merged at medium.

#### F-31 — Backspace or Escape anywhere in holzBar deletes or deselects the selected gradient stop and is swallowed

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:112`
- **Classification:** auto-fixable. UI subsystem: an `onKeyDown` overload that passes the event, plus window, first-responder and modifier checks at the two handlers.
- **Merged from:** R08-ui: "Backspace or Escape anywhere in the app (for example the colour panel's hex field) deletes or deselects the gradient stop and is swallowed".

**Summary.**
- `onKeyDown` is an NSEvent local monitor. It sees every keyDown the app receives, in any window, before the first responder does.
- The picker installs it for Delete and Escape whenever a stop is selected, which is exactly while the in-process NSColorPanel is open.
- It checks neither the window, nor the first responder, nor modifiers.

**Evidence.** `HolzBarGradientPicker.swift:112-120`; `OnKeyDown.swift:16`; `KeyCode.swift:94`.

**Failure scenario.**
- With a stop selected, the user corrects a digit in the colour panel's "Hex Color #" field with Backspace, and the stop is deleted instead.
- Escape meant for another sheet only deselects the stop and closes the colour panel.

**Fix.** Add an `onKeyDown` overload whose action receives the NSEvent. Return `.ignored` unless all of these hold:
- `event.window` is the picker's own window;
- the first responder is not an NSText;
- no device-independent modifiers are set.

Alternatively, move to focus-based `.onKeyPress` and `.onExitCommand` on a focusable picker.

**Verification.** Confirmed medium.

#### F-32 — Menu Bar Layout pane: the source row of a drag stops updating after a drop into another row or a cancelled drag

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift:497`
- **Classification:** auto-fixable. One file: reset the flag on the source container when the drag session ends.
- **Merged from:** R06-appearance-layoutbar: "Source row of a layout-bar drag stays frozen when the item is dropped into another row or the drag is cancelled".

**Summary.**
- `draggingSession(_:willBeginAt:)` sets `canSetArrangedViews = false` on the source container.
- Only `LayoutBarPaddingView.performDragOperation` resets it, and only on the drop target.
- After a drop into another row, or a cancelled drag, `setArrangedViews(items:)` returns early for the source row on every item-cache change. This lasts until something is dropped onto that row or the pane is rebuilt.

**Evidence.**
- `LayoutBarItemView.swift:496-498` and `:512-535`.
- `LayoutBarPaddingView.swift:64-69`: the only reset.
- `LayoutBarContainer.swift:176-181`: the early return.
- grep finds no other code that writes the flag.

**Failure scenario.**
1. The user drags an item from Hidden to Visible.
2. Later, an app adds an item to Hidden, or the user moves one there with ⌘2.
3. The item leaves Visible but never appears in Hidden, so it vanishes from the pane.
4. Keyboard moves in the frozen row work from stale neighbours.

**Fix.**
1. Store the source container in `willBeginAt`.
2. In `draggingSession(_:endedAt:operation:)`, after any reinsert, set its `canSetArrangedViews = true` and call `setArrangedViews(items: appState.itemManager.itemCache[section])`.
3. Keep the reset of the target in `performDragOperation`.

**Verification.** Confirmed medium. Inherited from Ice; affects macOS 26 and 27.

#### F-33 — Keyboard and VoiceOver moves in the Layout pane lose focus after one step

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/LayoutBar/LayoutBarContainer.swift:188`
- **Classification:** auto-fixable. One function: restore the first responder after `setArrangedViews`.
- **Merged from:** R06-appearance-layoutbar: "Keyboard moves in the Layout pane lose keyboard focus because item views are recreated whenever an item's bounds change".

**Summary.**
- `setArrangedViews(items:)` reuses a view only when `$0.item == item`, and `MenuBarItem ==` also compares bounds, title and isOnScreen.
- A move changes the item's bounds, so the focused view is replaced and removed from its superview, which drops the first responder.
- The only `makeFirstResponder` call is in `LayoutBarRouter.moveFocus`, so nothing restores focus.

**Evidence.**
- `LayoutBarContainer.swift:122-124` and `:187-193`.
- `MenuBarItem.swift:279-289`: the equality.
- `LayoutBarRouter.swift:348`: the only `makeFirstResponder` call.

**Failure scenario.** On macOS 26 the user focuses an item and presses ⌥→.
- The item moves, the cache refreshes, and focus drops to the window.
- The next ⌥→ does nothing, and VoiceOver loses its place.

⌘1/2/3 and the accessibility actions behave the same way.

**Fix.**
1. Before reassigning, remember the tag of the focused view.
2. Afterwards, make its successor (the view with the same tag) the first responder.

Alternatively, match views by tag and windowID, and update a mutable `item` in place.

**Verification.** Confirmed medium. In-row keyboard moves exist only on macOS 26, because macOS 27 refuses them; section moves lose focus on both.

#### F-34 — The "Focused app" rehide strategy fires even when "Automatically rehide" is off

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/MenuBarManager.swift:192`
- **Classification:** auto-fixable. One guard.
- **Merged from:** R05-menubar-other: "The 'Focused app' rehide fires even when 'Automatically rehide' is off".

**Summary.**
- `frontmostApplicationDidChange` checks only `rehideStrategy == .focusedApp`, never `settings.general.autoRehide`.
- The strategy picker is hidden while auto-rehide is off, and a hotkey and a URL command toggle auto-rehide directly. So a stored `.focusedApp` stays in effect without being visible.
- The timed and smart strategies both check `autoRehide`.

**Evidence.**
- `MenuBarManager.swift:189-202`: the missing check.
- `GeneralSettingsPane.swift:252-253`: the picker is hidden.
- `MenuBarSection.swift:255`, `InputMonitors.swift:59`, `HIDEventManager.swift:392`: the other strategies check it.
- `HotkeyActionPerform.swift:82` and `URLCommands.swift:180-188`: direct toggles.

**Failure scenario.** The user picks "Focused app", then turns "Automatically rehide" off to keep hidden items shown. Every app switch with the pointer outside the menu bar still hides the section.

**Fix.** Add `appState.settings.general.autoRehide` to the condition in `frontmostApplicationDidChange`.

**Verification.** Confirmed medium.

#### F-35 — The Shelf jumps after it opens, because every resize recomputes its position from the current mouse location

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/Shelf/HolzBarShelf.swift:119`
- **Classification:** auto-fixable. One file: compute the horizontal anchor once, at show.
- **Merged from:** G3-layout-faults: "Shelf moves after it opens: every resize recomputes its origin from the current mouse position (default 'Dynamic' jumps to the holzBar icon, 'Mouse pointer' follows the cursor)".

**Summary.**
- The panel's content is an NSHostingView with `.fixedSize()` content, so the window follows the content's width.
- The `setFrame(_:display:)` override calls `updateOrigin(for:)` on every size change, and `updateOrigin` recomputes the anchor from the mouse:
  - for `.dynamic` (the default) it asks `isMouseInsideEmptyMenuBarSpace`. That is false once the pointer is on the Shelf below the bar, so the Shelf moves to the holzBar icon;
  - for `.mousePointer` it re-centres the Shelf on the cursor.
- The width does change while the Shelf is open:
  - on macOS 27 the refresh runs alongside the open Shelf, and placeholders are replaced by images;
  - on both systems the image cache refreshes every 3 s, and item widths change (clock, percentages).

**Evidence.**
- `HolzBarShelf.swift:119-125`: the `setFrame` override.
- `HolzBarShelf.swift:128-179`: `updateOrigin`.
- `HolzBarShelf.swift:194-204`, `:407` and `:572-580`.
- MenuBarItemImageCache refreshes while `isShelfPresented`.
- `MenuBarHitTesting.swift:103`.

**Failure scenario.**
- macOS 27, default "Dynamic": the user clicks empty menu bar space on the left, and the Shelf opens under the pointer. The user moves down onto it, the images arrive, and the Shelf jumps to the holzBar icon on the right. The click lands elsewhere.
- With "Mouse pointer": a change in the clock's width re-centres the Shelf under the cursor just as the user clicks, which opens the wrong item.

**Fix.**
1. Choose the horizontal anchor once, in `show(section:on:)`: the mouse x or the control item's midX, according to the setting and the mouse position at opening. Store it (`anchorX`).
2. In `updateOrigin`, only re-centre on that anchor and clamp to the screen.
3. Clear the anchor in `close()`.
4. Do not read the mouse or call `isMouseInsideEmptyMenuBarSpace` from `setFrame`.

**Verification.** Confirmed medium. The resize path through `setFrame(_:display:)` was not observed at runtime, but the override exists for exactly that path. Opening from the holzBar icon is not affected.

#### F-36 — Opening a hidden item without showing it treats a menu-opening AXPress as a failure and clicks the item again

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/MenuBarItems/ItemOpener.swift:85`
- **Classification:** manual-only. There are several valid approaches with different failure modes for hung apps: treat `.cannotComplete` as taken, or detect the menu window. The fix also must not change the shared provider element's timeout on macOS 27.
- **Merged from:** L5-concurrency: "pressWithoutShowing gives AXPress 0.25 s, but a press that opens a menu only returns when the menu closes, so a successful press is taken as failure and the item is clicked again".

**Summary.**
- With "Open hidden items in the menu bar" off, `openItem` first presses a hidden item through Accessibility with a 0.25 s messaging timeout. It treats anything but `.success` as "not taken".
- The project measured that a status-item press blocks while its menu is open (`ItemClicker27.swift:62-63`, `MenuBarItemProvider27.swift:127-128`). So a press that opens a menu returns `.cannotComplete` after 0.25 s while the menu is up.
- `openItem` then shows the item and clicks it.
- On macOS 27 the 0.25 s timeout is also written onto the provider's shared stored element, which shortens later presses and reads.

**Evidence.**
- `ItemOpener.swift:32-36` and `:79-89`.
- `ItemClicker27.swift:62-63`.
- `MenuBarItemProvider27.swift:126-128`.

**Failure scenario.** The user turns "Open hidden items in the menu bar" off and opens a hidden item from the Shelf or with a hotkey.
1. The menu opens.
2. 0.25 s later holzBar reveals the item and clicks it.
3. That closes or reopens the menu, and the item flashes into the bar.

**Fix.**
1. Choose between:
   - treating `.cannotComplete` as "taken" (a hung app then gets no fallback); and
   - deciding success by a new menu window of the owner PID within about 300 ms (`ItemClick27.interfaceIsOpen`).
2. Do not leave a short timeout on the provider's shared element: reset it to 0 afterwards, or use a freshly looked-up element.

**Verification.** Confirmed medium. Limited to users who turn this default-on setting off.

#### F-37 — macOS 26 source-PID lookups have no overall time limit, so one slow app stalls every item read

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26
- **Location:** `Shared/Services/SourcePIDCache.swift:148`
- **Classification:** manual-only. Touches the XPC service's deliberate default timeout, the app-side request deadline (which overlaps K2) and the fallback. It needs a policy for deadlines.
- **Merged from:** G1-hostile-items: "macOS 26: source-PID lookups have no overall time limit, so one slow app or an app with very many AX children stalls every item read".

**Summary.**
- Each uncached window starts a scan of every app's extras-bar children: `isEnabled` plus the frame for each child. The scan uses the default 6 s messaging timeout, because `AXHelpers.application` is called without one, and it runs inside the state lock.
- A cached bar is returned without checking `isValidForAccessibility` again. So an app that hangs after its bar was cached is still asked.
- On the app side, the serial request queue sends each window in turn with no reply deadline, and ServiceBackend26.items awaits them one by one.
- Windows that never resolve (clones, and the second display's copies) are scanned again every 30 s and pay the hung app's timeout again.

**Evidence.**
- `SourcePIDCache.swift:68-70`: the cached bar.
- `SourcePIDCache.swift:148-165`: the scan.
- `AXHelpers.swift:63-76`: no messaging timeout.
- `MenuBarItemServiceConnection.swift:99` and `:183`: the serial queue.

**Failure scenario.** An app with a status item answers Accessibility slowly. When another app adds an item:
- holzBar's item read blocks for seconds per window, or minutes at startup or after a Control Center restart;
- meanwhile the item cache, the Layout pane, the Shelf and section restore stay stale.

**Fix.**
1. Create the service's app elements, and the extras bar, with a short messaging timeout (0.25–0.5 s).
2. Check `isValidForAccessibility` again before using a cached bar.
3. Cap the children read per app and the total scan time per lookup.
4. Add a reply deadline on the app side, so the item falls back to a UUID namespace.

**Verification.** Confirmed medium. The `sendSync` API choice itself is K2; the missing timeouts and the cached-bar check are new.

#### F-38 — The sync device ID lives in the preferences file, so Macs set up by Migration Assistant, restore or clone ignore each other's changes

- **Severity:** medium · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Utilities/SettingsSync.swift:50`
- **Classification:** manual-only. What a re-identified Mac does with the existing sync file is part of the conflict policy in F-02. Storing an identifier derived from the hardware also needs a privacy decision (hash it).
- **Merged from:** L2-untrusted-data: "The sync device ID lives in the copied preferences, so Macs set up with Migration Assistant or from a backup ignore each other's changes".

**Summary.**
- The ID that tells Macs apart is a UUID in holzBar's own defaults (`SettingsSyncDeviceID`). It is excluded from export and sync.
- But Migration Assistant, Time Machine restores and disk clones copy `~/Library/Preferences/com.holzcloud.holzBar.plist` unchanged.
- Both Macs then carry the same ID, so `isFromThisMac` is true for every file the other Mac writes.
- Sync silently applies nothing, and each push overwrites the other Mac's changes.

**Evidence.**
- `SettingsSync.swift:50-57`: the ID.
- `SettingsSyncDevice.isFromThisMac`.
- The `excludedKeyPrefixes` comment in SettingsBackup: "A copied id would make two Macs ignore each other's changes".

**Failure scenario.** The user moves to a new MacBook with Migration Assistant and keeps the old iMac, both syncing. Changes never reach the other Mac, and whichever Mac writes last wins.

**Fix.**
1. Store a hardware identity alongside the ID, in a `SettingsSync*` key. For example, a salted hash of IOPlatformUUID, read locally through IOKit, with no network.
2. When the stored identity does not match this Mac, create a new ID and clear the last-synced date.
3. What the re-identified Mac then does with the existing file belongs to the conflict policy of F-02.

**Verification.** Confirmed medium.

#### F-39 — The Split menu bar shape always degrades to the full shape on macOS 27

- **Severity:** medium · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift:832`
- **Classification:** manual-only. Two valid approaches, which is a product decision: compute the split from the backend's item frames, or hide Split on macOS 27.
- **Merged from:** R06-appearance-layoutbar: "Split menu bar shape always degrades to the full shape on macOS 27".

**Summary.**
- `pathForSplitShape` sizes the trailing half from the WindowServer item windows (`MenuBarItem.getMenuBarItemWindows`).
- On macOS 27, items are drawn inside MenuBarAgent and have no such windows; the code says so in several places.
- So the trailing bounds are `.zero`, and the full-shape branch is always taken.
- The editor offers Split on every OS.

**Evidence.**
- `MenuBarOverlayPanel.swift:831-835` and `:851`.
- `MenuBarItemProvider27.swift:13-14` and `AccessibilityBackend27.swift:52`: no item windows on macOS 27.
- MenuBarShapePicker: Split is offered everywhere.

**Failure scenario.** On macOS 27 the user picks Shape Kind "Split" and gets a single full-width pill, with no explanation.

**Fix.** A product choice between:
- on macOS 27, computing the trailing width from the backend's item frames (the item cache or `MenuBarItemProvider27.items()`, excluding concealed PIDs); and
- hiding or annotating Split on macOS 27.

**Verification.** Confirmed medium from the code's own documented assumptions. Not run on macOS 27.

#### F-40 — install.sh skips the TCC reset for ad hoc builds most of the time (SIGPIPE under pipefail)

- **Severity:** medium · **Category:** bug · **Affects:** build, CI and release (local source installs)
- **Location:** `Scripts/install.sh:73`
- **Classification:** auto-fixable. One line in a developer script, and `release.yml` already uses the safe pattern. Note the interaction with F-107.
- **Merged from:** R11-scripts-build: "install.sh skips the TCC reset for ad hoc builds most of the time (SIGPIPE under pipefail)".

**Summary.** The script runs under `set -euo pipefail`, and the check is `codesign -dv … 2>&1 | grep -q 'Signature=adhoc'`. That pipeline usually fails:
1. grep exits as soon as it matches.
2. codesign still has lines to write, so it gets SIGPIPE and exits with 141.
3. pipefail makes the `if` false.
4. Both `tccutil reset` calls are skipped, without a message.

**Evidence.**
- `Scripts/install.sh:13` and `:73-77`.
- `release.yml:129-134` already uses the safe pattern: capture the output, then grep a here-string.
- Two reproductions: 237 of 300 runs and 154 of 200 runs skipped the reset.

**Failure scenario.**
1. A developer runs `install.sh` again. The new ad hoc build has a new cdhash.
2. About 80% of the time, TCC keeps the old grants.
3. System Settings shows holzBar as allowed while the new binary is denied, and holzBar stays at its permissions window. This is the jordanbaird/Ice#1004 problem.

**Fix.**
1. Use `DETAILS=$(codesign -dv "$DEST/holzBar.app" 2>&1); if grep -q 'Signature=adhoc' <<< "$DETAILS"; then …`.
2. Check other `cmd | grep -q` pipelines that run under pipefail.

**Verification.** Confirmed medium with two independent reproductions. Fixing it makes the reset run every time, which also revokes the Homebrew copy's grants (F-107).

#### F-41 — verify-layout.sh restores MacOS27Layout with string values, wiping the real macOS 27 layout while printing PASS

- **Severity:** medium · **Category:** bug · **Affects:** macOS 27 (maintainer tool)
- **Location:** `Scripts/macos27/verify-layout.sh:49`
- **Classification:** auto-fixable. One maintainer script. A save and restore that keeps the value types can be checked against a scratch defaults domain.
- **Merged from:** R11-scripts-build: "verify-layout.sh 'restores' MacOS27Layout with string values, wiping the real macOS 27 layout while reporting PASS".

**Summary.**
- The script saves the layout as `defaults read` text and writes it back with `defaults write … "$LAYOUT_BEFORE"`.
- That old-style plist text has no number type, so every value comes back as a string.
- The app reads the key with `as? [String: Int]`. The cast fails and the layout becomes empty.
- `MacOS27LayoutSeeded` stays true, so nothing reseeds the layout.
- The script's own check compares `defaults read` text, which looks identical, so it prints PASS.

This is the same loss that the comment at lines 25-27 says was fixed.

**Evidence.**
- `verify-layout.sh:25-27` and `:49`, plus the restore and compare lines.
- The readers: `Concealer27.swift:76`, `LayoutProfiles.swift:120`, `LayoutBarPaddingView.swift:283`.
- A reproduction on a scratch domain: `plutil -p` shows "1" and "2" as strings.

**Failure scenario.** The maintainer runs the script on macOS 27. On exit it writes the strings back, so at the next launch every hidden application becomes visible and the layout is gone.

**Fix.**
1. Save with types preserved: `defaults export com.holzcloud.holzBar - | plutil -extract MacOS27Layout xml1 -o "$WORK/layout.plist" -`.
2. Restore through an exported domain plist with `plutil -replace MacOS27Layout -xml …` and `defaults import`. If the key was absent before, run `defaults delete` instead.
3. Compare the XML extracts, not `defaults read` text.

**Verification.** Confirmed medium with a reproduction. It is a maintainer tool only, but it loses data on every run.

### Low

#### F-42 — Any app can crash holzBar on macOS 27 by reporting a non-finite or huge Accessibility frame

- **Severity:** low · **Category:** security · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:411`
- **Classification:** auto-fixable. Validate frames at the single source (`MenuBarItemProvider27.frame(of:)`) and use conversions that cannot trap at the known sinks. A pure validation helper can be unit-tested in HolzBarMacOS27Core.
- **Merged from:** R04-backends-controlitem: "Any app can crash holzBar on macOS 27 with a non-finite or huge Accessibility frame (Int conversion trap)"; G1-hostile-items: "macOS 27: non-finite Accessibility frames reach other traps besides the known Int conversion (ClosedRange in the layout drag, NSView frames)".

**Summary.** `MenuBarItemProvider27.frame(of:)` accepts whatever CGPoint and CGSize the owning process reports. Three sinks then fail on bad values:
- `AccessibilityBackend27.itemListSignature` converts with `Int($0.bounds.minX)` on every item-change check. That traps on NaN, on infinity and on values out of range.
- LayoutBarContainer builds `(midX - offset)...(midX + offset)` from view frames sized from item bounds. That traps when the value is NaN.
- NaN geometry can also raise in Core Animation.

The crash repeats at every launch for as long as the offending app runs.

**Evidence.**
- `MenuBarItemProvider27.swift:411-429`: `frame(of:)`.
- `AccessibilityBackend27.swift:54-57`: the Int conversion.
- `LayoutBarContainer.swift:251-253`: the range.
- The LayoutBarItemView initializer: views are sized with `item.bounds.size`.

**Failure scenario.** A buggy or hostile app publishes a status item whose AX position is (NaN, 0) or (1e300, 0). holzBar on macOS 27 crashes on the next scan, and again after every relaunch. While that app runs, concealment of hidden items is gone.

**Fix.**
1. Reject frames at the source: return nil unless origin and size are finite, the size is non-negative, and every value lies within a sane range (|v| < 1e6).
2. Use conversions that cannot trap at the sinks: `Int32(exactly: x.rounded(.down)) ?? 0` and `abs(x - midX) <= offset`.
3. Put the validation in a pure helper that HolzBarMacOS27Core can test.

**Verification.** Both were confirmed low. It needs a deliberately or unusually broken local app, and the result is a repeated denial of service; no security boundary is crossed.

#### F-43 — Any local process can freeze concealment, Zen mode and item placement with a spoofed com.apple.screenIsLocked notification

- **Severity:** low · **Category:** security · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Events/SystemActivityMonitor.swift:61`
- **Classification:** manual-only. The only lock-state source that cannot be spoofed is the session dictionary's undocumented `CGSSessionScreenIsLocked` key. Relying on it is a design decision under the project's "Apple's way" principle.
- **Merged from:** R07-utilities-permissions-events: "Any process, including sandboxed apps, can post the screen-lock distributed notification and freeze holzBar's hiding and item handling"; L1-attack-surface: "Any local process can freeze concealment, Zen mode and item placement by posting a spoofed com.apple.screenIsLocked distributed notification".

**Summary.**
- SystemActivityMonitor takes the distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` as the lock state.
- Any process of the user can post them without userInfo, sandboxed processes included. The sender is not checked, and the state is not confirmed.
- While holzBar thinks the screen is locked, it pauses:
  - `Concealer27.update()` returns early;
  - MenuBarItemManager stops re-reading items;
  - SectionRestore stops reconciling.
- The pause lasts until a real unlock, a wake or a session change.

**Evidence.**
- `SystemActivityMonitor.swift:59-66`: the observers.
- `SystemActivity.swift:55-56`.
- `Concealer27.swift:197-199`.
- `MenuBarItemManager.swift:187`, `:468`, `:716`, `:971` and `:1066`.
- `SectionRestore.swift:160`.

**Failure scenario.** An app posts the notification.
- On macOS 27, clicking the holzBar icon no longer hides or shows items. If the user had just revealed items, neither auto-rehide nor automatic Zen can hide them again during a screen share.
- On macOS 26, moves, item reads and captures stop.

**Fix.**
1. When either notification arrives, confirm the state from `CGSessionCopyCurrentDictionary()` (`CGSSessionScreenIsLocked`), and ignore a lock it does not confirm.
2. Check the state again when settling.

The key is undocumented, so choosing it as the source of truth is a decision.

**Verification.** Both were confirmed low. It needs local code execution, the effect can be undone, and it is visible to the user.

#### F-44 — macOS 26: a process named like holzBar or Control Center gets their item tags, and a fake divider becomes the section divider

- **Severity:** low · **Category:** security · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItem.swift:375`
- **Classification:** manual-only. Deciding which namespaces are protected (holzBar's own, Apple system processes) and how to verify them (PID, executable path, code signature) is a design decision.
- **Merged from:** G1-hostile-items: "macOS 26: a process named com.holzcloud.holzBar (no bundle) gets holzBar's own control-item tags, and the first one found becomes the section divider".

**Summary.**
- The macOS 26 namespace is `app.bundleIdentifier ?? app.localizedName`, and nothing verifies it.
- An unbundled process has a nil bundle ID, so its executable name is used as the namespace.
- The title is the window title, which is the status item's autosave name.
- So a process named `com.holzcloud.holzBar` with an item named `holzBar.ControlItem.Hidden` produces a tag equal to `.hiddenControlItem`.
- ServiceBackend26 recognises only holzBar's real control items by frame. ControlItemPair and other code take the first matching tag from the left.
- The same trick works for `com.apple.controlcenter` with the titles Clock or BentoBox-0.
- There is no single-instance check either.

**Evidence.**
- `MenuBarItem.swift:374-386`: the namespace.
- `MenuBarItemManager.swift:341` and `:877`, `MenuBarManager.swift:273`: first-match lookups.
- `ServiceBackend26.swift:45`: frame-based recognition of the real control items.

**Failure scenario.** Such a process places its item left of the real hidden divider. Then:
- cache building, SectionRestore and the hiding of application menus use the fake divider;
- items between the two dividers are classed as visible;
- "visible" placements land in the hidden area;
- the fake item never appears in the Layout pane.

**Fix.**
1. Give the `.holzBar` namespace only to windows that OwnStatusItemWindows matched, or whose source PID is holzBar's own.
2. Give any other window that resolves to holzBar's or an Apple system namespace a distinct namespace. Verify Apple processes by executable path or code signature.
3. Do not use `localizedName` as the namespace when it looks like such a reverse-DNS ID.

**Verification.** Confirmed low. It needs a deliberately spoofing local process, and it only corrupts the layout.

#### F-45 — macOS 27: a second process with bundle ID com.apple.MenuBarAgent overwrites the system-item frames the click bridge uses

- **Severity:** low · **Category:** security · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:278`
- **Classification:** manual-only. The check needs MenuBarAgent's real location on macOS 27, or a confirmed platform-binary code-signing check. MenuBarAgent does not exist on this macOS 26 host, and a wrong check would disable system-item detection.
- **Merged from:** G1-hostile-items: "macOS 27: a second process with bundle ID com.apple.MenuBarAgent overwrites the system item frames used by the click bridge".

**Summary.**
- MenuBarAgent is found only by its bundle ID.
- Every app with that ID takes the MenuBarAgent branch and overwrites `lastSystemFramesByDisplay`, `lastDrawnFramesByDisplay`, `lastSystemItemFrames` and the overflow-button frame.
- So the last one read wins. A fake process with no windows writes empty dictionaries.

**Evidence.** `MenuBarItemProvider27.swift:213-311`.

**Failure scenario.** A locally built app claims `com.apple.MenuBarAgent`. While items are concealed, the click bridge no longer recognises clicks on the real clock or Control Centre.

**Fix.**
1. Accept only the first process that passes a platform-binary code-signing check, or whose `executableURL` lies at MenuBarAgent's confirmed system path.
2. Skip any other process that claims the ID.

**Verification.** Confirmed low.

#### F-46 — macOS 27: a spoofed theme-change notification discards all item images and resets the photo schedule, so concealed apps flash into the bar

- **Severity:** low · **Category:** security · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:94`
- **Classification:** auto-fixable. One file: discard only when the effective appearance actually changed.
- **Merged from:** G1-hostile-items: "macOS 27: a spoofed AppleInterfaceThemeChanged resets the photo schedule and discards all item images, so concealed apps are revealed again on every Shelf refresh".

**Summary.**
- The theme observer accepts the distributed notification from any sender.
- `discardImages()` clears the index and the images, deletes the folder, and replaces PhotoSchedule27, which drops its 45 s / 10 min backoff.
- While the Shelf, search, a group panel or the Layout pane is shown, the cache refreshes every 3 s. Each time, photographMissing reveals up to six concealed apps for 600 ms each and forces a capture.

**Evidence.** `ItemImageStore27.swift:92-113`; `MenuBarItemImageCache.swift:210` and `:407`.

**Failure scenario.** An app posts the notification every few seconds. With the Shelf open, concealed apps keep flashing into the real menu bar, and the screen is captured again and again.

**Fix.**
1. Observe `NSApp.effectiveAppearance` with KVO, which fires after the change, instead of trusting the distributed notification.
2. Discard only when `bestMatch(from: [.aqua, .darkAqua])` actually changed.
3. Keep the photo schedule, or rate-limit discards.

**Verification.** Confirmed low. A related race exists: the detached folder removal can delete freshly written PNGs (F-58).

#### F-47 — Item groups read from settings are not capped; a crafted import or sync file floods the menu bar with status items

- **Severity:** low · **Category:** security · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/Groups/MenuBarItemGroups.swift:74`
- **Classification:** manual-only. The maximum number of groups is a product decision, and the Add Group UI needs the same limit.
- **Merged from:** L2-untrusted-data: "The number of item groups from a file is not capped; each group creates a status item, so a crafted import or sync file floods the menu bar at every launch".

**Summary.**
- ItemGroups is decoded with no limit on count, duplicates or lengths.
- `updateStatusItems` creates one NSStatusItem per group. Spacers, by contrast, are capped at 10.
- A 1 MiB file holds thousands of minimal groups. Duplicate UUIDs share a status item and break ForEach identity.
- The decoded groups persist in local defaults.

**Evidence.** `MenuBarItemGroups.swift:72-81` and the `updateStatusItems` loop; `MenuBarSpacers.maximumCount`.

**Failure scenario.** A settings file the user is talked into importing, or a write to the sync folder, carries 10,000 groups. holzBar creates 10,000 status items at launch, and the bar, Control Center and the item cache stall at every launch until the defaults are cleaned.

**Fix.**
1. When decoding, and in `addGroup`, deduplicate by id and cap the count.
2. Limit the lengths of `name` and `itemTags`.

The maximum itself is a product decision.

**Verification.** Confirmed low. It needs a crafted file plus an import confirmation, or write access to the sync folder. The claim that pullIfNeeded re-applies the file at every launch is overstated, because a file is applied only once; but the decoded groups persist.

#### F-48 — The app never verifies the XPC service's code, and the comment's reasons for skipping it are wrong

- **Severity:** low · **Category:** security · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift:157`
- **Classification:** manual-only. Code-signing validation at runtime (a nested-code check and a cdhash peer requirement) must be verified with both ad hoc and certificate-signed builds. It is a partial mitigation of F-04.
- **Merged from:** G2-bundle-integrity: "The app never checks the XPC service's code, and the reason given in the code is false: the framework it cites is already weak-linked on macOS 14.0, and the session code only runs on macOS 26".

**Summary.**
- `getOrCreateSession` sets a peer requirement only for builds with a team identifier, and no real holzBar build has one. It does no static check either.
- The comment's two reasons are wrong:
  - launchd starts whatever file is at that path inside a user-writable bundle, so "no other code can answer" does not hold;
  - `Session` is declared `@available(macOS 26.0, *)`, and the service target already weak-links LightweightCodeRequirements with a 14.0 deployment target, so the framework's availability is no obstacle.
- A static nested-code check of the app's own bundle before each session, plus a peer requirement pinned to the verified cdhashes, would refuse a swapped service and fall back to the local cache.
- It is only a partial gate: launchd relaunches a dead service, and the check does not run again.

**Evidence.**
- `MenuBarItemServiceConnection.swift:129-132` and `:157-166`.
- `MenuBarItemService/Listener.swift:7` and `:91-94`.
- `otool -L` of the service shows the framework linked weak.
- `project.pbxproj:316` and `:375`: the deployment target.

**Failure scenario.** The service executable has been swapped (F-04). holzBar starts it and trusts every `.sourcePID` reply. With the check in place, holzBar would refuse the swapped service and use its local cache.

**Fix.**
1. In `Session.Storage.getOrCreateSession`, off the main thread, run `SecStaticCodeCheckValidity` on the app's own static code with `kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures`. On failure, throw, so that the local cache is used.
2. For team-less builds, set a peer requirement of `SigningIdentifier(MenuBarItemService.name)` plus `CodeDirectoryHash.in(...)` of the embedded service.
3. Rewrite the comment, including that a relaunched service is not checked again.
4. Verify with ad hoc and certificate-signed builds.

**Verification.** Confirmed low, rated down from medium: the main harm of F-04 remains, and there is a time-of-check gap.

#### F-49 — docs/signing.md and SECURITY.md (T-06-M4) present the trojanized-app threat as mitigated, but a swapped nested service keeps the grants

- **Severity:** low · **Category:** security · **Affects:** macOS 26
- **Location:** `docs/signing.md:7`
- **Classification:** manual-only. Security documentation whose wording depends on how F-04 and F-48 are resolved.
- **Merged from:** G2-bundle-integrity: "docs/signing.md and SECURITY.md T-06-M4 claim a trojanized holzBar.app loses the permission, but swapping the nested service keeps it with no prompt".

**Summary.**
- `docs/signing.md:7` says a holzBar.app whose binary was replaced does not get the permission. That is true for the main executable only.
- `docs/signing.md:99` says the service "pins exactly the app it ships in". It actually limits who may connect to it. It reads the hashes from disk when it starts, so it protects nothing against changes on disk.
- `SECURITY.md:28` marks T-06-M4, "A trojanized holzBar.app gets Accessibility", as "Mitigated", and has no row for nested-code replacement.
- The attestation covers the zip as downloaded, not the installed bundle the user can write to.

**Evidence.** `docs/signing.md:3`, `:7` and `:99`; `SECURITY.md:28`; `Listener.swift:83-90`.

**Failure scenario.**
- A user sees no new Accessibility prompt after the bundle was changed and concludes holzBar is untouched, while a swapped service runs with its grants on macOS 26.
- Maintainers reading "Mitigated" do not prioritise F-04.

**Fix.**
1. Narrow `signing.md:7` to the main executable, and add that on macOS 26 nested code runs with holzBar's grants and is not covered.
2. Reword line 99.
3. Mark T-06-M4 "Partially mitigated", and add an "Open" row for replacement of the nested service (macOS 26).
4. Update both as F-04 and F-48 are resolved.

**Verification.** Confirmed low; a documentation gap.

#### F-50 — The 0.0.6 release notes verify the certificate SHA-256 with a command that never prints it

- **Severity:** low · **Category:** security · **Affects:** all versions
- **Location:** `docs/release-notes/v0.0.6.md:120`
- **Classification:** manual-only. The published GitHub release body must be edited as well, which is a release-infrastructure action.
- **Merged from:** L3-supply-chain: "Release notes tell users to verify the certificate SHA-256 with a command that never prints it".

**Summary.**
- The install section gives the certificate's SHA-256 and says that `codesign -dv --verbose=4` shows it.
- That command prints only Authority, CDHash and TeamIdentifier.
- A look-alike self-signed certificate with the CN "holzBar Release Signing" produces the same Authority line.

**Evidence.**
- `v0.0.6.md:120-123`.
- The actual output on `/Applications/holzBar.app`.
- `docs/signing.md:105-109` has the correct procedure.

**Failure scenario.** A user who got holzBar.app elsewhere runs the documented command, sees the expected Authority line, and grants Accessibility to a binary signed with a look-alike certificate.

**Fix.**
1. Replace the command with `codesign -d --extract-certificates=/tmp/holzbar-certificate /Applications/holzBar.app && shasum -a 256 /tmp/holzbar-certificate0`, and tell users to compare the result with e55f0df1….
2. Do this in these notes and in later ones.
3. Edit the published release body as well.

**Verification.** Confirmed low. The TCC designated requirement still keeps a look-alike from inheriting existing grants.

#### F-51 — macOS 27: the menu bar capture does not check that the bar is on screen, so fragments of the window underneath become item icons

- **Severity:** low · **Category:** privacy · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:189`
- **Classification:** auto-fixable. One guard in one function, reusing the visibility check the click bridge already has. The fullscreen case depends on F-19.
- **Merged from:** R02-macos27: "The menu bar capture does not check that the bar is on screen, so other content is cropped and stored as item icons".

**Summary.**
- `performCapture` captures the top strip of the active display and crops it at each item's AX frame. It never checks that the menu bar is visible.
- In a fullscreen space, or with an auto-hiding bar:
  - `visibleFrame` reaches the top of the screen, so `barHeight` falls back to 22;
  - the strip then shows the window underneath;
  - the AX frames stay stable, so `settledTags` passes;
  - dark or light text passes the glyph test and is stored as a PNG in the Caches folder.
- The click bridge already handles this case.

**Evidence.**
- `ItemImageStore27.swift:189` and `:193-235`.
- SystemItemClickBridge27's `visibleMenuBarRect` handles it.
- Trigger: `MenuBarItemImageCache.updateCacheWithoutChecks`.

**Failure scenario.** The user opens the Shelf or Search with a hotkey while a fullscreen app is frontmost. holzBar shows fragments of the document as item icons and writes them to `~/Library/Caches`.

**Fix.**
1. Before capturing, require the menu bar to be on screen, as `visibleMenuBarRect` does.
2. In a fullscreen space or with auto-hide, require `WindowInfo.menuBarWindow(for:)` to be on screen, and take the strip height from that window.

The fullscreen part depends on F-19.

**Verification.** Confirmed low. The images stay on the Mac; wrong icons are the main effect.

#### F-52 — An unpinned, unsandboxed SwiftLint build phase runs in every build, including the release job with contents:write and id-token:write

- **Severity:** low · **Category:** supply-chain · **Affects:** build, CI and release
- **Location:** `holzBar.xcodeproj/project.pbxproj:232`
- **Classification:** manual-only. Build and release infrastructure: an Xcode build phase and the release job's permissions.
- **Merged from:** R11-scripts-build: "Xcode SwiftLint build phase runs an unpinned swiftlint from PATH, outside the script sandbox, in every build including release builds"; L3-supply-chain: "Release build runs with a job-wide contents:write token and id-token:write, and an unsandboxed script phase executes whatever `swiftlint` is on PATH".

**Summary.**
- The holzBar target's SwiftLint phase prepends `/opt/homebrew/bin` to PATH and runs whatever `swiftlint` it finds.
  - It runs on every build (`alwaysOutOfDate`).
  - User-script sandboxing is off for the target.
- `release.yml` does not disable the phase. It also grants contents:write, id-token:write and attestations:write to the whole job, build included.
- `lint.yml` pins SwiftLint by digest precisely to avoid running an arbitrary version.
- The risk is latent today: the xcode-27 image has no SwiftLint ("SwiftLint not installed").
- A newer SwiftLint with new error-level rules could also make release or `install.sh` builds fail.

**Evidence.**
- `project.pbxproj:215-233`, `:399` and `:434`.
- `release.yml:22-25`.
- `lint.yml:17`.
- Release log 37282353481.

**Failure scenario.** A runner-image update adds Homebrew SwiftLint, or a bottle is compromised. The release build then runs it unsandboxed, with the persisted write credential and the OIDC token request. It could push to main, rewrite release assets, or attest a substitute zip.

**Fix.**
1. Delete the phase, since `lint.yml` already enforces linting, or skip it under CI and for Release.
2. Turn user-script sandboxing on for the target.
3. Split the release into two jobs:
   - a build job with contents: read, `persist-credentials: false` and no id-token;
   - a sign, attest and publish job that holds the secrets, id-token and contents:write.

**Verification.** Both were confirmed low. An attacker who controls the runner image is already trusted, so this is hardening and an extension of T-06-L6.

#### F-53 — The documented `gh attestation verify -R holzcloud/holzBar` accepts an attestation from any workflow on any ref

- **Severity:** low · **Category:** supply-chain · **Affects:** build, CI and release
- **Location:** `docs/signing.md:118`
- **Classification:** manual-only. Documentation for verifying releases. It only means something after F-10 restricts the release workflow to tags.
- **Merged from:** L3-supply-chain: "Documented `gh attestation verify -R holzcloud/holzBar` accepts any workflow on any ref of the repository".

**Summary.**
- The README, the signing docs and the release notes say the attestation proves that a zip was built by the release workflow.
- But the command they give pins only the repository. Any branch workflow can request id-token and attestations write and attest an arbitrary zip.
- `--signer-workflow`, mentioned as optional, still accepts `release.yml` dispatched from a branch.
- Neither form pins the source ref.

**Evidence.** `docs/signing.md:118`, `:124` and `:127`; `v0.0.6.md:76` and `:118`; `release.yml:5-9`.

**Failure scenario.** An attacker with push access attests a trojan zip from a branch workflow, and the documented check passes.

**Fix.**
1. Document this command everywhere as the default: `gh attestation verify <zip> -R holzcloud/holzBar --signer-workflow holzcloud/holzBar/.github/workflows/release.yml --source-ref refs/tags/v<version> --deny-self-hosted-runners`.
2. Correct the wording in `v0.0.6.md:76`.
3. Restrict `release.yml` to tags (F-10).

**Verification.** Confirmed low. It has the same precondition as F-10, and adds little until tags are protected.

#### F-54 — The "no Swift packages" CI gate is bypassed by omitting Package.resolved; project.pbxproj package references are never checked

- **Severity:** low · **Category:** supply-chain · **Affects:** build, CI and release
- **Location:** `.github/scripts/privacy-check.py:166`
- **Classification:** auto-fixable. One CI script, and the new check can be run locally (`python3 .github/scripts/privacy-check.py`).
- **Merged from:** L3-supply-chain: "Swift package gate is bypassed by not committing Package.resolved; project.pbxproj package references are never checked".

**Summary.**
- The no-network job checks only `Package.swift` for `.package(`, and it checks the pins only if `Package.resolved` exists.
- `project.pbxproj` is never scanned for `XCRemoteSwiftPackageReference` or `XCLocalSwiftPackageReference`.
- xcodebuild resolves a missing `Package.resolved` by itself.
- `build.yml` only prints the resolved packages; it does not fail on them.

**Evidence.** `privacy-check.py:159-175`; `build.yml:32-34` and `:290-303`; `allowed-packages.txt`.

**Failure scenario.** A pull request, or an agent session, adds an SPM dependency to the Xcode project without `Package.resolved`. The gate passes, and CI builds the package in.

**Fix.** Fail when:
- `project.pbxproj` contains a package reference whose URL or path is not in `allowed-packages.txt`; or
- such a reference exists without a `Package.resolved`.

**Verification.** Confirmed low. The binary scan for network symbols and the review of pbxproj diffs still apply.

#### F-55 — Debouncer runs a superseded or cancelled action when its sleep had already finished

- **Severity:** low · **Category:** concurrency · **Affects:** all versions
- **Location:** `holzBar/Core/Debouncer.swift:48`
- **Classification:** auto-fixable. `holzBar/Core`, with existing Debouncer tests.
- **Merged from:** R01-core: "Debouncer runs a superseded or cancelled action when its sleep has already finished".

**Summary.**
- `schedule` and `throttle` only cancel the waiting Task.
- Once `Task.sleep` has completed and the resumption is queued on the main actor, cancelling no longer makes the sleep throw. The closure never checks `Task.isCancelled` after waking, so the stale action runs.
- In `throttle`, a stale task also clears `task` and `lastRun`, and can take a newer task's pending action.

**Evidence.** `Debouncer.swift:46-55`, and the throttle closure.

**Failure scenario.** A main-actor event, queued just before the timer fires, calls `schedule` or `cancel`. The old task still runs its action. The debounced work then runs twice, or runs after `cancel()`, contrary to the documented contract. For example, SettingsSync pushes once more after sync was turned off.

**Fix.**
1. Add `guard !Task.isCancelled else { return }` after the sleep in both closures.
2. In `throttle`, capture the task's identity and check `self.task == thisTask` before clearing state.
3. Add a test.

**Verification.** Confirmed low. The window is small, and the effects are mostly harmless.

#### F-56 — A superseded item-cache refresh keeps running after cancellation and can overwrite the newer result

- **Severity:** low · **Category:** concurrency · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:236`
- **Classification:** auto-fixable. Add cancellation checks after each await in one operation.
- **Merged from:** R03-menubaritems: "CacheActor's 'replace' cancels nothing; superseded cache bodies keep running concurrently"; L5-concurrency: "A cancelled item-cache task still writes its stale result over the newer one".

**Summary.**
- `runCacheTask` cancels the previous task. But the `cacheItemsRegardless` body never checks for cancellation after its awaits (`getMenuBarItems`, `updateCachedItemWindowIDs`, `enforceControlItemOrder`, `uncheckedCacheItems`).
- So two bodies interleave on the main actor, and the older one can finish last. It then:
  - writes its earlier window list into `itemCache` and `cachedItemWindowIDs`;
  - runs `saveSections`;
  - starts `reconcileSections` with stale items.
- A cancelled body's divider move fails at `guard !Task.isCancelled` and counts toward MoveBackoff.

**Evidence.** `MenuBarItemManager.swift:236-241`, `:449-454` and `:476-537`.

**Failure scenario.** An app quits during a refresh. The newer refresh finishes first with the right list, then the cancelled one overwrites it.
- The Shelf and the Layout pane show a stale item until the next event.
- A reconcile works from stale positions.

**Fix.**
1. Add `guard !Task.isCancelled else { return }` after each await in the body, and before every state write (inside `uncheckedCacheItems` too).
2. Or stamp each run with a generation number and commit only the latest one.

**Verification.** Both were confirmed low. It corrects itself on the next refresh.

#### F-57 — macOS 27 item scan sets a short messaging timeout only on the application element; per-item reads wait up to 6 s

- **Severity:** low · **Category:** concurrency · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:235`
- **Classification:** manual-only. Conflicts with the deliberate choice not to shorten the timeout on elements that ItemClicker27 presses. It needs a design for setting and resetting timeouts per element.
- **Merged from:** R02-macos27: "Accessibility timeout is set only on the application element; follow-up calls use the default ~6 s timeout and can stall every caller"; L5-concurrency: "macOS 27 item scan sets a messaging timeout only on the application element; every per-item Accessibility read waits the default 6 s".

**Summary.**
- `AXUIElementSetMessagingTimeout` applies only to the element it is set on. AXHelpers documents this, and ItemOpener and ItemChangeWatcher set the timeout per child.
- `readItems` sets it only on the application element. The bar, its children, the hosted elements and MenuBarAgent's windows keep the default.
- The scan schedule records only the result of the first call, and item owners are never paused.
- The scan runs on one serial queue that ItemClicker27, the concealer checks, the image store and the item cache all await.

**Evidence.**
- `MenuBarItemProvider27.swift:126-128`: the deliberate choice for presses.
- `MenuBarItemProvider27.swift:210-212`, `:234-276`, `:286-289` and `:385-391`: the scan and its reads.
- `AXHelpers.swift:81`: the timeout is per element.

**Failure scenario.** An owner answers `kAXExtrasMenuBar`, then becomes busy. Each of its later reads waits up to 6 s, so the serial scan stalls for tens of seconds. Shelf clicks and concealment checks wait behind it.

**Fix.**
1. During the scan, set a short timeout on the bar, children, hosted and window elements.
2. Reset it to `0` afterwards, so ItemClicker27's presses keep the default.
3. Count a timeout from any read toward AccessibilityScanSchedule27, and stop reading a process once one of its reads times out.

**Verification.** Both were confirmed low; the window between the first reply and the later reads is narrow. Leaving the timeout off item elements was a deliberate choice for presses.

#### F-58 — macOS 27: image-store deletes and writes run in unordered detached tasks, so old-appearance glyphs can survive a theme switch

- **Severity:** low · **Category:** concurrency · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:110`
- **Classification:** auto-fixable. One file: a generation counter and one serial I/O queue.
- **Merged from:** L5-concurrency: "ItemImageStore27 deletes and writes the image folder in unordered detached tasks, so glyphs from the old appearance can survive a light/dark switch".

**Summary.**
- `discardImages` removes the folder in a `Task.detached`.
- `store()` and `writeIndex()` write the PNGs, `index.json` and `version.txt` in other detached tasks.
- Nothing orders these tasks.
- In addition, `performCapture` awaits before storing, so a capture taken before a theme switch can be stored after the discard.

**Evidence.** `ItemImageStore27.swift:105-113`, `:191-201`, `:234-237` and `:425-450`.

**Failure scenario.** The appearance changes at sunset right after a capture. The old-colour glyphs are written after the delete. At the next launch the Shelf shows nearly invisible icons until they are photographed again.

**Fix.**
1. Add a generation counter that `discardImages` increments.
2. Capture it before `performCapture`'s first await, and check it before `store` and `writeIndex`.
3. Do all of the store's file I/O on one serial queue.

**Verification.** Confirmed low. The effect is cosmetic and recovers by itself.

#### F-59 — One bad entry in a dictionary- or JSON-valued setting empties the whole setting, and the next save writes the loss back

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/MenuBarItems/ItemIconStore.swift:46`
- **Classification:** manual-only. Cross-cutting: six readers in different subsystems plus SettingsSchema. It also needs a policy for data that cannot be decoded: skip it, back it up, or refuse to overwrite it.
- **Merged from:** L2-untrusted-data: "One bad entry in a dictionary-valued setting empties the whole setting, and the next save writes the empty value back"; R09-settings-main-hotkeys: "One non-Data entry in the Hotkeys dictionary drops every hotkey at every launch"; R05-menubar-other: "A stored profile or group list that fails to decode is silently replaced on the next save".

**Summary.**
- SettingsSchema checks dictionary-kind keys (ItemIcons, MacOS27Layout, ItemSections, Hotkeys, RevealRules) only at the top level, on the stated assumption that their readers check the contents.
- But the readers cast the whole dictionary at once (`as? [String: String]`, `[String: Int]`, `[String: Data]`), and fall back to empty when one entry is wrong.
- LayoutProfiles and MenuBarItemGroups decode their JSON with `try?` and keep an empty array, without logging or a backup.
- The next write then persists the empty value plus the new entry.
- HotkeysSettings is worse: it returns before loading any hotkey, and its save copies the bad entry back, so the loss repeats at every launch.

**Evidence.**
- `ItemIconStore.swift:46`, and its save.
- `Concealer27.swift:76`, and `setSection`.
- `LayoutProfiles.swift:81-89` and `:120`.
- `SectionRestore.swift:49` and `:64`.
- `HotkeysSettings.swift:58`, and `save`/`removeHotkey`.
- `MenuBarItemGroups.swift:72-81`.
- The `.dictionary` check in SettingsSchema.

**Failure scenario.**
- An imported or synced file has MacOS27Layout with one value stored as 1.5 or as "1". On macOS 27 every app becomes visible, and the user's first move writes a layout that contains only that app.
- Or one Hotkeys value is not Data. After a restart no hotkey works, and hotkeys recorded again vanish at the next launch.

**Fix.**
1. Read the values one by one (`compactMapValues { $0 as? Int }`, per-element JSON decoding) and skip bad entries. Alternatively, sanitise the dictionary kinds in `SettingsSchema.validated` before applying them.
2. For JSON blobs that cannot be decoded, log the error and do not overwrite them until the user changes something on purpose, or back up the raw data first.

**Verification.** All three were confirmed low; a malformed, hand-edited or foreign-version file is needed.

#### F-60 — Applying synced settings deletes local keys the sending Mac never had, wiping the per-OS layout between macOS 26 and 27 Macs

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Utilities/SettingsBackup.swift:66`
- **Classification:** manual-only. A sync-semantics decision (merge or replace, and which keys stay local) that interacts with F-02.
- **Merged from:** R07-utilities-permissions-events: "Applying synced settings deletes local keys the other Mac does not have, wiping the per-OS layout (MacOS27Layout or ItemSections) when macOS 26 and 27 Macs sync".

**Summary.**
- `apply()` removes every importable local key that is missing from the incoming dictionary, and sync uses the same `apply()`.
- Some keys exist only on one OS generation:
  - `ItemSections` is written only before macOS 27;
  - `MacOS27Layout`, `MacOS27LayoutSeeded` and `KnownApplications27` only on macOS 27.
- So a file from a Mac of the other generation that never held one of these keys deletes the receiving Mac's layout state.

**Evidence.** `SettingsBackup.swift:62-71`; `SettingsSync.swift:425`; the Defaults keys listed above.

**Failure scenario.**
- A macOS 27 Mac pulls an existing file written only by a macOS 26 Mac. MacOS27Layout and the seeded flag are deleted, and the layout is reseeded, possibly empty.
- In the other direction, the macOS 26 Mac loses `ItemSections`, which it then saves again from the current bar.

**Fix.**
1. For sync (not for file import), set only the incoming keys and do not remove keys the sender lacks: pass `removesMissingKeys: false` from `pullIfNeeded`. Alternatively, treat the generation-specific keys as local.
2. Decide this together with F-02.

**Verification.** Confirmed low. Once both Macs hold the keys, steady-state syncing keeps them, so the join case matters most.

#### F-61 — A custom icon of a few hundred KB pushes the sync file over the 1 MiB read limit, and other Macs silently ignore all synced settings

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Core/SettingsSyncFile.swift:27`
- **Classification:** manual-only. Spans the push, the sync UI (a new warning, with strings in five languages) and the Ice import, and the size policy is a decision.
- **Merged from:** L2-untrusted-data: "Settings with a custom icon of a few hundred KB produce a sync file that every other Mac refuses as too large, with no warning"; L4-privacy-permissions: "The sync file's 1 MB read limit is smaller than the custom-icon data holzBar accepts (8 MB, stored twice and base64-encoded twice), so sync can break silently on the other Macs".

**Summary.**
- Readers refuse sync files over 1 MiB, but `push()` writes any size.
- The custom icon takes much more room in the file than on disk:
  - it is stored twice, because hidden and visible get the same data;
  - JSON base64-encodes it, and the XML plist encodes it again;
  - so the file holds about 3.5 times the image bytes.
- Icons chosen in holzBar are 256 px PNGs and stay small. But icons imported from Ice were stored raw, up to the 8 MiB CustomIconData limit.
- The writing Mac reports success. Receivers only log "Ignoring the sync file: tooLarge".

**Evidence.**
- `SettingsSyncFile.swift:27` and `:114-116`: the limit.
- `SettingsSync.swift:297-319` and `:361-362`: no size check; the log.
- `ControlItemImageSet.swift:57-58`: the icon stored twice.
- `CustomIconData.swift:17-18` and `:31`.

**Failure scenario.** A user who came from Ice with a 400 KB icon turns sync on. The file is about 1.4 MB, and the other Mac never applies any setting, while the UI says it syncs.

**Fix.**
1. Check the encoded size in `push()`. When it is too large, do not write; show a warning in the sync UI (new strings).
2. Write the plist in binary format.
3. Convert an imported Ice icon once with `customIconPNG` during migration.
4. Store the image only once.

**Verification.** Both were confirmed low. It mostly affects users who came from Ice with a large icon.

#### F-62 — A stored custom icon that ImageIO refuses leaves holzBar's own menu bar icon blank, with no fallback

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/ControlItem/ControlItem.swift:400`
- **Classification:** auto-fixable. One file: fall back to the default icon set when the custom image cannot be decoded.
- **Merged from:** L2-untrusted-data: "A stored custom icon that ImageIO refuses (an Ice SVG icon, more than 4096 px, or more than 8 MB) leaves holzBar's menu bar icon blank, with no fallback".

**Summary.**
- The bitmap-only decoder rejects formats and sizes that Ice accepted. Ice stored the raw chosen file, and PDF template icons are common.
- When the decoder returns nil, the control item gets `image = nil` and `title = ""`.
- The custom icon set stays stored.

**Evidence.**
- `ControlItem.swift` (about lines 370-400).
- `ControlItemImage.bitmapImage(from:)` and `CustomIconData.allowedTypeIdentifiers`.
- `Migration.swift` imports IceIcon unchanged.

**Failure scenario.** A user who came from Ice with an SVG icon launches holzBar, and the holzBar icon is an empty slot.

**Fix.**
1. When a custom image cannot be decoded, use the image of `ControlItemImageSet.defaultHolzBarIcon`, and log it once.
2. Convert IceIcon with `customIconPNG` during the Ice import.

**Verification.** Confirmed low. Settings can still be reached by reopening the app.

#### F-63 — An unknown shape kind, end cap or black-background value fails the whole appearance decode, and the next edit overwrites it

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/Appearance/Configurations/MenuBarAppearanceConfigurationV2.swift:82`
- **Classification:** auto-fixable. A lenient `init(from:)` for three enums, following the pattern MenuBarTintKind already uses.
- **Merged from:** R06-appearance-layoutbar: "An unknown shape kind, end cap or black-background value makes the whole appearance configuration fail to decode".

**Summary.**
- MenuBarTintKind and BorderStyle are designed to decode unknown values leniently.
- MenuBarShapeKind, MenuBarEndCap and MenuBarBlackBackground use the synthesized Int raw-value decoding, which throws on an unknown value. `decodeIfPresent ?? default` only covers a missing key, not an unknown value.
- `loadInitialState` then keeps the defaults, and the next edit writes them back, which also syncs.

**Evidence.**
- `MenuBarAppearanceConfigurationV2.swift:82`, `:87` and `:198`.
- `MenuBarShapes.swift:9` and `:17`.
- `MenuBarAppearanceManager.swift:111-119`.

**Failure scenario.**
1. A newer holzBar adds a shape kind.
2. An older build receives the settings by sync, import or downgrade, and shows the default appearance.
3. Its next edit syncs back over the newer Mac's appearance.

**Fix.** Give the three enums the same lenient `init(from:)` as MenuBarTintKind, mapping an unknown raw value to the default case. Alternatively, decode those keys with `try?` in the V2 initializer.

**Verification.** Confirmed low. No current version writes unknown values.

#### F-64 — New items are marked known before they are placed, so a failed or paused placement is never retried

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:250`
- **Classification:** auto-fixable. One function: write KnownItemTags after the move loop, leaving out new items that were not placed.
- **Merged from:** R03-menubaritems: "New items are marked known before they are placed; a failed or paused placement is never retried".

**Summary.**
- `performReconciliation` adds every candidate key to KnownItemTags before the moves run.
- A new item's move can throw: `automaticMovesPaused` breaks the loop, and other errors are only logged.
- Then the item is not in `placedSections`, so its section is not saved.
- Later passes see it as known with no saved section, and never place it.

**Evidence.** `SectionRestore.swift:249-253` and `:256-280`.

**Failure scenario.** "Place new menu bar items in" is set to Hidden, and a new app's item appears while MoveBackoff is paused. The item stays where macOS put it, for good.

**Fix.** Update KnownItemTags after the move loop, and leave out new items that were not placed.

**Verification.** Confirmed low.

#### F-65 — "Keep Live Activities visible" and the new-items placement fight over the same item in every reconciliation

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:233`
- **Classification:** auto-fixable. One filter condition.
- **Merged from:** R03-menubaritems: "Keep Live Activities Visible and the new-items placement fight over the same item in one reconciliation".

**Summary.**
1. `keepLiveActivitiesVisible`, which is on by default, moves a hidden Live Activity to Visible.
2. The same item is then evaluated as a normal candidate, because Live Activities are not excluded.
3. It gets the new-items target and is moved straight back, and `placedSections` stores Hidden.
4. Every later restore repeats both moves, two per pass, which trips MoveBackoff.

**Evidence.** `SectionRestore.swift:206-217`, `:233` and `:310-325`.

**Failure scenario.** "Place new menu bar items in" is set to Hidden, and a Live Activity appears. On every launch, settle and app launch, holzBar drags it to Visible and back, hiding the pointer each time, until MoveBackoff pauses all automatic moves.

**Fix.** When `keepLiveActivitiesVisible` is on, add `!item.tag.isLiveActivity` to the candidates filter. Alternatively, force the target to `.visible` for such items and never store a non-visible section for them.

**Verification.** Confirmed low. It needs a non-default new-items placement, and the Live Activity detection is heuristic.

#### F-66 — A running restore keeps moving items after the user starts dragging, and the reverted arrangement is saved

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:256`
- **Classification:** auto-fixable. One check per loop iteration.
- **Merged from:** R03-menubaritems: "A running restore keeps moving items after the user started dragging; the reverted arrangement is then saved".

**Summary.**
- `reconcileSections` checks `isDraggingMenuBarItem` and `needsSectionSave` once, before `performReconciliation`.
- The move loop does not check them again.
- `EventPoster.move` only waits for the user to pause input.

**Evidence.** `SectionRestore.swift:160-167` and `:256-280`.

**Failure scenario.**
1. A launch restore, which takes seconds on macOS 26, is about to move an app's item to Hidden.
2. The user ⌘-drags that item to Visible.
3. After the drop, the restore drags it back, and the next section save stores Hidden.

**Fix.** At the top of each iteration, and in `keepLiveActivitiesVisible`, break when `wanted == nil && (appState.isDraggingMenuBarItem || needsSectionSave)`.

**Verification.** Confirmed low.

#### F-67 — Position-based identity keys swap between items of one app, so restore can put each item in the other's section

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/SectionRestore.swift:209`
- **Classification:** manual-only. A design decision: it needs a per-app order or discriminator that does not depend on the bar.
- **Merged from:** R03-menubaritems: "Position-based identity keys swap between items of one app, so restore puts the wrong item in each section".

**Summary.**
- `identityKeys(for:)` sorts items by `minX`, and ItemIdentity numbers them in bar order:
  - `#1, #2, …` for the items of title-changing owners;
  - `base, base:2, …` for duplicate canonical titles.
- So a key belongs to a position, not to an item, and moving one item past its sibling swaps their keys.
- This matters when macOS loses the remembered positions, which is exactly when restore matters.

**Evidence.** `SectionRestore.swift:209`; `ItemIdentity.swift:83-97`.

**Failure scenario.**
1. App X has items A (left) and B (right).
2. The user drags B into Hidden, so B is now `#1`, saved as hidden.
3. After a relaunch, macOS restores A to the left of B.
4. The restore now treats A as `#1` and moves it into Hidden.
5. Icons, groups and hotkeys follow the wrong item too.

**Fix.** A design decision: number an app's items by an order that does not depend on the bar, such as the order of its AX extras-bar children, or the autosave or AX identifier where one exists. At minimum, document the limitation.

**Verification.** Confirmed low. The behaviour is a documented design, and the trigger is narrow.

#### F-68 — On macOS 27 identity keys are never disambiguated, so all items of a learned title-changing app share one key

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1166`
- **Classification:** auto-fixable. One assignment in the macOS 27 cache branch.
- **Merged from:** R03-menubaritems: "On macOS 27 identity keys are never disambiguated; items of a learned title-changing app all get key 'ns:#1'".

**Summary.**
- `identityKeysByWindow` is filled only by `updateIdentities`.
- `updateIdentities` runs only `if backend.canMoveItems`, which is false on AccessibilityBackend27, and the macOS 27 branch returns before that point anyway.
- `identityKey(for:)` therefore falls back to calling `keys()` on a single item.
- For a namespace in `titleChangingOwners`, every item then gets `ns:#1`. Such namespaces arrive by sync or import, or are kept from macOS 26.

**Evidence.** `MenuBarItemManager.swift:94`, `:499-512` and `:1162-1198`; `Defaults.swift:313`.

**Failure scenario.** On macOS 27 with settings from a macOS 26 Mac, a custom icon, a group membership, an item hotkey or "Show When It Changes" set on one of a system monitor's items applies to all of them, or to the wrong one.

**Fix.** In the macOS 27 `cacheFromLayout` branch, set `identityKeysByWindow = identityKeys(for: items)` before returning, without the title learning if that is not wanted on 27.

**Verification.** Confirmed low.

#### F-69 — Learned title-changing owners are never unlearned and can be poisoned by a process presenting another app's namespace

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:1185`
- **Classification:** manual-only. Excluding Apple namespaces, or ageing out learned owners, changes how existing users' items are keyed, which needs a decision.
- **Merged from:** G1-hostile-items: "Persisted titleChangingOwners and knownItemTags grow without bound and can be poisoned by a process that shares another app's namespace".

**Summary.**
- `learnTitleChangingOwners` adds a namespace for good once two reads show the same item count with different canonical titles. Only holzBar's own namespace is excluded.
- On macOS 26 the namespace can come from an unverified bundle ID or process name (F-44).
- So a process presenting `com.apple.controlcenter` with a changing title permanently switches Control Center's items to position-based keys.
- `knownItemTags` also only grows, but that is harmless.

**Evidence.** `MenuBarItemManager.swift:1180-1198`; ItemIdentity's `learnTitleChangingOwners`; `SectionRestore.swift:249-253`.

**Failure scenario.** From then on, Control Center's items are keyed `com.apple.controlcenter:#n`, so their saved sections and profile entries follow positions rather than items.

**Fix.**
1. Learn only from namespaces backed by a real bundle ID, and never for Apple or holzBar namespaces.
2. And/or age out learned owners that have not been seen for weeks.

This changes how existing users' items are keyed.

**Verification.** Confirmed low. It needs spoofing or a rare coincidence.

#### F-70 — Any app keeps its item out of the hidden section by putting "LiveActivit" in its title

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemTag.swift:72`
- **Classification:** auto-fixable. One expression in MenuBarItemTag.
- **Merged from:** G1-hostile-items: "Any app keeps its item in the visible section by putting 'LiveActivit' in its title".

**Summary.**
- `isLiveActivity` matches any title containing "LiveActivit", in any namespace.
- `keepLiveActivitiesVisible`, on by default, moves every such hidden item right of the hidden divider on each reconcile, ignoring the saved section.

**Evidence.** `MenuBarItemTag.swift:70-73`; `SectionRestore.swift:309-328`.

**Failure scenario.** An app names its status item "MyLiveActivity". Every time the user hides it, holzBar moves it back at the next launch, app launch or settle.

**Fix.** Apply the title heuristic only to UUID namespaces and Apple (`com.apple.*`) namespaces.

**Verification.** Confirmed low.

#### F-71 — "Show When It Changes" never starts watching an item whose Accessibility element was not found the first time

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift:110`
- **Classification:** auto-fixable. One function: record only the items whose observer was added.
- **Merged from:** R03-menubaritems: "ItemChangeWatcher records items whose Accessibility element was not found and never retries them".

**Summary.**
- `updateObservers` sets `watchedWindows` before it looks up each item's element.
- The lookup can fail: `element(for:)` returns nil because the app is not answering yet or the frame does not match yet, or, on macOS 26, a source PID that is not resolved yet falls back to Control Center. `AXObserverAddNotification` can also fail.
- The item still counts as watched, and later calls with the same key-to-window map return early, so it is never tried again.

**Evidence.** `ItemChangeWatcher.swift:103-118` and `:113`.

**Failure scenario.** After the watched item's app relaunches, the first cache arrives before the app answers. The item is never revealed on change, until its window changes or holzBar restarts.

**Fix.** Build `watchedWindows` only from items whose observer was actually added (let `observe` return Bool). Alternatively, include the resolved PID in the compared map.

**Verification.** Confirmed low.

#### F-72 — The negative lookup cache stores lookups that never scanned for 30 s, giving new items a temporary UUID namespace

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `Shared/Services/SourcePIDCache.swift:248`
- **Classification:** auto-fixable. One file: record a failure only after a full scan.
- **Merged from:** R10-shared-xpc: "Negative lookup cache stores failures that never scanned (unstable bounds, untrusted, app not yet finished launching) for 30 s, giving items random UUID namespaces".

**Summary.**
- `pid(for:)` records a failure whenever `updatePID` leaves no PID. That includes cases where nothing was actually scanned:
  - `updatePID` returned before scanning, because the process is not trusted or the bounds are still moving;
  - it skipped an app whose `isFinishedLaunching` is still false.
- When `isFinishedLaunching` later flips, `runningApplications` does not change, so the 30 s entry stays.
- Meanwhile the item gets a UUID namespace (stable per window), and its tag changes once the lookup succeeds.

**Evidence.** `SourcePIDCache.swift:50-53`, `:138-144` and `:239-256`; `MenuBarItem.swift:374-386`.

**Failure scenario.** A newly launched app's item is read while the app still reports `isFinishedLaunching == false`. For 30 s it is an unknown item that new-item placement may move; then its tag changes again.

**Fix.** Let `updatePID` report whether a full scan over valid apps ran, and record a failure only in that case.

**Verification.** Confirmed low. The race is narrow, and the UUID is stable per window.

#### F-73 — macOS 27: continuous AX created/destroyed notifications from one owner keep postponing item-list refreshes, including the 60 s fallback

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:186`
- **Classification:** auto-fixable. One file: let the 60 s fallback bypass the debouncer, and bound the wait.
- **Merged from:** G1-hostile-items: "macOS 27: continuous AX created/destroyed notifications from any item owner starve the item-list debouncer, including the 60 s fallback".

**Summary.**
- ItemChangeObserver27 observes `kAXCreated` and `kAXUIElementDestroyed` on each owner's whole application element.
- Each callback calls `itemListMayHaveChanged()`, whose `Debouncer.schedule` restarts a 1 s wait.
- The `runningApplications` observer and the 60 s fallback go through the same debouncer.
- So an owner that creates or destroys elements at least once a second postpones `cacheItemsIfNeeded` indefinitely. App activation has its own path and still refreshes.

**Evidence.** `MenuBarItemManager.swift:103-139` and `:186`; `Debouncer.swift:46-48`.

**Failure scenario.** An app updates its UI every 500 ms. A newly launched app's item is then never picked up: placeNewApplications does not conceal it, and it is missing from the Shelf and the Layout pane until the user switches apps.

**Fix.**
1. Let the fallback timer call `cacheItemsIfNeeded()` directly.
2. Give the item-list debouncer a maximum wait, or use throttle, so a refresh runs at least every few seconds while events keep coming.

**Verification.** Confirmed low. Whether common apps produce churn that steady is unproven.

#### F-74 — macOS 27: the theme observer is not installed when the image store's version check fails, so theme switches keep old glyphs

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:80`
- **Classification:** auto-fixable. Move one block above the version check.
- **Merged from:** R02-macos27: "The theme observer is never installed when the image store's version check fails (first run, upgrade, after a theme switch)".

**Summary.**
- `init` returns early when `version.txt` does not match, which happens on first install, after an upgrade, and after a discard. This happens before `appearanceTask` is set, so no theme observer exists for that session.
- Glyphs are tinted at capture time.
- Concealed items are not photographed again while they already have an image.
- So hidden items keep the old tint until relaunch.

**Evidence.** `ItemImageStore27.swift:80-83` and `:92`.

**Failure scenario.** After installing or updating, the user switches to Dark. The hidden items' glyphs stay black and are nearly invisible in the Shelf and the Layout pane.

**Fix.** Install the appearance observer before the version check, and make only the index loading depend on that check.

**Verification.** Confirmed low.

#### F-75 — macOS 27: item images keyed by identifiers other apps choose are never pruned

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/ItemImageStore27.swift:425`
- **Classification:** manual-only. Needs a pruning policy (age, cap) and a last-seen field in the index, which changes the store format.
- **Merged from:** G1-hostile-items: "macOS 27: item images are keyed by identifiers other apps choose and are never pruned (index, in-memory cache and PNG files)".

**Summary.**
- `store()` adds to `loaded` and `index`, and writes a PNG per tag description (bundle ID plus AX identifier).
- Only `discardImages`, on a theme change, clears them. The macOS 26 store prunes; this one does not.
- An app whose identifier changes per launch or per capture adds a file and an index entry each time. While a panel is open, captures run every 3 s.

**Evidence.** `ItemImageStore27.swift:425-437`.

**Failure scenario.** An item with a changing identifier makes the Caches folder, the memory use and the fully re-encoded `index.json` grow until the next appearance change.

**Fix.** Prune entries that are not in the current item list and have not been seen for some time, or cap the index. Both need a last-seen field, which changes the store format.

**Verification.** Confirmed low. In practice the growth is bounded by daily appearance changes.

#### F-76 — macOS 27: system items on the inactive display are guessed with a "widest frame over 80 pt is the clock" rule that misfires

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/MenuBarItemProvider27.swift:302`
- **Classification:** manual-only. Needs a different classification approach, with several options.
- **Merged from:** R02-macos27: "System items on the non-active display are picked by a 'widest frame > 80 pt is the clock' rule, which misfires".

**Summary.**
- On the inactive display, the widest frame wider than 80 pt is taken as the clock, and the frames near it count as system items. This misfires in two ways:
  - A compact clock (time only, 24-hour, or analog) is not wider than 80 pt. That display then gets no system frames, and the click bridge falls back to the other display's frames.
  - An app item wider than the clock (now playing, a ticker) is taken as the clock, and pulls app items into the system set.

**Evidence.** `MenuBarItemProvider27.swift:301-306`; `SystemItemClickBridge27.swift:99-106`.

**Failure scenario.** With two displays and items concealed:
- clicking the clock on the second display does nothing; or
- clicking a wide app item there lifts concealment, and hidden items flash.

**Fix.** Classify the per-display frames:
- by the system items' AX identifiers (`com.apple.menuextra.*`); or
- by matching the active display's system item widths and order.

At minimum, drop the 80 pt rule.

**Verification.** Confirmed low. Only multi-display setups with these configurations are affected.

#### F-77 — macOS 27: a failed concealment apply leaves holzBar claiming concealment, with no retry

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/Concealer27.swift:232`
- **Classification:** auto-fixable. One catch block: a bounded retry.
- **Merged from:** R02-macos27: "A failed concealment apply leaves isConcealing and concealedPIDs claiming concealment, with no retry".

**Summary.**
- `update()` sets `isConcealing`, `concealedPIDs`, `lastConcealed` and the provider's PIDs before the asynchronous apply runs.
- If the apply throws, because it is rejected or MenuBarAgent hits its 3 s timeout, the error is only logged.
- Everything that reads this state then assumes a concealment that does not exist: hit-testing, `leftEdge`, capture skipping and the click bridge.

**Evidence.** `Concealer27.swift:216-239`; `MenuBarAssessmentAssertion27.swift:121-127`.

**Failure scenario.** MenuBarAgent is busy after login or wake. Hidden items stay on the bar while holzBar treats their space as free, until something else calls `update()`.

**Fix.** Schedule a bounded retry of `update()` from the catch block (with a counter, about 1 s). Alternatively, recompute the state from the specs that were actually applied.

**Verification.** Confirmed low. It heals itself on the next `update()`.

#### F-78 — macOS 27: an earlier suspension timer ends a later, longer suspension early

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/MacOS27/Concealer27.swift:418`
- **Classification:** auto-fixable. A deadline check in two timers.
- **Merged from:** R02-macos27: "Overlapping suspensions: an earlier timer ends a later, longer suspension early".

**Summary.**
- Each `suspend` and `suspendReleased` call starts a timer.
- When it fires, the timer always sets `suspendedUntil = nil` and calls `update()`, without checking that the deadline is still its own.

**Evidence.** `Concealer27.swift:418-422` and `:443-447`.

**Failure scenario.** A bridged clock click arrives during a 400 ms relayout suspension. The first timer re-applies concealment while the replayed click is still in flight, and MenuBarAgent ignores the click.

**Fix.** Let each timer capture the deadline it set, and clear only if `suspendedUntil == deadline`. Alternatively, keep a single resume task that each new suspension cancels and replaces.

**Verification.** Confirmed low.

#### F-79 — macOS 27: a drag within one row shows an order macOS does not keep and registers a no-op undo

- **Severity:** low · **Category:** bug · **Affects:** macOS 27
- **Location:** `holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift:78`
- **Classification:** auto-fixable. One condition, plus a reset of the row.
- **Merged from:** R06-appearance-layoutbar: "On macOS 27 a drag inside one row shows a new order that macOS does not keep, and registers a no-op undo".

**Summary.**
- On macOS 27 items keep no order within a section, so the keyboard path refuses in-row moves.
- The drag path still reorders the row. On drop it always calls `setSection` with the row's own section, which:
  - registers an undo;
  - announces "<item> moved to Visible".
- The cache does not change, so the row keeps showing the order the user dragged.

**Evidence.** `LayoutBarContainer.swift:258-265`; `LayoutBarPaddingView.swift:78-85`; `setSection27` at 282-300.

**Failure scenario.** On macOS 27 the user drags an item to the left within Visible.
- The pane shows the new order, but the menu bar is unchanged.
- VoiceOver announces a section move.
- Undo does nothing visible.

**Fix.**
1. On macOS 27, call `setSection` only when the item came from another container.
2. Otherwise, restore the row from the item cache.
3. Optionally, skip the in-row rearrangement during the drag.

**Verification.** Confirmed low.

#### F-80 — holzBar's own activation (to hide application menus) counts as a focus change and rehides the section it just showed

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarManager.swift:189`
- **Classification:** auto-fixable. One guard.
- **Merged from:** R05-menubar-other: "holzBar's own activation (Hide application menus) counts as a focus change and rehides the section it just showed".

**Summary.**
- `hideApplicationMenus` activates holzBar, which changes `NSWorkspace.frontmostApplication`.
- `frontmostApplicationDidChange` does not ignore holzBar itself.
- So with "Focused app" and the pointer outside the menu bar, it hides the hidden section 0.1 s later.

**Evidence.**
- `MenuBarManager.swift:139-146` and `:189-202`.
- `AppState.activate`.
- DockIconPolicy: holzBar does not activate while the Dock icon is kept hidden, which is the default.

**Failure scenario.** With "Hide application menus" on, "Focused app" selected and "Keep the Dock icon hidden" off, showing the hidden section by hotkey, URL or reveal rule hides it again within about 100 ms.

**Fix.**
1. Return early when the new frontmost app is `NSRunningApplication.current`.
2. Compare against the last frontmost PID that is not holzBar.

**Verification.** Confirmed low. It needs two non-default settings.

#### F-81 — Application menus can be hidden after the section was already hidden again (stale async result)

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/MenuBarManager.swift:258`
- **Classification:** auto-fixable. Check the state again after the await.
- **Merged from:** R05-menubar-other: "sectionStatesDidChange hides the application menus after the section was hidden again (stale async result)".

**Summary.**
- `sectionStatesDidChange` starts a Task that awaits `getMenuBarItems`. On macOS 26 that is one XPC lookup per window.
- The Task then calls `hideApplicationMenus()` without checking that a section is still shown.
- If the section was hidden meanwhile, holzBar activates and sets `isHidingApplicationMenus` while every section is hidden.

**Evidence.** `MenuBarManager.swift:258-296`.

**Failure scenario.** A quick double click on the holzBar icon leaves the section hidden. But the frontmost app loses focus, and its menus disappear until the user clicks it.

**Fix.** After the await, add `guard sections.contains(where: { $0.controlItem.state == .showSection }) else { return }`, or use a generation counter.

**Verification.** Confirmed low. It has the same default-setting limit as F-80.

#### F-82 — Opening Settings or closing its window while application menus are hidden leaves the hiding flag stale

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/Main/AppState.swift:377`
- **Classification:** auto-fixable. Call `showApplicationMenus()`, or reset the flag, at the two places that switch to `.accessory`.
- **Merged from:** R09-settings-main-hotkeys: "Opening Settings or closing its window resets the activation policy while application menus are hidden, leaving isHidingApplicationMenus stale".

**Summary.**
- `activate(for: .settings)` sets the `.accessory` activation policy.
- `applicationShouldTerminateAfterLastWindowClosed` also deactivates with `.accessory`.
- Neither clears `isHidingApplicationMenus`.
- So the other app's menus come back while holzBar still thinks it is hiding them.

**Evidence.**
- `AppState.swift:377` and DockIconPolicy.
- `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`.
- `MenuBarManager.toggleApplicationMenus`.

**Failure scenario.**
1. The user hides the application menus with the hotkey.
2. They open Settings with ⌘,, and the menus reappear.
3. The next press of the hotkey does nothing visible.

**Fix.** Wherever holzBar switches to `.accessory` outside `showApplicationMenus`, call `showApplicationMenus()` when `isHidingApplicationMenus` is true, or reset the flag.

**Verification.** Confirmed low.

#### F-83 — Closing the Shelf while it waits for the cache leaves it on screen with no section, and Escape does not close it

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/Shelf/HolzBarShelf.swift:206`
- **Classification:** auto-fixable. A show generation counter in one file.
- **Merged from:** R05-menubar-other: "Closing the Shelf while it waits for the cache leaves an orphaned, undismissable Shelf on screen".

**Summary.**
- Before macOS 27, `show()` sets `currentSection` and `isShelfPresented`, then awaits the cache for up to 1 s before ordering the panel front.
- A `close()` during that await clears both, but `show()` still orders the panel front afterwards.
- With `currentSection` nil, the hidden section reads as hidden. So Escape and item clicks call a `hide()` that returns at `guard !isHidden`, and the panel stays.

**Evidence.** `HolzBarShelf.swift:194-216`, `:77-90`, `:425`, `:455`, `:485`, `:537` and `:551`.

**Failure scenario.** The user double-clicks the holzBar icon, or presses the toggle hotkey twice. The Shelf appears after the second press and stays at level `.mainMenu+1`, until a Space or screen change or another click on the icon.

**Fix.**
1. Keep a show generation counter that both `show()` and `close()` increment.
2. After the await, check `guard generation == showGeneration, currentSection == section else { return }` before setting `contentView` and ordering the panel front.

**Verification.** Confirmed low. It recovers on a Space change or another click.

#### F-84 — The search panel still opens after it was closed while waiting for the image cache

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/Search/MenuBarSearchPanel.swift:122`
- **Classification:** auto-fixable. Store and cancel the show task, in one file.
- **Merged from:** R05-menubar-other: "Search panel opens after it was closed while waiting for the image cache".

**Summary.**
- `show()` sets `isSearchPresented`, then awaits `updateCache()` in an unstructured Task before `makeKeyAndOrderFront`.
- `close()` does not cancel that Task.
- `toggle()` checks `isVisible`, which is still false while the show is pending, so a double toggle starts two shows.

**Evidence.** `MenuBarSearchPanel.swift:91-103`, `:108-139` and `:148-154`.

**Failure scenario.** The user presses the search hotkey and switches Space right away. The panel appears on the new Space after it was closed, with `isSearchPresented` false, so its images go stale.

**Fix.**
1. Store the show task, cancel it in `close()`, and check for cancellation after the await.
2. In `toggle()`, treat a pending show as visible.

**Verification.** Confirmed low. It is cosmetic, and the next click outside closes the panel.

#### F-85 — "Show the hidden section for a moment" hides early on repeated presses and overrides a later manual show

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/Hotkeys/HotkeyActionPerform.swift:69`
- **Classification:** auto-fixable. One cancellable task stored on the menu bar manager.
- **Merged from:** R09-settings-main-hotkeys: "\"Show the hidden section for a moment\" hides early on repeated presses and overrides a later manual show".

**Summary.**
- Each press starts a new, untracked Task that hides the section after `tempShowInterval`.
- A second press does not extend the time, because the first task still hides at its own deadline.
- A manual show in between is undone by the pending task.

**Evidence.** `HotkeyActionPerform.swift:69-74`.

**Failure scenario.**
- With a 15 s interval, the user presses at t=0 and again at t=12, and the section hides at t=15.
- Or the user presses, then clicks the icon to keep the items shown, and they vanish when the timer fires.

**Fix.**
1. Keep one cancellable task, for example on MenuBarManager.
2. Cancel it on each press, and when the section is shown or hidden by any other path.
3. Check for cancellation before hiding.

**Verification.** Confirmed low.

#### F-86 — With Caps Lock on, Option-click and Control-click on the holzBar icon and on empty menu bar space do the wrong thing

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/ControlItem/ControlItem.swift:524`; `holzBar/Events/HIDEventManager.swift:353`, `:361`
- **Classification:** auto-fixable. Mechanical: mask the flags at three comparisons in two files, ideally with the same helper as F-21.
- **Merged from:** R04-backends-controlitem: "Control-click and Option-click on control items fail while Caps Lock is on"; R07-utilities-permissions-events: "Option-click (always-hidden) and Control-click (context menu) on empty menu bar space fail when Caps Lock or another modifier flag is set".

**Summary.**
- `performAction` and HIDEventManager compare the full `NSEvent.modifierFlags` with `== .control` and `== .option`.
- The class property also includes `.capsLock` (and `.function` or `.numericPad`), so the comparisons fail.
- The click then toggles the ordinary hidden section.

**Evidence.** `ControlItem.swift:519-545`; `HIDEventManager.swift:353` and `:361`.

**Failure scenario.** With Caps Lock on:
- Option-click does not reveal the always-hidden section;
- Control-click opens no menu (a right-click still works).

**Fix.** At all three sites, compare `NSEvent.modifierFlags.intersection([.shift, .control, .option, .command])` with `.control` or `.option`.

**Verification.** Both were confirmed low.

#### F-87 — Section dividers keep the drag marker and 3 pt width after a Command-drag ends

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/ControlItem/ControlItem.swift:221`
- **Classification:** auto-fixable. Drop one condition in an observer.
- **Merged from:** R04-backends-controlitem: "Section divider keeps the drag marker '|' and 3 pt width after a Command-drag ends".

**Summary.**
- The divider shows a vertical-bar title and a 3 pt length only while `isDraggingMenuBarItem` and `showAllSectionsOnUserDrag` are both true. Both are defaults.
- The observer calls `updateStatusItem` only when a drag begins.
- When the drag stops, holzBar only clears the flag and saves the sections, so nothing redraws the divider.

**Evidence.** `ControlItem.swift:221-226`, `:421-424` and `:462-468`; `HIDEventManager.swift:480-486`.

**Failure scenario.** On macOS 26 with default settings, the markers stay in the menu bar after a ⌘-drag, until the sections are hidden again. With auto-rehide off, they stay indefinitely.

**Fix.** Call `updateStatusItem()` on every change of `isDraggingMenuBarItem`.

**Verification.** Confirmed low. The effect is cosmetic.

#### F-88 — NSScreen.screenWithMouse returns nil at the top pixel row, so hit tests can use the wrong display

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Utilities/Extensions.swift:506`
- **Classification:** auto-fixable. One expression.
- **Merged from:** R07-utilities-permissions-events: "NSScreen.screenWithMouse returns nil at the top edge of a display, so hit tests fall back to NSScreen.main, which can be the wrong display".

**Summary.**
- `screenWithMouse` uses `CGRect.contains`, which excludes `maxY`.
- At the top pixel row, `NSEvent.mouseLocation` has `y == frame.maxY`, so no screen matches. `isMouseInsideMenuBar` itself accepts that value.
- `bestScreen` then falls back to `NSScreen.main`, the screen of the key window.

**Evidence.** `Extensions.swift:505-507`; `MenuBarHitTesting.swift:19-21` and `:53-56`.

**Failure scenario.** With two displays, the pointer is pinned at the very top of the secondary display while the key window is on the primary one.
- Show on hover, click and scroll do not trigger.
- The hover-hide branch may run.

**Fix.** Use `screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }`.

**Verification.** Confirmed low. Only multi-display setups are affected.

#### F-89 — Permissions are never re-checked after setup: a revoked Accessibility still shows "Permission Granted"

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/Permissions/Permission.swift:108`
- **Classification:** auto-fixable. A check when the app becomes active: one file plus one observer.
- **Merged from:** R07-utilities-permissions-events: "Permission state is never re-checked after setup: a revoked Accessibility still shows 'Permission Granted', and the re-grant recovery never runs".

**Summary.**
- The check task stops once the permission is granted, and AppState calls `stopAllChecks()` at setup.
- `hasPermission` changes only through `performRequest()` or `waitForPermission()`. Neither is reachable while it shows true.
- HIDEventManager's recovery observer runs `healthCheck()` only on a change from false to true, so it never runs either.

**Evidence.**
- `Permission.swift:108-131`.
- `AppState.swift:140`.
- `AdvancedSettingsPane.swift:249-260`.
- `HIDEventManager.swift:265-272`.

**Failure scenario.** The user, an MDM profile or `tccutil` removes Accessibility while holzBar runs.
- Moves, clicks and AX reads fail.
- Settings still shows "Permission Granted", with no Grant button.
- After the user grants it again, no health check runs, so dead taps stay dead until sleep and wake.

**Fix.** Check again, without polling, on `NSApplication.didBecomeActiveNotification` and when the Advanced pane appears. For example, a `refresh()` that updates `hasPermission` and starts the check only when the permission is missing.

**Verification.** Confirmed low.

#### F-90 — On macOS 26 the Layout pane checks Control Center's responsiveness instead of the item's own app

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/LayoutBar/LayoutBarItemView.swift:133`
- **Classification:** auto-fixable. Use `sourcePID ?? ownerPID` at three call sites in one file.
- **Merged from:** R06-appearance-layoutbar: "On macOS 26 the layout bar checks whether Control Center is unresponsive, not the item's own app".

**Summary.**
- On macOS 26, Control Center owns every item window (`ownerPID`), and the real app is `sourcePID`.
- The warning badge, `checkMovable` and the `mouseDragged` guard use `item.ownerPID`. So a hung app is never detected, and a brief Control Center hang flags every item.
- Other code already uses `sourcePID ?? ownerPID`.

**Evidence.** `LayoutBarItemView.swift:133`, `:317` and `:470`; `MenuBarItem.swift:63-65` and `:183-191`.

**Failure scenario.**
- A hung app's item shows no badge, and dragging it fails with a generic error.
- During a Control Center hiccup, every item shows the warning, and the alert names the wrong app.

**Fix.** Add a `responsivenessPID` (`item.sourcePID ?? item.ownerPID`) and use it at the three call sites.

**Verification.** Confirmed low.

#### F-91 — With a dynamic appearance, overlay panels exist only for the current mode, so the other mode's style and Hold to Preview never show

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/Appearance/MenuBarAppearanceManager.swift:166`
- **Classification:** auto-fixable. One function: consider every partial configuration.
- **Merged from:** R06-appearance-layoutbar: "Dynamic appearance: overlay panels are only created for the current light/dark mode, so the other mode's style and 'Hold to Preview' never show".

**Summary.**
- `needsOverlayPanels(for:)` looks only at `configuration.current`.
- Panels are built at setup, on configuration changes (only when none exist), on screen changes, and on settle. A light/dark switch is not among these.
- The manager has no appearance observer.

**Evidence.**
- `MenuBarAppearanceManager.swift:122-131` and `:166-184`.
- `MenuBarAppearanceConfigurationV2.swift:35-41`.
- `MenuBarAppearanceEditor.swift:381-383`.
- `MenuBarOverlayPanel.swift:239-245`.

**Failure scenario.** In light mode, the user turns on dynamic appearance and tints only the Dark mode.
- No panels exist, so "Hold to Preview" for Dark shows nothing.
- Switching to dark leaves the bar untinted until sleep or a display change.

**Fix.** Decide from every partial configuration that can become active: light and dark when the appearance is dynamic, plus a preview configuration.

**Verification.** Confirmed low.

#### F-92 — The System Glass view is not added or removed when light/dark mode switches under a dynamic appearance

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift:608`
- **Classification:** auto-fixable. One override in one view.
- **Merged from:** R06-appearance-layoutbar: "System Glass tint view is not added or removed when light/dark mode switches under a dynamic appearance".

**Summary.**
- `updateGlassView()` runs only from the didSet of `fullConfiguration` and `previewConfiguration`.
- It decides from `configuration.tintKind`, which depends on the current appearance.
- A mode switch changes neither property, so the glass view is not updated.

**Evidence.** `MenuBarOverlayPanel.swift:239-245`, `:586-598`, `:608-623` and `:634-636`.

**Failure scenario.** Light uses System Glass and Dark a solid tint.
- Switching to dark leaves the glass over the solid tint.
- Starting in dark and switching to light shows no glass.

**Fix.** Override `viewDidChangeEffectiveAppearance()` in the content view to call `updateGlassView()` and redraw.

**Verification.** Confirmed low. It needs a niche configuration.

#### F-93 — Several hotkey recorders can record at once; a forgotten one swallows key presses in all of holzBar's windows

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/Views/HotkeyRecorder.swift:177`
- **Classification:** auto-fixable. A static weak reference in the model.
- **Merged from:** R08-ui: "Several HotkeyRecorders can record at once; a forgotten one keeps swallowing every key press in the app".

**Summary.**
- Each recorder has its own local keyDown monitor, which returns nil for every event and so swallows all key presses in the app.
- Clicking Record on a second row does not stop the first one, because mouse events are not monitored.
- Only one of them receives the combination. The other stays in recording mode with its hotkey disabled, and eats keystrokes in every holzBar window while the Hotkeys pane is open.

**Evidence.** `HotkeyRecorder.swift:177-183`.

**Failure scenario.** The user clicks Record on two rows. Typing in the search panel then only beeps. A modified key such as ⌘V would even be recorded as the stray row's hotkey.

**Fix.** Make recording exclusive: keep a static weak "current" recorder, and have `startRecording()` stop it before taking over.

**Verification.** Confirmed low. The stray row visibly shows "Type Hotkey".

#### F-94 — While a hotkey problem alert is shown, recording swallows the keyboard, so Return cannot dismiss the alert

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/Views/HotkeyRecorder.swift:221`
- **Classification:** auto-fixable. One guard in the monitor closure.
- **Merged from:** R08-ui: "Recording swallows the keyboard while the hotkey problem alert is shown, so the alert cannot be dismissed with Return".

**Summary.**
- For Option-only and system-reserved combinations, the model shows an alert but deliberately keeps recording.
- The monitor returns nil for every keyDown, so the alert never gets the keys:
  - Return beeps;
  - Escape stops recording but leaves the alert up;
  - a valid combination typed meanwhile is recorded behind the alert.

**Evidence.** `HotkeyRecorder.swift:221-231`, and the monitor closure.

**Failure scenario.** The user types ⌥⇧K. The "macOS does not allow this hotkey" alert appears, and only the mouse can close it.

**Fix.** In the monitor, return the event unchanged while `presentedProblem != nil`.

**Verification.** Confirmed low.

#### F-95 — Activating another colour well while a gradient stop is selected overwrites the stop's colour

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:132`
- **Classification:** manual-only. The fix relies on how SwiftUI's ColorPicker takes over NSColorPanel (target and action), which is undocumented. It needs verification, and possibly a different design such as a colour well of its own.
- **Merged from:** R08-ui: "Activating another ColorPicker while a gradient stop is selected overwrites the stop's colour".

**Summary.**
- While a stop is selected, the picker writes the colour from every NSColorPanel `colorDidChange` notification into the stop. It never checks which control the panel is editing for.
- Activating the Border Color well posts `colorDidChange` with that well's colour, and keeps the panel and the selection.

**Evidence.**
- `HolzBarGradientPicker.swift:127-136` and `:249-260`.
- `MenuBarAppearanceEditor.swift:235` and `:272`.
- Probe `cp.swift`.

**Failure scenario.** With a stop selected, the user clicks the Border Color well. The stop takes the border colour, and every further edit changes both.

**Fix.** End the stop selection when another well takes over the panel. For example, own the panel's target and action while a stop is selected, and deselect when the target changes.

**Verification.** Confirmed low.

#### F-96 — Distributing gradient stops re-sorts them under an index-based selection, so the panel edits a different stop

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:284`
- **Classification:** auto-fixable. One function.
- **Merged from:** R08-ui: "Distributing stops re-sorts them under an index-based selection, so the colour panel then edits a different stop".

**Summary.**
- `distributeStops()` replaces the stops with a copy sorted by location, but leaves the index-based selection unchanged.
- The stops are usually unsorted, because `insertStop` appends new stops at the end.

**Evidence.** `HolzBarGradientPicker.swift:201` and `:284-300`.

**Failure scenario.**
1. The user selects the stop at 0.8, which is index 0.
2. They double-click to distribute the stops.
3. The highlight jumps to the leftmost stop, and the next colour change recolours that stop.

**Fix.** In `distributeStops()`, map the selection through the sort, or clear it.

**Verification.** Confirmed low.

#### F-97 — Gradient stop handles cannot get keyboard focus and expose nothing to VoiceOver

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/HolzBarUI/HolzBarGradientPicker.swift:345`
- **Classification:** manual-only. Accessibility labels and actions need new strings in five languages and an accessibility design.
- **Merged from:** R08-ui: "Gradient stop handles cannot get keyboard focus: onKeyPress(.space) is dead and the picker is inaccessible".

**Summary.**
- `onKeyPress(.space)` only fires for a focused view, and the handle is never made `.focusable()`.
- There are no accessibility labels, values or actions.
- So keyboard and VoiceOver users cannot select, add, recolour or delete stops.

**Evidence.** `HolzBarGradientPicker.swift:345-348` and `:366`.

**Failure scenario.**
- Tabbing through the Menu Bar Appearance pane skips the picker.
- VoiceOver announces no control for the tint gradient.

**Fix.**
1. Make the handles focusable.
2. Give them accessibility elements, labels ("Color stop N"), values, the button trait, and adjustable or custom actions. These need new strings in five languages.

**Verification.** Confirmed low; an accessibility gap.

#### F-98 — The search list's app-wide arrow and Return monitors break input-method composition in the search field

- **Severity:** low · **Category:** bug · **Affects:** macOS 26 and 27
- **Location:** `holzBar/UI/Views/SectionedList.swift:74`
- **Classification:** auto-fixable. Pass-through checks in three handlers. Needs the event in the `onKeyDown` action, as in F-31.
- **Merged from:** R08-ui: "SectionedList's app-wide arrow/Return monitors break input-method composition and modified arrow keys in the search field".

**Summary.**
- Local keyDown monitors for Down, Up and Return ignore modifiers.
- They are active whenever an item is selected, which is always the case while results are shown.
- They run before the field's input context sees the key. So during input-method composition:
  - Up and Down move the selection instead of choosing a candidate;
  - Return activates an item instead of committing the marked text.

**Evidence.** `SectionedList.swift:74-96`; `MenuBarSearchPanel.swift:235-240`.

**Failure scenario.** A user types an item name with Kotoeri or Pinyin and presses Return to commit it. Instead, the selected menu bar item is clicked.

**Fix.** Pass the event through when the field editor has marked text, or when Command, Option, Control or Shift is held.

**Verification.** Confirmed low.

#### F-99 — Profile names are unique case-sensitively but looked up case-insensitively, so the wrong profile can be applied

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/Profiles/LayoutProfiles.swift:151`
- **Classification:** auto-fixable. Prefer an exact match in one function.
- **Merged from:** R05-menubar-other: "Profile names are unique case-sensitively but looked up case-insensitively, so the wrong profile can be applied"; R09-settings-main-hotkeys: "Profile hotkeys, Shortcuts and URLs apply the wrong profile when two names differ only in case".

**Summary.**
- `saveCurrentLayout` and `rename` compare names exactly, so "Work" and "work" can both exist.
- `profile(named:)` and `apply(named:)` take the first case-insensitive match in sorted order.
- `replaceProfiles` does not remove duplicates.
- `id: name` gives SwiftUI IDs that look like duplicates.

**Evidence.**
- `LayoutProfiles.swift:107`, `:131`, `:150-152`, `:193-196` and `:205`.
- `HotkeyActionPerform.swift:19` and `HolzBarIntents.swift:160`: lookups by name.

**Failure scenario.** The hotkey for "work" applies "Work". Items move to the wrong sections, and the wrong profile is recorded as current.

**Fix.**
1. In `profile(named:)`, prefer an exact match, and fall back to case-insensitive matching only when there is none.
2. Optionally, refuse names that collide case-insensitively in save and rename.

**Verification.** Both were confirmed low.

#### F-100 — Deleting a group leaves its custom image file in ItemIcons

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/Groups/MenuBarItemGroups.swift:110`
- **Classification:** auto-fixable. Delete the file in one function.
- **Merged from:** R05-menubar-other: "Deleting a group leaves its custom image file in ItemIcons".

**Summary.** `deleteGroup` only removes the group. Its `imageFile` is never passed to `itemIconStore.deleteFile`.

**Evidence.** `MenuBarItemGroups.swift:110-112` and `:200-206`.

**Failure scenario.** The copied images of deleted groups pile up in `Application Support/holzBar/ItemIcons`.

**Fix.**
1. Capture `group.imageFile`.
2. Remove the group.
3. Call `itemIconStore.deleteFile(named:)`, which skips files that are still in use.

**Verification.** Confirmed low.

#### F-101 — Applying a new item spacing on macOS 26 silently skips apps whose source PID could not be resolved

- **Severity:** low · **Category:** bug · **Affects:** macOS 26
- **Location:** `holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift:191`
- **Classification:** manual-only. Needs a new user-facing message, in five languages.
- **Merged from:** R05-menubar-other: "Spacing relaunch silently skips every app whose source PID could not be resolved on macOS 26".

**Summary.**
- For items without a source PID, `applyOffset` falls back to `ownerPID`, which is Control Center on macOS 26.
- `processesToRelaunch` drops Control Center.
- So the real owner is never relaunched or reported, and `applyOffset` reports success.

**Evidence.**
- `MenuBarItemSpacingManager.swift:191` and `:224-230`.
- `ServiceBackend26.swift:43-56`.
- `SpacingRelaunch.processesToRelaunch`.

**Failure scenario.** Some items could not be resolved. After the user applies a new spacing, only Control Center and the resolved apps restart. The others keep the old spacing, and holzBar reports success.

**Fix.**
1. On macOS 26, count the unresolved items that are not control items, and report them, for example "N items could not be attributed to an app; log out to apply". This needs new strings.
2. Or retry the resolution once.

**Verification.** Confirmed low.

#### F-102 — The spacing relaunch can leave an app quit and not restarted while the error says it did not quit

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift:144`
- **Classification:** manual-only. Needs new user-facing messages, in five languages.
- **Merged from:** R05-menubar-other: "Spacing relaunch can leave an app quit and not restarted, while the error says it 'did not quit'".

**Summary.**
- `relaunchApp` throws the same error in three different cases:
  - the app has no bundle;
  - quitting timed out;
  - `openApplication` failed after the app had already quit.
- `relaunchFailure` keeps only the app's name.
- The grouped message always says the apps did not quit and were not restarted.

**Evidence.** `MenuBarItemSpacingManager.swift:20-32`, `:133-145` and `:149-172`.

**Failure scenario.** A VPN or backup client quits on request but cannot be reopened, because its bundle was moved or updated. The alert says it did not quit, so the user assumes it is still running.

**Fix.**
1. Use distinct error cases: `noBundle`, `quitTimedOut` and `launchFailed`.
2. Show a separate "quit but could not be reopened" list. This needs new strings.

**Verification.** Confirmed low.

#### F-103 — Shortcuts actions run before setup and do nothing or fail misleadingly; the notReady error is never thrown

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/Main/HolzBarIntents.swift:38`
- **Classification:** auto-fixable. A readiness flag on AppState, checked by `intentAppState()`. The error text already exists.
- **Merged from:** R09-settings-main-hotkeys: "Shortcuts actions run before setup and report success with no effect; the notReady error is dead code".

**Summary.**
- `intentAppState()` only checks `AppState.current`, which `AppDelegate.init` sets before setup.
- Setup takes seconds, and never runs while permissions are missing.
- During that time, actions misbehave:
  - ChangeSectionIntent throws `sectionUnavailable`;
  - OpenMenuBarItemIntent throws `noMatchingItem`;
  - SearchMenuBarItemsIntent reports success while nothing happens.

**Evidence.** `HolzBarIntents.swift:18-43`; `AppDelegate.init`; `AppState.setupTask`.

**Failure scenario.** An automation launches holzBar and runs an action at once, or permissions are missing. Shortcuts reports the wrong reasons, or success with no effect.

**Fix.**
1. Add `private(set) var isSetUp` to AppState, and set it at the end of `setupTask`.
2. In `intentAppState()`, throw `.notReady` (whose message already exists) unless it is set.

**Verification.** Confirmed low. The finding's headline example was refuted: a profile apply does not report success, because Shortcuts resolves the entity first and reports an unresolved parameter. The other intents behave as described.

#### F-104 — The Settings window opened before setup shows defaults instead of stored values and drops hotkey edits

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/Main/AppDelegate.swift:126`
- **Classification:** auto-fixable. Open the permissions window instead, at two call sites.
- **Merged from:** R09-settings-main-hotkeys: "Settings window opened before setup shows defaults instead of stored values and drops hotkey edits".

**Summary.**
- The settings models load their stored values only in `setupTask`, which is skipped while permissions are missing.
- `applicationShouldHandleReopen` and `holzbar://settings` still open Settings. Its panes then:
  - show the properties' default values;
  - write those wrong states when the user toggles something;
  - neither register nor save recorded hotkeys.

**Evidence.** `AppDelegate.swift:126`; `AppState.setupTask`; `HotkeysSettings.performSetup`; `Hotkey.Listener.init`.

**Failure scenario.** Accessibility was revoked. The user opens holzBar from Finder, and Settings opens next to the permissions window. It shows "Show on hover" as off although it is on.

**Fix.** While permissions are missing, open the permissions window instead, both in `applicationShouldHandleReopen` and in the `.settings` URL command.

**Verification.** Confirmed low.

#### F-105 — The conflicting-app check matches any app by display name and force-terminates it after 3 s

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `holzBar/Main/ConflictingApps.swift:28`
- **Classification:** auto-fixable. Stop force-terminating apps that match only by name, in one file.
- **Merged from:** R09-settings-main-hotkeys: "Conflicting-app check matches any app by display name and force-terminates it after 3 s"; L1-attack-surface: "Conflicting-app check matches any app by display name and force-terminates it after 3 s".

**Summary.**
- Any running app whose `localizedName` is "Ice", "Thaw", "Bartender" or "Hidden Bar" counts as a menu bar manager.
- After the user agrees, holzBar sends `terminate()`, and calls `forceTerminate()` after 3 s. An app that is showing a save sheet loses its work.
- An app can also name itself this way to make holzBar ask at every launch; declining quits holzBar.

**Evidence.** `ConflictingApps.swift:28`, `:39`, `:61` and `:65-75`.

**Failure scenario.** An unrelated document app named "Ice" has unsaved changes. The user confirms "Quit Ice first?", and the app is force-killed.

**Fix.**
1. Never force-terminate an app that matched only by name: send `terminate()` only, and log if it stays.
2. Match by bundle identifier where it is known; add Hidden Bar's and Thaw's IDs once confirmed.

**Verification.** Both were confirmed low. It needs an unrelated app with exactly that name, plus the user's confirmation.

#### F-106 — The Raycast profile script does not encode "/" and needs python3, so some profiles apply wrongly or not at all

- **Severity:** low · **Category:** bug · **Affects:** all versions
- **Location:** `Integrations/Raycast/holzbar-profile.sh:14`
- **Classification:** auto-fixable. One line in one script.
- **Merged from:** R11-scripts-build: "Raycast profile script leaves '/' unencoded, so profile names with a slash apply the wrong profile or none"; R11-scripts-build: "Raycast profile script depends on python3, which a stock macOS lacks; failure opens holzbar://profile/ silently"; L1-attack-surface: "Raycast profile script mis-encodes profile names containing '/' and depends on python3"; L4-privacy-permissions: "Raycast profile script does not percent-encode '/', so a profile whose name contains a slash cannot be applied, or a different profile is targeted".

**Summary.** Two problems in the same line:
- **"/" is not encoded.** `urllib.parse.quote` keeps "/" by default. URLCommand splits the path on "/" and uses only the first component. So "Home/Office" asks for "Home"; profile names may contain "/".
- **python3 may be missing.** Without the Command Line Tools, `/usr/bin/python3` is a stub that shows an installer dialog and prints nothing. The script has no `set -e`, so it silently opens `holzbar://profile/`, which is an unknown command.

**Evidence.** `holzbar-profile.sh:14`; `URLCommand.swift:96-100` and `:130`; `LayoutProfiles.swift:107`.

**Failure scenario.**
- A user runs "Apply holzBar Profile" with "Home/Office" and is asked to apply "Home".
- A user without the Command Line Tools gets an installer dialog, and nothing happens.

**Fix.** Use `NAME=$(osascript -l JavaScript -e 'function run(a){return encodeURIComponent(a[0])}' "$1") || exit 1; [ -n "$NAME" ] || exit 1; open "holzbar://profile/$NAME"`. At least use `quote(sys.argv[1], safe='')`.

**Verification.** All four were confirmed low. holzBar always asks before applying a profile, which limits the damage.

#### F-107 — install.sh's TCC reset by bundle ID also revokes the Homebrew release's permissions

- **Severity:** low · **Category:** bug · **Affects:** build, CI and release (developers with both installs)
- **Location:** `Scripts/install.sh:76`
- **Classification:** manual-only. A design decision about TCC identity: a separate bundle identifier for source builds, or a warning.
- **Merged from:** R11-scripts-build: "install.sh's TCC reset by bundle ID also revokes the Homebrew release's permissions".

**Summary.**
- `tccutil reset` clears the grants of every copy with the bundle ID `com.holzcloud.holzBar`.
- So installing a source build to `~/Applications` wipes the Accessibility and Screen Recording grants of the stably signed copy in `/Applications`. TCC keeps only one code requirement per bundle ID anyway.
- Both copies register `holzbar://`, so LaunchServices may start either one for a URL.

**Evidence.** `install.sh:76-77`, and its default `DEST`; `Casks/holzbar.rb:21`.

**Failure scenario.**
- A user with the cask builds from source once, then returns to `/Applications/holzBar.app` and must grant both permissions again.
- A Raycast command may launch the other copy.

**Fix.** Either:
- warn before resetting when another copy is registered (`mdfind "kMDItemCFBundleIdentifier == 'com.holzcloud.holzBar'"`); or
- build source installs with a distinct bundle identifier suffix.

**Verification.** Confirmed low. Only developers with both installs are affected. F-40's fix makes the reset run every time.

#### F-108 — verify-conceal.sh leaves a screencapture loop running when interrupted

- **Severity:** low · **Category:** bug · **Affects:** macOS 27 (maintainer script)
- **Location:** `Scripts/macos27/verify-conceal.sh:77`
- **Classification:** auto-fixable. One function in one script.
- **Merged from:** R11-scripts-build: "verify-conceal.sh leaves a runaway screencapture loop when interrupted".

**Summary.**
- The capture loop is a background subshell that stops only when `$WORK/stop` exists.
- In a non-interactive bash, background commands ignore SIGINT.
- The EXIT trap neither creates the stop file nor kills the loop.
- The work folders in `/tmp` are never removed.

**Evidence.** `verify-conceal.sh:51-56` and `:77-85`.

**Failure scenario.** Ctrl-C during the hover cycles leaves screencapture running. Several times a second, it writes PNGs of the menu bar, which can show notification counts or VPN state, into `/tmp`, until the process is killed or the Mac reboots.

**Fix.**
1. In `restore()`: `touch "$WORK/stop"; if [ -n "${CAPTURE:-}" ]; then kill "$CAPTURE" 2>/dev/null || true; wait "$CAPTURE" 2>/dev/null || true; fi`.
2. Remove `$WORK` on success.

**Verification.** Confirmed low; a maintainer script.

#### F-109 — The clock-restore and reveal-window probes leave a MacOS27ClickRestoreDelay override behind when interrupted

- **Severity:** low · **Category:** bug · **Affects:** macOS 27 (maintainer probes)
- **Location:** `Scripts/macos27/clock-restore.swift:99`
- **Classification:** auto-fixable. Signal handling in two maintainer probes.
- **Merged from:** R11-scripts-build: "clock-restore / reveal-window leave a MacOS27ClickRestoreDelay override behind when interrupted".

**Summary.**
- Both probes write the override to holzBar's real defaults for each delay they test, and delete it only after the loop. Neither handles SIGINT.
- SystemItemClickBridge27 honours any stored value, clamped to 30–2000 ms, until it is removed.

**Evidence.**
- `clock-restore.swift:99-106` and `:155-160`.
- `reveal-window.swift:85-92` and `:159-164`.
- `SystemItemClickBridge27.swift:193`.

**Failure scenario.** The developer stops reveal-window during its 400 ms pass. From then on, every clock or Control Centre click on macOS 27 lifts concealment for 400 ms instead of 120 ms, which exposes hidden items longer.

**Fix.** Handle SIGINT with a DispatchSource that runs the delete before exiting. Or honour the override only in DEBUG builds.

**Verification.** Confirmed low.

#### F-110 — The project's MARKETING_VERSION is stale (0.0.5), so source builds report the wrong version

- **Severity:** low · **Category:** bug · **Affects:** all versions (source builds)
- **Location:** `holzBar.xcodeproj/project.pbxproj:444`
- **Classification:** manual-only. Release versioning process: bump per release, or derive from tags.
- **Merged from:** R11-scripts-build: "Project MARKETING_VERSION is stale (0.0.5), so source builds show the wrong version".

**Summary.**
- Only `release.yml` overrides `MARKETING_VERSION`.
- The project says 0.0.5 in all four configurations, while v0.0.6 and v0.0.7-beta1 exist.
- `install.sh` passes nothing, so the About pane of a source build shows 0.0.5.

**Evidence.** `project.pbxproj:409`, `:444`, `:467` and `:492`; `release.yml:65`; `AboutSettingsPane.swift:70`.

**Failure scenario.** A tester's bug report from an `install.sh` build names a version two releases older than the code.

**Fix.** Bump `MARKETING_VERSION` with each release, or derive it in `install.sh` from `git describe --tags`.

**Verification.** Confirmed low.

#### F-111 — Dispatching the release for an existing tag publishes a binary built from a different commit than the tag

- **Severity:** low · **Category:** bug · **Affects:** build, CI and release
- **Location:** `.github/workflows/release.yml:183`
- **Classification:** manual-only. Release infrastructure.
- **Merged from:** L3-supply-chain: "workflow_dispatch for a version whose tag already exists publishes a binary built from a different commit than the tag".

**Summary.**
- On `workflow_dispatch`, the zip is built from the dispatched ref.
- `gh release create` uses an existing tag as it is.
- Nothing checks that the tag points at `GITHUB_SHA`.

**Evidence.** `release.yml:42` and `:183-184`.

**Failure scenario.**
1. The tag-push run for v0.0.7 fails in Build.
2. The maintainer fixes main and dispatches the release for 0.0.7.
3. The release carries a binary built from commit B, under a tag and source archive from commit A. That breaks the GPL source correspondence.

**Fix.** In "Determine version", fail on dispatch when `refs/tags/v$VERSION` exists and differs from `GITHUB_SHA`. Or remove `workflow_dispatch`.

**Verification.** Confirmed low; a maintainer recovery path.

#### F-112 — The release job cannot be re-run after a failed cask update and has no concurrency guard

- **Severity:** low · **Category:** bug · **Affects:** build, CI and release
- **Location:** `.github/workflows/release.yml:186`
- **Classification:** manual-only. Release infrastructure.
- **Merged from:** L3-supply-chain: "Release job is not re-runnable and has no concurrency guard; a failed cask push leaves a published release with a stale cask".

**Summary.**
- The release is created before the cask is bumped.
- Re-running after a failed cask push rebuilds a zip with a different hash, and fails at `gh release create`.
- Re-running after the cask commit fails at `git commit -am`.
- There is no concurrency group, so two tags pushed together race on main.

**Evidence.** `release.yml:171-197`: no existence check, no retry, no `concurrency:`.

**Failure scenario.** Two tags pushed together leave the cask at the wrong version, or one run fails. Re-running cannot fix it, so the cask has to be fixed by hand.

**Fix.**
1. Add `concurrency: { group: release, cancel-in-progress: false }`.
2. Skip release creation when the release already exists.
3. Use `git diff --quiet || git commit`.
4. Retry `git pull --rebase && git push`.
5. Only ever move the cask forward.

**Verification.** Confirmed low; an operational issue. The cask's hash always matches a genuine asset.

## Coverage

### What was examined

| Slice | Files reviewed |
|---|---|
| R01-core | 64 |
| R02-macos27 | 32 |
| R03-menubaritems | 32 |
| R04-backends-controlitem | 27 |
| R05-menubar-other | 35 |
| R06-appearance-layoutbar | 35 |
| R07-utilities-permissions-events | 43 |
| R08-ui | 42 |
| R09-settings-main-hotkeys | 57 |
| R10-shared-xpc | 22 |
| R11-scripts-build | 47 |
| L1-attack-surface | 69 |
| L2-untrusted-data | 46 |
| L3-supply-chain | 21 |
| L4-privacy-permissions | 71 |
| L5-concurrency | 60 |
| G1-hostile-items (gap round) | 31 |
| G2-bundle-integrity (gap round) | 16 |
| G3-layout-faults (gap round) | 41 |

At least one slice, and usually several, read each of the following:
- every Swift file under `holzBar/`, `Shared/` and `MenuBarItemService/`;
- the Info.plists, the pbxproj and `Package.swift`;
- `Scripts/`, `Integrations/` and `Casks/`;
- the `.github/` workflows and scripts;
- `SECURITY.md` and the key docs.

The critic compared `git ls-files` (without `.planning/`, `.claude/`, images and localisation catalogs) with every slice's list and found the shipping code completely covered. The branch diff (13 files) was read by R01, R03, R04 and L5. The new `StatusItemWindowFrame.assign` logic looks sound.

The critic also checked these patterns for repeats; all were already covered:
- `Task(timeout:)` has 4 call sites: EventPoster ×3 and HolzBarShelf.
- `NSScreen.screenWithMouse` has one definition.
- All strict modifier-flag comparisons were reported (F-21, F-86).
- The private API surface is `Shims.swift` and `MenuBarAssessmentAssertion27.swift`.
- Unmanaged/CF ownership is correct.
- Hotkey integer conversions use `exactly:`, and persisted numbers are clamped.
- Image and icon file names cannot be steered by path traversal.
- There is no ObservableObject/@Published, no document type and no AppleScript.
- No secrets are committed in tracked source.
- Every periodic loop and timer was reviewed.

Repository protection was checked through the GitHub API with read-only calls only (F-10).

The gap round targeted the following:
- **G1:** data that other apps control (their AX attributes, window names, bundle IDs, item churn).
- **G2:** whether replacing nested code keeps the TCC grants.
- **G3:** layout faults outside the R06 and R08 regions.

Synthesizer checks for this report:
- `OwnStatusItemWindows` covers only control items (F-12).
- A modal run loop started from a main-actor Task blocks other main-actor work (F-02, F-14). Probe: `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/audit-synth/modal.swift`.
- MenuBarAgent does not exist on this macOS 26 host (F-45).
- The String Catalogs require German, French, Italian and Romansh for every new string. This affected the classification.

### What was not examined, or only partly

- **Tests.** No slice reviewed these:
  - `Tests/HolzBarMacOS27CoreTests/*.swift` (9 files);
  - 38 of the 43 files in `Tests/HolzBarCoreTests`. Only the AsyncLock, Debouncer and ItemIdentity tests were read, and the SettingsSyncFile and SettingsSyncDevice tests only for their names.

  To make sure they hide nothing, the critic ran `swift test` on a copy of the package at HEAD 3d2f1bb, and everything passed:
  - SharedCodeSigning: 6 tests;
  - HolzBarMacOS27Core: 127 tests in 25 suites;
  - HolzBarCore: 248 tests in 43 suites.
- **Files the critic read itself, with no issue found:**
  - `holzBar/Hotkeys/KeyCode.swift`;
  - the shared schemes `holzBar.xcscheme` and `MenuBarItemService.xcscheme`;
  - `Resources/Logo/render-banner.js` (a local dev tool);
  - `.github/scripts/strings-check.py` beyond line 80 (it only opens files).
- **Not code, not reviewed:** `holzBar.xcodeproj/project.xcworkspace/*`, `.github/ISSUE_TEMPLATE/*.yml`, `docs/build-and-troubleshooting.md`, `docs/features.md`, `docs/macos27.md`, `docs/comparison.md`, older release notes, CODE_OF_CONDUCT, LICENSE, NOTICE, `.gitattributes` and the asset-catalog `Contents.json` files. The docs were only grepped for `xattr`, `spctl`, `sudo` and `tccutil` advice, and none was found.
- **Runtime limits.**
  - The host runs macOS 26.7.1, so every macOS 27 finding rests on the code and its own documented measurements, not on runtime observation.
  - This Mac has only the Command Line Tools, so the app target was not built locally.
  - No exploit was run end to end:
    - F-04 would need a TCC grant for a test bundle, or a write to the installed bundle;
    - no fullscreen space was created (F-19), and Caps Lock was not toggled (F-21), to avoid changing the user's session.
  - The running holzBar and its XPC service were not quit, relaunched or signalled.
- **Localisation catalogs and images** were excluded from the review. Only their language set was checked.

## Known issues excluded

The following known issues were excluded. They were not re-reported, except where a finding shows new evidence or a different consequence; each such case is noted in that finding.

- **K1 (fixed on this branch):** the blocking `XPCSession.sendSync` on the main thread, and the recognition of holzBar's own control items by window frame (BlockingWork, StatusItemWindowFrame, OwnStatusItemWindows). F-12 is a different lock in the local fallback, which K1's fix left shared with a main-thread handler.
- **K2:** `XPCSession.sendSync` is used instead of `send(_:replyHandler:)`. F-37 notes that the missing timeouts and reply deadline are new, beyond the API choice.
- **K3:** a data race in the XPC session's cancellation handler (`Session.Storage` sets `session = nil` without the lock). F-12 is not K3.
- **K4:** on macOS 26 with "Displays have separate Spaces" off, the second display's copies of items get UUID namespaces. F-37 mentions these windows only as a trigger for repeated scans.
