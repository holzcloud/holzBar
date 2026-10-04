# Website rows for the comparison table, milestone 0.0.7 (planned, not released)

For https://holzcloud.ch/holzbar (holzcloud CMS, page 59 `holzbar`, German is the site language; English is the master). Matches `README.md` ("holzBar vs. Ice and Thaw") as of the planning of 0.0.7. **Do not push to the CMS before the release exists** (CLAUDE.md: never claim what is not true yet); until then 🔜 only means planned. When a phase ships, change its 🔜 to ✅ here and in the README (Phase 22 fact check). If a feature is dropped, delete its row.

## English

Addition to the intro sentence: "🔜 means planned for the next release (0.0.7): it is **not available yet**."

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| Rules that apply a profile or show items when a Wi-Fi network, an app, the time of day, the power source or a display matches (all or any) | ❌ | ✅ | 🔜 |
| Profile applied by a Focus filter | ❌ | ✅ | 🔜 |
| Scripts as a rule condition or action | ❌ | ✅ | 🔜 only from a folder you choose, after you confirm |
| Menu bar items of your own (clock, battery, CPU, Shortcut button) | ❌ | — | 🔜 |
| AppleScript dictionary | — | — | 🔜 |
| Touch ID or password to show hidden items | — | — | 🔜 |
| Smooth show and hide | — | — | 🔜 |

Note under the table: "The last three 🔜 rows are about features other menu bar apps have (AppleScript: Bartender 7 and SaneBar; Touch ID lock: SaneBar; smooth show and hide: Vanilla), not Ice or Thaw as far as their documentation says."

## Deutsch

Ergänzung zum Einleitungssatz: "🔜 heißt: für das nächste Release (0.0.7) geplant, **noch nicht verfügbar**."

| | Ice 0.11.12 | Thaw 3.0 Beta | holzBar |
|---|:---:|:---:|:---:|
| Regeln, die ein Profil anwenden oder Einträge zeigen, wenn ein WLAN, eine App, die Tageszeit, die Stromquelle oder ein Bildschirm passt (alle oder eine Bedingung) | ❌ | ✅ | 🔜 |
| Profil über einen Fokus-Filter anwenden | ❌ | ✅ | 🔜 |
| Skripte als Bedingung oder Aktion einer Regel | ❌ | ✅ | 🔜 nur aus einem Ordner, den du wählst, und erst nach deiner Bestätigung |
| Eigene Einträge in der Menüleiste (Uhr, Batterie, CPU, Kurzbefehl-Taste) | ❌ | — | 🔜 |
| AppleScript-Wörterbuch | — | — | 🔜 |
| Touch ID oder Passwort, um versteckte Einträge zu zeigen | — | — | 🔜 |
| Weiches Ein- und Ausblenden | — | — | 🔜 |

Hinweis unter der Tabelle: "Die letzten drei 🔜-Zeilen betreffen Funktionen, die andere Menüleisten-Apps haben (AppleScript: Bartender 7 und SaneBar; Touch-ID-Sperre: SaneBar; weiches Ein- und Ausblenden: Vanilla), nicht Ice oder Thaw, soweit deren Dokumentation das sagt."

## Sources for each claim

Ice: README roadmap (triggers and widgets planned) and feature list, github.com/jordanbaird/Ice. Thaw: README, github.com/thaw-app/Thaw (triggers including Focus and script result, profile binding to a Focus filter). Bartender 7: macbartender.com/Bartender7/ (AppleScript, widgets). SaneBar: github.com/sane-apps/SaneBar (Touch ID or password lock, AppleScript). Vanilla: MacStories roundup (fluid animations). Details in `COMPETITORS.md`.
