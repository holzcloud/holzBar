---
status: awaiting_human_verify
trigger: "macOS 26.7.1 (25G241), holzBar 0.0.6 installed via Homebrew: Settings > Menu Bar Layout shows \"Loading menu bar items…\" forever (items never load). Findings so far: unified log of the running app (pid 19393) repeatedly shows `[MenuBarItemManager] Missing control item for hidden section, clearing menu bar item cache (22 items)` and `[SectionRestore] Missing control item for hidden section, not reconciling sections`; no XPC/MenuBarItemService errors. Window list: holzBar's 4 control-item windows (IDs 2055-2058, two displays, hidden divider expanded to width 5016) are owned by Control Center (pid 855), not holzBar. Defaults have autosave names `holzBar.ControlItem.Hidden/Visible` but no ItemSections key, so the control items were never recognised on this install. The 0.0.5 fix c261c07 (OwnStatusItemWindows: match NSWindow.windowNumber of own status items) evidently does not work. Tag match needs namespace .holzBar AND title == autosave name; title comes from kCGWindowName of the Control-Center-owned window (needs Screen Recording), ScreenCapture.checkPermissions() judges permission by the first non-own window's title. No Xcode on this Mac (only CLT), so the app can only be built in CI. After the fix, also review all other holzBar logs for further errors."
created: 2026-10-05T06:41:02Z
updated: 2026-10-05T09:45:00Z
---

## Current Focus
<!-- OVERWRITE on each update - always reflects NOW -->

hypothesis: CONFIRMED (AND-gate of two causes). (A) Since 0.0.6 the app target builds with SWIFT_APPROACHABLE_CONCURRENCY (NonisolatedNonsendingByDefault), so `MenuBarItemService.Connection.start()` / `sourcePID(for:)` run their blocking `XPCSession.sendSync` on the main thread (callers are @MainActor). The XPC service resolves an item's app by asking every app's extras menu bar through Accessibility — holzBar's own included — and holzBar cannot answer while its main thread waits for that very reply, so holzBar's control items never get a source PID → `.uuid` namespace → `.hiddenControlItem` never matches → cache cleared → "Loading…" (Layout pane and Shelf; the Shelf is what the icon click opens, UseIceBar = 1). (B) The fallback meant for exactly this (OwnStatusItemWindows, matching NSWindow.windowNumber) never matches on macOS 26.7.1, because a status item's NSWindow.windowNumber is k << 32, not the Control-Center window's CGWindowID. 0.0.5 had (B) but not (A) (Swift 5 mode), so it worked.
test: Fix both causes; regression tests in HolzBarCore (swift test); typecheck the app module locally with swiftc; human verification of a CI build on the user's Mac.
expecting: holzBar's own control items are recognised (namespace com.holzcloud.holzBar, title = identifier) on macOS 26, the main thread is never blocked by an XPC lookup, the Layout pane and Shelf list the items.
next_action: Awaiting human verification of ONE CI build of the branch fix/macos26-own-control-items at 470ed14 (commits 722ede9 + 470ed14; origin has 722ede9, the local branch is 1 ahead and not pushed). The orchestrator pushes, CI builds, the user installs the build and runs human_verify_steps below. On "confirmed fixed" → archive_session; otherwise resume the investigation with the new log.
human_verify_steps:
  - "Install the CI build of 470ed14 (quit holzBar 0.0.6 first, replace /Applications/holzBar.app, xattr -dr com.apple.quarantine /Applications/holzBar.app, launch). Keep both displays connected."
  - "Main display: open Settings > Menu Bar Layout. Expected: the items appear by section within a few seconds (no endless 'Loading menu bar items…')."
  - "Click the holzBar icon on the main display's menu bar. Expected: the holzBar Shelf opens and lists the hidden items (UseIceBar = 1)."
  - "Second display (specialist suggestion 1): click a window on the second (built-in) display so its menu bar becomes the active one, wait 2 s, then open the Shelf from the holzBar icon on that display. Expected: the Shelf lists the hidden items there too."
  - "Check the log: /usr/bin/log show --last 10m --predicate 'subsystem == \"com.holzcloud.holzBar\"' --info --debug | grep -E 'Missing control item|Missing sourcePID|Couldn.t find section'. Expected: no 'Missing control item for hidden section' after the launch (a single one right after a display switch that is followed by a successful read is tolerable since 470ed14 retries; a repeating one is a failure)."
  - "Optional: /usr/bin/log show --last 10m --predicate 'process == \"holzBar\" AND (messageType == error OR messageType == fault)' to review the other errors (expected: no 'Security … should not be called on the main thread' fault any more)."
  - "Report 'confirmed fixed' or what still fails (with the log output). If the second-display step fails while the main display works, the documented fallback is matching by distance from the display's right edge (specialist suggestion 1)."
