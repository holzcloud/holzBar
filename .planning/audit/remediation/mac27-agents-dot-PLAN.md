---
phase: audit-remediation-mac27-agents-dot
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - holzBar/Core/PresentationSignals.swift
  - Tests/HolzBarCoreTests/PresentationSignalsTests.swift
  - holzBar/MenuBar/PresentationMonitor.swift
  - holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift
  - Tests/HolzBarMacOS27CoreTests/AgentLaunches27Tests.swift
  - holzBar/MenuBar/MacOS27/Concealer27.swift
  - holzBar/Core/CaptureIndicator.swift
  - Tests/HolzBarCoreTests/CaptureIndicatorTests.swift
  - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
  - holzBar/Core/Defaults.swift
  - holzBar/Settings/Models/GeneralSettings.swift
  - holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift
  - holzBar/Main/AppState.swift
  - holzBar/MenuBar/ControlItem/CaptureDotView.swift
  - holzBar/MenuBar/ControlItem/ControlItem.swift
  - holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift
  - holzBar/Resources/Localizable.xcstrings
  - .planning/audit/remediation/mac27-agents-dot-SUMMARY.md
autonomous: true
requirements: [F-17, F-08]

estimate:
  tokens: 230000
  raw_tokens: 230000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "macOS 26 and 27: with automatic Zen on, Zen turns on when macOS's screen sharing agent starts and off when it quits, with no other app launching or quitting (D-01a)"
    - "A change of the running applications that leaves the set of bundle identifiers as it was (a second instance, a helper restart) causes no Zen evaluation and no concealment update (D-01a, D-01d)"
    - "macOS 27: a Visible menu bar agent that launches or relaunches after holzBar is in the allowlist of the next concealment apply, with no debounce, so it is drawn at full width (D-01f, D-01g)"
    - "macOS 27: an agent whose saved section is Hidden or Always Hidden gets a launch grace when it launches, so its item is created allowed and then concealed (D-01f)"
    - "macOS 27: WebKit, browser and Electron helpers and other nested bundles holzBar never saw on the bar trigger no concealment update; known apps and top-level apps do (D-01e)"
    - "macOS 27: while holzBar conceals items and another process records from the microphone, holzBar's icon shows an orange dot; while one uses a camera, a green dot; the icon's accessibility label and tooltip say what is in use (D-02b, D-02c, D-02e)"
    - "No dot while holzBar conceals nothing (Control Centre draws its own indicator then) or while the new setting is off; the setting is on by default (D-02e, D-02i)"
    - "holzBar requests no permission and no entitlement, never starts audio or video I/O, never polls, and never counts its own process (D-02b, D-02d)"
    - "With Show holzBar icon off, the icon appears with the dot while a capture runs and goes away afterwards; when a capture starts and MenuBarAgent dropped the icon, it is put back (D-02f, D-02g)"
    - "Every new text exists in English, German (Swiss spelling), French, Italian and Romansh; strings-check passes (D-02j)"
  artifacts:
    - path: holzBar/Core/PresentationSignals.swift
      provides: "PresentationSignals.Trigger: evaluate only when the running bundle identifiers changed (pure, swift-tested)"
      contains: "struct Trigger"
    - path: holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift
      provides: "Diff and classification of running-application changes for the macOS 27 concealer (pure, swift-tested)"
      contains: "enum AgentLaunches27"
    - path: Tests/HolzBarMacOS27CoreTests/AgentLaunches27Tests.swift
      provides: "Tests of AgentLaunches27"
      contains: "AgentLaunches27Tests"
    - path: holzBar/Core/CaptureIndicator.swift
      provides: "CaptureActivity, CaptureBadge, CaptureIndicator.badge/showsHolzBarIcon (pure, swift-tested)"
      contains: "enum CaptureIndicator"
    - path: Tests/HolzBarCoreTests/CaptureIndicatorTests.swift
      provides: "Tests of the capture badge decision and the activity bookkeeping"
      contains: "CaptureIndicatorTests"
    - path: holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift
      provides: "Event-driven microphone (CoreAudio process objects) and camera (CoreMediaIO) monitor, macOS 27 only"
      contains: "final class CaptureActivityMonitor27"
    - path: holzBar/MenuBar/ControlItem/CaptureDotView.swift
      provides: "The coloured dot drawn over holzBar's icon"
      contains: "final class CaptureDotView"
  key_links:
    - from: NSWorkspace runningApplications KVO in PresentationMonitor.start()
      to: PresentationSignals.Trigger.needsEvaluation(running:) -> evaluate -> MenuBarManager.setAutomaticZenMode
      via: "Task { @MainActor in } hop; observation invalidated in stop()"
    - from: NSWorkspace runningApplications KVO in Concealer27.performSetup
      to: AgentLaunches27.reaction -> launchGrace.begin / showTemporarily(bundleIDs:) / update()
      via: "runningApplicationsDidChange(); exactly one update() per relevant callback"
    - from: CoreAudio and CoreMediaIO listener blocks (DispatchQueue.main)
      to: CaptureActivityMonitor27.activity -> AppState.captureBadge27 -> ControlItem observer
      via: "ObservationLoop.observe on captureBadge27 -> updateMenuBarPresence() + updateStatusItem() -> CaptureDotView"
    - from: CaptureActivityMonitor27 badge observer (nil -> badge)
      to: Concealer27.checkOwnIconForCapture() -> ControlItem.reinsert()
      via: "two settled reads of MenuBarItemProvider27.items() without .visibleControlItem"
    - from: GeneralSettings.holzBarIconShowsCaptureDot (Defaults key HolzBarIconShowsCaptureDot)
      to: CaptureActivityMonitor27 start/stop and CaptureIndicator.badge(isEnabled:)
      via: "ObservationLoop in CaptureActivityMonitor27.performSetup"
---

# mac27-agents-dot: F-17 (agent launches and quits) and F-08 (capture dot on holzBar's icon)

Audit remediation chain `mac27`, part `agents-dot`. Worktree:
`/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks`
(branch `audit-manual/mac27-clicks`, based on `audit/remediation-2026-10-05`; F-26 and F-27 of the
`clicks` part are already committed on it, HEAD 4dddd7c5).

