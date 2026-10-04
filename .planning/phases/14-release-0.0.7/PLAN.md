---
phase: 14-release-0.0.7
status: planned (outline)
requirements: [FACT-02, REL-02]
depends_on: the phases the user chose to include
---

# Phase 14: Release 0.0.7

## Goal

Users can install and update to `0.0.7-beta1` (then `-beta2`, ...) with accurate notes and docs. A stable `0.0.7` only when the user says so (CLAUDE.md).

## Plans

1. **14-01 Fact check and docs**: re-check every README, website (all five languages) and comparison-table claim against code and sources; update the table rows (see the impact list below), the feature list ("Automation"), the Permissions table (Location Services row, only if Phase 8's Wi-Fi opt-in ships; the "Info.plist usage strings: none" row changes with it), the Principles text, SECURITY.md register (T-09-* status), `docs/upstream-bugs.md` if an Ice bug is fixed (Ice's roadmap items triggers and widgets are not bugs), and the website rows file `.planning/research/WEBSITE-UPDATE.md` style for the CMS.
2. **14-02 Release**: `docs/release-notes/v0.0.7-beta1.md` (Highlights, New, Fixed, Changed, Known issues, Install with `brew tap`, `brew trust --cask holzcloud/holzbar/holzbar`, `brew install`, `brew update && brew upgrade --cask holzbar`, `xattr -dr com.apple.quarantine /Applications/holzBar.app`), pre-release tag `v0.0.7-beta1`, cask follows by workflow, one push, CI green first.

## README and website comparison-table impact

Rule (CLAUDE.md): never claim what is not true yet; a 🔜 row only for what is genuinely planned and says so; update the row when it lands; compare with Ice and Thaw as the README does. The README has no 🔜 row today; adding some is a user decision (open question 11). Rows, with the state they get when each phase lands:

| Row (group) | Ice | Thaw | holzBar when shipped | Phase |
|---|---|---|---|---|
| Automatic rules: reveal items or apply a profile when a Wi-Fi network, app, time of day, power or display condition holds (Features) | ❌ | ✅ | ✅ (🔜 before) | 8 |
| Rules combine conditions with all/any | ❌ | ✅ | ✅ | 8 |
| Profile applied by a Focus filter (Features) | ❌ | ✅ | ✅ only if the spike works, otherwise no row | 8 |
| Asks for Location Services only when you add a Wi-Fi-name rule (Privacy and permissions) | — | — | ✅ | 8 |
| Run a script as a rule condition or action (Features) | ❌ | ✅ | ✅ | 9 |
| Scripts run only from a folder you chose, only after you confirm, never from a URL, import or sync (Privacy) | — | — | ✅ | 9 |
| Custom menu bar items (widgets) (Features) | ❌ | — | ✅ stage 1: text from built-in sources, no permission; script widgets later | 10 |
| Widgets do nothing while hidden (Code and resources) | — | — | ✅ | 10 |
| Touch ID or password to reveal hidden items (Privacy) | ❌ | — | ✅ | 11 |
| Smooth show and hide (Features) | ❌ | — | ✅ (not macOS 27 if the spike says so) | 12 |
| Hide desktop icons | ❌ | — | only if shipped | 13 |

Also: README feature list gets an "Automation" line per shipped phase; "Principles" and Permissions table mention Location only if Phase 8 ships it; the existing "Show hidden items on low battery or when offline" row says it is now one of the rules.

## Risks

Claims that outrun the code (the CLAUDE.md rule); a beta that ships Phase 9 without its security review; website rows pushed to the CMS before the release exists.
