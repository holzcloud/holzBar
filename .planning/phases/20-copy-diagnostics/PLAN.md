---
phase: 20-copy-diagnostics
status: planned (outline; run /gsd-plan-phase 20)
requirements: [DIAG-01, DIAG-02, DIAG-03]
depends_on: Phase 7 (counts from Phases 9, 14, 16, 17 are added as those exist)
---

# Phase 20: Bug report by click

## Goal

A **Copy Diagnostics** button builds a redacted report the user reads first, then copies and pastes into an issue; the issue tracker opens in the browser. holzBar sends nothing.

## Why

Bug reports for a menu bar manager fail on missing facts (macOS version, backend, displays, permissions). A one-click report removes that, and doing it as "show, then copy" keeps the never-online promise. The issue tracker link is the allowed browser exception (`Constants.issuesURL`).

## Report content (allowlist; anything not listed is not in it)

holzBar version and build; macOS version and build; Mac model identifier and architecture (for example `Mac15,6`, `arm64`; not the serial number, not the name); backend kind (14 to 25, 26, 27); display count, which have a notch, whether any is mirrored; permission states (Accessibility, Screen Recording: granted or not; launch at login: on or off); number of items per section, profiles, groups, spacers, rules, item rules, snapshots (numbers only); the **values of an allowlisted set of non-personal settings** (booleans, enums and numbers such as show on hover, rehide strategy, spacing, appearance mode), picked by an explicit `Defaults.Key` flag, default **not** included; names of settings keys changed from default only for that allowlist; the last **typed events** (below).

Never: item titles, bundle identifiers, app names, profile, group or rule names, Wi-Fi names, file paths, folder names, user or computer name, hotkeys, usage counters, snapshot contents, script names, anything from the pasteboard.

## Design

- **Pure builder in `holzBar/Core`** (`DiagnosticsReport.make(from: DiagnosticsInput)`), where `DiagnosticsInput` is a struct of already-redacted primitives; Swift Testing includes a **sentinel test**: a fully populated model whose every string is a unique sentinel (`"SENTINEL-Mail"`, `"SENTINEL-HomeWiFi"`, `"/Users/SENTINEL"`) and the test fails if any sentinel appears in the output. Adding a field without redacting it breaks the test.
- **Recent events** (DIAG-03, question 27): a small in-memory ring buffer (at most 100) of **typed events**: an enum of holzBar actions and system events (`.profileApplied`, `.sectionRevealed(method)`, `.rulesEvaluated(count)`, `.displayChanged`, `.wake`, `.moveFailed(reason enum)`) with a time stamp; no associated strings, so it cannot carry personal data by construction; never written to disk. The alternative, reading the unified log (`OSLogStore`, macOS 12+ for `init(scope:)`; Apple's page says entries of a store can be read with `getEntries(with:at:matching:)`), depends on how `.private` interpolations appear to the same process: unverified, so spike first.
- **UI** (DIAG-02): in the About pane (and a link from Advanced, question 28) a **Copy Diagnostics…** button opens a sheet with the **exact text** in a read-only selectable view, a short explanation ("Nothing is sent. Read it, then copy it into your issue."), and the buttons **Copy** (writes the pasteboard only on this click), **Copy and Open Issue Tracker** (copy, then open `Constants.issuesURL` with the browser) and Cancel. The issue template mentions the report. VoiceOver reads the sheet in order.
- **Docs**: README feature line; `privacy-check.py` extended so the diagnostics code cannot reference network APIs (already covered) or log public values.

## Privacy and permission analysis

No permission, no network. The report is assembled in memory, shown, and only the user's click writes the pasteboard. Redaction is allowlist-based and tested with sentinels.

## Plans (outline)

1. **20-01 Report builder and sentinel tests (Core)**: input struct, allowlist flag on `Defaults.Key`, formatter, sentinel test.
2. **20-02 Event trail and collectors**: typed ring buffer; collectors for versions, displays, permissions, counts (each returns primitives only).
3. **20-03 About-pane UI**: sheet with exact text, copy and open tracker, five languages, issue template line, README.

## Risks

- A future field added without redaction: the sentinel test and the allowlist-by-flag design.
- The Mac model identifier plus macOS build can narrow a person down a little: it is the least information that still helps and is shown before copying.
- A log spike result (`OSLogStore`) may be worse than the typed trail: the typed trail is the default.

## Open design questions

27. **What are "recent lines" in the report?** A. A typed in-memory event trail with no free text (**recommended**); B. The process's own unified log lines (spike first; depends on how private values appear); C. No recent events.
28. **Where is the button?** A. About pane, with a link from Advanced (**recommended**); B. Advanced only; C. About only.