bug_class: Bohrbug (deterministic on every launch on this Mac)
reasoning_checkpoint:
  hypothesis: "holzBar 0.0.6 cannot find its hidden control item on macOS 26 because the blocking XPC source-PID request runs on the main thread (NonisolatedNonsendingByDefault, new in 0.0.6), so the service's Accessibility query of holzBar's own extras menu bar cannot be answered and holzBar's items get UUID namespaces; the window-number fallback that should cover this never matches on macOS 26.7.1 (window numbers are k << 32)."
  confirming_evidence:
    - "Log of pid 26630: XPC session created/used on the main thread; main thread silent 2.5 s and 3.1 s during each lookup; 'NSAccessibility Request Received' only after the main thread unblocks, then 'Missing control item'."
    - "scratchpad/iso: the Connection.sourcePID shape runs its continuation body on the main thread with the v0.0.6 settings, off it with Swift 5 mode (v0.0.5)."
    - "Probe: NSStatusBarWindow.windowNumber = 0x1_0000_0000 (and 0x1…0x5 << 32 in holzBar's own log) — never a CGWindowID."
    - "Probe: own AX extras-menu-bar children are enabled and their frame centres equal the CC windows' centres (also expanded), so the service match works once holzBar can answer; 0.0.5 (same matching code, Swift 5 mode) worked on this macOS 26.7.1 for 3 days."
  falsification_test: "With the XPC send moved off the main thread (fix 1 alone), a CI build would still log 'Missing control item for hidden section' on the user's Mac; or the main thread would still show multi-second gaps around service lookups."
  fix_rationale: "Fix 1 removes the self-deadlock (root cause A): the main actor suspends instead of blocking, so AppKit answers the service's AX request and the service returns holzBar's PID, as in 0.0.5. Fix 2 repairs the dead fallback (cause B) with a measurement-backed identity (in-process frame == CC window bounds) and gives the control items their identifier as title, so recognition no longer depends on the service, Accessibility timing or the CC window title."
  blind_spots: "The app cannot be built or run here; verification on the real app needs a CI build. Control-Center window titles cannot be read from this shell (no Screen Recording), so (C) 'titles are not the autosave names' is excluded only indirectly (0.0.5 matched by title for 3 days) — fix 2 makes it irrelevant for the control items, not for other apps' items. Multi-display: only the main display's copy of each control item matches by frame (same as the AX path)."
  candidate_causes:
    - "code: blocking XPCSession.sendSync on the main actor (NonisolatedNonsendingByDefault) — CONFIRMED"
    - "code: OwnStatusItemWindows window-number match dead on macOS 26.7.1 — CONFIRMED (contributing)"
    - "config: build settings change SWIFT_VERSION 5.0 → 6.2 + SWIFT_APPROACHABLE_CONCURRENCY = YES for the app target in 0.0.6 — the trigger of cause A"
    - "environment: macOS 26.7.1 Control Center hosts status items (window ownership, window numbers, titles) — makes B necessary; title mismatch (C) unlikely (0.0.5 worked)"
    - "data: missing ItemSections in the new defaults domain — consequence, not cause (saveSections only runs after a successful cache)"
  and_gate: "yes — the failure needs (A) the service lookup of holzBar's own items failing AND (B) the in-process fallback not matching. 0.0.5 had B without A and worked. root_cause is the set {A, B}; both are fixed."
tdd_checkpoint: null

## Symptoms
<!-- Written during gathering, then immutable -->

expected: On macOS 26 the Menu Bar Layout settings pane and the holzBar Shelf list the menu bar items by section, and clicking the holzBar icon shows and hides the hidden section.
actual: The Menu Bar Layout pane shows "Loading menu bar items…" with a spinner forever (layout bars blurred). The holzBar Shelf also shows only "Loading…". Clicking the holzBar icon in the menu bar does not show or hide the hidden items (user: "Nein" — hiding/showing does not work).
errors: |
  Unified log (process holzBar, pid 19393, started 2026-10-05 08:30:09 local):
  08:30:12.247 E [com.holzcloud.holzBar:MenuBarItemManager] Missing control item for hidden section, clearing menu bar item cache (20 items: <mask.hash>)
  08:30:15.357 E [com.holzcloud.holzBar:SectionRestore] Missing control item for hidden section, not reconciling sections
  08:30:15.444 E [com.holzcloud.holzBar:MenuBarItemManager] Missing control item for hidden section, clearing menu bar item cache (22 items: <mask.hash>)
  (repeats at 08:31:25, 08:33:01, 08:33:27, 08:33:29)
  No errors from MenuBarItemService.Connection or the XPC service (pid 19394).
reproduction: Launch holzBar 0.0.6 (Homebrew cask, /Applications/holzBar.app) on macOS 26.7.1 with two displays; open Settings > Menu Bar Layout. Reproduces on every launch on this Mac.
started: Worked in holzBar 0.0.5 or earlier on this Mac (user answer: "Ging in 0.0.5 oder früher"); broken since updating to 0.0.6. Between 0.0.5 and 0.0.6 the app was renamed holzIce → holzBar (new bundle id com.holzcloud.holzBar, folder Ice/ → holzBar/), and the menu bar code was restructured (Backends/ServiceBackend26, MenuBarItemManager, SectionRestore, MenuBarItemTag, ControlItem, SourcePIDCache, Bridging changed). Screen Recording is ON for holzBar in System Settings (user confirmed).

## Eliminated
<!-- APPEND only - prevents re-investigating after /clear -->

