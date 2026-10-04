---
phase: 09-scripts
status: planned (outline; security design comes first, then /gsd-plan-phase 9)
requirements: [SCRIPT-01, SCRIPT-02, SCRIPT-03, SCRIPT-04, SCRIPT-05, SCRIPT-06]
depends_on: Phase 8 (rules and the engine's events)
research: .planning/research/COMPETITORS.md
---

# Phase 9: Scripts

## Goal

A user script or AppleScript can be a rule's condition and a rule's action, and a hostile input (a settings file, a sync file, a URL, a Wi-Fi name, a Shortcut, another app) can never make holzBar run code the user did not choose and confirm.

## Why (competitors)

Thaw (script result trigger, pre/post profile hooks), SaneBar (custom-script trigger, AppleScript), Bartender 7 (AppleScript, scripts as widget data), ExtraBar (shell scripts, Shortcuts). Power users ask for it; it is also the biggest risk in the milestone.

## Security analysis (first deliverable of the phase, before any runner code)

holzBar is not sandboxed, holds Accessibility (to read, move and click menu bar items and to see clicks and scrolls), and may hold Screen Recording. A script runner turns that into an interpreter. Assets and threats:

| ID (to add to SECURITY.md) | Threat | Entry | Mitigation |
|---|---|---|---|
| T-09-H1 | **Settings import or sync creates or alters a script binding**, so a crafted file or a hostile sync folder runs code on the next trigger | Export/import/sync, `SettingsSchema` | Script bindings, the folder, approvals and hashes are not settings: they live in a local-only file (`~/Library/Application Support/holzBar/Scripts.json`, mode 0600), outside `Defaults`, outside the export/import/sync allowlist. A rule that names a script, arriving by import or sync, is dropped and reported ("1 rule needs a script and was not imported") |
| T-09-H2 | **URL command or Shortcut creates, edits, approves or runs a script** | `holzbar://`, App Intents | No URL command and no intent can touch scripts. Rules cannot be created or edited by URL (Phase 8). A URL that enables a rule never confirms a script; the script's own confirmation (SCRIPT-03) stands |
| T-09-H3 | **Untrusted values become code**: an SSID such as `x"; do shell script "..."`, an app name, a profile name, item titles | Triggers, rules | No shell, no string building, no scripts text created by holzBar. `Process` with `executableURL` set to the file and `arguments = []`. Event details are not passed at all (not as arguments, not in the environment). The only context given is a fixed set of constant names in the environment (`HOLZBAR_EVENT=rule-started` or `rule-ended`) taken from an enum |
| T-09-H4 | **Same-user malware plants a script and a binding**, and so borrows holzBar's Accessibility (TCC attributes a child process to the responsible app: assumed, to verify) | Local file system | The folder is chosen by the user; files must be regular, owned by the user, not group or world writable, not symbolic links out of the folder, and without `com.apple.quarantine`. Bindings are pinned to the file's SHA-256 and a user confirmation (SCRIPT-03). Residual risk: malware running as the user can write the binding file and the approval too; options: seal the approval list in a Keychain item whose access control names holzBar's code signature, so only holzBar can add an approval without a prompt (spike; open question 6). Documented honestly in SECURITY.md either way |
| T-09-M1 | **Swap after approval** (time-of-check, time-of-use): the file changes between hash and run | Local file system | Hash and execute the same open file descriptor where the API allows (`posix_spawn` of `/dev/fd/N` is not portable): re-hash immediately before each run and refuse on mismatch; run only from a file the user cannot be tricked into replacing by a symlink (`O_NOFOLLOW`, `fstat`). Residual window documented |
| T-09-M2 | **A script hangs, floods or forks forever** | Runner | Timeout (default 10 s, maximum 60 s), then SIGTERM, then SIGKILL after 2 s, to the whole process group; stdout and stderr captured up to 64 KB, the rest dropped; one run per script at a time; at most 10 runs a minute overall; stdin from `/dev/null` |
| T-09-M3 | **Output is trusted**: a script prints text that is shown, opened or executed | UI, widgets | Output is data: plain text, first line, at most 80 characters for widgets, control characters removed, never parsed as a URL, a path, a command, markup or an attributed string |
| T-09-M4 | **Scripts inherit holzBar's environment and permissions** | Runner | Minimal environment (`PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `HOME`, `LANG`), working directory = the scripts folder; the pane says "Scripts run as you, with holzBar's permissions. macOS asks separately before a script controls another app" |
| T-09-L1 | A script condition used as a poll burns energy | Engine | Evaluated on engine events and manual re-check; an optional interval of at least 5 minutes, labelled as polling, off by default; not while the screen is locked or asleep |
| T-09-L2 | A script prompt spoofs holzBar's wording | Confirmation | The confirmation shows the file name, folder, size and the first 8 characters of its SHA-256, with fixed wording; names are shortened and cleaned like the URL prompts (`URLPrompt`) |

## Design decision (recommended)

- **Where scripts come from**: a folder the user picks once (an open panel, default `~/Library/Application Support/holzBar/Scripts`), listed in the pane. Nothing outside it can run; there is no "type a command" field and no inline script text in holzBar (smaller surface than competitors, deliberately).
- **What runs**: executable files (a shebang decides the interpreter; the user sets the executable bit) run directly; `.scpt`, `.scptd` and `.applescript` run through `/usr/bin/osascript` with the file path as the single argument. Both through `Process`, spike `NSUserUnixTask` / `NSUserAppleScriptTask` (V: they run user scripts "outside of the application's sandbox") to learn which TCC identity the script gets. If they avoid handing holzBar's Accessibility to the script, they are the better choice (Apple's way); otherwise `Process`.
- **Condition**: exit status 0 = true, anything else or a timeout = false (never "true on error").
- **Action**: the script runs once when the rule starts and, if chosen, once when it ends.
- **Not in v1**: profile pre/post hooks (Thaw), inline scripts, arguments, passing event data, running from a URL or Shortcut, a scripting dictionary for holzBar.
- **Confirmation (SCRIPT-03)**: a sheet in the pane on first use and after a change: file, folder, hash prefix, what a script can do, "Allow" and "Cancel". A script that needs confirmation does nothing while it waits; the rule shows "needs approval".
- **Local only**: nothing about scripts is in `Defaults`, the export, the sync file, logs (public), URL answers or Shortcuts results.

