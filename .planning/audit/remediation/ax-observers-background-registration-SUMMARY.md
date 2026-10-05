---
chain: ax-observers
part: background-registration
findings: [F-16, F-71]
decision: ax-observers-1 — "Im Hintergrund anmelden (Recommended)"
status: complete
---

# ax-observers / background-registration: Accessibility observer registration off the main thread

The maintainer chose to register in the background. Every Accessibility observer
registration (the macOS 27 owner observer and the "Show When It Changes" watcher) now runs
on its own serial dispatch queue. The callbacks still run on the main run loop. Failed
owner registrations back off; they are no longer retried on every refresh.

## F-16: observer registration on the main thread with no messaging timeout

**Cause.** `ItemChangeObserver27.addObserver` ran on the main actor on every item-cache
refresh. It called `AXObserverAddNotification` twice with the default timeout of about 6 s,
and retried a failed owner on every refresh. On macOS 27, `ItemChangeWatcher` registered
on the main actor too, on `MenuBarItemProvider27`'s shared element, also with the default
timeout. SystemItemClickBridge27's HID tap is serviced on the main run loop, so every
click on the Mac waited for these calls.

**Fix.**
- `holzBar/MenuBar/MacOS27/ItemChangeObserver27.swift`:
  - `observe(owners:)` stays `@MainActor`, and removals stay synchronous.
  - New owners are registered on a dedicated serial queue,
    `com.holzcloud.holzBar.ItemChangeObserver27`. It is deliberately not
    `MenuBarItemProvider27.queue`.
  - The queue work is `AXObserverCreate` plus a fresh `AXUIElementCreateApplication(pid)`
    with `AXUIElementSetMessagingTimeout(…, 0.25)`. That element is the observer's own, so
    presses are unaffected. Then `kAXCreatedNotification` is added, and
    `kAXUIElementDestroyedNotification` too unless the first call returned `.cannotComplete`.
  - Back on the main actor, the run-loop source is added to `CFRunLoopGetMain()` only if
    the pid is still wanted and has no observer yet. Otherwise the observer is dropped.
  - A pending set prevents duplicate registrations. A generation counter makes
    `removeAll()` discard registrations still in flight.
  - Now `@preconcurrency import ApplicationServices`.
- New `holzBar/MenuBar/MacOS27/Core/ObserverRegistrationSchedule27.swift`: a pure value
  type modelled on `AccessibilityScanSchedule27`. It takes a plain outcome enum
  (`registered`, `timedOut`, `unsupported`), not `AXError`.
  - A timeout is retried at the first refresh at least 5 s later. The pause doubles up to
    60 s.
  - `.notificationUnsupported` / `.notImplemented` on every call means no retry until the
    pid relaunches.
  - Success clears the entry, and `retain(running:)` forgets pids that quit. It runs only
    while an entry exists, against `NSWorkspace.runningApplications`.
  - Retries ride on the existing refreshes. No timer was added.
- `holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift`:
  - The main actor builds the wanted `(key, windowID, pid, bounds)` targets.
  - A serial queue, `com.holzcloud.holzBar.ItemChangeWatcher`, does the element lookup and
    `AXObserverCreate` / `AXObserverAddNotification` (title and value changed). It creates
    one fresh observer per process per batch. On macOS 26 the lookup is the existing
    0.25 s-bounded read. On macOS 27 it is `MenuBarItemProvider27.element(forWindowID:)`,
    and the shared element's messaging timeout is never changed (F-36, F-57).
  - Back on the main actor, a batch is applied only if its generation is still current.
    Otherwise its observers are released without their sources ever being added. Sources go
    to the main run loop, because the callback relies on `MainActor.assumeIsolated`.
  - The doc comments that claimed "waits 0.25 s at most" for every platform were corrected.

## F-71: an item whose element was not found the first time is never watched

Done in the same change, as the decision requires. The audit-fix commits d4f1cd05 and
bd9471da had already added a bounded retry. Their bookkeeping now lives in the new pure
`holzBar/Core/ItemChangeWatchList.swift`, which `swift test` covers.
- `watchedWindows` records only items whose registration actually succeeded.
- Items that were not observed are tried again alone, 2 s later, at most three times per
  list.
- A changed list removes the observers, resets the retries and invalidates any registration
  still in flight.
- The compared list maps each item key to its window and its process
  (`ItemChangeWatchList.Location`). On macOS 27 `SyntheticWindowID27` does not depend on
  the process, so a relaunched app's item keeps its window identifier. Without the process
  in the comparison, a quick relaunch (or one while reads pause, screen locked or asleep)
  left the observers on the process that quit (review AXO-R1).

## Deviation

The implementation note asked for "one dedicated serial queue for registration". Each of
the two registrars got its own dedicated serial queue instead. On macOS 27 the watcher must
keep the shared element's default ~6 s timeout. A hung app with a marked item could
otherwise hold up the owner observers' registrations, and so the detection of new menu
bar items, for up to 12 s. Neither queue is `MenuBarItemProvider27.queue`.

## Tests added

- `Tests/HolzBarMacOS27CoreTests/ObserverRegistrationSchedule27Tests.swift` (6 tests): the
  backoff steps 5/10/20/40/60/60 s, pauses that refreshes do not extend, success clearing
  the pause, unsupported until relaunch, and quit pids forgotten.
- `Tests/HolzBarCoreTests/ItemChangeWatchListTests.swift` (7 tests): a new list,
  an unchanged list, only observed items counting (F-71), discarding an outdated generation,
  the retry limit and its reset, an empty list, and a relaunch that keeps the window
  identifier but changes the process (AXO-R1).

## Gates (all passed before the commit)

- `appcheck.sh` (whole app module, Swift 6, macOS 26.5 SDK): ERRORS: 0.
- `servicecheck.sh`: SERVICE EXIT: 0.
- `swift test`: 272 + 142 + 6 tests passed. SwiftPM's Swift Build sometimes reports
  "plugin for module 'TestingMacros' not found" for `SharedCodeSigningTests`. That happens
  on an untouched HEAD copy too, and the run passes when repeated.
- `swiftlint lint --strict --quiet`: no output, exit 0.
- `privacy-check.py network`, `privacy-check.py logs`, `strings-check.py`: passed. No new
  strings.
- Former name check: no matches.

## User test steps (macOS 27 and 26)

1. Mark a hidden item "Show When It Changes", for example a clock or a counter app, and
   wait for it to change. It should appear for about 5 s.
2. On macOS 27: in System Settings > Control Center, turn a module's menu bar item on or
   off. holzBar should pick up the new or removed item within seconds.
3. Launch a heavy app that adds a menu bar item, then click around the menu bar and other
   apps while it is still busy finishing its launch. Clicks, hover and the Shelf should stay
   responsive.
4. Quit and relaunch an app whose item is marked "Show When It Changes". Its changes should
   reveal it again after the relaunch (F-71). Try a quick relaunch too (for example
   `killall` of an app that a launch agent restarts at once).

## Docs

None needed. No user-visible behaviour or claims change.