- hypothesis: The XPC item service is unreachable or rejects holzBar (peer requirement), so every lookup fails.
  evidence: The service logs "Listener requires the app's exact code (2 code directory hashes)", "Session activated" for the app's peer, and answers (no "Session failed"/"returned nil" errors in the app); the failure is limited to holzBar's own items.
  timestamp: 2026-10-05T07:25:00Z

- hypothesis: OwnStatusItemWindows (window-number match, 0.0.5 fix c261c07) recognises holzBar's own items on macOS 26.7.1.
  evidence: NSStatusBarWindow.windowNumber is k << 32 (low 32 bits zero), never a CGWindowID; CGWindowID(exactly:) gives nil.
  timestamp: 2026-10-05T07:15:00Z

- hypothesis: The hidden divider is skipped by the service because it is disabled-looking (appearsDisabled) or expanded beyond the window's width.
  evidence: AXEnabled is true with appearsDisabled; the expanded item's AXFrame centre equals the 5016-wide CC window's centre.
  timestamp: 2026-10-05T07:20:00Z

## Evidence
<!-- APPEND only - facts discovered during investigation -->

- timestamp: 2026-10-05T06:30:00Z
  checked: `/usr/bin/log show --last 3h --predicate '(processID == 19393 OR processID == 19394) AND subsystem BEGINSWITH "com.holzcloud"' --info --debug`
  found: Only errors "Missing control item for hidden section, clearing menu bar item cache (20/22 items)" (MenuBarItemManager.swift:505, in cacheItemsRegardless when `ControlItemPair(items:)` returns nil) and "Missing control item for hidden section, not reconciling sections" (SectionRestore.swift:199). No XPC session errors, so the XPC service answers.
  implication: The item list (20–22 windows) is read fine, but none of the items carries the tag `.hiddenControlItem`; the cache is cleared every time, so every view waiting for items shows "Loading…".

