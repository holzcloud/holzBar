---
phase: 16-cleanup-assistant
status: planned (outline; run /gsd-plan-phase 16)
requirements: [ASSIST-01, ASSIST-02, ASSIST-03]
depends_on: Phase 9 (snapshot before the assistant applies anything)
---

# Phase 16: First-launch clean-up assistant

## Goal

On first launch (and any time from Settings) holzBar looks at the menu bar items, groups them sensibly, proposes an arrangement, and the user accepts or edits it. Skippable; re-runnable.

## Why

A new user sees an unsorted bar and an empty "hidden" section; the value of holzBar starts only after they drag many items. No source read for `COMPETITORS.md` describes a guided first run in other managers (not claimed as a lead). The challenge is to propose well **without tracking**: at first launch there is no click history, and the principles forbid collecting one without opt-in (that is Phase 17).

## How items are grouped without history

Only static, local facts, nothing observed:

1. **System items by identifier**: Apple's items are known by their namespace and title identifiers (`com.apple.menuextra.*`, Control Centre, Clock, Wi-Fi, Battery, Sound, Bluetooth, Focus, Display, Spotlight, Siri, Now Playing, Screen Mirroring; K, built from a Mac in the spike). The essentials (Clock, Control Centre, Battery, Wi-Fi, Sound) stay visible; the others are proposed Hidden.
2. **App category**: the owning app's `LSApplicationCategoryType` from its `Info.plist` (local read of the app bundle, no permission; K), mapped to a class: set-and-forget (cloud storage sync, backup, updaters, system utilities, developer tools, VPN helpers) -> proposed Hidden; communication and calendar (`social-networking`, `productivity` mail/calendar) -> stays visible because their items carry badges; unknown -> unchanged.
3. **A small static table** in the repository (`KnownItems.json`, a few KB, bundle id -> class) for popular apps whose category is missing or misleading; maintained by pull requests, no network.
4. **Live-value items** (titles that change, found by `ItemIdentity.canonicalTitle`) are informational (clock, battery, CPU, mail count): never proposed for hiding, because the user reads them instead of clicking them.

## Design

- **Pure logic in `holzBar/Core`** (Swift Testing): `ItemClassifier` (namespace, app category, title kind -> `ItemClass`), `CleanUpProposal` (items -> proposed section with a reason string key), conservative defaults (question 18), never touches items the user already arranged (when a saved layout exists the assistant only offers items in the new-items area).
- **Flow** (a sheet or a small window; HIG: plain steps, default button on the safe choice): 1) what it does ("holzBar looks at the apps in your menu bar on this Mac. Nothing leaves your Mac and nothing is recorded"), 2) review: grouped lists (Essentials, Set-and-forget, Communication, Other) with app icon, name and a section menu per item and a group-level switch; "Why?" shows the reason, 3) Apply, which takes a `beforeAssistant` snapshot (Phase 9) so **Undo** is one click, 4) a last page offering Phase 17's opt-in suggestions and the Automation pane (no pressure, default off).
- **When shown** (question 19): once, at the first launch after Accessibility is granted and items are readable, **only if no layout was imported** (an Ice or earlier holzBar import skips it) and at least 6 items exist; "Not now" and "Don't show again" are explicit; the Menu Bar Layout pane has **Tidy Up…** to run it again, any time.
- **Pictures**: app icons only (no Screen Recording request at first launch; least privilege). If Screen Recording is already granted, real item images may be used.
- **macOS 27**: sections are per app, which matches the proposal unit; macOS 14 to 26 apply per item.

## Privacy and permission analysis

No permission beyond the Accessibility the app already holds; no Screen Recording asked. Reads other apps' `Info.plist` category keys (public, local). No history, no counters, no network, nothing stored except the user's accepted arrangement and a "shown" flag. Logs: counts only.

## Plans (outline)

1. **16-01 Classifier and proposal (Core)**: `ItemClassifier`, `CleanUpProposal`, `KnownItems.json` (system identifiers from a spike on the user's Macs), tests (system essentials stay, live items never hidden, unknown stays, existing arrangement is left alone).
2. **16-02 Assistant UI and first-launch rules**: the flow, snapshot and undo, skip and never-again, strings in five languages, VoiceOver-labelled groups.
3. **16-03 Re-run from Settings and docs**: "Tidy Up…" button, README feature line and gallery screenshot (real, from a Mac).

## Risks

- Wrong proposals annoy: conservative defaults, every item editable, one-click undo.
- The known-items table ages: it is only a hint; category mapping does the rest; tolerate absence.
- At first launch the item list may be incomplete (apps still starting): read again after the bar settles.
- No Mac in the environment: the system identifiers table is built by the user's spike.

## Open design questions

18. **How bold are the proposals?** A. Conservative: only system extras and known set-and-forget categories go to Hidden, everything else stays as is (**recommended**); B. Hide everything that is not an essential; C. Ask per category with nothing pre-selected.
19. **When does the assistant appear on its own?** A. Once at first launch, only without an imported layout (**recommended**); B. Never on its own, only from Settings; C. At every first launch including imports.
