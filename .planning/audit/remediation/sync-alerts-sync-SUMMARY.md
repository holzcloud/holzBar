---
phase: audit-remediation-sync-alerts
plan: sync
subsystem: settings-sync
tags: [sync, data-loss, concurrency, privacy, l10n]
requirements: [F-02, F-15, F-38, F-60]
status: complete
key-files:
  created:
    - holzBar/Core/SettingsSyncPolicy.swift
    - Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
  modified:
    - holzBar/Core/Defaults.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Core/SettingsSyncDevice.swift
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/Resources/Localizable.xcstrings
    - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift
completed: 2026-10-05
plan_head_before: 7e7ed6bf
actuals:
  tasks: 6
  commits: 3
---

# Chain sync-alerts, part sync: ask before replacing another Mac's settings (F-02, F-15, F-38, F-60)

The maintainer chose **"Nachfragen bei Konflikt"** (ask on conflict; decision `sync-1.md`).
Settings sync now compares SHA-256 digests of the user settings against a stored base. When two
Macs' settings conflict it asks with one new three-button alert. It never overwrites a pending
version from another Mac, keeps every access to the sync file off the main thread, ties the sync
id to the Mac and no longer deletes keys the other Mac lacks.

## Commits (branch audit-manual/sync-alerts, base 7e7ed6bf)

| Commit | Findings | Subject |
|--------|----------|---------|
| 88921465 | F-60 | fix(sync): resolve F-60 — keep local settings a synced file does not have |
| f2f8b9cc | F-02, F-15 | fix(sync): resolve F-02, F-15 — ask before replacing another Mac's settings, keep sync file I/O off the main thread |
| (this commit) | F-38 | fix(sync): resolve F-38 — give a Mac copied from another Mac its own sync id |

## Per finding

- **F-60 (low).** `SettingsBackup.apply(_:removesMissingKeys:)` removes only the keys that
  `Defaults.Key.keysRemoved(applying:over:removesMissingKeys:)` returns. A file import passes `true`.
  Every sync apply (launch, Restart, "Use Settings from Sync Folder", the learned-key merge) passes
  `false`. A macOS 26 file therefore no longer deletes MacOS27Layout and MacOS27LayoutSeeded on a
  macOS 27 Mac, and a macOS 27 file no longer deletes ItemSections on a macOS 26 Mac.
- **F-02 (high).**
  - New pure type `SettingsSyncPolicy` in Core:
    - `userDigest` is a canonical SHA-256 that sorts keys, compares 1 and 1.0 as equal and keeps
      Bool apart from numbers. It compares JSON inside Data by content and leaves out the learned
      keys.
    - `needsExchange` and the decision table `decide` have 10 rows. The outcomes are none, wait,
      retry, adopt, write, apply and ask.
    - The learned-key merge unites arrays and ORs flags.
  - The base is stored in `SettingsSyncBaseDigest` and a pending version in
    `SettingsSyncPendingModified`. Both are new local keys and are never synced.
  - Turning sync on no longer pushes (the didSet push is gone).
  - A push exits early when the user settings equal the base. Otherwise it reads and writes inside
    one coordinated access, and only on a `.write` decision.
  - A pending version pauses pushes. "Later" holds the version for the session, and the next
    launch asks again.
  - Turn On… and Change… read the chosen folder first. If another Mac's settings differ, a sheet
    on the Settings window asks with three buttons: "Use Settings from Sync Folder", "Keep This
    Mac's Settings" and Cancel. Nothing is stored before the answer.
  - While holzBar runs, a newer version and a local change at the same time ask the same question,
    with Later as the third button. A newer version without local changes keeps the existing
    Restart/Later prompt.
  - Windowless prompts run from `RunLoop.main.perform(inModes: [.default])` with
    `MainActor.assumeIsolated`, never `runModal()` inside a Task.
  - Learned keys never prompt and never push.
- **F-15 (medium).**
  - One serial `fileQueue` carries every access to the sync file and its folder: checks, pushes,
    the join read, and the folder setup (lstat, createDirectory, `open(O_EVTONLY)`). Async callers
    go through `@concurrent` and `BlockingWork.run(on:)`.
  - At launch (`AppDelegate.init`) holzBar waits at most 1 s. On timeout it cancels the
    coordinator. It skips the read when the file is dataless (`SF_DATALESS`) or ubiquitous and not
    `.current`.
  - The launch never writes and never asks. The check after setup handles a skipped file and asks
    when needed.
- **F-38 (medium).**
  - `SettingsSyncDeviceSalt` holds 32 random bytes and `SettingsSyncDeviceHash` holds SHA-256(salt
    ‖ hardware UUID). The UUID is read from IOKit (`kIOPlatformUUIDKey`).
  - When the stored hash does not match, holzBar creates a new id, clears last-synced, base and
    pending, and joins the folder again. On first use it rotates the id once and keeps last-synced.
  - Nothing identifying is logged, exported or synced.
  - The check runs in `pullIfNeeded` (sync on) and in `chooseFolder`.

## Gates