- timestamp: 2026-10-05T06:35:00Z
  checked: CGWindowListCopyWindowInfo(.optionAll) from a Swift script (this shell has no Screen Recording, so titles read as nil here)
  found: holzBar (pid 19393) owns only windows 2051 (layer 25, 216 wide at y=31, off screen — probably the Shelf panel), 2052, 2053, 2054 (Settings window), 2059. Control Center (pid 855) owns all layer-25 menu bar item windows, including 2055 (x=3232 w=33, main display) and 2056 (x=-206 w=33, second display) = holzBar icon, and 2057 (x=-1784 w=5016) and 2058 (x=-5222 w=5016) = hidden-section dividers expanded to 5016 pt (items currently hidden). The window IDs 2055–2058 follow holzBar's own 2051–2054 directly.
  implication: On macOS 26 the status item windows of holzBar belong to Control Center; holzBar must recognise them either by window ID (OwnStatusItemWindows, recorded from `statusItem.button.window.windowNumber` in ControlItem.windowDidChange) or by the source PID from the item service (AX lookup in the XPC service, which must query holzBar's own AX extras menu bar).

- timestamp: 2026-10-05T06:37:00Z
  checked: `defaults read com.holzcloud.holzBar`
  found: Keys "NSStatusItem Preferred Position holzBar.ControlItem.Hidden" = 1, "... holzBar.ControlItem.Visible" = 0, "NSStatusItem Visible ..." and "NSStatusItem VisibleCC ..." for Hidden/Visible/AlwaysHidden; HasImportedIceSettings = 1; EnableAlwaysHiddenSection = 0; no "ItemSections" key.
  implication: The autosave names (and thus the expected window titles) are `holzBar.ControlItem.*`. `saveSections()` never ran in this domain, so the hidden control item was never recognised since the 0.0.6 install (new defaults domain because of the bundle-id change).

- timestamp: 2026-10-05T06:38:00Z
  checked: code path (holzBar/MenuBar/Backends/ServiceBackend26.swift, MenuBarItem.swift `MenuBarItemTag.Namespace.init(uncheckedItemWindow:sourcePID:)`, ControlItem/OwnStatusItemWindows.swift, MenuBarItemServiceConnection.swift, Shared/Services/SourcePIDCache.swift, Utilities/ScreenCapture.swift)
  found: On macOS 26 the tag is built as namespace = `.holzBar` if `OwnStatusItemWindows.contains(windowID)`, else `.optional(bundleId)` of the service's source PID, else a per-window `.uuid`; title = `itemWindow.title ?? ""` (kCGWindowName). `ScreenCapture.checkPermissions()` returns the "has title" state of the first menu bar window not owned by holzBar; the layout pane shows "Loading…" (not the Screen Recording hint), so holzBar does read window titles. The XPC SourcePIDCache matches AX extras-menu-bar children of every running app by frame center (≤ 1 pt) — for holzBar's own items it must query holzBar's main thread via AX while holzBar may be waiting on the XPC reply.
  implication: Candidate causes: (a) `NSWindow.windowNumber` of the status item button's window ≠ the Control-Center-owned CGWindowID on macOS 26, so OwnStatusItemWindows never matches, and the service cannot resolve holzBar's own items (AX into the waiting app, or frame mismatch for a 5016-pt-wide divider); (b) the window title differs from `ControlItem.Identifier.rawValue`; (c) another 0.0.5→0.0.6 change.

- timestamp: 2026-10-05T07:00:00Z
  checked: git diff -M30% v0.0.5 v0.0.6 of MenuBarItemTag.swift, MenuBarItem.swift, OwnStatusItemWindows.swift, ControlItem.swift, MenuBarItemServiceConnection.swift, SourcePIDCache.swift, Listener.swift, project.pbxproj
  found: Tag/namespace construction and OwnStatusItemWindows are unchanged apart from renames (.ice → .holzBar, NSLock → OSAllocatedUnfairLock); ControlItem still records `button.window.windowNumber` (KVO .initial instead of Combine). The project changed SWIFT_VERSION 5.0 → 6.2 and added SWIFT_APPROACHABLE_CONCURRENCY = YES + SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor for the app. `Connection.sourcePID(for:)` is `nonisolated ... async` and calls `session.send` (XPCSession.sendSync) synchronously inside `withCheckedContinuation`; it is awaited from the @MainActor `ServiceBackend26.items`. SourcePIDCache (in the XPC service) sets the AX unresponsive timeout to 3 s and scans every running app's extras menu bar — including holzBar's.
  implication: Under NonisolatedNonsendingByDefault the nonisolated async func runs on the MainActor, so sendSync blocks holzBar's main thread while the service asks holzBar itself through AX → AX into holzBar times out (3 s) → holzBar's own items get no source PID. In 0.0.5 (Swift 5 mode) the same func ran on the global executor and holzBar's main thread could answer AX.

- timestamp: 2026-10-05T07:02:00Z
  checked: `/usr/bin/log show` for pid 19393 (app) and 19394 (XPC service) with timestamps
  found: Service activity ("New connection … secondary" = service starts a lookup) at 08:31:22.787, 08:33:24.781, 08:39:58.166 is followed by the app's "Missing control item" error at 08:31:25.838, 08:33:27.849, 08:40:01.249 — gaps of 3.05, 3.07, 3.08 s. At launch: service ready 08:30:09.84, first error 08:30:12.247, SectionRestore error 08:30:15.357 (+3.11 s).
  implication: Each item read waits ~3 s, exactly the AX unresponsive timeout — consistent with the service's AX call into the blocked holzBar process timing out.

- timestamp: 2026-10-05T07:03:00Z
  checked: `defaults read com.holzcloud.holzBar` (UseIceBar) and ControlItem.performAction / MenuBarSection.show
  found: UseIceBar = 1 (the holzBar Shelf is on). With the Shelf on, clicking the holzBar icon opens the Shelf panel (`shelfPanel.show(section: .hidden)`) instead of expanding the hidden divider, and the Shelf lists items from the same item cache.
  implication: "Clicking the icon does not show/hide the hidden items" is the same root cause: the Shelf opens but shows "Loading…" because the cache is empty.

- timestamp: 2026-10-05T07:10:00Z
  checked: (orchestrator) unified log of the predecessor app holzIce 0.0.5 (process /Applications/holzIce.app, subsystem com.holzcloud.holzIce) on this Mac, 7 days of error+fault entries (raw: /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/holz-errors-7d.ndjson)
  found: At 2026-10-05 08:20:34.859 +0200, BEFORE the update to 0.0.6, holzIce 0.0.5 logged the item tags unmasked (MenuBarItemTag.description = "namespace:title"): "Missing control item for hidden section, clearing menu bar item cache (23 items: 985661A4-4B3D-494C-AF4C-5F0E97AD9F9F:com.microsoft.OneDrive, 63220303-0862-4BB6-A1E2-DC5A9227873D:ch.switch.drive, E2AFAF6B-9018-4679-BACC-0E04BFD4EF59:com.electron.dockerdesktop, 90197048-3A6B-4102-87F9-DBC6616742D1:com.google.drivefs, 6E11A486-14A2-4F70-AE81-7A04B9C3F94C:com.ethanbills.DockDoor, 7FC6D80C-7015-4027-A001-EBD4777EE0FD:com.microsoft.Outlook, 23CD3C1C-E0BE-4D30-B696-AC4838B9E7BA:com.microsoft.teams2, 94569532-26FF-4A03-8667-4CEF324A57BA:cc.ffitch.shottr, 97B6F988-DB09-498E-A492-668AB010C078:nl.root3.support, 0E351EB4-C03C-40CE-9F9C-17679207F674:app.monitorcontrol.MonitorControl, F8386238-D46F-4419-BAD2-813F7FC6E4C5:com.holzcloud.holzIce, 9BD9F0AA-801F-4FCE-A8D6-2D8820A7B69D:com.linguee.DeepLCopyTranslator)".
  implication: On macOS 26.7.1 (1) EVERY item got a `.uuid` namespace — the source-PID lookup (XPC SourcePIDCache AX frame match) failed for all apps, not only for holzBar's own items, and OwnStatusItemWindows did not match holzIce's own window either; (2) the window title (kCGWindowName) of the Control-Center-owned item windows is the BUNDLE IDENTIFIER of the app that created the item (e.g. "com.holzcloud.holzIce" for holzIce's own item), NOT the NSStatusItem autosaveName — so a title match against `holzBar.ControlItem.Hidden` can never succeed, and several items of one app (holzBar icon + hidden divider + always-hidden divider) may share the same title; (3) 0.0.5 already showed the failure at that moment, so "worked in 0.0.5" may have been intermittent. This weakens H2 as the sole cause (H2 explains only holzBar's own items). Suggested experiment: a Swift script that creates two NSStatusItems with autosave names, then compares `statusItem.button.window.windowNumber` and `window.frame` with the Control-Center-owned layer-25 windows (IDs, bounds), to find a reliable way for holzBar to recognise its own windows (window ID, or in-process frame match) and to confirm what titles look like (this shell lacks Screen Recording, so other processes' window titles read as nil; an own-script window may still be readable).

- timestamp: 2026-10-05T07:15:00Z
  checked: scratchpad/probe_statusitem.swift and the AppKit log of holzBar's own NSStatusBarWindows (pid 19393 termination at 08:44:59: "NSStatusBarWindow windowNumber=100000000 … 500000000")
  found: On macOS 26.7.1 `statusItem.button.window.windowNumber` is 4294967296 (0x1_0000_0000; holzBar's are 0x1…0x5 << 32): the low 32 bits are zero and the value is not any CGWindowID. The real item windows (e.g. 2418/2419) belong to Control Center and get new CGWindowIDs. `CGWindowID(exactly:)` turns the number into nil, so OwnStatusItemWindows never records anything.
  implication: H1 confirmed — the 0.0.5 fix c261c07 is dead code on this macOS. In 0.0.5 holzIce's own items could therefore only have been recognised through the item service's AX frame match.

- timestamp: 2026-10-05T07:20:00Z
  checked: scratchpad/probe_expanded.swift and probe_frames.swift (own NSStatusItems: standard, expanded to 10 000, length 0 / content width 1, appearsDisabled)
  found: (1) The own process's AX extras menu bar lists each item once (main display) with AXEnabled = true even with appearsDisabled, and its AXFrame centre equals the Control-Center window's centre (expanded: CC window 5016 wide, AX 5002 wide, same centre). (2) The in-process NSStatusBarWindow frame, flipped to CoreGraphics coordinates with the primary screen's height, equals the main-display Control-Center window's bounds exactly in every state (24×30, 5016×30 clamped, 16×30). The second display's replica (y = 458) matches neither. `window.screen` is nil for these windows.
  implication: Once holzBar's main thread is free, the service's AX frame match finds holzBar's own items (as in 0.0.5). Independently, holzBar can recognise its own item windows in-process by frame, without the service, AX or the window title.

- timestamp: 2026-10-05T07:25:00Z
  checked: unified log of the relaunched holzBar 0.0.6 (pid 26630, 08:47:21–08:47:27; the session was restarted outside this investigation)
  found: The XPC session is created and used on the main thread (thread 5ade61: "Session created with XPC Service", "activating connection … MenuBarItemService", plus the runtime fault "Security … should not be called on the main thread" from CodeSignature.currentTeamIdentifier). The main thread then logs nothing from 08:47:21.284 to 08:47:23.754; its next entry is "NSAccessibility Request Received" (23.768), immediately followed by "Missing control item" (23.801); then silence again until 26.905 (SectionRestore error), right after the service's next log line (26.904).
  implication: Direct observation of H2: the main thread is blocked in the synchronous XPC call while the service's AX request to holzBar waits; AppKit only receives the AX request after the lookup has already failed.

- timestamp: 2026-10-05T07:28:00Z
  checked: scratchpad/iso/main.swift — a nonisolated `Sendable` class whose nonisolated async method runs its work inside `withCheckedContinuation` (the shape of Connection.sourcePID), awaited from @MainActor; compiled with the v0.0.6 app settings (-swift-version 6 + NonisolatedNonsendingByDefault + default MainActor) and with Swift 5 mode (v0.0.5 app)
  found: v0.0.6 settings → "blocking send ran on the main thread: true"; Swift 5 mode → false; Swift 6 without NonisolatedNonsendingByDefault → false.
  implication: The regression is caused by the 0.0.6 switch to SWIFT_APPROACHABLE_CONCURRENCY (NonisolatedNonsendingByDefault), which moved the blocking `XPCSession.sendSync` onto the main thread.

- timestamp: 2026-10-05T07:30:00Z
  checked: Control Center's log (category appStatusItems) of status item hosts
  found: Hosts are identified as "bid:<bundle id>-<autosave name>-<pid>", e.g. "com.holzcloud.holzBar-holzBar.ControlItem.Hidden-26630", "com.holzcloud.holzIce-Ice.ControlItem.Hidden-54560", "com.microsoft.Outlook-Item-0-20888". holzIce 0.0.5 logged Outlook's item title as "com.microsoft.Outlook" (its autosave name is the default "Item-0").
  implication: Control Center knows the autosave names. Items with a default name ("Item-N") get a window title other than the autosave name; named items like holzIce's dividers carried their autosave name (0.0.5 matched `Ice.ControlItem.Hidden` for 3 days on 26.7.1). Titles cannot be read from this shell (no Screen Recording; SLSCopyWindowProperty returns an empty title), so in-process recognition that does not depend on the title is the safer second path.

- timestamp: 2026-10-05T09:40:00Z
  checked: Specialist review follow-ups (suggestions 2, 4, 5, 6) applied as commit 470ed14 on fix/macos26-own-control-items, on top of 722ede9. Callers of cacheItemsIfNeeded/cacheItemsRegardless and every observer of itemManager.itemCache (ItemChangeWatcher, MenuBarItemImageCache, LayoutBarContainer, MenuBarSearchPanel, Concealer27) read for loop risk; AccessibilityBackend27.cacheFromLayout / Concealer27.cacheFromSavedLayout read for the macOS 27 path.
  found: (2) The ControlItemPair failure branch of cacheItemsRegardless now calls `await cacheActor.clearCachedItemWindowIDs()` (the same call uncheckedCacheItems already makes for items without a source PID). cacheItemsIfNeeded is only called from the 1 s item-list debouncer (events), the 60 s fallback timer, the 1.5 s activation debouncer, the Shelf's show, the two bounded app-launch re-checks and Concealer27 (macOS 27 only); no itemCache observer calls back into caching, so clearing the signature cannot start a retry loop — it only stops the next normal trigger from being skipped. On macOS 27 cacheFromLayout always returns a cache (cacheFromSavedLayout is non-optional), so the failure branch is never reached there. (4) BlockingWork.run<Value>. (5) OwnStatusItemWindows.controlItem(forWindowBounds:) became controlItems(forWindowBounds: [CGRect]) -> [ControlItem.Identifier?]: one read of NSScreen.screens.first's height and of the control items' frames per item list; ServiceBackend26.items calls it once. (6) ServiceBackend26.items doc comment now says holzBar's frames cannot change while the windows are matched and that Control Center may lag behind them. No test added for (2): CacheActor is private to the @MainActor MenuBarItemManager in the app target, outside the HolzBarCore test package, and extracting a one-line call would be contortion.
  implication: A transient frame miss (Control Center updating windows after a length change or display switch) no longer leaves "Loading…" until the window list changes; the macOS 27 backend (AccessibilityBackend27 / Concealer27) is unaffected; deployment target unchanged (14.0).

- timestamp: 2026-10-05T09:44:00Z
  checked: Local checks on 470ed14 — `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing` (scratchpad/swifttest-followup.log); scratchpad/silcheck.sh with SDK=MacOSX26.5.sdk (scratchpad/sil-followup.txt); the same whole-app SIL compile against MacOSX27.0.sdk with the reviewer's @State stub (scratchpad/tree27-followup, scratchpad/sil27-followup.txt); the CI former-name git grep (pattern and excludes from build.yml); tabs, trailing whitespace and file headers of the 4 changed files; .github/scripts/privacy-check.py network and logs.
  found: swift test: 6 + 127 + 245 tests passed (SharedCodeSigning, HolzBarMacOS27Core, HolzBarCore; BlockingWork and StatusItemWindowFrame suites green). SIL compile macOS 26.5 SDK: exit 0, 0 errors, only the pre-existing ScreenCapture.swift:86 deprecation warning. SIL compile macOS 27.0 SDK (with stub): exit 0, 0 errors, same single warning. Former name: no matches in content or file names. No tabs, no trailing whitespace, headers match the SwiftLint file_header pattern. Privacy checks: "No network code", "Every log interpolation names its privacy". SwiftLint itself is not installed locally (CI runs it).
  implication: The follow-up commit compiles for macOS 26 and 27 and keeps every existing test green; app-level behaviour still needs the CI build on the user's Mac.

## Resolution
<!-- OVERWRITE as understanding evolves -->

root_cause: "(A) 0.0.6 builds the app with SWIFT_APPROACHABLE_CONCURRENCY (NonisolatedNonsendingByDefault), so MenuBarItemService.Connection.start()/sourcePID(for:) — nonisolated async functions awaited from the @MainActor ServiceBackend26 — ran the blocking XPCSession.sendSync on the main thread; the XPC service resolves an item's app by asking every app's extras menu bar through Accessibility, holzBar's own included, which AppKit answers on the main thread, so the lookup of holzBar's own items always timed out and they got `.uuid` namespaces; `.hiddenControlItem` never matched, the item cache was cleared on every read and the Layout pane and the Shelf (opened by the icon click, UseIceBar = 1) stayed on 'Loading…'; (B) the in-process fallback OwnStatusItemWindows matched NSWindow.windowNumber, which on macOS 26.7.1 is k << 32 and never a CGWindowID, so it never recognised anything (0.0.5 had B but not A and worked)."
fix: "Fix 1 (A): new holzBar/Core/BlockingWork.swift — BlockingWork.run(on:_:) runs blocking work on a dispatch queue and suspends the caller; MenuBarItemService.Connection sends every request through it on a dedicated serial `requestQueue` (also the local fallback on `localQueue`), so the main thread is free to answer the service's Accessibility requests (and the code-signature lookup in the session setup leaves the main thread too). Fix 2 (B): new holzBar/Core/StatusItemWindowFrame.swift (AppKit frame → window-list bounds, 1-pt tolerance on every edge); OwnStatusItemWindows now keeps weak references to the control items' NSStatusItems (registered in ControlItem.StatusItemStorage) and recognises a Control Center item window whose bounds match a visible control item's window frame; ServiceBackend26.items recognises them before the first await and builds them with the new MenuBarItem(uncheckedItemWindow:controlItem:) (tag = the control item's tag, sourcePID = holzBar), skipping the XPC lookup; the dead window-number check was removed from the macOS 26 namespace init. docs/upstream-bugs.md row for #687/#710/#711 updated. Follow-up 470ed14 (specialist review 2/4/5/6): MenuBarItemManager.cacheItemsRegardless clears the cached window-ID signature when ControlItemPair(items:) fails, so the next normal trigger retries instead of being skipped; OwnStatusItemWindows.controlItems(forWindowBounds:) matches a whole list against one primary-screen height and one snapshot of the control items' frames; BlockingWork.run<Value>; ServiceBackend26.items comment corrected."
verification:
  target_test: { result: pass, tests: "Tests/HolzBarCoreTests/BlockingWorkTests.swift (3 tests), Tests/HolzBarCoreTests/StatusItemWindowFrameTests.swift (4 tests, 11 cases); red before the fix (inline-continuation shape and never-matching stub: 7 issues), green after" }
  mutation_check: { result: pass, reason_if_skipped: "Stryker does not support Swift; manual mutants seeded at the fix sites instead", mutant_killed: "5/5 — M1 work inline on caller's actor (2 tests red, 2 s timeout), M2 no y flip, M3 tolerance 2, M4 maxX not compared, M5 empty-frame guard removed" }
  no_op_deletion: { result: pass, deletion_justified_by_rca: true, note: "Only deletion: the OwnStatusItemWindows.contains(windowID) branch, proven dead (window numbers are k << 32); replaced by the frame-based recognition" }
  adjacent_tests: { result: pass, suites_run: ["swift test: 6 + 127 + 245 tests (SharedCodeSigning, HolzBarMacOS27Core, HolzBarCore)", "whole-app SIL compile (swiftc -emit-sil -wmo, app flags, macOS 26.5 SDK, asset-symbol stubs): 0 errors, 1 pre-existing deprecation warning; checker shown to catch an isolation error", "macOS 27 SDK typecheck: no errors in changed files (only the SwiftUI @State macro plugin missing from the CLT)", "follow-up 470ed14: swift test 6 + 127 + 245 passed; SIL compile macOS 26.5 SDK 0 errors; SIL compile macOS 27.0 SDK with @State stub 0 errors; former-name, whitespace/header and privacy checks clean"] }
  stability: "BlockingWork/StatusItemWindowFrame tests run 25 times: 0 failures"
  revert_and_reconfirm: { result: partial, bug_returned_on_revert: true, fixed_on_reapply: true, note: "At unit level (M1 = the 0.0.6 code shape → red; reapplied → green). App-level revert/reconfirm needs a CI build on the user's Mac (0.0.6 reproduces on every launch) — pending human verification." }
  guardrail_verdict: accepted
oracle_type: "derived — window bounds and frames measured on this Mac (macOS 26.7.1) with probe scripts; the blocking test models the measured self-deadlock (work waits for the main actor)"
files_changed:
  - holzBar/Core/BlockingWork.swift (new)
  - holzBar/Core/StatusItemWindowFrame.swift (new)
  - holzBar/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift
  - holzBar/MenuBar/ControlItem/OwnStatusItemWindows.swift
  - holzBar/MenuBar/ControlItem/ControlItem.swift
  - holzBar/MenuBar/Backends/ServiceBackend26.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItem.swift
  - Tests/HolzBarCoreTests/BlockingWorkTests.swift (new)
  - Tests/HolzBarCoreTests/StatusItemWindowFrameTests.swift (new)
  - docs/upstream-bugs.md
  - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift (470ed14)
  - holzBar/Core/BlockingWork.swift (470ed14)
  - holzBar/MenuBar/ControlItem/OwnStatusItemWindows.swift (470ed14)
  - holzBar/MenuBar/Backends/ServiceBackend26.swift (470ed14)
commits: [722ede9, 470ed14]
open_follow_ups: "Specialist suggestions 3 (XPCSession.send(_:replyHandler:) instead of sendSync on a parked thread), 7 (cancellation handler writes session without the lock) and 8 (separate Spaces off: second display copy gets .uuid) stay documented, not done."

other_log_findings: |
  Reviewed every error/fault of holzBar and its XPC service in the last 3 h (0.0.6) and holzIce 0.0.5's last 3 days:
  - "Missing control item for hidden section" (MenuBarItemManager, SectionRestore): this bug.
  - Fault "Security … This method should not be called on the main thread" (8×, at each launch): CodeSignature.currentTeamIdentifier evaluated in the XPC session setup on the main thread — same cause (A); now runs on requestQueue.
  - com.apple.appintents "Unable to get synchronousRemoteObjectProxy … com.apple.linkd.autoShortcut" / "Error registering app with intents framework" (Code 4097): system-wide (also Brave, Chrome, jamf, Autoupdate, Microsoft) — linkd on this Mac, not holzBar.
  - libsqlite3 "cannot open … /private/var/db/DetachedSignatures": Security framework noise in every process.
  - BaseBoard "Unable to obtain a task name port right for pid 418": pid 418 is WindowServer (a root daemon), queried via NSRunningApplication for a window it owns; harmless.
  - MenuBarItemService Bridging "CGSGetScreenRectForWindow failed with error 1000" (1×): a window vanished during the stable-bounds check (the probe scripts' items); handled (nil).
  - SwiftUI fault "Bound preference FramePreferenceKey tried to update multiple times per frame" (1× per launch) and AppKit WarnOnce "layoutSubtreeIfNeeded on a view which is already being laid out" (1× per session): pre-existing layout feedback warnings (View.onFrameChange users such as HolzBarForm); not functional failures, not part of this bug — candidates for a separate cleanup.
  - libCoreFSCache "fopen failed for data file": system noise.

## Specialist Review
<!-- swift_concurrency review of commit 722ede9 (session manager, 2026-10-05) -->

verdict: SUGGEST_CHANGE (no blocker; direction correct, safe to ship for verification)
confirmed_correct: BlockingWork Sendable/continuation (resumed exactly once, blocking on a dispatch queue not the cooperative pool, no QoS inversion, requestQueue outside the session's target-queue hierarchy so no sendSync deadlock); plain `nonisolated` (nonsending) is right for the wrapper, `@concurrent` not needed; CG coordinate conversion (y = H - maxY of NSScreen.screens[0]); false positives practically impossible; matching before the first await is sound; macOS 27 backend (AccessibilityBackend27 / MenuBarItemProvider27) unaffected; macOS 14/15 WindowListBackend unchanged; deployment target 14.0 OK (new init is `@available(macOS 26)`); 7 new tests pass, former-name check clean. Two displays: "Displays have separate Spaces" is on, `getMenuBarItems(option: .activeSpace)` lists one copy per status item (the active display's), so no duplicate control-item tags reach ControlItemPair.
suggestions:
  1. SHOULD (verify on device): when the built-in display holds the active menu bar, only its copies are listed; they are recognised only if AppKit moves the in-process NSStatusBarWindow frame to that display (unverified; not a regression — the AX path depends on the same frame). Add to the human check: click a window on the built-in display, wait 2 s, open the Shelf, check the log for "Missing control item". Fallback if it fails: match by distance from the display's right edge (~3 pt tolerance, fragile).
  2. SHOULD: MenuBarItemManager.swift ~482/510 — the window-ID signature is stored before the ControlItemPair check and not reset on failure; `cacheItemsIfNeeded` compares only window IDs, so one transient frame miss (Control Center updates windows asynchronously after a length change or display switch) leaves "Loading…" until the window list changes. Fix: `await cacheActor.clearCachedItemWindowIDs()` (or equivalent) in the failure branch.
  3. SHOULD (follow-up, "Apple's way"): MenuBarItemServiceConnection.swift ~180-219 — use `XPCSession.send(_:replyHandler:)` inside `withCheckedContinuation` instead of `sendSync` on a parked thread (no thread parked up to 3 s, no OSAllocatedUnfairLock held across IPC); resume in reply handler and in the synchronous-throw catch; keep session creation (CodeSignature.currentTeamIdentifier) off the main thread. Current version is correct; can come later.
  4. NIT: BlockingWork.swift:24 — generic parameter `Result` shadows `Swift.Result`; rename to `Value`.
  5. NIT: OwnStatusItemWindows.swift:40 — `NSScreen.screens.first?.frame.height` evaluated per window; compute once per `items()` call and pass it in.
  6. NIT: ServiceBackend26.swift:37-39 — comment "the frames and the window list describe the same moment" overstates it (Control Center lags holzBar); say holzBar's frames cannot change while the windows are matched.
  7. NIT (pre-existing): MenuBarItemServiceConnection.swift:155 — XPC cancellation handler writes `self.session = nil` without the lock while `send` holds it on requestQueue (data race hidden by @unchecked Sendable). Caution: taking a non-recursive lock there could deadlock/crash if the handler runs while send holds the lock.
  8. NIT (pre-existing, out of scope): with separate Spaces off, both display copies are listed; the second copy gets `.uuid` and is filed by x position, as for every app.
probes: scratchpad/review/probe_spaces.swift, probe_second.swift

## Constraints for the fix
<!-- Orchestrator notes, read before fixing -->

- This Mac has only the Command Line Tools (no Xcode): the app cannot be built here; CI (macOS runner) builds it. `swift test` of the package `HolzBarMacOS27Core` and standalone Swift scripts (`swift file.swift`) do run locally. Experiments on the real macOS 26.7.1 menu bar can be done with small Swift scripts (e.g. create an NSStatusItem with an autosaveName in a script, print `statusItem.button?.window?.windowNumber`, then list layer-25 windows and their owners) — the installed holzBar 0.0.6 is running (pid 19393) and must keep running.
- Repository rules (CLAUDE.md): everything in English; commit locally, do NOT push (the orchestrator pushes once at the end, as the GitHub account holzcloud); keep persisted names; follow Apple's current APIs; no network.
- If the fix touches release notes: the next release is a beta of the next version (e.g. `docs/release-notes/v0.0.7-beta1.md`); do not bump to a stable version.
- Scope (user decision, 2026-10-05): only macOS 26 and macOS 27 compatibility is required. macOS 14/15 behaviour is optional (the user cannot test it), so the fix may simplify or skip 14/15-specific handling. The code must still compile with the current deployment target; raising the deployment target is a user decision (return a CHECKPOINT with options, do not change it on your own). The fix must not break the macOS 27 backend (AccessibilityBackend27 / Concealer27).
