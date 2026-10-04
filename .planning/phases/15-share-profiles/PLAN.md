---
phase: 15-share-profiles
status: planned (outline; run /gsd-plan-phase 15)
requirements: [SHARE-01, SHARE-02, SHARE-03, SHARE-04]
depends_on: Phase 9 (snapshot before importing a profile); `SettingsSchema` and `URLPrompt` rules
---

# Phase 15: Share profiles

## Goal

The user can export one layout profile as a small file (and, if decided, a `holzbar://` link), send it to someone, and the receiver can import it after a confirmation. It is data only: it never runs anything.

## Why

Thaw lists "import and export profiles for backup or sharing" (github.com/thaw-app/Thaw). holzBar exports and imports all settings, but a single profile cannot be shared without carrying everything else (hotkeys, appearance, folders).

## What a shared profile contains (decided by this design, question 25-26)

Only: `format` version, the profile name (cleaned, at most 80 characters) and a list of **bundle identifier -> section** (0 visible, 1 hidden, 2 always hidden). Matching on another Mac is by bundle identifier, because item tags and titles differ between Macs; on macOS 14 to 26 the section is applied to all items of that app, on macOS 27 per application (which is how that backend works anyway).

Never carried: display or Space bindings (UUIDs of this Mac's hardware), Wi-Fi names, automation rules, item rules, scripts or script bindings, hotkeys, group definitions, item images, paths, the computer's or the user's name, usage data, snapshots. There is no option to include them in v1. Bundle identifiers still reveal which apps a person uses, so the export sheet shows the list of apps with checkboxes before the file is written (question 26).

## Design

- **Format**: JSON, UTF-8, at most 64 KB, at most 500 entries, `.holzbarprofile` with its own exported type (`UTExportedTypeDeclarations` and `CFBundleDocumentTypes` in Info.plist, conforming to `public.json`; K, confirm). Decoded only with `Codable`, no property-list object graphs, no `NSKeyedUnarchiver`.
- **Validation (pure, Swift Testing, reusing `SettingsSchema.NumberRule`)**: known `format`, name cleaned like `URLPrompt` (control characters removed, shortened), each bundle id a reverse-DNS string of allowed characters up to 255, section in range, duplicates removed, size and count limits; anything else rejects the whole file with a plain message.
- **Import**: opening a file (Finder double-click, the "Import Profile…" button, drag onto the Layout pane) or, if shipped, a link, shows a sheet: "Import profile 'Work' with 24 apps (18 are installed on this Mac)", the list, and Import / Cancel. A name clash offers Rename (default) or Replace; it never replaces silently. A `beforeImport` snapshot is taken (Phase 9) only when the profile is applied, not when imported (importing a profile does not move items; the user applies it as any other).
- **Link** (question 25): `holzbar://import-profile?data=<base64url of the compact JSON>`; the link route is an input path like any URL command: it only ever opens the same confirmation sheet, is rate limited (one prompt at a time, as `URLPrompt`), is disabled while Zen mode is on, and limited to a few KB. Larger profiles use the file.
- **Export**: from the profile's row in the Layout pane: "Share…" opens the app list with checkboxes, then the save panel (or Copy Link). Nothing is written without that step.
- **Docs**: README (feature, formats, what is never included), `SECURITY.md` entry (confused-deputy prompt, file as untrusted input), the importer's "what is in this file" view.

## Privacy and permission analysis

No permission beyond the save/open panels (user-selected files, no sandbox here). No network (the link is text the user sends themselves). The file lists app identifiers, so the sheet shows them first. Logs: counts only.

## Plans (outline)

1. **15-01 Format and validation (Core)**: `SharedProfile`, encoder/decoder, limits, cleaning; tests with hostile input (huge names, bad bundle ids, nesting, duplicates, extra keys, `1e300`-style numbers, wrong types).
2. **15-02 Export UI and file type**: app checkboxes, save panel, document type in Info.plist.
3. **15-03 Import UI**: open handler, confirmation sheet, name clash, apply flow, optional link route with prompt rules; five languages; docs and SECURITY.md.

## Risks

- A file association is a new input path: double-clicking a file from the internet must show the sheet and do nothing else; quarantine already marks downloaded files.
- Link size limits and chat apps mangling long URLs.
- Profiles are partly meaningless on a Mac without those apps: say so in the sheet.
- `Info.plist` and UTI declarations are checked only by CI build and the user's Finder.

## Open design questions

25. **File, link, or both?** A. File only in this milestone; the link later if wanted (**recommended**: smaller input surface); B. File and a `holzbar://import-profile` link; C. Link only.
26. **How are the apps in the file chosen?** A. A list with checkboxes before saving, everything checked (**recommended**); B. Always all apps, no choice; C. Only apps that are not Apple's.