| Gate | Result on A | B | C |
|------|-------------|---|---|
| appcheck (whole app, Swift 6, macOS 26.5 SDK) | ERRORS 0 | ERRORS 0 | ERRORS 0 |
| servicecheck | SERVICE EXIT 0 | 0 | 0 |
| swift test | filtered green (17 SettingsSchema) | full: 6 + 136 + 301 passed | full: 6 + 136 + 307 passed |
| swiftlint --strict --quiet | no output, exit 0 | exit 0 | exit 0 |
| privacy-check network / logs | exit 0 / 0 | 0 / 0 | 0 / 0 |
| strings-check | 369 strings | 373 strings, exit 0 | exit 0 |
| former name check | no hits | no hits | no hits |
| no "ß" in catalog | 0 | 0 | 0 |

`swift test` sometimes fails to find the TestingMacros plugin, a known transient on this host. The
local wrapper retries until the test run starts.

## Deviations from the plan

1. **[Rule 1] Dates in the digest count in whole seconds**, not as a bit pattern. The sync file is
   an XML property list, which stores dates to the second. Hashing exact bit patterns would make a
   setting that holds a date look different after a round trip and cause needless prompts. Today no
   synced setting holds a date, so the effect is preventive.
2. **Launch availability check.** If `lstat` of the file fails (missing or unreadable), holzBar
   still runs the bounded read, and the read reports missing or unreadable. The plan said to return
   `.missing` straight away. This change keeps the `holzBar` folder symlink check of the read in
   force.
3. **Queued exchanges** are kept as a set (keep > check > push) instead of one slot, so a push that
   arrives while a check is running is not dropped.
4. **F-14 order**: no F-14 commit was on the branch, so the private run-loop presenter was added as
   planned.

Interpretations taken from the plan, unchanged:
- A re-identified Mac and an install without a base both count as joining. Cancel turns sync off on
  that Mac.
- Learned-only local changes do not push. They travel with the next real change, and a Mac that
  has synced merges them silently at launch.
- JSON inside Data is compared after parsing, with sorted keys.

## Known risks and open items

- **Two-Mac human check (D-23) is open.** See the user test steps below.
- The first launch after the update rotates every Mac's id and starts without a base. Macs whose
  settings already match stay silent. Macs that differ get one conflict question, and Cancel turns
  sync off there.
- Coordinator `cancel()` was verified on macOS 26.7.1 only. If macOS 27 ignores it, the 1 s bound
  still holds, but the stuck block delays later accesses to the sync file on `fileQueue` (never the
  main thread).
- The app target was only type-checked locally. The first real Xcode 27 build happens in CI after
  the chain's push.

## Doc updates needed (not done here: this run must not edit docs, release notes or SECURITY.md)

- `docs/privacy-and-permissions.md`: settings sync stores a random salt and a salted SHA-256 of the
  Mac's hardware UUID in holzBar's preferences, to recognise a Mac copied by Migration Assistant.
  It never leaves the Mac and is never exported, synced or logged.
- `docs/features.md` (sync bullet): holzBar asks which settings to use when two Macs differ; it
  never overwrites another Mac's settings unasked; the launch never waits for the cloud; settings a
  Mac does not have are kept.
- Settings pane annotation (code, a future change): the text "Changes from another Mac apply after
  a restart." is still true. Consider mentioning the question.
- `SECURITY.md` T-06-L2: the launch read is now off the main thread too, bounded to 1 s, and
  online-only files are skipped.
- Release notes of the next beta (`docs/release-notes/v0.0.7-beta2.md`): Fixed F-02, F-15, F-38,
  F-60; New: the sync conflict question.

## User test steps (two Macs, same sync folder)

1. Joining: Mac A has sync on with a customised layout. On Mac B, which has different settings,
   choose Turn On… with the same folder. A sheet asks. Cancel leaves sync off and A untouched. Turn
   On… again and choose "Use Settings from Sync Folder": B relaunches with A's settings, and A gets
   no prompt. Repeat with Change… and "Keep This Mac's Settings": A then offers Restart.
2. Relaunch several times on A and on B without changing anything. No prompt appears, and the
   file's modification date stays the same.
3. Later: change a setting on A. On B answer Restart/Later with Later, then change a setting on B.
   A must not change. Relaunch B: it asks the conflict question, with Later as the third button.
4. Online-only file: remove the local download of holzBar/Settings.plist, change a setting on the
   other Mac, and log in offline. The holzBar icon appears at once. Once back online, the question
   comes after launch.
5. macOS 26 and 27 Macs: after syncing, the 27 Mac keeps MacOS27Layout and the 26 Mac keeps
   ItemSections.
6. A Mac copied by Migration Assistant asks once, or stays silent if its settings are equal.
   Afterwards both Macs see each other's changes.
7. macOS 27: with the restart prompt open, click the clock, battery and Control Centre. Their menus
   open.

## Out of scope

The relayed question "Können wir das mit dem signieren nicht doch anders lösen?" concerns release
signing (release chain, decision release-1.md, F-05/F-10/F-11/F-52/F-53/F-54). This part changes
nothing about signing; the question goes back to the maintainer.

## Self-Check: PASSED

The created files exist. Commits 88921465 and f2f8b9cc are ancestors of HEAD. All gates are green
on the final tree.
