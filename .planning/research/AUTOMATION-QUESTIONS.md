# Decisions for milestone 0.0.7 "Automation"

**All 11 questions DECIDED by the user on 2026-10-04.** The answer is in the **DECIDED** line under each question; the options stay for the record. Where the user chose differently from the recommendation, the line says so.

1. **How should 0.0.7 ship?**
   - A. One milestone, numbered betas as phases land: `0.0.7-beta1` after Phase 8, `-beta2` after Phase 11, `-beta3` with widgets stage 1 and the gap phases (**Recommended**: each beta stays reviewable; CLAUDE.md allows it)
   - B. One beta with everything at the end
   - C. Triggers and scripts as 0.0.7, widgets and gaps as 0.0.8
   - **DECIDED: B.** One beta at the end: `0.0.7-beta1` when the whole milestone is done, no beta per phase (differs from the recommendation).

2. **Where does the rules screen live?**
   - A. A new settings pane "Automation" (rules; later scripts folder) (**Recommended**: Advanced is already crowded and HIG favours one pane per task)
   - B. Inside Advanced
   - C. Inside the Menu Bar Layout pane next to profiles
   - **DECIDED: A.** New settings pane "Automation".

3. **When a rule stops being true, what happens by default?**
   - A. Restore the profile that was active before (per-rule switch to turn off) (**Recommended**: what Bartender and Thaw users expect for "at work")
   - B. Nothing; the profile stays until the user changes it
   - C. Ask every time (rejected by the principles: interruptions)
   - **DECIDED: A.** Restore the previous profile, with a per-rule switch.

4. **Wi-Fi network name condition (needs Location Services on macOS 14+)?**
   - A. Offer it as opt-in: asked only when the user adds that condition, with the reason first; spike before promising it (**Recommended**)
   - B. Offer only "any Wi-Fi / Ethernet / offline / phone hotspot", which needs no permission
   - C. Offer both, with B as the default choice in the pane
   - **DECIDED: A.** Optional Location, asked only when the user adds that condition (opt-in), spike on a Mac first.

