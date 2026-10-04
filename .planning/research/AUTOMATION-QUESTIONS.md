# Open decisions for milestone 0.0.7 "Automation"

The user answers only multiple choice. Each question has 2 to 4 options and a recommendation (marked **Recommended**). Numbers are referenced by the phase outlines.

1. **How should 0.0.7 ship?**
   - A. One milestone, numbered betas as phases land: `0.0.7-beta1` after Phase 8, `-beta2` after Phase 9, `-beta3` with widgets stage 1 and the gap phases (**Recommended**: each beta stays reviewable; CLAUDE.md allows it)
   - B. One beta with everything at the end
   - C. Triggers and scripts as 0.0.7, widgets and gaps as 0.0.8

2. **Where does the rules screen live?**
   - A. A new settings pane "Automation" (rules; later scripts folder) (**Recommended**: Advanced is already crowded and HIG favours one pane per task)
   - B. Inside Advanced
   - C. Inside the Menu Bar Layout pane next to profiles

3. **When a rule stops being true, what happens by default?**
   - A. Restore the profile that was active before (per-rule switch to turn off) (**Recommended**: what Bartender and Thaw users expect for "at work")
   - B. Nothing; the profile stays until the user changes it
   - C. Ask every time (rejected by the principles: interruptions)

4. **Wi-Fi network name condition (needs Location Services on macOS 14+)?**
   - A. Offer it as opt-in: asked only when the user adds that condition, with the reason first; spike before promising it (**Recommended**)
   - B. Offer only "any Wi-Fi / Ethernet / offline / phone hotspot", which needs no permission
   - C. Offer both, with B as the default choice in the pane

5. **Are Wi-Fi names and chosen apps in exported files and the sync file?**
   - A. Yes, rules travel as written; logs keep them private; the README says so (**Recommended**: the user's own data, needed on the other Mac)
   - B. Rules sync but Wi-Fi names are left out (the rule arrives disabled with a hint)
   - C. Rules never leave the Mac

6. **How strong is the script approval (Phase 9)?**
   - A. Local file with the file's SHA-256 and a confirmation sheet; residual same-user-malware risk documented (**Recommended** as the minimum)
   - B. A, plus the approval list sealed in a Keychain item bound to holzBar's code signature (spike first; stronger against malware that writes files as the user)
   - C. Do not build script support (end Phase 9 after the security design)

7. **How are script conditions evaluated?**
   - A. On the engine's events and a manual re-check only (**Recommended**: nothing polls)
   - B. A, plus an optional interval of at least 5 minutes, off by default, labelled "polls" in the pane
   - C. A, plus an interval of any length (rejected: energy)

8. **What is in widgets stage 1?**
   - A. Text widgets (date/time, battery, CPU, memory, uptime) and a Shortcut button (**Recommended**)
   - B. Text widgets only
   - C. Defer all widgets to a later milestone, after the spike on macOS 27

9. **Which competitor gaps get a phase besides the three big ones?**
   - A. Lock hidden items (Touch ID) and smooth animation, desktop icons as a spike only (**Recommended**, the plan as written)
   - B. Lock only
   - C. Lock, animation and a holzBar AppleScript dictionary (adds an input path; URL and Shortcuts already cover most uses)

10. **If the Focus-filter spike shows `SetFocusFilterIntent` is broken on the user's macOS (a May 2026 forum report says `perform` is never called on 26.5)?**
    - A. Ship without Focus and record it; retry on the next macOS point release (**Recommended**)
    - B. Wait and hold the milestone
    - C. Read the Focus by file (needs Full Disk Access): not recommended, breaks least privilege

11. **README comparison table: show planned features?**
    - A. Add 🔜 rows now for triggers, scripts and widgets, where Thaw or Bartender have them (CLAUDE.md allows 🔜 and requires truth; the README has none today)
    - B. Add rows only when each feature ships (**Recommended**: the safest reading of "never claim what is not true yet")
    - C. Add 🔜 rows on the website only