## Plans (outline)

1. **09-01 Security design and register**: write the design above as `09-SECURITY-DESIGN.md`, add T-09-* to `SECURITY.md` as "Planned", run the spikes (TCC identity of child processes; `NSUserUnixTask` vs `Process`; Keychain seal feasibility with holzBar's self-signed certificate), and let the user decide open questions 6 and 7. No runner code.
2. **09-02 Gate and runner (pure core + thin shell)**: `ScriptGate` (path rules, owner, mode, quarantine, symlink, hash, approval check) as pure logic over a file-info struct with Swift Testing; `ScriptRunner` with timeout, output cap, process group kill, rate limit; tests with fake runners for every refusal; nothing wired to the UI.
3. **09-03 Rules integration and pane**: script condition and action in the engine and the Automation pane; the confirmation sheet; local-only store; import/sync drop-and-report; strings in five languages; privacy-check for logs.
4. **09-04 Hardening and docs**: re-verify T-09-* with the tests, README Permissions and Principles text (scripts run with holzBar's permissions; nothing about scripts syncs), SECURITY.md entries to "Mitigated" or "Accepted".

## Risks

- Child processes may inherit holzBar's Accessibility and Screen Recording: if so, every approved script is as powerful as holzBar. Mitigated by choice, confirmation and pinning; never fully removable.
- A Keychain seal may not work with a self-signed certificate across updates (holzBar keeps the same certificate since 0.0.6, `docs/signing.md`): spike.
- Hardened runtime and library validation do not restrict child processes; do not rely on them.
- The feature may be judged "too dangerous" by the user: the phase is optional and can end after 09-01 with the register entries and a decision.
- `privacy-check.py` forbids network code; `Process` is already used once (`Permission.swift`); no new pattern needed, but add a CI check that the runner is the only caller of the script APIs.

## Out of scope

Profile hooks, inline script editor, remote scripts, any script source other than the chosen folder, scripts reading holzBar's data, AppleScript dictionary for holzBar.
