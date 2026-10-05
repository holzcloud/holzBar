---
chain: mac27
part: agents-dot
findings: [F-17, F-08]
decisions: agent-launches-1 - "Bekannte + eigenständige Apps (Recommended)"; indicators-2 - "Punkt im holzBar-Symbol (Recommended)"
status: complete
plan_head_before: 4dddd7c5590209b48028fc6e7779c2e7ff07d11a
plan_head_after: the F-08 commit that contains this file (child of 3a0c23be)
commits: 2
actuals:
  tasks: 3
  commits: 2
---

# mac27 / agents-dot: notice menu bar agents that launch or quit; a capture dot on holzBar's icon

F-17 changes automatic Zen on every macOS version that has it, plus the macOS 27 concealer.
F-08 is macOS 27 only. All new app code is either `@available(macOS 27.0, *)` or plain
AppKit/KVO that exists on macOS 14. The new setting and Defaults key exist on every version but
only do something on 27. The decision logic lives in pure, swift-tested types:
`PresentationSignals.Trigger` and `CaptureIndicator`/`CaptureActivity` (`holzBar/Core`), and
`AgentLaunches27` (`holzBar/MenuBar/MacOS27/Core`).

**Not in scope: the user's signing question** ("Können wir das mit dem signieren nicht doch
anders lösen?"). Neither F-17 nor F-08 touches signing. The question belongs to the `release`
part (F-05, F-10, F-11, F-52, F-53, F-54) and to `xpc-trust` (F-04/F-48, where buying an Apple
Developer ID was rejected). The orchestrator has to ask the user about it as a multiple choice
before those parts run. One fact from this part matters for that conversation:
`ControlItem.swift` notes that holzBar "is signed locally, so MenuBarAgent drops its items
whenever anything is concealed (measured on macOS 27.0)", and Ice#1001 says MenuBarAgent can
also drop holzBar's own icon. The F-08 dot is drawn on that icon, so
`checkOwnIconForCapture()` checks that the icon is there when a capture starts and puts it back
if it is missing. Nobody has measured whether a Developer ID signature would change how
MenuBarAgent behaves. No release, signing or CI file was changed.

## F-17: agents without a Dock icon that launch or quit (commit 3a0c23be)

**Cause.** NSWorkspace sends its didLaunch/didTerminate notifications only for regular apps.
- Automatic Zen (`PresentationMonitor`) re-evaluated only on those notifications and on display
  changes. So it noticed `com.apple.screensharing.agent` (an LSUIElement bundle that launchd
  starts on demand) only by chance, when some other app launched or quit.