5. **Are Wi-Fi names and chosen apps in exported files and the sync file?**
   - A. Yes, rules travel as written; logs keep them private; the README says so (**Recommended**: the user's own data, needed on the other Mac)
   - B. Rules sync but Wi-Fi names are left out (the rule arrives disabled with a hint)
   - C. Rules never leave the Mac
   - **DECIDED: A.** Wi-Fi names and chosen apps are included in export and sync; logs stay private; the README says so.

6. **How strong is the script approval (Phase 11)?**
   - A. Local file with the file's SHA-256 and a confirmation sheet; residual same-user-malware risk documented (**Recommended** as the minimum)
   - B. A, plus the approval list sealed in a Keychain item bound to holzBar's code signature (spike first; stronger against malware that writes files as the user)
   - C. Do not build script support (end Phase 11 after the security design)
   - **DECIDED: A** as the minimum: file hash plus a confirmation sheet; scripts only from a folder the user picked; never created or changed through sync, import or URL. The Keychain seal (B) is not required.

7. **How are script conditions evaluated?**
   - A. On the engine's events and a manual re-check only (**Recommended**: nothing polls)
   - B. A, plus an optional interval of at least 5 minutes, off by default, labelled "polls" in the pane
   - C. A, plus an interval of any length (rejected: energy)
   - **DECIDED: A.** On the engine's events plus a manual "Check now"; no polling interval (stricter than the optional B).

8. **What is in widgets stage 1?**
   - A. Text widgets (date/time, battery, CPU, memory, uptime) and a Shortcut button (**Recommended**)
   - B. Text widgets only
   - C. Defer all widgets to a later milestone, after the spike on macOS 27
   - **DECIDED: A.** Text widgets (clock, battery, CPU, memory, uptime) plus a Shortcut button.

9. **Which competitor gaps get a phase besides the three big ones?**
   - A. Lock hidden items (Touch ID) and smooth animation, desktop icons as a spike only (**Recommended**, the plan as written)
   - B. Lock only
   - C. Lock, animation and a holzBar AppleScript dictionary (adds an input path; URL and Shortcuts already cover most uses)
   - **DECIDED (different):** lock for hidden items and smooth show/hide as phases, **plus an AppleScript dictionary for holzBar as its own phase after widgets** (Phase 13). The desktop-icons spike is **not** selected; it stays a backlog note.

10. **If the Focus-filter spike shows `SetFocusFilterIntent` is broken on the user's macOS (a May 2026 forum report says `perform` is never called on 26.5)?**
    - A. Ship without Focus and record it; retry on the next macOS point release (**Recommended**)
    - B. Wait and hold the milestone
    - C. Read the Focus by file (needs Full Disk Access): not recommended, breaks least privilege
   - **DECIDED: B.** HOLD the milestone if the Focus filter does not work on the user's macOS. It is a release blocker; the spike on macOS 26 and 27 runs first, early in Phase 8, and the roadmap says the milestone waits for its result (differs from the recommendation).

11. **README comparison table: show planned features?**
    - A. Add 🔜 rows now for triggers, scripts and widgets, where Thaw or Bartender have them (CLAUDE.md allows 🔜 and requires truth; the README has none today)
    - B. Add rows only when each feature ships (**Recommended**: the safest reading of "never claim what is not true yet")
    - C. Add 🔜 rows on the website only
   - **DECIDED: A.** Add the rows now as 🔜 (README, plus `research/WEBSITE-ROWS-0.0.7.md` in English and German); 🔜 only means planned, so every claim stays true.

## Questions added with the second and third feature batches (2026-10-04, OPEN)

The user selected eight more feature phases (9, 10, 14 to 17, 20, 21) and five macOS 27 / Xcode 27 / Swift 6.4 phases (22 to 26). Each phase outline in `.planning/phases/` states its question in full; this is the index. **All OPEN** unless marked DECIDED.

| # | Phase | Question | Options | Recommended |
|---|---|---|---|---|
| 12 | 9 Snapshots | When are snapshots taken? | A after settle, daily if changed and before applies; B daily only; C before applies only | A |
| 13 | 9 | How many are kept? | A newest 10 + one a day for 20 days (max 30, plus starred); B newest 10; C as many as fit in 2 MB | A |
| 14 | 9 | Backups? | A not excluded; B excluded | A |
| 15 | 9 | When the layout looks reset? | A banner with Restore; B restore automatically; C do nothing | A |
| 16 | 10 Item rules | Item rule against a layout profile? | A item rule wins; B profile wins until the condition changes; C ask | A |
| 17 | 10 | Where does a hidden-by-rule item go? | A Hidden by default, per-item choice; B always Always-hidden; C always Hidden | A |
| 18 | 16 Assistant | How bold are the proposals? | A conservative; B hide all non-essential; C ask per category | A |
| 19 | 16 | When does it appear? | A once at first launch, only without an imported layout; B only from Settings; C at every first launch | A |
| 20 | 17 Usage | How is it offered? | A off by default, offered in the assistant and Settings; B Settings only; C ask after two weeks | A |
| 21 | 17 | Observation window? | A 14 days observed, no click in 14, keep 30; B 30 days; C 7 days | A |
| 22 | 17 | Backups for the counters? | A excluded; B included | A |
| 23 | 14 Palette | Palette and item search? | A separate hotkey, shared panel code; B merge into one panel; C palette replaces search | A |
| 24 | 14 | Ranking? | A fuzzy score and fixed order, no history; B recent actions first | A |
| 25 | 15 Share | Formats? | A file only; B file and `holzbar://` link; C link only | A |
| 26 | 15 | Which apps go in the file? | A checkboxes before saving; B always all; C only non-Apple | A |
| 27 | 20 Diagnostics | Recent lines? | A typed in-memory event trail; B own unified log lines (spike); C none | A |
| 28 | 20 | Where is the button? | A About with a link from Advanced; B Advanced; C About | A |
| 29 | 21 Accessibility | Verification? | A checklist by the user plus code audit; B A plus an XCUITest audit in CI if stable | A |
| 30 | 21 | When may README and website mention it? | A after the user ran the checklist; B after the code audit | A |
| 31 | 22 Overflow | Shelf and the native overflow? | A keep the one switch and de-duplicate automatically; B three-way picker; C do nothing | A |
| 32 | 23 Glass | If no public slider signal exists? | A follow Reduce Transparency and Increase Contrast only; B read the system preference file (not public, rejected by the principles); C leave glass as is | A |
| 33 | 24 Reorder | Plan the SwiftUI reorder phase? | A spike with criteria, decide after; B drop now; C adopt without a spike | A |
| 34 | 25 Control | Control Center control? | A late go/no-go spike, build only on a clean go; B drop now; C build without a spike | A |
| 35 | 26 Swift 6.4 | When does the cleanup run? | A after all features, before the release; B at the start; C split: syntax sweep now, workaround re-test at the end | A |

Premises of the selected items that the research did **not** confirm (recorded so nothing false enters the README):
- **Liquid Glass slider**: it exists (System Settings > Appearance, three notches, per several news sources) but Gigazine's text does not mention it and no public API or notification for its value was found; Phase 23 follows Reduce Transparency for certain and the slider only if the spike finds a public signal.
- **`reorderable()` and the reorder container**: the WWDC26 session 271 transcript (as summarised) puts them on macOS 26 and newer, not only 27; to be confirmed in the SDK documentation.
- **Swift 6.4**: `await` in `defer` (SE-0493) is confirmed on swift.org; `anyAppleOS` is reported by secondary sources but not listed in the swift.org release summary I fetched; "faster Foundation URL parsing" was not found in any source, and the Xcode 27.2 beta 2 release notes list no Swift features (they do list the `.xcproj` format).
- **Control Widgets on a self-signed, non-sandboxed app**: unknown; Phase 25 is a go/no-go spike.
