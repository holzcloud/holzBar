---
phase: 23-liquid-glass-transparency
plan: 01
subsystem: macos27-spike
tags: [liquid-glass, accessibility, spike, sdk-scan]
requires: []
provides:
  - "M27-04 decision: not-applicable (no public Liquid Glass slider signal in the macOS 27.0 SDK)"
  - "Scripts/macos27/scan-glass-api.sh: re-runnable static SDK scan"
  - "Scripts/macos27/glass-signals.swift: runtime probe for UAT U-13"
affects: [23-03]
key-files:
  created:
    - Scripts/macos27/scan-glass-api.sh
    - Scripts/macos27/glass-signals.swift
    - .planning/phases/23-liquid-glass-transparency/23-01-SPIKE.md
  modified: []
decisions:
  - "M27-04: not-applicable. The SDK scan exited 0; the runtime half is pending UAT U-13."
metrics:
  completed: 2026-10-09
status: complete
actuals:
  tokens: 9000
  tasks: 3
  commits: 3
plan_head_before: 0c6033a59aeefc04e55092faac064fa58e931ea7
plan_head_after: 02d593846499c4d51b639968dcc3cf24dd5d4834
---

# Phase 23 Plan 01: Liquid Glass slider spike Summary

A re-runnable SDK scan and a runtime probe show that the macOS 27.0 SDK has no public signal for the Liquid Glass slider, so M27-04 is recorded as `not-applicable`, with the runtime check left to UAT U-13.

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | Tracer: SDK scan with anchors, known lists, verdict | 3796a2f2 |
| 2 | Runtime probe of the public signals | ba36910c |
| 3 | 23-01-SPIKE.md with evidence and Decision line | 02d59384 |

## Results

- Scan: six anchors found, 322 focused files, `VERDICT: no public signal for a Liquid Glass slider in MacOSX27.0.sdk (16 glass and 23 transparency/contrast identifiers, all known)`, exit 0; `SDK=/nonexistent` gives `VERDICT: scan invalid` and exit 2. Matches the planning-time evidence; no list needed an addition.
- Probe: compiles with `swiftc -O` and with `-swift-version 6`; `--once`, watch mode and `--all-notifications` run on this host.
- Decision: `M27-04: not-applicable`. Runtime evidence on macOS 27 is pending UAT U-13 ("Not yet run" in the note).

## Deviations from Plan

None in substance. The probe's state is held in a `@MainActor` class started with `MainActor.assumeIsolated`, because Swift 6 mode rejects main-actor globals in top-level code; behavior is as the plan specifies.

## Known Stubs

None.

## Threat Flags

None. No file under `holzBar/` was touched; the probe prints notification names only.

## Self-Check: PASSED

Files and the three task commits exist; the commits list only the plan's three files.
