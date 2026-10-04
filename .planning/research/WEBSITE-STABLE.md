# Website changes for the stable 0.0.6

For https://holzcloud.ch/holzbar (holzcloud CMS, website 1, page 59 `holzbar`). German is the site language; English is the master; the other three languages (fr, it, rm) are translated by whoever applies this, with the same meaning. Apply after `v0.0.6` is released. It builds on `WEBSITE-UPDATE.md` (the 0.0.6-beta1 texts). Claims checked against `README.md`, `docs/release-notes/v0.0.6.md`, `docs/signing.md` and `SECURITY.md` at the commit that adds this file.

0.0.6 is the stable release. GitHub still flags it as a pre-release, because every 0.x release is one; that is expected, so never write "stable" to mean "not a pre-release".

## 1. Status line

Replace the beta status line with:

- **EN** — Version 0.0.6 — [Release on GitHub](https://github.com/holzcloud/holzBar/releases/tag/v0.0.6). Feedback counts on the [issue tracker](https://github.com/holzcloud/holzBar/issues). holzBar is a young fork of Ice and is actively developed, so a lot may still change before 1.0.
- **DE** — Version 0.0.6 — [Release auf GitHub](https://github.com/holzcloud/holzBar/releases/tag/v0.0.6). Rückmeldungen zählen auf dem [Issue-Tracker](https://github.com/holzcloud/holzBar/issues). holzBar ist ein junger Fork von Ice und wird aktiv weiterentwickelt, bis 1.0 kann sich noch einiges ändern.

No "Beta", no "Beta 1/2" anywhere. The release workflow does not write this line for 0.x pre-releases the way it does for later ones, so set it by hand (check `.github/cms-version.py` skips or handles it; if the script already writes the version, make sure it does not add "Beta").

## 2. Links

| What | URL |
|---|---|
| Release link (status line, install section) | https://github.com/holzcloud/holzBar/releases/tag/v0.0.6 |
| Download link | https://github.com/holzcloud/holzBar/releases/download/v0.0.6/holzBar-0.0.6.zip |

The zip name appears **twice per language page**: in the link text and in the link target (`holzBar-0.0.6.zip`, and `.../download/v0.0.6/holzBar-0.0.6.zip`). Replace every `v0.0.6-beta1`, `v0.0.6-beta2`, `holzBar-0.0.6-beta1.zip` and `holzBar-0.0.6-beta2.zip` the same way. In the verify command use `gh attestation verify holzBar-0.0.6.zip -R holzcloud/holzBar`.

Sentence next to the download link:

- **EN** — The archive [`holzBar-0.0.6.zip`](https://github.com/holzcloud/holzBar/releases/download/v0.0.6/holzBar-0.0.6.zip) is also available directly on the release.
- **DE** — Das Archiv [`holzBar-0.0.6.zip`](https://github.com/holzcloud/holzBar/releases/download/v0.0.6/holzBar-0.0.6.zip) gibt es auch direkt im Release.

## 3. Comparison table

- Delete the sentence "🔜 marks work in progress in this beta" and keep "— means not available or not documented":
  - **EN** — What the original [Ice](https://github.com/jordanbaird/Ice) 0.11.12 and the other active fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta do, and what holzBar adds. — means not available or not documented.
  - **DE** — Was das ursprüngliche [Ice](https://github.com/jordanbaird/Ice) 0.11.12 und der andere aktive Fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 Beta können, und was holzBar dazu bringt. — heisst: nicht vorhanden oder nicht dokumentiert.
  - Leave "Thaw 3.0 beta" in the column heading: it is Thaw's version.
- Row "Stable signature, so Accessibility survives updates": holzBar column 🔜 becomes ✅ (own certificate, `docs/signing.md`).
- Row "Build provenance attestation (`gh attestation verify`)": holzBar column 🔜 becomes ✅.
- Row "Fixes from 282 open bug reports" becomes:
  - **EN** — Every bug group of Ice's 282 open reports solved | — | — | ✅ confirmed on a Mac in 0.0.6, see the list
  - **DE** — Jede Fehlergruppe der 282 offenen Meldungen von Ice behoben | — | — | ✅ auf einem Mac bestätigt in 0.0.6, siehe Liste
- No 🔜 may remain in the table; if one does, it must be for something that is still not true.
- Everything else in the table stays (371 tests, 16.7 MB, 14, 15, 26 and 27).

## 4. Install section

Three paths, in this order, same wording as the README ("Updating") and the release notes:

- **EN** — **New install:** `brew tap holzcloud/holzbar https://github.com/holzcloud/holzBar`, then `brew trust --cask holzcloud/holzbar/holzbar`, then `brew install --cask holzbar`.
- **EN** — **Update from 0.0.6 beta 1 or 2:** `brew update && brew upgrade --cask holzbar`. The Accessibility permission stays.
- **EN** — **Update from 0.0.5:** different app and cask. Export the settings in the old app (Settings → Advanced → Export…), uninstall the old cask, install holzBar, grant Accessibility, import the file (Import…) and turn "Launch at login" on again.
- **DE** — **Neu installieren:** wie oben, drei Befehle.
- **DE** — **Von 0.0.6 Beta 1 oder 2 aktualisieren:** `brew update && brew upgrade --cask holzbar`. Die Bedienungshilfen-Freigabe bleibt erhalten.
- **DE** — **Von 0.0.5 aktualisieren:** andere App und anderes Cask. Einstellungen in der alten App exportieren (Einstellungen → Erweitert → Exportieren…), das alte Cask deinstallieren, holzBar installieren, Bedienungshilfen freigeben, die Datei importieren (Importieren…) und „Beim Anmelden öffnen“ wieder einschalten.

Keep the quarantine command (`xattr -dr com.apple.quarantine /Applications/holzBar.app`) and the supported systems: macOS 14 Sonoma to 27, checked in CI on 14, 15, 26 and 27.

Remove any remaining sentence that says signing is "coming", "from the next release" or "ad hoc"; add (optional, one line):

- **EN** — Releases are signed with holzBar's own certificate (SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`) and carry a build provenance attestation: `gh attestation verify holzBar-0.0.6.zip -R holzcloud/holzBar`.
- **DE** — Die Releases sind mit holzBars eigenem Zertifikat signiert (SHA-256 `e55f0df15060b8c06c6842ccee85e6bc9f86cbbda3bd408abf991457840b1d95`) und tragen einen Herkunftsnachweis des Builds: `gh attestation verify holzBar-0.0.6.zip -R holzcloud/holzBar`.

## 5. Known issues and limitations

Keep (unchanged):

- The macOS 27 privacy-indicator bullet (camera, microphone and screen recording indicator hidden while items are hidden).
- "Items can't be reordered on the bar itself on macOS 27, only assigned to sections", and the ~150 ms for system items.

Change:

| Passage | Change |
|---|---|
| "After an update, macOS may ask for Accessibility again" (macOS 27 limitations) | **EN** — Coming from 0.0.5 or earlier, macOS asks for Accessibility once more. **DE** — Beim Wechsel von 0.0.5 oder früher fragt macOS einmal erneut nach den Bedienungshilfen. |
| Any "this is the first release signed with holzBar's own certificate, Accessibility is asked again" | Delete (that was true for beta 1 only). |
| Any note that open bugs of Ice (empty layout editor on macOS 26, items that time out, stuck pointer, tint or shape in the wrong place, split shape on ultrawide displays, volume and brightness HUD, high CPU) are still being checked | Delete; they are solved and confirmed on a Mac. If the page has a "what is fixed" list, add them in plain words (README / release notes, "Fixed"). |
| "Beta", "beta release", "Preview" next to holzBar's own status | Remove. Keep the BETA tag of the item-spacing feature. |
| Machine-translation note (de, fr, it, rm) | Keep. |

## Checklist

- [ ] `v0.0.6` is released and its notes are `docs/release-notes/v0.0.6.md`.
- [ ] `grep -c 'holzBar-0.0.6.zip'` per language page is 2 (link text and target) and no `beta` remains next to holzBar's version.
- [ ] No 🔜 left in the comparison table of any language.
- [ ] Nothing on the page names the app's former name.
