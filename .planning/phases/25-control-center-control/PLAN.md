---
phase: 25-control-center-control
status: planned (OPTIONAL and RISKY; explicit go/no-go spike first; run /gsd-plan-phase 25)
requirements: [M27-06, M27-07]
depends_on: Phase 8 (rules and Zen/profile actions exist), Phase 13 (the shared action catalog), Phase 18 (the lock gate for reveals)
---

# Phase 25: Control Center control

## Goal

A Control Widget (WidgetKit `ControlWidget`) lets the user toggle Zen mode or apply a layout profile from Control Center (and, where the user allows it, from the menu bar). Shipped only if a spike shows it works for holzBar's self-signed, non-sandboxed distribution without breaking a principle.

## What is known

- (V, Apple docs) `ControlWidget` is available from macOS 26.0 (`SwiftUI/ControlWidget`); `WidgetKit/ControlCenter` (`reloadControls(ofKind:)`, `currentControls()`) macOS 26.0. Controls are buttons or toggles defined with SwiftUI templates; "when someone interacts with a control, it performs its action using an app intent you specify"; "when the system loads or reloads a control, it runs the body of the control from the widget extension"; to open the app the intent must be an `OpenIntent` and "the system requires the Target Membership of the app intent to be set to both the app and the widget extension". A control is created by adding a **Widget Extension target** ("Include Control").
- (secondary, search results) On Mac, third-party controls can be placed in Control Center or shown as **menu bar items** ("Allow in the Menu Bar" in System Settings). A control a user puts in the menu bar is therefore a new system-owned menu bar item that holzBar's discovery will see and the user may want to hide or place; holzBar has to classify it.
- Unknown, to be settled by the spike: whether macOS loads an app extension from a **non-sandboxed, self-signed** app at all. On macOS app extensions are normally required to be sandboxed (K, to verify; the extension would carry `com.apple.security.app-sandbox` while the host app stays unsandboxed); whether a self-signed extension is registered by `pluginkit` and shown in the controls gallery without notarization (K); what the extension may share with the app without an **App Group** (the group needs a team identifier, which a self-signed build lacks; K).

## Design questions the spike answers

1. **Does it work at all?** Build a throwaway extension target in `holzBar.xcodeproj` (CI build is the only compiler; the user installs the CI artifact and checks the controls gallery on macOS 26.7.1 and 27). Go/no-go criterion 1.
2. **How does the control reach the running app?** Preferred: an `AppIntent` defined in the **app** target so the system runs it in the app process (no shared storage, no XPC, no App Group). The control is then **stateless**: a button "Toggle Zen Mode" or "Apply Profile <Name>" (configurable profile via an `AppIntentControlConfiguration` whose option list needs the profile names: that list lives in the app, so the entity query is also an app-side intent). A toggle that shows "Zen is on" needs state shared with the extension: only possible with an App Group, or by the extension asking the app via the intent. The recommendation is to start with buttons, no state, no App Group (least privilege).
3. **Entitlements**: the extension gets the App Sandbox entitlement only if macOS requires it (more restrictive, so compatible with "least privilege"); **no** App Group, **no** network, **no** other entitlements. The README row "Entitlements: none" changes honestly to "none for the app; the Control Center extension is sandboxed and has no entitlements besides the sandbox" if shipped.
4. **Signing and the XPC peer check**: the extension is a nested bundle (`PlugIns/*.appex`) and must be signed with the same self-signed certificate and hardened runtime as the app (`docs/signing.md`, release workflow signs after the build; the nested bundle must be signed first, `codesign --deep` is discouraged, sign inside-out). The `MenuBarItemService` XPC peer check accepts only holzBar's own code (team or exact code hash): the extension is not a peer and never talks to that service; it must not be added to the allowed set. Any change that makes the app accept connections from the extension would weaken the XPC peer check and is out of bounds. CI's release job and `SharedCodeSigningTests` need updating for the extra code object (hash pinned).
5. **Size budget**: holzBar is lean (app 16.7 MB, README claim). Budget: the extension may add at most **1 MB** (about 6 percent) to the zip and no new dependencies; the spike measures with the CI artifact (`build.yml` already reports app size). Over budget means no-go.
6. **Lean at runtime**: a control extension is launched by the system only when the control is shown or used; holzBar adds no process of its own. Measure idle (no extra wake-ups).
7. **Gate and safety**: a control that reveals items must pass Phase 18's lock; "Toggle Zen" off follows the Zen-off rules (refuse while the screen is shared, like URL commands, T-06-M1); the control cannot create or edit anything.
8. **Discovery side effect**: if the user adds the control to the menu bar, the item appears as a ControlCenter-owned item; the layout editor, search and Phase 16 classifier must handle it (as an Apple system item).

## Go / no-go criteria (all required)

1. The extension is installed and its control appears in the gallery from a CI-built, self-signed app on macOS 26 and 27.
2. The button runs holzBar's action in the running app (or launches it) reliably.
3. No App Group, no network, no extra entitlement besides the sandbox if macOS demands it; the XPC peer set is unchanged.
4. App size increase is at most 1 MB; no new Swift package.
5. Gatekeeper and quarantine do not block it for the Homebrew install path (cask removes quarantine; check).
If any fails: stop, record `25-01-SPIKE.md`, and drop the phase (the milestone does not wait for it).

## Privacy and permission analysis

If shipped: no network, no data shared with the extension, no App Group; the extension sees nothing but the intent's parameters (a profile name chosen by the user). Sandboxed extension reduces, not increases, privilege.

## Plans (outline)

1. **25-01 Go/no-go spike**: extension target, one button control, app-side intent, CI artifact install, the five criteria; write the note.
2. **25-02 (only on go) Controls**: Toggle Zen Mode, Apply Profile (configurable), strings in five languages, symbol images, gating; signing steps in the release workflow and `docs/signing.md`; size check in CI; README row only after the user verified.
3. **25-03 (only on go) Discovery and docs**: classify the control's menu bar item, SECURITY.md entry (extension is not a peer), Permissions table row for the extension sandbox.

## Risks

- Highest uncertainty of the milestone: extension loading for self-signed apps is unverified; expect a no-go.
- Release pipeline complexity (nested signing, pinned code hashes, `SharedCodeSigningTests`).
- A user-visible new process type and a new "extension" in System Settings; must be explained.
- macOS 26+ only: the control is guarded; macOS 14 and 15 build without it (the extension is embedded only conditionally or ignored by older systems: spike).

## Open design question

34. **Control Center control: spike or drop now?** A. Run the go/no-go spike late in the milestone (after Phases 8 to 21) and build it only on a clean go (**recommended**); B. Drop it now and record it in the backlog; C. Build it without a spike (not recommended).