**Relayed user message (not part of this part's scope).** The user's message that started this run
asks, in German, whether the *signing* could be solved differently after all. Neither F-17 nor F-08
changes code signing, and this plan does not answer or change anything about it. The signing
questions belong to the `release` part (F-05, F-10, F-11, F-52, F-53, F-54; `release-1.md`) and
`xpc-trust` (F-04/F-48, where "Apple Developer ID kaufen" was rejected). The orchestrator has to
take that question back to the user as a multiple choice (CLAUDE.md) before those parts run. One
fact from this part is relevant to that conversation: `ControlItem.swift:422-426` records that
holzBar "is signed locally, so MenuBarAgent drops its items whenever anything is concealed
(measured on macOS 27.0)", and Ice#1001 says MenuBarAgent can also drop holzBar's own icon while
assertions are live. F-08's dot is drawn on that icon, so it depends on the icon staying on the bar
while concealing (Task 3 re-checks and reinserts it). Whether a Developer ID signature would change
MenuBarAgent's behaviour is not measured. The executor must not touch release, signing or CI files.

**Decision IDs used below**

| ID | Source | Chosen option |
|----|--------|---------------|
| D-01 | `SP/decisions/agent-launches-1.md` (F-17) | "Bekannte + eigenständige Apps (Recommended)": react to apps holzBar has seen on the bar and to new top-level apps; WebKit, browser and Electron helpers do not count |
| D-02 | `SP/decisions/indicators-2.md` (F-08) | "Punkt im holzBar-Symbol (Recommended)": an orange (microphone) or green (camera) dot on holzBar's own icon while it conceals; hidden items stay hidden; screen recording is not covered |

Sub-items, cited in the tasks:

- D-01a PresentationMonitor: one `runningApplications` KVO with options `[.old, .new]`, existing only
  while `autoZenWhileSharingScreen` is on (created in `start()`, invalidated in `stop()`); hop to the
  main actor; call `evaluate()` when the bundle-ID set changed; keep the screen-parameters task.
- D-01b Doc comments in PresentationMonitor and `holzBar/Core/PresentationSignals.swift` say "when
  the running applications change".
- D-01c The Zen trigger logic lives in `holzBar/Core`, tested in `Tests/HolzBarCoreTests`.
- D-01d Concealer27.performSetup: the launch and terminate notification tasks are replaced by a
  `runningApplications` KVO that diffs bundle-ID sets against the last snapshot; callbacks that leave
  the set unchanged (7 of 9 in the 5-minute probe) do nothing.
- D-01e Known = `Set(savedLayout.keys)` plus Defaults `.knownApplications27`. Standalone = some
  instance whose `bundleURL` has extension `app` and whose parent path contains none of `.app/`,
  `.framework/`, `.xpc/`, `.appex/`, `.bundle/`. Do not rely on `activationPolicy` (WebKit `.xpc`
  and Electron/browser helpers run `.accessory` with LSUIElement=1; OneDrive declares
  LSBackgroundOnly=1 yet runs `.accessory`).
- D-01f Per callback: added known IDs whose saved section is concealed start launch graces
  (`launchGrace.begin`, one `showTemporarily(bundleIDs:)`, one `LaunchGrace27.timeout` task); added
  known or standalone IDs and removed known IDs run `notchConcealed.removeAll()` and exactly one
  `update()`; everything else is ignored. `applicationDidLaunch(bundleID:)` becomes a batch form.
- D-01g No trailing debounce: the allowlist must land before the agent creates its status item
  (Ice#1007, 3 pt squash).
- D-01h Diff and classification are pure functions in `holzBar/MenuBar/MacOS27/Core`
  (`AgentLaunches27`, taking (bundleID, bundle path, policy) tuples and the known set), tested in
  `Tests/HolzBarMacOS27CoreTests`.
- D-01i Never block or take a lock in the main-thread KVO handler (F-12). Coordinate with F-28
  (`notchConcealed`; already fixed on this branch, commits 02678651 and 19da231c).
- D-01j Gates: swift test, xcodebuild (CI) and SwiftLint `--strict`; the maintainer's macOS 27
  checklist (M1-M4 below).
- D-02a `CaptureActivityMonitor` (app target, `@MainActor`, macOS 27 only) runs only while the
  setting is on.
- D-02b Microphone through CoreAudio process objects: `kAudioHardwarePropertyProcessObjectList` on
  `kAudioObjectSystemObject` and `kAudioProcessPropertyIsRunningInput` on each process object;
  holzBar's own PID (`kAudioProcessPropertyPID`) is ignored.
- D-02c Camera through CoreMediaIO: `kCMIOHardwarePropertyDevices` and
  `kCMIODevicePropertyDeviceIsRunningSomewhere` with `CMIOObjectAddPropertyListenerBlock`.
- D-02d No polling, permission or entitlement; confirm on a real Mac that reading shows no TCC
  prompt. `kAudioDevicePropertyDeviceIsRunningSomewhere` is NOT the main signal (device-wide; it also
  fires when a headset is used for output only). The computed task text named it as an example;
  the maintainer's decision rules it out, and the decision wins.
- D-02e In `ControlItem.updateStatusItem` (`.visible`): an orange dot (microphone) or green dot
  (camera) on the icon while `Concealer27.isConcealing` and a capture is active, with an
  accessibility description.
- D-02f With `showHolzBarIcon` off, the icon shows while the capture runs.
- D-02g Make sure the icon is present when a capture starts (`ControlItem.reinsert`, Ice#1001).
- D-02h The pure decision (setting, concealing, mic, camera -> badge) lives in `holzBar/Core` with
  swift tests.
- D-02i A new setting in GeneralSettings, on by default, next to PrivacyIndicatorNote, and the
  note's text updated.
- D-02j Every new string in en/de/fr/it/rm in `holzBar/Resources/Localizable.xcstrings`
  (`strings-check.py`).
- D-02k Docs (`docs/privacy-and-permissions.md:31`, `docs/features.md:84`, README): NOT edited by
  the executor (this run forbids docs edits); listed under "Doc updates needed".
- D-02l Nothing is revealed, so Zen mode and screen shares are unaffected.
- D-02m The maintainer checks on macOS 27 during a Voice Memos recording.

Rejected options (must NOT be implemented): F-17 "Nur bekannte Apps", "Alle App-Prozesse
beachten", "Nur Zen-Teil jetzt"; F-08 "Verstecken bei Aufnahme pausieren", "Punkt plus
Pause-Option", "Vorerst nur Hinweistext", and the audit's proposal to release concealment during
capture.

<objective>
Close F-17 and F-08 exactly as the maintainer decided (D-01, D-02). The decision logic goes into
pure, swift-tested types: `PresentationSignals.Trigger` and `CaptureIndicator` in `holzBar/Core`,
and `AgentLaunches27` in `holzBar/MenuBar/MacOS27/Core`. The app-target wiring stays thin and
event-driven. There is one atomic commit per finding.

Purpose:
- Automatic Zen must notice the start and end of Screen Sharing, and the macOS 27 concealer must
  allow a Visible menu bar agent that starts after holzBar (F-17).
- On macOS 27 a user whose items are concealed (the normal state) must still see when another app
  uses the microphone or the camera (F-08).

Output:
- Two commits: `fix(menubar): resolve F-17 …` and `fix(macos27): resolve F-08 …`.
- New Core types with tests, the macOS 27 `CaptureActivityMonitor27`, the dot on holzBar's icon,
  one new General setting with its strings in five languages.
- `.planning/audit/remediation/mac27-agents-dot-SUMMARY.md`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
Absolute paths. WT = the worktree above; SP = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`.

- Decisions: `SP/decisions/agent-launches-1.md` (D-01), `SP/decisions/indicators-2.md` (D-02).
- Findings: `WT/.planning/audit/FULL-AUDIT-2026-10-05.md`, "#### F-17" (line 785) and "#### F-08"
  (line 462). F-28 (line 1153), F-73 and F-77 are already fixed on this branch. F-12 belongs to the
  xpc-trust part; only its rule applies here: no lock and no blocking in a main-thread KVO handler.
- Rules: `WT/CLAUDE.md` covers:
  - English everywhere; modern Swift 6; events over polling.
  - Private: no network; values from other apps in logs use `privacy: .private`.
  - Naming: the holzBar icon's members are `holzBarIcon<Name>`.
  - Persisted keys are never renamed, only added.
  - New strings in five languages.

  `WT/.swiftlint.yml` requires the file header `//\n//  <File>.swift\n//  holzBar\n//`, mandatory
  trailing commas in multi-line collections, no force unwrapping, and `unavailable_function`.
- Code (read once each; line numbers as of HEAD 4dddd7c5):
  - `WT/holzBar/MenuBar/PresentationMonitor.swift` (105 lines): doc comment 9-17, `start()` 52-76,
    `stop()` 79-86, `evaluate()` 88-104.
  - `WT/holzBar/Core/PresentationSignals.swift` (27 lines) and
    `WT/Tests/HolzBarCoreTests/PresentationSignalsTests.swift` (19 lines).
  - `WT/holzBar/MenuBar/MacOS27/Concealer27.swift` (850 lines):
    - properties 20-105;
    - `performSetup` 107-161 (notification tasks 113-126, screen-parameters task 127-136);
    - `deinit` 163-167;
    - `applicationDidLaunch(bundleID:)` 169-195;
    - `itemsAppeared`/`endGraces` 197-211;
    - `applyChanges()` 228-302;
    - `checkOwnIcon()` 381-410;
    - `timeUntilSettled()` 625-629;
    - `showTemporarily(bundleIDs:)` 640-648;
    - `placeNewApplications` 699-735 (how `.knownApplications27` is read).
  - `WT/holzBar/MenuBar/MacOS27/Core/LaunchGrace27.swift` (69 lines) and
    `WT/Tests/HolzBarMacOS27CoreTests/Displays27Tests.swift` 57-100 (Core test style: mutate outside
    `#expect`).
  - `WT/holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift` 104-118: the existing
    `runningApplications` KVO pattern (`Task { @MainActor in }` hop). Do NOT change this file (F-73
    is done there).
  - `WT/holzBar/MenuBar/Appearance/WallpaperChangeMonitor.swift` 24-55: the pattern for a callback
    on `DispatchQueue.main` with `MainActor.assumeIsolated`.
  - `WT/holzBar/MenuBar/ControlItem/ControlItem.swift` (799 lines):
    - `configureObservers()` 203-268;
    - `updateMenuBarPresence()` 293-315;
    - `windowDidChange` 318-343;
    - `updateStatusItem()` 370-462;
    - `reinsert()` 517-525.
  - `WT/holzBar/Main/AppState.swift`: properties 78-120 (the macOS 27 storage pattern of
    `concealer27`), setup task 145-176.
  - `WT/holzBar/Core/Defaults.swift` 144-239 (keys) and 248-325 (`settingsKind`);
    `WT/Tests/HolzBarCoreTests/SettingsSchemaTests.swift` 155-176.
  - `WT/holzBar/Settings/Models/GeneralSettings.swift` 1-90 and 155-212.
  - `WT/holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift` 35-59, 78-82 and 367-394
    (PrivacyIndicatorNote).
  - `WT/holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift` 52-65: the measurement that the
    capture indicator is gone while an assertion is live.
  - `WT/.github/scripts/strings-check.py`: the positions it scans include `String(localized:`,
    `Toggle(`, `.annotation(`, `Text(`, `setAccessibilityLabel(` and `toolTip =`.
  - `WT/holzBar/Resources/Localizable.xcstrings`. Its exact on-disk format is reproduced by
    Python's `json.dumps(data, indent=2, ensure_ascii=False, separators=(',', ' : '),
    sort_keys=True)` plus a trailing newline (verified byte-identical at HEAD). Edit it only that
    way, never by hand.

**Facts measured for this plan (read-only probes on this Mac, macOS 26.7.1, 2026-10-05):**
- The installed macOS 27.0 and 26.5 SDKs both declare `kAudioHardwarePropertyProcessObjectList`,
  `kAudioProcessPropertyPID`, `kAudioProcessPropertyIsRunningInput`,
  `kAudioHardwarePropertyServiceRestarted`, `kCMIOHardwarePropertyDevices`,
  `kCMIODevicePropertyDeviceIsRunningSomewhere`, `AudioObjectAdd/RemovePropertyListenerBlock` and
  `CMIOObjectAdd/RemovePropertyListenerBlock`. Only the `…ElementMaster` spellings are deprecated;
  use the `…ElementMain` constants.
- A CLI probe read the process object list: 39 objects, status 0. Its own process was in the list
  as soon as it called CoreAudio, so the own-PID filter (D-02b) is required. It read
  `IsRunningInput` for each object, read 3 CoreMediaIO devices and their `IsRunningSomewhere`, and
  added and removed one listener on each system object. Every call returned 0.
- TCC log for that window (`/usr/bin/log show`, process `tccd`):
  - coreaudiod made preflight-only queries (`preflight=yes`) for kTCCServiceMicrophone,
    kTCCServiceScreenCapture and kTCCServiceAudioCapture for the new HAL client. They answered
    within 7 ms, with no prompt.
  - The CoreMediaIO reads caused no TCC query at all (0 kTCCServiceCamera lines).

  So reading these properties needs no permission and shows no prompt on macOS 26. macOS 27 is
  confirmed by the maintainer in M11.
- holzBar's Info.plist has no NSMicrophoneUsageDescription or NSCameraUsageDescription, and none
  may be added. A non-preflight TCC request without a usage string would terminate holzBar, so M11
  also checks that holzBar keeps running.
</context>

## Interfaces to create (signatures only; the executor writes the bodies)

`holzBar/Core/PresentationSignals.swift`, inside `nonisolated enum PresentationSignals`:

```swift
/// Tells which changes of the running applications are evaluated: only those that change the
/// set of bundle identifiers.
nonisolated struct Trigger: Equatable, Sendable {
    /// The bundle identifiers last evaluated; nil before the first evaluation.
    private(set) var evaluated: Set<String>?
    /// Whether `running` differs from the identifiers last evaluated; records it when it does.
    mutating func needsEvaluation(running: Set<String>) -> Bool
    /// Forgets the last identifiers, so the next call evaluates.
    mutating func reset()
}
```

New `holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift`:

```swift
nonisolated enum AgentLaunches27 {
    /// NSApplication.ActivationPolicy without AppKit.
    nonisolated enum Policy: Equatable, Sendable { case regular, accessory, prohibited }
    /// One running process: its bundle identifier, the path of its bundle, its policy.
    typealias Instance = (bundleID: String, bundlePath: String?, policy: Policy)
    /// What the concealer does about one change.
    nonisolated struct Reaction: Equatable, Sendable {
        var running: Set<String>        // the snapshot the next change is compared with
        var graces: [String]            // added IDs whose saved section is concealed, sorted
        var updatesConcealment: Bool    // notchConcealed.removeAll() + exactly one update()
    }
    /// Path parts that mark a bundle nested in another one.
    static let nestingMarkers: [String]   // [".app/", ".framework/", ".xpc/", ".appex/", ".bundle/"]
    static func isStandalone(bundlePath: String?, policy: Policy) -> Bool
    static func reaction(
        previous: Set<String>,
        instances: [Instance],
        known: Set<String>,
        concealedInLayout: Set<String>
    ) -> Reaction
}
```

New `holzBar/Core/CaptureIndicator.swift`:

```swift
/// What holzBar's icon shows while another app records.
nonisolated enum CaptureBadge: Equatable, Sendable {
    case microphone
    case camera
    case cameraAndMicrophone
    /// Whether the dot is green (a camera), as Control Centre colours its indicator; orange otherwise.
    var showsCamera: Bool { get }
}

/// The processes recording from the microphone and the cameras in use, by object ID.
nonisolated struct CaptureActivity: Equatable, Sendable {
    init(ownPID: Int32)
    private(set) var microphones: Set<UInt32>     // CoreAudio process objects with input running
    private(set) var cameras: Set<UInt32>         // CoreMediaIO devices running somewhere
    var isMicrophoneInUse: Bool { get }
    var isCameraInUse: Bool { get }
    mutating func setInput(of process: UInt32, pid: Int32, isRunning: Bool)   // ignores ownPID
    mutating func keepProcesses(_ processes: Set<UInt32>)                    // drops gone objects
    mutating func setCamera(_ device: UInt32, isRunning: Bool)
    mutating func keepCameras(_ devices: Set<UInt32>)
}

nonisolated enum CaptureIndicator {
    static func badge(isEnabled: Bool, isConcealing: Bool, isMicrophoneInUse: Bool, isCameraInUse: Bool) -> CaptureBadge?
    static func showsHolzBarIcon(isIconEnabled: Bool, badge: CaptureBadge?) -> Bool
}
```

App target (all `@available(macOS 27.0, *)` except where noted):

```swift
// holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift
@MainActor @Observable final class CaptureActivityMonitor27 {
    private(set) var activity: CaptureActivity
    func performSetup(with appState: AppState)
}
// holzBar/Main/AppState.swift
var captureActivityMonitor27: CaptureActivityMonitor27 { get }   // lazy storage, like concealer27
var captureBadge27: CaptureBadge? { get }                        // CaptureIndicator.badge over the live state
// holzBar/MenuBar/MacOS27/Concealer27.swift
func checkOwnIconForCapture() async
// holzBar/MenuBar/ControlItem/CaptureDotView.swift (any macOS; only used on 27)
final class CaptureDotView: NSView { var color: NSColor }
// holzBar/Core/Defaults.swift (any macOS)
case holzBarIconShowsCaptureDot = "HolzBarIconShowsCaptureDot"   // settingsKind .bool
// holzBar/Settings/Models/GeneralSettings.swift (any macOS)
var holzBarIconShowsCaptureDot = true
```

## Source audit (GOAL / REQ / RESEARCH / CONTEXT)

| Source | Item | Covered by |
|--------|------|-----------|
| GOAL | F-17 failure scenario 1 (Zen misses Screen Sharing start/end) closed | Task 1 (A, B) |
| GOAL | F-17 failure scenario 2 (later Visible agent hidden and squashed on 27) closed | Task 1 (C, D) |
| GOAL | F-08 failure scenario (no microphone cue while concealing on 27) closed for microphone and camera; screen recording disclosed as not covered | Tasks 2 and 3 |
| REQ | F-17 | Task 1, commit 1 |
| REQ | F-08 | Tasks 2 and 3, commit 2 |
| RESEARCH | 115 processes share 90 IDs; 7 of 9 KVO callbacks leave the set unchanged | Task 1 (set diff, early return), AgentLaunches27Tests "unchanged set" |
| RESEARCH | LSUIElement and background apps produce only the KVO change, no notification | Task 1 (KVO replaces notifications in both places) |
| RESEARCH | ScreensharingAgent.bundle (non-.app) and SSMenuAgent.app (top-level) | Task 1 (any set change re-evaluates Zen; SSMenuAgent is standalone), tests |
| RESEARCH | OneDrive LSBackgroundOnly yet `.accessory`; helpers `.accessory` | Task 1 (policy not used to exclude), tests |
| RESEARCH | Every allowlist change costs a ~250 ms re-layout plus four AX reads | Task 1 (filter + one update per callback), risk R2 |
| RESEARCH | CoreAudio process objects list the reader itself; TCC preflight only; CoreMediaIO no TCC | Task 2 (own-PID filter), M11 |
| RESEARCH | coreaudiod restart drops listeners (header text for `kAudioHardwarePropertyServiceRestarted`) | Task 2 (re-register) |
| CONTEXT | D-01a, D-01b, D-01c | Task 1 A-B |
| CONTEXT | D-01d, D-01e, D-01f, D-01g, D-01h, D-01i | Task 1 C-D |
| CONTEXT | D-01j | Gates (all tasks), manual M1-M5 |
| CONTEXT | D-02a, D-02b, D-02c, D-02d, D-02g, D-02h | Task 2 |
| CONTEXT | D-02e, D-02f, D-02i (UI part), D-02j | Task 3 |
| CONTEXT | D-02i (setting model) | Task 2 |
| CONTEXT | D-02k | "Doc updates needed" (executor must not edit docs in this run) |
| CONTEXT | D-02l | No code reveals anything; checked by M12 |
| CONTEXT | D-02m | Manual M6 |

Not gaps:
- The optional shared `RunningApplicationsMonitor` (D-01) and the optional app name from
  `kAudioProcessPropertyBundleID` (D-02) are discretion items X3 and X4, deliberately not taken.
- The rejected options are excluded.

Claude's discretion (consistent with D-01/D-02; record each in the summary):
- X1: an instance with policy `.regular` also counts as standalone. The removed launch
  notifications covered every regular app, so a regular app nested in another bundle (rare)
  still causes an update as before. Helpers are `.accessory`, so they stay excluded.
- X2: the KVO payload (`[.old, .new]`) is used only to skip a change whose inserted and removed
  applications carry no bundle identifier. Such a change cannot alter the bundle-ID set. The set
  diff itself runs on the main actor against the live `NSWorkspace.shared.runningApplications`.
- X3: no shared RunningApplicationsMonitor. The three observers have different lifetimes: Zen only
  while its setting is on, the concealer always on 27, and MenuBarItemManager's KVO (F-73) is left
  untouched.
- X4: holzBar's menu does not name the recording app. CoreMediaIO cannot name a camera's user, so
  naming only microphone users would be lopsided, and it would add another app's bundle ID to
  holzBar's state.
- X5: the dot is a subview (`CaptureDotView`), not a composite image, so the icon keeps its
  template rendering and the dot keeps its colour. The colour resolves in `updateLayer()` for the
  current appearance. The dot never changes the status item's length, so it never reflows the
  bar on 27.
- X6: the accessibility label and the tooltip carry the same text and are reset when no capture
  runs.
- X7: the monitor runs while the setting is on and assertions are available, not only while
  concealing. Concealing is the normal state, and starting and stopping on every reveal would add
  churn.
- X8: the icon check on capture start mirrors `checkOwnIcon()`. It waits for pending applies and
  the settle time, reads twice 400 ms apart, then reinserts once (`checkOwnIconForCapture()`).
- X9: CoreAudio and CoreMediaIO callbacks are delivered on `DispatchQueue.main` and handled with
  `MainActor.assumeIsolated`, as `WallpaperChangeMonitor` does. They come only on events, with a
  few small property reads each.
- X10: a `kAudioHardwarePropertyServiceRestarted` listener re-registers everything, because the
  header says listeners must be re-established after a reset.
- X11: camera plus microphone shows green (camera), as Control Centre does, and gets its own
  accessibility text.
- X12: the setting is named `holzBarIconShowsCaptureDot`, Defaults key
  `HolzBarIconShowsCaptureDot` (CLAUDE.md naming). It is importable and synced like every other
  setting.

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (F-17): follow runningApplications by KVO for automatic Zen and the macOS 27 concealer</name>
  <files>holzBar/Core/PresentationSignals.swift, Tests/HolzBarCoreTests/PresentationSignalsTests.swift, holzBar/MenuBar/PresentationMonitor.swift, holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift, Tests/HolzBarMacOS27CoreTests/AgentLaunches27Tests.swift, holzBar/MenuBar/MacOS27/Concealer27.swift</files>
  <read_first>
    - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/agent-launches-1.md (D-01, whole file)
    - WT/.planning/audit/FULL-AUDIT-2026-10-05.md lines 785-829 (F-17) and 1153-1182 (F-28)
    - WT/holzBar/MenuBar/PresentationMonitor.swift (whole file)
    - WT/holzBar/Core/PresentationSignals.swift and WT/Tests/HolzBarCoreTests/PresentationSignalsTests.swift
    - WT/holzBar/MenuBar/MacOS27/Concealer27.swift lines 20-221, 228-302, 640-735
    - WT/holzBar/MenuBar/MacOS27/Core/LaunchGrace27.swift and WT/Tests/HolzBarMacOS27CoreTests/Displays27Tests.swift lines 55-100
    - WT/holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift lines 104-118 (KVO hop pattern; read only)
  </read_first>
  <behavior>
    Suite "PresentationSignals" (extend WT/Tests/HolzBarCoreTests/PresentationSignalsTests.swift; mutate the trigger outside #expect):
    - A new Trigger evaluates the first set it sees: needsEvaluation(running: ["a"]) is true.
    - The same set again is not evaluated (a second instance of a running app, a helper restart): false.
    - A set with an added identifier is evaluated (com.apple.screensharing.agent starts): true; a set with it removed again: true.
    - A set that differs only in order of insertion is the same set: false.
    - After reset() the next set is evaluated again, even when it equals the last one.
    New file WT/Tests/HolzBarMacOS27CoreTests/AgentLaunches27Tests.swift (header block like the other test files; import Foundation, Testing, @testable import HolzBarMacOS27Core), suite "AgentLaunches27":
    - isStandalone: "/Applications/Rectangle.app" .accessory -> true; "/System/Library/CoreServices/SSMenuAgent.app" .accessory -> true; "/Applications/OneDrive.app" .prohibited -> true (policy never excludes).
    - isStandalone: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc" -> false; "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/1.0/Helpers/Brave Browser Helper (Renderer).app" .accessory -> false; "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app" .accessory -> false; "/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle" -> false; nil path -> false.
    - isStandalone: a nested .regular app ("/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app", .regular) -> true (X1).
    - reaction, unchanged set (previous == instances' IDs, a second WebKit instance added): graces empty, updatesConcealment false, running equals previous.
    - reaction, only a helper added ("com.apple.WebKit.GPU" with its .xpc path): updatesConcealment false.
    - reaction, an unknown standalone app added ("com.knollsoft.Rectangle" at /Applications/Rectangle.app): updatesConcealment true, graces empty.
    - reaction, a known app added that the layout keeps visible (in known only): updatesConcealment true, graces empty.
    - reaction, a known app added whose saved section is hidden or always hidden (in concealedInLayout): updatesConcealment true, graces == [that ID].
    - reaction, a known app added that is itself a nested helper bundle: updatesConcealment true (known wins over nesting).
    - reaction, a known app removed: updatesConcealment true, graces empty; an unknown standalone app removed: false; a helper removed: false.
    - reaction, a login batch (two known concealed IDs, one unknown standalone, three helpers added at once): graces == the two IDs sorted, updatesConcealment true.
    - reaction, an ID with one nested and one top-level instance counts as standalone ("some instance").
    - reaction.running is exactly the set of the instances' bundle IDs.
  </behavior>
  <action>
    Work in WT only. Write the tests of the behavior block first, then the code; the Core types are new, so the tests compile only together with them (as in the sibling part). Per D-01 throughout; no audit IDs in code or comments; English; match the files' comment style (measured facts, why), density and SwiftLint rules.

    A. Zen trigger in Core (D-01c, D-01b), WT/holzBar/Core/PresentationSignals.swift:
    A1. Inside nonisolated enum PresentationSignals add nonisolated struct Trigger (Equatable, Sendable) exactly as in "Interfaces": needsEvaluation(running:) returns true and records running when evaluated is nil or differs from running, otherwise returns false; reset() sets evaluated to nil. Doc comment: NSWorkspace reports every process that starts or quits, helpers included, and most of those changes leave the set of bundle identifiers as it was (measured 2026-10-05: 115 processes shared 90 identifiers, and 7 of 9 changes in five idle minutes left the set unchanged), so only a change of the set is evaluated.
    A2. Rewrite the type's doc comment so the screen sharing agent is read among the running applications "when the running applications change" (replace the launch-or-quit wording), keeping the rest (no permission, no polling, Thaw comparison).

    B. PresentationMonitor (D-01a, D-01b, D-01i), WT/holzBar/MenuBar/PresentationMonitor.swift:
    B1. Replace the array of notification tasks with private var screenParametersTask: Task<Void, Never>? (the existing screen-parameters loop, unchanged) and private var runningApplicationsObservation: NSKeyValueObservation?, plus private var trigger = PresentationSignals.Trigger(). Doc comment each.
    B2. start(): guard screenParametersTask == nil; create the screen-parameters task as today; create runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) with a handler that (X2) collects the bundle identifiers of change.newValue and change.oldValue, returns when none of them has one, and otherwise hops with Task { @MainActor in self?.runningApplicationsDidChange() }; the handler reads only those properties, keeps no reference to the NSRunningApplication objects, takes no lock and never waits (D-01i). Then call evaluate() as today. The two NSWorkspace launch and terminate notification tasks are deleted.
    B3. stop(): cancel and nil screenParametersTask; invalidate and nil runningApplicationsObservation; trigger.reset(); then isPresenting = false and setAutomaticZenMode(false) as today. The observation therefore exists only while the setting is on.
    B4. runningApplicationsDidChange(): read the running bundle-ID set; guard trigger.needsEvaluation(running:) else return; then evaluate. Restructure evaluate() so the screen-parameters path and start() also record the set in trigger (for example evaluate(running:) called by a parameterless evaluate() that reads the set and calls trigger.needsEvaluation(running:) discarding the result), keeping the existing presenting logic and log lines unchanged.
    B5. Rewrite the class doc comment (lines 9-17) to say holzBar looks for the screen sharing agent among the running applications when they change, observed through NSWorkspace's runningApplications (launch and quit notifications reach regular apps only, and the agent is a background agent), and still that nothing runs while the setting is off.

    C. Pure diff and classification (D-01e, D-01h), new file WT/holzBar/MenuBar/MacOS27/Core/AgentLaunches27.swift (file header per SwiftLint, import Foundation):
    C1. Implement the "Interfaces" signatures. nestingMarkers = [".app/", ".framework/", ".xpc/", ".appex/", ".bundle/"] (multi-line literal with trailing comma per SwiftLint).
    C2. isStandalone(bundlePath:policy:): true when policy is .regular (X1); otherwise false for a nil path; otherwise true exactly when the path's extension, compared case-insensitively, is "app" and the parent directory path with a trailing "/" contains none of nestingMarkers (case-insensitive). Doc comment cites the measurement: a top-level test kept the 41 identifiers of real menu bar apps and system agents and dropped 14 nested helper apps and 10 non-.app identifiers; activationPolicy cannot tell helpers apart (WebKit .xpc services and Electron and browser helpers run .accessory with LSUIElement=1, and OneDrive declares LSBackgroundOnly=1 yet runs .accessory).
    C3. reaction(previous:instances:known:concealedInLayout:): running = the instances' bundle IDs; added = running minus previous; removed = previous minus running; an added ID is relevant when it is in known or when some instance with that ID isStandalone; graces = (added intersected with concealedInLayout) sorted; updatesConcealment = any relevant added ID, or any removed ID in known. Doc comments explain why removed unknown apps are ignored (they never had an item holzBar placed) and why graces need the saved section (Ice#1007: concealed before its status item exists, the item is squashed to 3 points).

    D. Concealer27 (D-01d, D-01f, D-01g, D-01i, coordinated with F-28), WT/holzBar/MenuBar/MacOS27/Concealer27.swift:
    D1. Properties: @ObservationIgnored private var runningApplicationsObservation: NSKeyValueObservation? and @ObservationIgnored private var runningBundleIDs = Set<String>() (the snapshot), each with a doc comment. Update the comment of observerTasks (only the screen-parameters task remains) and of notchConcealed ("cleared when the active display changes, an application that may own items launches or quits, or what the sections conceal changes").
    D2. performSetup: after the availability guard, set runningBundleIDs from NSWorkspace.shared.runningApplications, then create the KVO exactly as in B2 (options [.old, .new], same skip rule, Task { @MainActor in self?.runningApplicationsDidChange() }). Delete the two NSWorkspace launch and terminate notification tasks; keep the screen-parameters task and everything else.
    D3. Add private func runningApplicationsDidChange(): read NSWorkspace.shared.runningApplications once; compute the bundle-ID set; if it equals runningBundleIDs return at once (no Defaults read, no update: the 7-of-9 case). Otherwise map the applications that have a bundle identifier to AgentLaunches27.Instance (bundleURL?.path(percentEncoded: false), activationPolicy mapped to Policy with @unknown default -> .accessory), compute known = Set(savedLayout.keys) union the strings in Defaults .knownApplications27 (read as in placeNewApplications), concealedInLayout = the savedLayout keys whose section is not .visible, call AgentLaunches27.reaction(previous: runningBundleIDs, …), store reaction.running into runningBundleIDs, and when reaction.updatesConcealment call applicationsDidChange(graces: reaction.graces). Log at debug only counts (privacy: .public), never bundle IDs.
    D4. Replace applicationDidLaunch(bundleID:) with the batch form private func applicationsDidChange(graces candidates: [String]): notchConcealed.removeAll() (comment: the bar is laid out anew, so the notch is worked out again); let now = ContinuousClock.now; begun = candidates filtered by launchGrace.begin($0, isConcealed: true, at: now); when begun is empty call update() once and return; otherwise log the existing debug line (pluralised wording is fine, no IDs), call showTemporarily(bundleIDs: begun) (which runs the one update()), and start one bounded wait per callback: a Task that waits LaunchGrace27.timeout and then calls endGraces(launchGrace.expired(at: .now)), as the old single-ID code did. Keep the Ice#1007 doc comment, rewritten for a batch. Exactly one update() per relevant callback; no debounce and no delay before it (D-01g).
    D5. Do not touch MenuBarItemManager, placeNewApplications, applyChanges or the F-28 notchCoverBasis logic.
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm --filter 'PresentationSignals|AgentLaunches27'</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks mac27-agents-f17 | tail -1 | grep -q 'ERRORS: 0  EXIT: 0'</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && ! grep -q 'didLaunchApplicationNotification' holzBar/MenuBar/PresentationMonitor.swift holzBar/MenuBar/MacOS27/Concealer27.swift && ! grep -q 'didTerminateApplicationNotification' holzBar/MenuBar/PresentationMonitor.swift holzBar/MenuBar/MacOS27/Concealer27.swift</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && grep -q 'observe(\\.runningApplications, options: \[\.old, \.new\])' holzBar/MenuBar/PresentationMonitor.swift && grep -q 'observe(\\.runningApplications, options: \[\.old, \.new\])' holzBar/MenuBar/MacOS27/Concealer27.swift && grep -q 'AgentLaunches27.reaction' holzBar/MenuBar/MacOS27/Concealer27.swift && grep -q 'needsEvaluation(running:' holzBar/MenuBar/PresentationMonitor.swift && grep -q 'when the running applications change' holzBar/Core/PresentationSignals.swift && grep -q 'running applications' holzBar/MenuBar/PresentationMonitor.swift</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && git diff --quiet -- holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift</automated>
    <human-check>Maintainer, macOS 27 session: manual tests M1-M5 below.</human-check>
  </verify>
  <acceptance_criteria>
    - Every test of the behavior block exists and passes; the full swift test run passes (gate G1).
    - appcheck.sh reports ERRORS: 0 for the whole app module.
    - Neither PresentationMonitor.swift nor Concealer27.swift uses the NSWorkspace launch or terminate notifications any more; both observe runningApplications with options [.old, .new].
    - PresentationMonitor's observation is created in start() and invalidated in stop().
    - Concealer27 returns before reading Defaults when the bundle-ID set is unchanged, and calls update() exactly once per relevant callback (either directly or through showTemporarily(bundleIDs:)).
    - MenuBarItemManager.swift is unchanged.
  </acceptance_criteria>
  <done>F-17 committed atomically after the gate set passes (commit message in "Commits"). Screen Sharing start and end re-evaluate automatic Zen; a later Visible agent is allowed in the next apply and a concealed-section agent gets its launch grace.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2 (F-08, part 1): capture state from CoreAudio and CoreMediaIO, the badge decision, the new setting and the icon check</name>
  <files>holzBar/Core/CaptureIndicator.swift, Tests/HolzBarCoreTests/CaptureIndicatorTests.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift, holzBar/Core/Defaults.swift, holzBar/Settings/Models/GeneralSettings.swift, holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift, holzBar/Main/AppState.swift, holzBar/MenuBar/MacOS27/Concealer27.swift</files>
  <read_first>
    - /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/indicators-2.md (D-02, whole file)
    - WT/.planning/audit/FULL-AUDIT-2026-10-05.md lines 462-492 (F-08)
    - WT/holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift lines 52-65
    - WT/holzBar/MenuBar/Appearance/WallpaperChangeMonitor.swift lines 24-55
    - WT/holzBar/MenuBar/PresentationMonitor.swift (as changed in Task 1; the setting-follows pattern)
    - WT/holzBar/Main/AppState.swift lines 78-176
    - WT/holzBar/Core/Defaults.swift lines 144-239 and 248-325; WT/Tests/HolzBarCoreTests/SettingsSchemaTests.swift lines 155-176
    - WT/holzBar/Settings/Models/GeneralSettings.swift lines 1-90 and 155-212
    - WT/holzBar/MenuBar/MacOS27/Concealer27.swift: checkOwnIcon() (about lines 381-410 before Task 1's edits; find it by name) and timeUntilSettled()
    - /Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardware.h lines 560-640 and 1925-1980; .../CoreMediaIO.framework/Headers/CMIOHardwareObject.h lines 410-455
  </read_first>
  <behavior>
    New file WT/Tests/HolzBarCoreTests/CaptureIndicatorTests.swift (import Testing, @testable import HolzBarCore), suite "CaptureIndicator":
    - badge is nil when the setting is off, whatever is in use.
    - badge is nil when nothing is concealed (Control Centre draws its own indicator then), whatever is in use.
    - badge is nil when neither the microphone nor a camera is in use.
    - microphone only -> .microphone, showsCamera false; camera only -> .camera, showsCamera true; both -> .cameraAndMicrophone, showsCamera true.
    - showsHolzBarIcon: icon enabled -> true with or without a badge; icon disabled with a badge -> true; icon disabled without -> false.
    Suite "CaptureActivity" (mutate outside #expect):
    - A new activity uses nothing.
    - setInput(of: 7, pid: other, isRunning: true) -> isMicrophoneInUse; then isRunning false -> not in use.
    - holzBar's own process (pid == ownPID) is never counted, even with input running.
    - Two recording processes, one stops -> still in use; keepProcesses without the other one -> not in use (a process that quit while recording).
    - setCamera(3, isRunning: true) -> isCameraInUse; keepCameras([]) -> not in use (a camera unplugged while running).
    - Equal activities compare equal (the observation de-duplicates on it).
    SettingsSchemaTests: add to "Stored key names never change" that holzBarIconShowsCaptureDot's raw value is "HolzBarIconShowsCaptureDot", and to "Settings keep their kinds" that its kind is .bool.
  </behavior>
  <action>
    Work in WT only. Tests first, then code. Per D-02 throughout; no audit IDs in code or comments; English.

    A. Core (D-02h), new file WT/holzBar/Core/CaptureIndicator.swift (SwiftLint header, import Foundation, Foundation only: the views translate the texts):
    A1. Implement CaptureBadge, CaptureActivity and CaptureIndicator exactly as in "Interfaces". badge(isEnabled:isConcealing:isMicrophoneInUse:isCameraInUse:) returns nil unless isEnabled and isConcealing and something is in use; camera and microphone -> .cameraAndMicrophone, camera -> .camera, microphone -> .microphone. showsHolzBarIcon(isIconEnabled:badge:) = isIconEnabled or badge != nil. CaptureActivity.setInput ignores pid == ownPID.
    A2. Doc comments (file style, measured facts): on macOS 27 Control Centre's capture indicator is not drawn while any MenuBarAgent assessment assertion is live, whatever the allowlist holds (measured on macOS 27.0, MenuBarAssessmentAssertion27), and concealing is holzBar's normal state; holzBar marks its own icon instead, in Control Centre's colours (green for a camera, orange for the microphone only), and never while nothing is concealed, because Control Centre draws its indicator then; screen recording by other apps has no public signal and is not covered.

    B. Setting (D-02i, model part):
    B1. WT/holzBar/Core/Defaults.swift: add case holzBarIconShowsCaptureDot = "HolzBarIconShowsCaptureDot" to the General Settings group of Defaults.Key, with a doc comment (macOS 27: a dot on holzBar's icon while another app uses the microphone or a camera), and add it to the .bool group of settingsKind. Rename nothing.
    B2. WT/holzBar/Settings/Models/GeneralSettings.swift: add var holzBarIconShowsCaptureDot = true with a didSet that stores it under .holzBarIconShowsCaptureDot (same shape as showHolzBarIcon), a doc comment, and Defaults.ifPresent(key: .holzBarIconShowsCaptureDot, assign: &holzBarIconShowsCaptureDot) in loadInitialState().
    B3. SettingsSchemaTests: the two expectations of the behavior block.

    C. Monitor (D-02a, D-02b, D-02c, D-02d), new file WT/holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift (SwiftLint header; import CoreAudio, CoreMediaIO, Foundation, Observation, OSLog explicitly):
    C1. @available(macOS 27.0, *) @MainActor @Observable final class CaptureActivityMonitor27. Tracked: private(set) var activity = CaptureActivity(ownPID: ProcessInfo.processInfo.processIdentifier). @ObservationIgnored: weak appState, the setting observer (ObservationLoop), the badge observer (ObservationLoop), the last badge, the icon-check task, isRunning, the system-object listener blocks (process list, service restarted, CoreMediaIO device list), [AudioObjectID: (pid: pid_t, listener: AudioObjectPropertyListenerBlock)] for process objects with a listener, a Set<AudioObjectID> of process objects that are holzBar's own (no listener), [CMIOObjectID: CMIOObjectPropertyListenerBlock] for cameras, and Logger(category: "CaptureActivityMonitor27"). Store every listener block in a property of the block type and pass that same value to the matching Remove call (the Remove call needs the same block).
    C2. Class doc comment: why (the capture indicator is gone while concealing, measured on macOS 27.0), how (CoreAudio process objects for the microphone, because the device-wide running-somewhere property of an audio device also turns on when a headset only plays sound; CoreMediaIO devices for cameras), cost and privacy (listeners only, nothing polls, no audio or video is opened, no permission or entitlement: measured on macOS 26.7.1 on 2026-10-05, coreaudiod only preflights the Microphone, Screen Recording and audio capture status of a new client, with no prompt, and CoreMediaIO reads cause no TCC query), and that holzBar's own process appears among the process objects as soon as it reads them and is ignored. Nothing runs while the setting is off.
    C3. performSetup(with:): store appState; observe appState.settings.general.holzBarIconShowsCaptureDot with ObservationLoop.observe (as PresentationMonitor follows its setting) and call setRunning(isOn && MenuBarAssessmentAssertion27.isAvailable); observe appState.captureBadge27 with the Equatable ObservationLoop.observe and, when it changes from nil to a badge, cancel any running icon check and start Task { await appState.concealer27.checkOwnIconForCapture() } (section E of this task). Call setRunning once with the current value.
    C4. start(): guard !isRunning. Register on AudioObjectID(kAudioObjectSystemObject), with DispatchQueue.main, a listener for kAudioHardwarePropertyProcessObjectList (handler: MainActor.assumeIsolated { self?.processesChanged() }) and one for kAudioHardwarePropertyServiceRestarted (handler: stop() then start(), X10). Register on CMIOObjectID(kCMIOObjectSystemObject), with DispatchQueue.main, a listener for kCMIOHardwarePropertyDevices (handler: camerasChanged()). Use global scope and the Main element constants for both frameworks (the Master spellings are deprecated). Then call processesChanged() and camerasChanged() once. Log a notice "Watching microphone and camera use" with nothing interpolated.
    C5. processesChanged(): read the process object list (size, then data). For each object no longer listed: remove its listener (ignore the status; the object is gone) and forget it. For each new object: read kAudioProcessPropertyPID; when it equals holzBar's own PID, remember it as own and add no listener; otherwise add a kAudioProcessPropertyIsRunningInput listener on DispatchQueue.main whose handler re-reads that one object's value and calls activity.setInput(of:pid:isRunning:), and read the value once now. Finally activity.keepProcesses(Set(list)). On a failed read keep the previous state and log the OSStatus at debug (privacy: .public; a status code is not personal data).
    C6. camerasChanged(): the same for kCMIOHardwarePropertyDevices and kCMIODevicePropertyDeviceIsRunningSomewhere (activity.setCamera, activity.keepCameras). CoreMediaIO's integer constants need the CMIOObjectPropertySelector/Scope/Element and CMIOObjectID conversions.
    C7. stop(): remove every listener it added (system objects, processes, cameras) with the same queue and blocks, clear the tables, isRunning = false, activity = CaptureActivity(ownPID:), log a notice "Stopped watching microphone and camera use". Logs never contain bundle identifiers, PIDs or device names; activity changes may be logged at debug as two Booleans with privacy: .public.
    C8. Small private static read helpers (object ID array, UInt32, pid_t) keep the C calls in one place; no force unwrapping. Nothing here may poll or schedule repeated work; every read happens in start(), stop() or a listener callback.

    D. AppState (D-02a, D-02h), WT/holzBar/Main/AppState.swift:
    D1. Add the storage and the @available(macOS 27.0, *) computed captureActivityMonitor27, following the concealer27 pattern exactly (typed-loosely @ObservationIgnored storage, doc comments).
    D2. Add @available(macOS 27.0, *) var captureBadge27: CaptureBadge? returning CaptureIndicator.badge(isEnabled: settings.general.holzBarIconShowsCaptureDot, isConcealing: concealer27.isConcealing, isMicrophoneInUse: captureActivityMonitor27.activity.isMicrophoneInUse, isCameraInUse: captureActivityMonitor27.activity.isCameraInUse). It reads only observed state and has no early return, so an observation started before the monitor's setup still tracks every input. Doc comment: what holzBar's icon shows while another app records on macOS 27.
    D3. In the setup task, right after presentationMonitor.performSetup(with: self), add if #available(macOS 27.0, *) { captureActivityMonitor27.performSetup(with: self) } with a one-line comment.

    E. Concealer27, the icon check (D-02g, X8), WT/holzBar/MenuBar/MacOS27/Concealer27.swift (as committed with F-17):
    E1. In checkOwnIcon()'s guard, replace the plain appState.settings.general.showHolzBarIcon condition with CaptureIndicator.showsHolzBarIcon(isIconEnabled: appState.settings.general.showHolzBarIcon, badge: appState.captureBadge27), so an icon shown only for a capture is put back too.
    E2. Add func checkOwnIconForCapture() async with a doc comment: holzBar's icon carries the capture dot while concealing, checkOwnIcon() looks for the icon only after a concealment change, and a capture can start long after one (jordanbaird/Ice#1001). Body: return unless appState exists and isConcealing; await waitForPendingApplies(); wait out timeUntilSettled() if it returns a duration; read MenuBarItemProvider27.items() and return if it contains an item tagged .visibleControlItem; wait settleAfterChange; read once more and return if found; return if the task was cancelled or nothing is concealed any more; otherwise log the notice "holzBar's icon was missing when a capture started, putting it back", set didReinsertIcon = true and call appState.menuBarManager.controlItem(withName: .visible)?.reinsert(). It reinserts at most once per call and never loops.
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm --filter 'CaptureIndicator|CaptureActivity|SettingsSchema'</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks mac27-agents-f08a | tail -1 | grep -q 'ERRORS: 0  EXIT: 0'</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && F=holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift && grep -q 'kAudioHardwarePropertyProcessObjectList' $F && grep -q 'kAudioProcessPropertyIsRunningInput' $F && grep -q 'kAudioProcessPropertyPID' $F && grep -q 'kAudioHardwarePropertyServiceRestarted' $F && grep -q 'kCMIOHardwarePropertyDevices' $F && grep -q 'kCMIODevicePropertyDeviceIsRunningSomewhere' $F && grep -q 'AudioObjectRemovePropertyListenerBlock' $F && grep -q 'CMIOObjectRemovePropertyListenerBlock' $F && ! grep -nE 'Timer|asyncAfter|Task\.sleep|kAudioDevicePropertyDeviceIsRunningSomewhere|ElementMaster' $F</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && ! grep -q 'NSMicrophoneUsageDescription' holzBar/Resources/Info.plist && ! grep -q 'NSCameraUsageDescription' holzBar/Resources/Info.plist && ! git grep -q 'device.audio-input' -- '*.entitlements' && ! git grep -q 'device.camera' -- '*.entitlements'</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && grep -q 'func checkOwnIconForCapture' holzBar/MenuBar/MacOS27/Concealer27.swift && grep -q 'CaptureIndicator.showsHolzBarIcon' holzBar/MenuBar/MacOS27/Concealer27.swift && grep -q 'checkOwnIconForCapture()' holzBar/MenuBar/MacOS27/CaptureActivityMonitor27.swift</automated>
  </verify>
  <acceptance_criteria>
    - Every test of the behavior block exists and passes.
    - appcheck.sh reports ERRORS: 0 for the whole app module.
    - Concealer27 has checkOwnIconForCapture(), and checkOwnIcon() also keeps an icon that is shown only for a capture.
    - The monitor uses only listener callbacks (no polling construct appears in it), the Main element constants, and the process-object signal, not the device-wide audio signal.
    - No usage description or capture entitlement was added; the stored key name HolzBarIconShowsCaptureDot and its .bool kind are pinned by tests.
  </acceptance_criteria>
  <done>The capture state reaches AppState.captureBadge27 on macOS 27 while the setting is on; nothing is displayed yet and nothing is committed (F-08 is committed atomically after Task 3).</done>
</task>

<task type="auto">
  <name>Task 3 (F-08, part 2): the dot on holzBar's icon, the setting in General, strings; gates, commits, summary</name>
  <files>holzBar/MenuBar/ControlItem/CaptureDotView.swift, holzBar/MenuBar/ControlItem/ControlItem.swift, holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift, holzBar/Resources/Localizable.xcstrings, .planning/audit/remediation/mac27-agents-dot-SUMMARY.md</files>
  <read_first>
    - WT/holzBar/MenuBar/ControlItem/ControlItem.swift lines 136-268, 293-370, 370-462, 517-525
    - WT/holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift lines 35-82 and 367-394
    - WT/.github/scripts/strings-check.py lines 39-60
    - WT/.planning/audit/remediation/mac27-clicks-SUMMARY.md (format of a part summary; read only)
  </read_first>
  <action>
    Work in WT only. Per D-02 throughout; no audit IDs in code or comments; English; SwiftLint rules.

    A. CaptureDotView (D-02e, X5), new file WT/holzBar/MenuBar/ControlItem/CaptureDotView.swift (SwiftLint header, import Cocoa):
    A1. final class CaptureDotView: NSView with var color: NSColor = .systemOrange whose didSet sets needsDisplay = true; init() makes a 6 by 6 point view with wantsLayer = true and setAccessibilityElement(false); required init?(coder:) marked @available(*, unavailable) per SwiftLint; override wantsUpdateLayer to true; updateLayer() sets layer?.backgroundColor = color.cgColor and cornerRadius = bounds.width / 2 (the system colour resolves for the current appearance there); override hitTest(_:) to return nil so a click on the dot reaches holzBar's button. Doc comment: the dot holzBar draws over its own icon while another app records on macOS 27, a subview so the icon keeps its template rendering and the dot its colour.

    B. ControlItem (D-02e, D-02f), WT/holzBar/MenuBar/ControlItem/ControlItem.swift:
    B1. @ObservationIgnored private var captureDot: CaptureDotView? with a doc comment, and a private computed captureBadge: CaptureBadge? that is nil unless identifier == .visible and macOS 27 is available, where it returns appState?.captureBadge27.
    B2. configureObservers(): inside the identifier == .visible block, on macOS 27 (if #available(macOS 27.0, *)), append ObservationLoop.observe { appState.captureBadge27 } onChange: { [weak self] _ in self?.updateMenuBarPresence(); self?.updateStatusItem() }.
    B3. updateMenuBarPresence(), case .visible: add the item when CaptureIndicator.showsHolzBarIcon(isIconEnabled: appState.settings.general.showHolzBarIcon, badge: captureBadge), remove it otherwise (D-02f). The other cases stay.
    B4. updateStatusItem(), case .visible: after button.image = image call updateCaptureDot(on: button). New private func updateCaptureDot(on button: NSStatusBarButton): without a badge, remove captureDot from its superview, set it to nil, and reset button.toolTip to nil and the accessibility label with button.setAccessibilityLabel(nil); with a badge, create or reuse the dot, add it to the button if needed, set its color to .systemGreen when badge.showsCamera and .systemOrange otherwise, position it (B5), and set the same localized text as tooltip and accessibility label: String(localized: "Microphone in use"), String(localized: "Camera in use") or String(localized: "Camera and microphone in use") for .microphone, .camera and .cameraAndMicrophone. The status item's length never changes for the dot (no reflow on macOS 27).
    B5. private func positionCaptureDot(): when captureDot and the button exist, place the 6 point dot at the top-trailing corner of the drawn image, from button.cell?.imageRect(forBounds: button.bounds) (fall back to the button's bounds), overlapping the image by 1 point, honouring button.isFlipped. Call it from updateCaptureDot and from the existing window-frame observer in windowDidChange after updateOnScreenFrame(), so a change of the bar's height moves the dot with the icon.
    B6. Doc comments in the file's style on the new members: why the dot exists (Control Centre's capture indicator is not drawn while holzBar conceals on macOS 27) and that it never shows while nothing is concealed.

    C. (The icon check in Concealer27 was done in Task 2, section E.)

    D. Settings (D-02i, D-02j), WT/holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift:
    D1. Pass the settings in: PrivacyIndicatorNote(settings: settings) in body; PrivacyIndicatorNote gets @Bindable var settings: GeneralSettings.
    D2. In PrivacyIndicatorNote's HolzBarSection, keep the label and replace the note's Text with the new note text (K3 below); then, as the section's second row, add Toggle("Show a dot on the holzBar icon while the microphone or camera is in use", isOn: $settings.holzBarIconShowsCaptureDot) with .annotation("Orange for the microphone, green for the camera. Uses no permission; holzBar cannot tell when an app records the screen."), styled like the other toggles of the pane.
    D3. Update the struct's doc comment: holzBar cannot keep Control Centre's indicator, so it says so and offers the dot on its own icon (microphone and camera only).

    E. Strings (D-02j), WT/holzBar/Resources/Localizable.xcstrings, edited with a short Python script in SP (not in WT) that loads the JSON, changes "strings", and writes it back with json.dumps(data, indent=2, ensure_ascii=False, separators=(',', ' : '), sort_keys=True) plus a trailing newline. Each new entry has the shape of the existing ones: {"localizations": {"de"|"fr"|"it"|"rm": {"stringUnit": {"state": "translated", "value": …}}}}. Delete the entry of the note text that K3 replaces (its English key is the current text of the note's Text at GeneralSettingsPane.swift line 385). Add exactly these six entries, values verbatim (German in Swiss spelling, no ß):
    K1 key "Show a dot on the holzBar icon while the microphone or camera is in use": de "Punkt im holzBar-Symbol zeigen, solange Mikrofon oder Kamera verwendet werden"; fr "Afficher un point sur l'icône de holzBar pendant l'utilisation du micro ou de la caméra"; it "Mostra un punto sull'icona di holzBar mentre il microfono o la fotocamera sono in uso"; rm "Mussar in punct sin il simbol da holzBar, uschè ditg ch'il microfon u la camera è en diever".
    K2 key "Orange for the microphone, green for the camera. Uses no permission; holzBar cannot tell when an app records the screen.": de "Orange für das Mikrofon, grün für die Kamera. Braucht keine Berechtigung; dass eine App den Bildschirm aufnimmt, kann holzBar nicht erkennen."; fr "Orange pour le micro, vert pour la caméra. Aucune autorisation requise ; holzBar ne peut pas savoir quand une app enregistre l'écran."; it "Arancione per il microfono, verde per la fotocamera. Non serve alcuna autorizzazione; holzBar non può sapere quando un'app registra lo schermo."; rm "Oransch per il microfon, verd per la camera. Na dovra nagina permissiun; holzBar na po betg savair, cura ch'ina app registrescha il monitur."
    K3 key "On macOS 27, while holzBar hides menu bar items, Control Centre does not show its indicator for the camera, the microphone or screen recording. It comes back while holzBar hides no item. holzBar can mark its own icon instead, for the microphone and the camera but not for screen recording. The small green dot beside the clock still appears while the camera is on.": de "Unter macOS 27 zeigt das Kontrollzentrum seine Anzeige für Kamera, Mikrofon und Bildschirmaufnahme nicht, solange holzBar Menüleistenelemente ausblendet. Sie erscheint wieder, sobald holzBar kein Element ausblendet. holzBar kann stattdessen sein eigenes Symbol markieren, für Mikrofon und Kamera, aber nicht für die Bildschirmaufnahme. Der kleine grüne Punkt neben der Uhr erscheint weiterhin, solange die Kamera an ist."; fr "Sous macOS 27, tant que holzBar masque des éléments de la barre des menus, le Centre de contrôle n'affiche pas son indicateur pour la caméra, le micro ou l'enregistrement de l'écran. Il réapparaît dès que holzBar ne masque plus aucun élément. holzBar peut marquer sa propre icône à la place, pour le micro et la caméra, mais pas pour l'enregistrement de l'écran. Le petit point vert à côté de l'horloge apparaît toujours lorsque la caméra est active."; it "Su macOS 27, finché holzBar nasconde elementi della barra dei menu, il Centro di Controllo non mostra il suo indicatore per fotocamera, microfono e registrazione schermo. Riappare quando holzBar non nasconde alcun elemento. holzBar può invece segnalarlo sulla propria icona, per microfono e fotocamera ma non per la registrazione schermo. Il piccolo punto verde accanto all'orologio appare comunque quando la fotocamera è attiva."; rm "Sin macOS 27, uschè ditg che holzBar zuppenta elements da la trav da menu, na mussa il Center da controlla betg ses indicatur per la camera, il microfon u la Bildschirmaufnahme. El cumpara puspè, uschespert che holzBar na zuppenta nagin element. holzBar po marcar empè ses agen simbol, per il microfon e la camera, ma betg per la Bildschirmaufnahme. Il pitschen punct verd sper l'ura cumpara vinavant, uschè ditg che la camera è activa."
    K4 key "Microphone in use": de "Mikrofon wird verwendet"; fr "Micro en cours d'utilisation"; it "Microfono in uso"; rm "Microfon en diever".
    K5 key "Camera in use": de "Kamera wird verwendet"; fr "Caméra en cours d'utilisation"; it "Fotocamera in uso"; rm "Camera en diever".
    K6 key "Camera and microphone in use": de "Kamera und Mikrofon werden verwendet"; fr "Caméra et micro en cours d'utilisation"; it "Fotocamera e microfono in uso"; rm "Camera e microfon en diever".
    The English keys in code must match K1-K6 character for character (straight apostrophes in the translations as above, matching the catalog's existing style).

    F. Gates and commits. Run the gate set below after Task 1 (then commit F-17) and after this task (then commit F-08). Never push, never switch branches, never change git config, never launch, quit or relaunch holzBar, never run tccutil or defaults write.
    G1 full swift test: cd WT, then swift test with --scratch-path SP/mac27-clicks-swiftpm. If it fails only with "plugin for module 'TestingMacros' not found", run it once more (a known flake of the Command Line Tools on this host).
    G2 whole-app typecheck: zsh SP/appcheck.sh WT with label mac27-agents-f17 or mac27-agents-f08, last line "ERRORS: 0  EXIT: 0". It is the only local compile check of the app target (macOS 26.5 SDK, Swift 6, MainActor default isolation); CI's Xcode 27 build stays the final word (D-01j).
    G3 lint: cd WT, then TOOLCHAIN_DIR=/Library/Developer/CommandLineTools SP/swiftlint/swiftlint lint --strict --quiet, no output and exit 0.
    G4 python3 .github/scripts/privacy-check.py logs, python3 .github/scripts/privacy-check.py network, python3 .github/scripts/strings-check.py. After F-17 the catalogs hold 369 strings; after F-08, 374 (six added, one replaced).
    G5 former name: cd WT, then the negated git grep for the former app name pattern with the excludes from .github/workflows/build.yml (.planning, .claude, .github/cms-version.py) prints nothing.
    G6 git -C WT status --short lists only the files of the finding being committed (plus the summary for the F-08 commit, plus the untracked PLAN files, which are never added).
    Commit with git -C WT add (explicit paths, never -A) and git -C WT commit, using the messages in "Commits" verbatim.
    After the F-08 gates pass, write .planning/audit/remediation/mac27-agents-dot-SUMMARY.md in the sibling format. Frontmatter: chain mac27, part agents-dot, findings [F-17, F-08], decisions "agent-launches-1 - Bekannte + eigenständige Apps (Recommended); indicators-2 - Punkt im holzBar-Symbol (Recommended)", status complete. Then, per finding: Cause, Fix (files and functions), Tests, the discretion items X1-X12, the gates with their real output, risks R1-R14, the manual tests M1-M14, and the doc updates still needed. Include the summary in the F-08 commit. Leave this PLAN file untouched.
    If a gate fails and cannot be fixed within the decision: git -C WT restore and git -C WT clean only the paths of the uncommitted finding, report fix-failed with the failing gate output, and stop the part (an already committed F-17 stays).
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && swift test --scratch-path /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/mac27-clicks-swiftpm && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swiftlint/swiftlint lint --strict --quiet && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/strings-check.py && python3 .github/scripts/strings-check.py | tail -1 | grep -q '374 strings' && ! git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'</automated>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks mac27-agents-f08 | tail -1 | grep -q 'ERRORS: 0  EXIT: 0'</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && python3 -c "import json,sys; s=json.load(open('holzBar/Resources/Localizable.xcstrings'))['strings']; keys=['Show a dot on the holzBar icon while the microphone or camera is in use','Microphone in use','Camera in use','Camera and microphone in use']; sys.exit(0 if all(k in s for k in keys) and sum(k.startswith('On macOS 27, while holzBar hides menu bar items') for k in s)==1 and sum(k.startswith('Orange for the microphone, green for the camera.') for k in s)==1 else 1)"</automated>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks && grep -q 'CaptureDotView' holzBar/MenuBar/ControlItem/ControlItem.swift && grep -q 'setAccessibilityLabel' holzBar/MenuBar/ControlItem/ControlItem.swift && grep -q 'captureBadge27' holzBar/MenuBar/ControlItem/ControlItem.swift && grep -q 'CaptureIndicator.showsHolzBarIcon' holzBar/MenuBar/ControlItem/ControlItem.swift && grep -q 'positionCaptureDot' holzBar/MenuBar/ControlItem/ControlItem.swift && grep -q 'holzBarIconShowsCaptureDot' holzBar/Settings/SettingsPanes/GeneralSettingsPane.swift && python3 -c "import json; json.load(open('holzBar/Resources/Localizable.xcstrings'))"</automated>
    <automated>git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/mac27-clicks log --format=%s -2</automated>
    <human-check>The two subjects printed are the F-08 subject first, then the F-17 subject, exactly as in "Commits". The maintainer runs M1-M14 on macOS 27 (M5 also possible on macOS 26).</human-check>
  </verify>
  <done>Both commits exist on audit-manual/mac27-clicks with the required message shape, every gate passed on each, the summary is committed with F-08, nothing was pushed, and no README, docs, SECURITY.md, release notes or CLAUDE.md file changed.</done>
</task>

</tasks>

Task sizes: Tasks 1 and 2 touch more than five files each (6 and 8). This part has exactly one
plan file (this one), so it cannot be split into further plans. Each task instead ends at a point
where swift test and appcheck are green, and F-08 is committed only after Task 3.

## Commits (use verbatim; the subject dash is an em dash)

F-17 (after Task 1; files: PresentationSignals.swift, PresentationSignalsTests.swift,
PresentationMonitor.swift, AgentLaunches27.swift, AgentLaunches27Tests.swift, Concealer27.swift):

```
fix(menubar): resolve F-17 — notice menu bar agents that launch or quit, for Zen and macOS 27 concealment

The maintainer chose to react to apps holzBar knows and to top-level apps, not helpers.
NSWorkspace posts launch and quit notifications only for regular apps, so automatic Zen
missed the screen sharing agent and macOS 27 concealment kept later Visible agents hidden
and squashed. Both now observe runningApplications by KVO: Zen re-evaluates when the
bundle-ID set changes (PresentationSignals.Trigger), and the concealer answers added known
or top-level apps and removed known ones with one update, starting launch graces for
concealed sections (AgentLaunches27, tested).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

F-08 (after Task 3; files: CaptureIndicator.swift, CaptureIndicatorTests.swift,
SettingsSchemaTests.swift, Defaults.swift, GeneralSettings.swift, CaptureActivityMonitor27.swift,
AppState.swift, CaptureDotView.swift, ControlItem.swift, Concealer27.swift,
GeneralSettingsPane.swift, Localizable.xcstrings, mac27-agents-dot-SUMMARY.md):

```
fix(macos27): resolve F-08 — mark holzBar's icon while another app uses the microphone or camera

The maintainer chose a dot on holzBar's own icon over releasing concealment.
While an assessment assertion is live, macOS 27 draws no Control Centre capture
indicator, and concealing is holzBar's normal state. CaptureActivityMonitor27 follows
CoreAudio process input and CoreMediaIO cameras with listeners (no polling, no
permission), and the icon shows an orange or green dot while holzBar conceals and
another app records (CaptureIndicator, tested). A new General setting, on by default,
turns it off; screen recording cannot be detected and the note says so.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## How each failure scenario is closed

**F-17, scenario 1 (Zen and Screen Sharing; macOS 26 and 27):**
- Someone connects with Screen Sharing and launchd starts `com.apple.screensharing.agent`.
  NSWorkspace adds it to `runningApplications`; for LSUIElement agents that is the only signal,
  as the probe showed. The KVO handler hops to the main actor.
- The bundle-ID set changed, so `Trigger.needsEvaluation` is true, `evaluate()` finds the agent,
  and `setAutomaticZenMode(true)` turns Zen on. Hover, scroll, reveal rules and change reveal are
  refused from then on.
- When the session ends and the agent quits, the set changes again and Zen turns off. No unrelated
  app launch is needed any more in either direction.
- Helper restarts that leave the set unchanged do not evaluate. The observation exists only while
  the setting is on.

**F-17, scenario 2 (macOS 27 Visible agent launched later):**
- A Visible LSUIElement agent (a login item, or a relaunch) appears in `runningApplications`.
- `AgentLaunches27.reaction` classifies its ID as relevant: holzBar knows it from the saved layout
  or `.knownApplications27`, or its bundle is a top-level `.app`.
- `notchConcealed` is cleared and `update()` runs once, with no debounce. The allowlist (running
  minus concealed) now contains the agent, so MenuBarAgent draws it at full width; the update lands
  before the agent's status item normally exists.
- An agent whose saved section is Hidden or Always Hidden first gets a launch grace (shown until
  its item appears, at most 10 s), so it is not squashed to 3 pt (Ice#1007).
- WebKit, browser and Electron helpers do not cause a re-layout, so the bar does not twitch on
  every Safari tab or screenshot.

**F-08 (macOS 27):**
- A background app or a browser tab starts recording from the microphone while holzBar conceals
  items. Its CoreAudio process object reports `IsRunningInput = 1`, and the listener updates
  `activity`.
- `captureBadge27` becomes `.microphone`: the setting is on by default and `isConcealing` is true.
- ControlItem's observer shows the icon (even with "Show holzBar icon" off) and draws an orange
  dot. VoiceOver and the tooltip say "Microphone in use".
- `checkOwnIconForCapture()` puts the icon back if MenuBarAgent had dropped it.
- A camera gives a green dot.
- When the capture stops, the dot goes, and an icon that was shown only for the capture goes too.
- When holzBar conceals nothing, Control Centre draws its own indicator and holzBar shows no dot.
- Screen recording by another process has no public signal and stays uncovered; Settings says
  so. Nothing is revealed, so Zen and screen shares behave as before (D-02l).

## Risks (macOS 26 and 27)

- **R1 (27):** whether MenuBarAgent mirrors a subview of holzBar's status button into the bar is
  not measured. If the dot does not show in M6, the fallback is a non-template composite image
  for the time of the capture (icon drawn in the label colour plus the dot); that is a follow-up,
  not part of this plan.
- **R2 (27, F-17):** each relevant launch or quit rebuilds concealment: a new assertion, a
  re-layout of about 250 ms and four AX reads. At login, several callbacks in a row can each
  cause one update, because there is no debounce (D-01g). M2 and M4 measure it with the
  "Concealment apply: started" count.
- **R3 (27, F-17):** an agent whose status item comes from an embedded helper `.app` is caught only
  once holzBar has seen it on the bar (known). Before that it can stay hidden until another event,
  which is the trade-off the maintainer accepted.
- **R4 (26/27, F-17):** a quit and relaunch of the same ID that land in one main-actor turn leave
  the set unchanged, so nothing happens. A Visible agent stays allowed, because the allowlist is
  by bundle ID. A Hidden-section agent then gets no grace and may be squashed until revealed. This
  is rare (the old and new process normally lie hundreds of ms apart).
- **R5 (26/27, F-17):** if `ScreensharingAgent.bundle` never checks in with LaunchServices, it never
  appears in `runningApplications`, and Zen stays blind to it, as before. The decision context
  rates check-in "very likely"; M5 is optional.
- **R6 (27, F-08):** TCC was measured on macOS 26.7.1 only: preflight queries, no prompt, no camera
  query. A different macOS 27 behaviour would show in M11. A real (non-preflight) request would
  terminate holzBar, because it has no usage strings. In that case turn the setting off by default
  and report back.
- **R7 (27, F-08):** reading CoreAudio makes holzBar a HAL client. That costs some memory for
  CoreAudio and CoreMediaIO in the process, and the reader itself appears in the process list
  (filtered). There is no I/O and no idle CPU. M13 checks memory and CPU.
- **R8 (27, F-08):** the HAL and CoreMediaIO reads run on the main thread at events, a few small IPCs
  each. If coreaudiod stalls, holzBar's main thread waits with it, as any app touching CoreAudio
  on main does. If M13 or daily use shows hitches, move the reads to a serial queue.
- **R9 (27, F-08):** apps that keep the microphone open all the time (voice-activation tools,
  audio routing) keep the dot orange, as macOS's own indicator would.
- **R10 (27, F-08):** cameras count any CoreMediaIO device running anywhere: virtual cameras,
  Continuity Camera, an iPhone screen in QuickTime. Legacy unsigned DAL plug-ins do not load in a
  hardened process, so those devices are not seen.
- **R11 (27, F-08):** during a click-bridge suspension `isConcealing` is false for a moment, so the
  dot blinks off. Control Centre's indicator is drawn in that moment instead.
- **R12 (27, F-08):** while a capture runs, holzBar's button has the accessibility label "Microphone
  in use" and so on, instead of none. MenuBarItemProvider27 identifies holzBar's items by
  AXIdentifier, not by the description, so nothing else changes.
- **R13 (27, F-08):** with "Show holzBar icon" off, adding the icon during a capture is itself a
  bar change that MenuBarAgent may answer by dropping it (Ice#1001). `checkOwnIconForCapture()`
  reinserts once per capture start.
- **R14 (14/15/26):** all new app code is behind `@available(macOS 27.0, *)` or plain AppKit and
  KVO available since macOS 14. The Defaults key and the setting exist on every version but do
  nothing before 27. Local compile checks use the 26.5 SDK; only CI compiles against 27.

## Manual test on macOS 27 (maintainer, one session; M5 also on macOS 26)

Setup:
- Install with `Scripts/install.sh` and grant Accessibility. The Hidden section holds at least one
  app and is concealed; the setting "Show a dot on the holzBar icon…" is on (the default).
- Watch three log streams in Terminal:
  - `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "ConcealmentController27"'`
  - `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND (category == "Concealer27" OR category == "CaptureActivityMonitor27" OR category == "PresentationMonitor")'`
  - `log stream --info --predicate 'process == "tccd" AND eventMessage CONTAINS "com.holzcloud.holzBar"'`

F-17 (D-01j):
- **M1:** with Hidden concealed, quit and relaunch a Visible LSUIElement agent (Rectangle). It
  must come back at full width within about 1 s.
- **M2:** log out and back in with agents as login items. Every Visible agent must show.
- **M3:** relaunch an agent from the Hidden section. It must show briefly, then be concealed, and
  be full width when revealed.
- **M4:** open several Safari tabs, take a screenshot and use Touch ID. The bar must not twitch,
  and the count of "Concealment apply: started" must not rise for these actions.
- **M5 (optional, macOS 26 or 27):** turn on "Turn on Zen mode while the screen is mirrored or
  shared", then connect from another Mac with Screen Sharing. Zen must turn on within about 1 s
  ("Zen mode on" in the PresentationMonitor log). After disconnecting, it must turn off once the
  agent quits.

F-08 (D-02m):
- **M6:** record in Voice Memos with Hidden concealed. An orange dot must appear on holzBar's icon
  within about 1 s and go away when the recording stops.
- **M7:** Photo Booth or FaceTime: a green dot. With the microphone in use too: still green.
  VoiceOver (Cmd-F5) on holzBar's icon reads "Camera and microphone in use", and hovering shows
  the same tooltip.
- **M8:** click holzBar's icon during a recording to reveal hidden items. The dot must go away and
  Control Centre's orange indicator appear; hiding again brings the dot back.
- **M9:** with the holzBar Shelf on, the dot shows while recording.
- **M10:** in Settings → General, turn the new toggle off: no dot while recording. Turn it on
  again. Then turn "Show holzBar icon" off and start a recording: the icon appears with the dot.
  Stop the recording: the icon goes away and stays away.
- **M11 (permissions):** before the first recording test, watch the tccd stream. Expected:
  - at most `preflight=yes` lines from coreaudiod (Microphone, ScreenCapture, AudioCapture);
  - no prompt, no kTCCServiceCamera line, and holzBar keeps running;
  - holzBar is not listed in System Settings → Privacy & Security → Microphone or Camera.
- **M12:** with Zen mode on and the screen shared (any app), record. Hidden items stay hidden and
  the dot shows.
- **M13:** in Activity Monitor, holzBar's CPU stays at 0 % at idle with the setting on. Note its
  memory with the setting on and off.
- **M14 (opportunistic):** if holzBar's icon ever vanishes while concealing (Ice#1001), start a
  recording. The icon must come back with the dot ("putting it back" in the Concealer27 log).

## Doc updates needed (not by the executor; for the maintainer or a docs part)

- `docs/privacy-and-permissions.md:31` (warning box):
  - holzBar now marks its own icon, orange for the microphone and green for a camera, while it
    hides items on macOS 27. The setting is in Settings → General and on by default.
  - Screen recording by other apps is not covered: there is no public API for it.
  - Reading the state needs no permission; holzBar opens no audio or video.
  - Optionally add a row to the permissions table: "Microphone and camera state — read through
    CoreAudio and CoreMediaIO, no permission, nothing is recorded".
- `docs/features.md:84` (macOS 27 limitations): the same, shorter. Add a feature entry for the
  dot.
- `docs/features.md:129` alt text and `Resources/Screenshots/settings-spacing.png`: the General
  pane now shows the new toggle under the macOS 27 note. Retake the screenshot.
- `README.md:86` (macOS 27 note) and the README feature list: mention the dot. Add a row to the
  "holzBar vs. Ice and Thaw" comparison table if it is relevant (CLAUDE.md).
- `SECURITY.md:27` (T-06-M3): the disposition becomes "Mitigated for microphone and camera (dot on
  holzBar's icon, on by default); disclosed for screen recording".
- Release notes of the next beta (`docs/release-notes/v0.0.7-betaN.md`):
  - Fixed: "Automatic Zen mode now turns on and off when Screen Sharing starts and ends".
  - Fixed: "macOS 27: menu bar apps without a Dock icon that start after holzBar are no longer
    kept hidden or squashed".
  - New: "macOS 27: a dot on holzBar's icon while an app uses the microphone (orange) or the
    camera (green), because macOS hides Control Centre's indicator while holzBar hides items".

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| other processes -> holzBar (NSWorkspace runningApplications) | Bundle identifiers and bundle paths of other processes decide whether the concealer re-applies and whether Zen turns on |
| coreaudiod / CoreMediaIO -> holzBar (capture state) | Booleans about other processes' microphone and camera use decide what holzBar's icon shows |
| holzBar -> MenuBarAgent (assertions, status item) | Each relevant launch re-activates an assertion; adding or reinserting holzBar's icon |
| settings file / sync -> holzBar (Defaults) | The new key HolzBarIconShowsCaptureDot is importable like every setting |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-M27A-01 | Denial of Service | Concealer27 runningApplications KVO | medium | mitigate | Only bundle-ID set changes that add a known or top-level app, or remove a known one, cause one update; helper churn and multi-instance launches do nothing (AgentLaunches27 tests). A crash-looping agent is throttled by launchd (respawns at least 10 s apart) |
| T-M27A-02 | Denial of Service | main-thread KVO handlers | medium | mitigate | The handlers read two properties of the changed apps, take no lock, never wait, and hop to the main actor (D-01i, the F-12 rule) |
| T-M27A-03 | Spoofing | AgentLaunches27 standalone rule | low | accept | Any process can claim a bundle ID or sit in a top-level .app. The worst case is an extra concealment update; nothing is revealed that the layout conceals |
| T-M27A-04 | Spoofing | PresentationSignals (screen sharing agent ID) | low | accept | A process naming itself com.apple.screensharing.agent turns Zen on, which only hides more. Same as before this change |
| T-M27A-05 | Information Disclosure | new log lines | low | mitigate | Logs carry counts, Booleans and OSStatus codes as .public; no bundle IDs, PIDs or device names. Gate: privacy-check.py logs |
| T-M27A-06 | Elevation of Privilege | CaptureActivityMonitor27 | medium | mitigate | No permission, entitlement or usage string is added (Task 2 grep gate). holzBar never starts audio or video I/O; TCC sees only preflight queries (measured; M11 on 27) |
| T-M27A-07 | Repudiation | capture dot | low | accept | A process that records outside the HAL or CoreMediaIO is not seen. The dot is a substitute, not the system indicator; Settings and the docs say so (D-02, D-02k) |
| T-M27A-08 | Tampering | Defaults key HolzBarIconShowsCaptureDot | low | accept | A settings file or another Mac can turn the dot off, as it can any setting; any process of the user can write holzBar's defaults anyway. Import and sync are user actions |
| T-M27A-09 | Information Disclosure | dot on a shared screen | low | accept | Viewers can see that the presenter's microphone or camera is in use, which they already know in a call. Hidden items stay hidden (D-02l) |
| T-M27A-SC | Tampering | npm/pip/cargo/Swift package installs | low | accept | None added; the project has no package dependencies (CI gate) |
</threat_model>

<verification>
- The Task 1 and Task 2 verify blocks pass, and the gate set G1-G6 passes before each commit.
- `git -C WT log --format=%s -2` shows the two subjects. After the F-08 commit,
  `git -C WT status --short` is empty except for the untracked PLAN files.
- No file outside `files_modified` changed.
- No README, docs, SECURITY.md, release notes or CLAUDE.md edits.
- No persisted Defaults key or autosave name renamed; exactly one key added
  (`HolzBarIconShowsCaptureDot`).
- New strings exist only in Localizable.xcstrings, in five languages (374 strings in all
  catalogs).
</verification>

<success_criteria>
- F-17:
  - Automatic Zen follows `runningApplications` changes that alter the bundle-ID set, only while
    its setting is on.
  - The macOS 27 concealer answers added known or top-level apps and removed known apps with
    exactly one update and launch graces, and ignores everything else.
  - Covered by the PresentationSignals and AgentLaunches27Tests suites.
- F-08:
  - On macOS 27 holzBar's icon shows an orange or green dot, with an accessibility label and a
    tooltip, while it conceals and another process uses the microphone or a camera. This is
    event-driven and needs no permission.
  - A General setting, on by default, turns it off.
  - The note says what is and is not covered.
  - Covered by the CaptureIndicator and CaptureActivity suites.
- Both commits are atomic, the gates are green, the summary is committed and nothing is pushed.
- The maintainer has the M1-M14 checklist.
</success_criteria>

<output>
Create `.planning/audit/remediation/mac27-agents-dot-SUMMARY.md` (sibling format, see Task 3) and
commit it with the F-08 commit. Do not modify this PLAN file.
</output>