- On macOS 27 the concealer's allowlist ("running minus concealed") was rebuilt on regular-app
  launches and quits. A Visible menu bar agent that started later (a login item or a relaunch)
  stayed outside the allowlist: it was hidden, and squashed to 3 pt if it created its status
  item while concealed (Ice#1007).

**Fix (D-01, "Bekannte + eigenständige Apps").**
- `holzBar/Core/PresentationSignals.swift`: the new `PresentationSignals.Trigger` has
  `needsEvaluation(running:)` and `reset()`. It evaluates only when the set of running bundle
  IDs changed. The doc comment now says "when the running applications change".
- `holzBar/MenuBar/PresentationMonitor.swift`:
  - The two NSWorkspace notification tasks are replaced by
    `NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new])`. The observation
    is created in `start()` and invalidated in `stop()`, so it exists only while "Turn on Zen
    mode while the screen is mirrored or shared" is on.
  - The handler skips changes whose apps have no bundle ID, then hops with
    `Task { @MainActor in }`. It takes no lock and never waits (F-12 rule).
  - `runningApplicationsDidChange()` evaluates only when the trigger says the set changed.
  - `evaluate()` (start, display changes) also records the set. The screen-parameters task, the
    presenting logic and the log lines are unchanged. The class doc comment was rewritten.
- `holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift` (new):
  - `Policy` and `Instance`.
  - `nestingMarkers` (`.app/`, `.framework/`, `.xpc/`, `.appex/`, `.bundle/`).
  - `isStandalone(bundlePath:policy:)`: true for a `.regular` app, otherwise for a top-level
    `.app` whose parent path contains no marker. `activationPolicy` never excludes anything.
  - `reaction(previous:instances:known:concealedInLayout:)` returns `Reaction` (`running`,
    sorted `graces`, `updatesConcealment`).
- `holzBar/MenuBar/MacOS27/Concealer27.swift`:
  - `performSetup` takes a snapshot `runningBundleIDs` and adds the same KVO as Zen. The
    launch/terminate tasks are gone; the screen-parameters task stays.
  - `runningApplicationsDidChange()` returns before reading anything else when the bundle-ID set
    is unchanged.
  - Otherwise it maps the apps to `Instance`s, builds known = saved layout keys +
    `.knownApplications27` and concealedInLayout = saved sections other than Visible, then calls
    `AgentLaunches27.reaction`. Only when `updatesConcealment` is true does it call
    `applicationsDidChange(graces:)`.
  - `applicationsDidChange(graces:)` is the batch form of the old `applicationDidLaunch`. It
    clears `notchConcealed`, starts the launch graces, and then runs exactly one `update()`:
    directly, or through one `showTemporarily(bundleIDs:)` plus one `LaunchGrace27.timeout`
    task. There is no debounce.
  - Logs show counts only (`.public`), never bundle IDs. MenuBarItemManager,
    `placeNewApplications`, `applyChanges` and the F-28 notch logic are untouched.

**Tests.**
- `PresentationSignalsTests`, four new tests: first set evaluated; same set (also reordered)
  not evaluated; screen sharing start and end evaluated; reset.
- `AgentLaunches27Tests`, 13 tests:
  - top-level apps are standalone whatever their policy (Rectangle, SSMenuAgent, OneDrive
    `.prohibited`, case-insensitive extension);
  - WebKit `.xpc`, Brave renderer, Slack helper, `ScreensharingAgent.bundle` and a nil path are
    not standalone; a nested `.regular` app is;
  - unchanged set; helper only; unknown standalone; known visible; known concealed (grace);
    known nested;
  - quit of a known, an unknown and a helper app; login batch; "some instance" is standalone;
    the snapshot equals the running set.

## F-08: a dot on holzBar's icon while another app records (commit: the one with this file)

**Cause.** While any MenuBarAgent assessment assertion is live, macOS 27 does not draw Control
Centre's capture indicator (measured on 27.0, `MenuBarAssessmentAssertion27`). Concealing is
holzBar's normal state, so most of the time users saw no microphone or screen-recording cue.
The small green camera dot beside the clock is the only cue that remains.

**Fix (D-02, "Punkt im holzBar-Symbol").**
- `holzBar/Core/CaptureIndicator.swift` (new):
  - `CaptureBadge` (`.microphone`, `.camera`, `.cameraAndMicrophone`, `showsCamera`).
  - `CaptureActivity`: process objects with input running and cameras running somewhere, by
    object ID. `setInput` ignores holzBar's own PID; `keepProcesses`/`keepCameras` drop objects
    that are gone.
  - `CaptureIndicator.badge(isEnabled:isConcealing:isMicrophoneInUse:isCameraInUse:)` and
    `showsHolzBarIcon(isIconEnabled:badge:)`.
- `holzBar/Core/Defaults.swift`: new key `holzBarIconShowsCaptureDot = "HolzBarIconShowsCaptureDot"`
  (General group, kind `.bool`). Nothing was renamed.
- `holzBar/Settings/Models/GeneralSettings.swift`: `holzBarIconShowsCaptureDot = true`, stored in
  `didSet` and loaded in `loadInitialState()`.
- `holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift` (new, `@MainActor @Observable`, 27
  only). It runs only while the setting is on and assertions are available.
  - Microphone, through CoreAudio: listens to `kAudioHardwarePropertyProcessObjectList` and
    `kAudioHardwarePropertyServiceRestarted` (which re-registers everything) on the system
    object. For each new process object it reads `kAudioProcessPropertyPID`; holzBar's own
    objects get no listener. Every other object gets a `kAudioProcessPropertyIsRunningInput`
    listener.
  - Camera, through CoreMediaIO: listens to `kCMIOHardwarePropertyDevices`, and to
    `kCMIODevicePropertyDeviceIsRunningSomewhere` on each device.
  - All listeners are delivered on `DispatchQueue.main` and handled with
    `MainActor.assumeIsolated`. Each block is stored and passed to the matching Remove call.
    Only the `…ElementMain` constants are used.
  - Nothing polls, and no audio or video I/O is opened. `activity` is assigned only when it
    changes. Logs carry Booleans and OSStatus codes (`.public`), never PIDs, bundle IDs or device
    names.
  - A badge observer starts `concealer27.checkOwnIconForCapture()` when the badge goes from nil
    to a value.
- `holzBar/Main/AppState.swift`: loosely typed storage plus `captureActivityMonitor27` (like
  `concealer27`), and `captureBadge27`, which is `CaptureIndicator.badge` over the setting,
  `concealer27.isConcealing` and the monitor's activity. The monitor is set up right after the
  PresentationMonitor.
- `holzBar/MenuBar/MacOS27/Concealer27.swift`:
  - `checkOwnIcon()` now also keeps an icon that is shown only for a capture
    (`CaptureIndicator.showsHolzBarIcon`).
  - New `checkOwnIconForCapture()`: waits for pending applies and the settle time, reads the bar
    twice 400 ms apart, and reinserts holzBar's icon once if both reads miss it.
- `holzBar/MenuBar/ControlItem/CaptureDotView.swift` (new): a 6 pt layer-backed circle. Its
  colour resolves in `updateLayer()`, it is not an accessibility element, and `hitTest` returns
  nil so clicks reach the button.
- `holzBar/MenuBar/ControlItem/ControlItem.swift`:
  - On 27 the visible item observes `captureBadge27`. `updateMenuBarPresence()` shows the icon
    while it carries a badge, even with "Show holzBar icon" off.
  - `updateCaptureDot(on:)` adds or removes the dot: green for a camera, orange for the
    microphone only. It sets the same localized text as tooltip and accessibility label, and
    resets both when the capture ends.
  - `positionCaptureDot()` places the dot at the top-trailing corner of the cell's image rect.
    It also runs when the window frame changes. The status item's length never changes.
- `holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift`: `PrivacyIndicatorNote` takes the
  settings. Its note text now mentions the dot and that screen recording is not covered. The
  section gets the new toggle and annotation.
- `holzBar/Resources/Localizable.xcstrings`: the old note entry is replaced and five entries are
  added (toggle, annotation, three badge texts). All six are in de (Swiss spelling, no ß), fr, it
  and rm, verbatim from the plan. The file was written with the byte-identical `json.dumps`
  format, and the catalog now has 374 strings.

**Tests.**
- `CaptureIndicatorTests`, 5 tests: off, not concealing, nothing in use, which badge,
  `showsHolzBarIcon`.
- `CaptureActivityTests`, 6 tests: new, record/stop, own PID ignored, quit while recording,
  camera unplugged, equality.
- `SettingsSchemaTests`: the raw value `HolzBarIconShowsCaptureDot` and kind `.bool` are pinned.
- No usage description and no capture entitlement was added (grep gate).

**Permission check.** The plan's read-only probe on this Mac (macOS 26.7.1, 2026-10-05) read the
process object list, `IsRunningInput`, 3 CoreMediaIO devices and `IsRunningSomewhere`, and added
and removed listeners. Every call returned 0. tccd logged only preflight queries from coreaudiod
(Microphone, ScreenCapture, AudioCapture) with no prompt, and logged no camera query at all.
macOS 27 still needs M11.

## Claude's discretion (X1-X12, as planned)

- **X1:** a `.regular` instance counts as standalone, so nested regular apps still update, as the
  removed notifications did.
- **X2:** the KVO payload is used only to skip changes without bundle IDs. The diff runs on the
  main actor against the live list.
- **X3:** no shared RunningApplicationsMonitor; the three observers have different lifetimes.
- **X4:** holzBar's menu does not name the recording app.
- **X5:** the dot is a subview, so the icon stays a template image and the bar never reflows.
- **X6:** the tooltip and the accessibility label carry the same text and are reset afterwards.
- **X7:** the monitor runs while the setting is on, not only while concealing.
- **X8:** `checkOwnIconForCapture()` mirrors `checkOwnIcon()`: two settled reads, one reinsert.
- **X9:** callbacks arrive on the main queue and are handled with `MainActor.assumeIsolated`.
- **X10:** the ServiceRestarted listener re-registers everything (via a main-actor Task, so the
  listener is not removed from inside its own callback).
- **X11:** camera plus microphone shows green and has its own text.
- **X12:** the key is `HolzBarIconShowsCaptureDot`; it can be imported and synced like every
  setting.

## Gates (run before each commit, all passed)

| Gate | F-17 | F-08 |
|------|------|------|
| `appcheck.sh` (whole app module, Swift 6, 26.5 SDK) | ERRORS: 0 EXIT: 0 | ERRORS: 0 EXIT: 0 |
| `servicecheck.sh` | SERVICE EXIT: 0 | SERVICE EXIT: 0 |
| `swift test` (full) | 6 + 174 + 270 passed | 6 + 174 + 281 passed |
| SwiftLint `--strict --quiet` | no output, exit 0 | no output, exit 0 |
| privacy-check network / logs | pass / pass | pass / pass (after one fix, below) |
| strings-check | 369 strings in 5 languages | 374 strings in 5 languages |
| former name check | nothing found | nothing found |
| plan grep gates (no launch/terminate notifications; KVO `[.old, .new]` in both; selectors present; no `Timer`/`asyncAfter`/`Task.sleep`/device-wide audio selector/`ElementMaster` in the monitor; no usage strings or capture entitlements; catalog keys) | pass | pass |

`swift test` hit the known Command Line Tools flake ("plugin for module 'TestingMacros' not
found") several times in a row and passed on a rerun with no code change. An extra appcheck run
against the macOS 27.0 SDK cannot be used with the Command Line Tools (the SwiftUI macro plugins
are missing). None of its errors are in the files changed here, and CI's Xcode 27 build remains
the final check.

## Deviations from the plan

- **[Rule 1] privacy-check:** the first F-08 gate run flagged two log lines. The checker treats
  any interpolation named `error` as personal data, and the read failures were bound as `error`.
  They are now bound as `failure` and log only `failure.status` (an OSStatus, `.public`).
- The plan's ServiceRestarted handler calls `stop()` then `start()` directly. Here it hops once
  through a main-actor `Task` to `restart()`, so the listener is not removed from inside its own
  callback. It runs once per event and does not poll (X10).
- `positionCaptureDot()` keeps the dot inside the button's bounds, so it is never clipped.
- Test-first: the tests and the new Core types were written in the same step, because the tests
  cannot compile without the types (as in the sibling part).
- STATE.md and ROADMAP.md were not touched, because this audit chain does not track them.

## Risks (macOS 26 and 27; open until the maintainer's session)

- **R1:** it is not measured whether MenuBarAgent mirrors a subview of holzBar's button. If M6
  shows no dot, the follow-up is a non-template composite image while a capture runs.
- **R2:** each relevant launch or quit costs one assertion change (about 250 ms re-layout plus
  four AX reads). At login several may run in a row (no debounce, by decision).
- **R3:** an agent whose item comes from an embedded helper `.app` is only caught once holzBar has
  seen it on the bar.
- **R4:** a quit and relaunch within one main-actor turn leaves the set unchanged, so a
  Hidden-section agent then gets no grace. This is rare.
- **R5:** if `ScreensharingAgent.bundle` never checks in with LaunchServices, Zen stays blind to it
  (M5 is optional).
- **R6:** TCC behaviour was measured on 26.7.1 only. A non-preflight request on 27 would terminate
  holzBar (it has no usage strings). If that happens, turn the setting off by default.
- **R7/R8:** holzBar becomes a CoreAudio/CoreMediaIO client: some memory, and a few small IPC
  reads on the main thread per event. If M13 or daily use shows hitches, move the reads to a
  serial queue.
- **R9/R10:** apps that keep the microphone open keep the dot orange. Virtual cameras and
  Continuity Camera count as cameras.
- **R11:** during a click-bridge suspension `isConcealing` is briefly false, so the dot blinks
  off.
- **R12:** while a capture runs, the button's accessibility label is the capture text. Items are
  identified by AXIdentifier, so nothing else changes.
- **R13:** with "Show holzBar icon" off, adding the icon for a capture is itself a bar change;
  `checkOwnIconForCapture()` reinserts once.
- **R14:** the local compile checks use the 26.5 SDK; only CI compiles against 27.
- **R15 (found while implementing):** with "Show holzBar icon" off, clicking the icon that was
  shown for a capture reveals the hidden items. Nothing is concealed then, so the badge and the
  icon go away until concealment resumes (Control Centre draws its own indicator in that time).
  M10 should note whether this feels wrong.

## Manual test on macOS 27 (maintainer, one session; M5 also on macOS 26)

Setup: install with `Scripts/install.sh`, grant Accessibility, keep at least one app in a
concealed Hidden section, and leave "Show a dot on the holzBar icon…" on (the default). Run three
log streams:
- `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "ConcealmentController27"'`
- `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND (category == "Concealer27" OR category == "CaptureActivityMonitor27" OR category == "PresentationMonitor")'`
- `log stream --info --predicate 'process == "tccd" AND eventMessage CONTAINS "com.holzcloud.holzBar"'`

F-17:
- **M1:** with Hidden concealed, quit and relaunch a Visible LSUIElement agent (Rectangle). It is
  back at full width within about 1 s.
- **M2:** log out and back in with agents as login items. Every Visible agent shows.
- **M3:** relaunch an agent from the Hidden section. It shows briefly, is then concealed, and is
  full width when revealed.
- **M4:** open Safari tabs, take a screenshot, use Touch ID. The bar does not twitch, and the
  count of "Concealment apply: started" does not rise.
- **M5 (optional, 26 or 27):** turn on "Turn on Zen mode while the screen is mirrored or shared"
  and connect with Screen Sharing from another Mac. "Zen mode on" appears within about 1 s;
  after disconnecting, Zen turns off once the agent quits.

F-08:
- **M6:** record in Voice Memos with Hidden concealed. An orange dot appears on holzBar's icon
  within about 1 s and goes away when the recording stops.
- **M7:** Photo Booth or FaceTime gives a green dot, still green with the microphone in use too.
  VoiceOver reads "Camera and microphone in use", and the tooltip shows the same text.
- **M8:** click holzBar's icon during a recording: the dot goes and Control Centre's orange
  indicator appears. Hiding again brings the dot back.
- **M9:** with the holzBar Shelf on, the dot shows while recording.
- **M10:** turn the new toggle off: no dot. Turn it on again. Then turn "Show holzBar icon" off and
  record: the icon appears with the dot and goes away afterwards (note R15).
- **M11 (permissions):** at most `preflight=yes` lines from coreaudiod; no prompt, no
  kTCCServiceCamera line, and holzBar keeps running. holzBar is not listed under Privacy &
  Security → Microphone or Camera.
- **M12:** with Zen on and the screen shared, record. Hidden items stay hidden and the dot shows.
- **M13:** in Activity Monitor, holzBar idles at 0 % CPU with the setting on. Note its memory with
  the setting on and off.
- **M14 (opportunistic):** if holzBar's icon vanishes while concealing, start a recording: the
  icon comes back with the dot ("putting it back" in the Concealer27 log).

## Doc updates needed (not done here; docs edits are forbidden in this run)

- `docs/privacy-and-permissions.md:31`: holzBar now marks its icon (orange for the microphone,
  green for a camera) while it hides items on macOS 27. The setting is in General and on by
  default. Screen recording is not covered (no public API). Reading the state needs no
  permission and nothing is recorded. Optionally add a permissions-table row for the
  microphone/camera state (CoreAudio/CoreMediaIO, no permission).
- `docs/features.md:84` (macOS 27 limitations): the same, shorter, plus a feature entry for the
  dot.
- `docs/features.md:129` alt text and `Resources/Screenshots/settings-spacing.png`: the General
  pane shows the new toggle under the macOS 27 note. Retake the screenshot.
- `README.md:86`, the feature list, and possibly a row in the "holzBar vs. Ice and Thaw" table.
- `SECURITY.md:27` (T-06-M3): "Mitigated for microphone and camera (dot on holzBar's icon, on by
  default); disclosed for screen recording".
- Release notes of the next beta:
  - Fixed: automatic Zen mode now turns on and off when Screen Sharing starts and ends.
  - Fixed: on macOS 27, menu bar apps without a Dock icon that start after holzBar are no longer
    kept hidden or squashed.
  - New: on macOS 27, a dot on holzBar's icon while an app uses the microphone (orange) or the
    camera (green).

## Self-Check: PASSED

- The new files exist: `Core/PresentationSignals.swift` (Trigger), `MacOS27/Core/AgentLaunches27.swift`,
  `AgentLaunches27Tests.swift`, `Core/CaptureIndicator.swift`, `CaptureIndicatorTests.swift`,
  `MacOS27/CaptureActivityMonitor27.swift` and `ControlItem/CaptureDotView.swift`.
- Commit 3a0c23be (F-17) is an ancestor of HEAD. The F-08 commit contains this file.
