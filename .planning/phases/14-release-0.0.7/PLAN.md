---
phase: 14-release-0.0.7
status: planned, decisions recorded 2026-10-04 (outline)
requirements: [FACT-02, REL-02]
depends_on: Phases 8 to 13, all of them; the Focus filter of Phase 8 is a release blocker
---

# Phase 14: Release 0.0.7-beta1

## Goal

Users can install and update to `0.0.7-beta1` with accurate notes and docs. **One beta, published once, when the whole milestone is done** (user decision 1): no beta per phase. A stable `0.0.7` only when the user says so (CLAUDE.md). The release is held if the Focus filter (TRIG-04) does not work on macOS 26 and 27.

## Plans

1. **14-01 Fact check and docs**: re-check every README, website (all five languages) and comparison-table claim against code and sources; flip each 🔜 row that shipped to ✅ (see below) and delete any that did not; update the feature list ("Automation"), the Permissions table (Location Services row only if the Wi-Fi opt-in shipped; the "Info.plist usage strings: none" row changes with it), the Principles text, SECURITY.md (T-09-* and T-11-* status), and the website rows (`.planning/research/WEBSITE-ROWS-0.0.7.md`, then into the CMS only after the release exists).
2. **14-02 Release**: `docs/release-notes/v0.0.7-beta1.md` (Highlights, New, Fixed, Changed, Known issues, Install with `brew tap`, `brew trust --cask holzcloud/holzbar/holzbar`, `brew install`, `brew update && brew upgrade --cask holzbar`, `xattr -dr com.apple.quarantine /Applications/holzBar.app`), pre-release tag `v0.0.7-beta1`, cask follows by the workflow, **one push at the end**, CI green first.

## README and website comparison-table rows

Decision 11: the rows were added now as 🔜 (README "holzBar vs. Ice and Thaw", with the sentence "🔜 means planned for the next release (0.0.7): it is **not available yet**"; website text in `.planning/research/WEBSITE-ROWS-0.0.7.md`, English and German). 🔜 only ever means planned. In this phase each row is re-checked against the code and flipped or removed:

| Row | Ice | Thaw | holzBar when shipped | Phase |
|---|---|---|---|---|
| Rules that apply a profile or show items when a Wi-Fi network, an app, the time of day, the power source or a display matches (all or any) | ❌ | ✅ | ✅ (if the Wi-Fi-name part is dropped, say which conditions exist) | 8 |
| Profile applied by a Focus filter | ❌ | ✅ | ✅ (a release blocker, so it must be true at release) | 8 |
| Scripts as a rule condition or action | ❌ | ✅ | ✅ only from a folder you choose, after you confirm | 9 |
| Menu bar items of your own (clock, battery, CPU, Shortcut button) | ❌ | — | ✅ stage 1; script widgets are not claimed | 10 |
| AppleScript dictionary | — | — | ✅ | 11 |
| Touch ID or password to show hidden items | — | — | ✅ | 12 |
| Smooth show and hide | — | — | ✅ (not macOS 27 if the Phase 13 spike says so) | 13 |

Rows to add at release, when true (not 🔜 now because they are properties, not plans): "Asks for Location Services only when you add a Wi-Fi-name rule" (Privacy and permissions), "Scripts run only from a folder you chose, only after you confirm, never from a URL, import or sync" (Privacy), "Widgets do nothing while hidden" (Code and resources). Also the README feature list gets an "Automation" line per shipped phase, and the existing "Show hidden items on low battery or when offline" row says it is now one of the rules.

## Risks

Claims that outrun the code (the CLAUDE.md rule); shipping Phase 9 without its security review; website rows pushed to the CMS before the release exists; a long milestone with one release at the end means a large diff: keep each phase's commits clear and CI green before the single push.
