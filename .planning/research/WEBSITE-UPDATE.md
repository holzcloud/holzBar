# Website update for 0.0.6-beta1 (FACT-01)

Final texts for https://holzcloud.ch/holzbar (holzcloud CMS, website 1, page 59 `holzbar`, a block page; German is the site language, the other four are translations). English is the master; every translation says the same thing. Everything here matches `README.md` at the Phase 7 fact check (commit "docs(07): fact check of the README before 0.0.6-beta1"). Replaces `WEBSITE-ROWS.md`.

Sources checked: the code at `e1c8ed8`, `Casks/holzbar.rb`, the workflows, CI run 37117883138 (app size 17,076 KB = 16.7 MB; 371 tests: 6 + 127 + 238; launch on macOS 14.8.9, 15.7.9, 26.6.2), Ice 0.11.12 (tag in this repository) and Thaw 3.0.0-beta.1 (sources: deployment target 26.0, 10 Swift packages, hardened runtime, `NSSplitViewItem` swizzling, Combine in 38 files).

Rules kept: 🔜 only for what is not true yet (stable signature, attestation: the user has not added the signing secrets); never claim the macOS 27 launch check before the first CI run with the `xcode-27` compat leg is green (push of Phase 7; if it fails, write "14, 15 and 26" until fixed).

## 0. Corrections elsewhere on the page (found in the current German page)

These passages on page 59 are no longer true and must change with the release:

| Where | Now | Change to |
|---|---|---|
| Status line | "Version 0.0.5, Beta — Release auf GitHub … holzBar hiess bis Oktober 2026 [former name] …" | "Version 0.0.6 Beta 1 — [Release auf GitHub](https://github.com/holzcloud/holzBar/releases/tag/v0.0.6-beta1). Rückmeldungen zählen auf dem [Issue-Tracker](https://github.com/holzcloud/holzBar/issues). holzBar ist ein junger Fork von Ice und wird aktiv weiterentwickelt, es kann sich noch einiges ändern." (the release workflow skips betas, so set it by hand) |
| Feature card "Automatisierung und Sync" | mentions the former URL scheme as an alias and "über iCloud Drive" | see section 3 (the alias is gone; sync through any folder) |
| Install | "Selbst bauen geht mit Xcode 26.6 auf macOS Tahoe 26.2 oder neuer" | "Selbst bauen geht mit Xcode 27 (macOS-27-SDK), wie in der CI; holzBar selbst läuft ab macOS 14." |
| Install | link to the 0.0.5 zip under the former name | "Das Archiv [`holzBar-0.0.6-beta1.zip`](https://github.com/holzcloud/holzBar/releases/download/v0.0.6-beta1/holzBar-0.0.6-beta1.zip) gibt es auch direkt im Release." |
| Install, migration subsection | trust of the old tap name, `brew migrate`, automatic import of the former app's settings | replace with section 4 (none of that exists any more: no rename mapping, no import of 0.0.5's settings) |
| Install, migration subsection | "Die Bildschirmfotos … stammen noch aus der Zeit, als die App [former name] hiess." | delete if the screenshots have been replaced with the ones in `Resources/Screenshots/`; otherwise "Einige Bildschirmfotos zeigen noch eine ältere Version." |
| Comparison | two columns (Ice, holzBar) with many 🔜 | the three-column table in section 2 |
| macOS 27 known limitations | four bullets | add the privacy indicator bullet (section 5) |

## 1. "Why holzBar?" (selling points)

Ten points, in this order. Icon, title, text.

### English (master)

| | |
|---|---|
| 📦 **Zero dependencies** | No third-party packages at all — every line that runs is in this repository. |
| 🦅 **Modern Swift 6** | Built with Swift 6.4 and Xcode 27, the latest stable Swift and the macOS 27 SDK, in Swift 6 language mode with data-race safety checked by the compiler; `@Observable` instead of Combine, one backend per macOS generation. |
| 🔒 **Never online** | No update checks, telemetry or analytics. A CI check proves there is no network code in the app. |
| 🛡️ **Least privilege** | Only Accessibility at first launch; Screen Recording only when a feature needs it. Hardened runtime, private logs. |
| 🍃 **Lean** | No polling where macOS sends an event, no mouse tracking unless you use it, nothing kept in memory that nobody shows. |
| 🪵 **macOS 27 compatible** | A dedicated backend for the redesigned macOS 27 menu bar drawn by `MenuBarAgent`. |
| ✅ **macOS 14 to 27, checked** | Every pull request launches the app on macOS 14, 15, 26 and 27 and runs the 371 unit tests on each. |
| ✨ **More features** | Profiles, folders, spacers, Zen mode, Shortcuts actions, a black menu bar, URL commands, settings sync through any folder. |
| 🌍 **Five languages** | English, German, French, Italian and Romansh. |
| 🍺 **Homebrew first** | Install and update with one command. |

### Deutsch

| | |
|---|---|
| 📦 **Keine Abhängigkeiten** | Kein einziges fremdes Paket — jede Zeile, die läuft, steht in diesem Repository. |
| 🦅 **Modernes Swift 6** | Gebaut mit Swift 6.4 und Xcode 27, dem neusten stabilen Swift und dem SDK von macOS 27, im Sprachmodus Swift 6, in dem der Compiler Data Races ausschliesst; `@Observable` statt Combine, ein Backend pro macOS-Generation. |
| 🔒 **Nie online** | Keine Update-Prüfung, keine Telemetrie, keine Analyse. Eine CI-Prüfung belegt, dass die App keinen Netzwerkcode enthält. |
| 🛡️ **Nur nötige Rechte** | Beim ersten Start nur die Bedienungshilfen; Bildschirmaufnahme erst, wenn eine Funktion sie braucht. Gehärtete Laufzeit, private Logs. |
| 🍃 **Schlank** | Keine Abfragen, wo macOS ein Ereignis meldet, keine Mausüberwachung, ausser man nutzt sie, nichts im Speicher, was niemand anzeigt. |
| 🪵 **Läuft auf macOS 27** | Ein eigenes Backend für die umgebaute Menüleiste von macOS 27, die `MenuBarAgent` zeichnet. |
| ✅ **macOS 14 bis 27, geprüft** | Jeder Pull Request startet die App auf macOS 14, 15, 26 und 27 und führt auf jedem die 371 Unit-Tests aus. |
| ✨ **Mehr Funktionen** | Profile, Ordner, Abstandhalter, Zen-Modus, Kurzbefehle-Aktionen, eine schwarze Menüleiste, URL-Befehle, Einstellungen über einen beliebigen Ordner abgleichen. |
| 🌍 **Fünf Sprachen** | Englisch, Deutsch, Französisch, Italienisch und Rätoromanisch. |
| 🍺 **Zuerst Homebrew** | Installieren und aktualisieren mit einem Befehl. |

### Français

| | |
|---|---|
| 📦 **Zéro dépendance** | Aucun paquet tiers — chaque ligne exécutée se trouve dans ce dépôt. |
| 🦅 **Swift 6 moderne** | Compilé avec Swift 6.4 et Xcode 27, le dernier Swift stable et le SDK de macOS 27, en mode de langage Swift 6 où le compilateur exclut les accès concurrents aux données ; `@Observable` au lieu de Combine, un backend par génération de macOS. |
| 🔒 **Jamais en ligne** | Aucune vérification de mises à jour, aucune télémétrie, aucune analyse. Un contrôle de la CI prouve que l'app ne contient aucun code réseau. |
| 🛡️ **Droits minimaux** | Seulement l'Accessibilité au premier lancement ; l'Enregistrement de l'écran uniquement quand une fonction en a besoin. Runtime renforcé, journaux privés. |
| 🍃 **Léger** | Aucune interrogation périodique là où macOS envoie un événement, aucun suivi de la souris si vous ne l'utilisez pas, rien en mémoire que personne n'affiche. |
| 🪵 **Compatible macOS 27** | Un backend dédié à la barre des menus repensée de macOS 27, dessinée par `MenuBarAgent`. |
| ✅ **macOS 14 à 27, vérifié** | Chaque pull request lance l'app sur macOS 14, 15, 26 et 27 et y exécute les 371 tests unitaires. |
| ✨ **Plus de fonctions** | Profils, dossiers, espaceurs, mode Zen, actions Raccourcis, barre des menus noire, commandes URL, synchronisation des réglages via n'importe quel dossier. |
| 🌍 **Cinq langues** | Anglais, allemand, français, italien et romanche. |
| 🍺 **Homebrew d'abord** | Installer et mettre à jour avec une seule commande. |

### Italiano

| | |
|---|---|
| 📦 **Zero dipendenze** | Nessun pacchetto di terze parti — ogni riga eseguita si trova in questo repository. |
| 🦅 **Swift 6 moderno** | Compilato con Swift 6.4 e Xcode 27, l'ultimo Swift stabile e l'SDK di macOS 27, in modalità linguaggio Swift 6, in cui il compilatore esclude i data race; `@Observable` invece di Combine, un backend per ogni generazione di macOS. |
| 🔒 **Mai online** | Nessun controllo degli aggiornamenti, nessuna telemetria, nessuna analisi. Un controllo della CI dimostra che l'app non contiene codice di rete. |
| 🛡️ **Permessi minimi** | Solo Accessibilità al primo avvio; Registrazione schermo solo quando una funzione ne ha bisogno. Runtime rafforzato, log privati. |
| 🍃 **Leggero** | Nessun polling dove macOS invia un evento, nessun tracciamento del mouse se non lo usi, niente in memoria che nessuno mostra. |
| 🪵 **Compatibile con macOS 27** | Un backend dedicato alla nuova barra dei menu di macOS 27, disegnata da `MenuBarAgent`. |
| ✅ **Da macOS 14 a 27, verificato** | Ogni pull request avvia l'app su macOS 14, 15, 26 e 27 ed esegue su ciascuno i 371 test unitari. |
| ✨ **Più funzioni** | Profili, cartelle, spaziatori, modalità Zen, azioni di Comandi rapidi, barra dei menu nera, comandi URL, sincronizzazione delle impostazioni tramite qualsiasi cartella. |
| 🌍 **Cinque lingue** | Inglese, tedesco, francese, italiano e romancio. |
| 🍺 **Prima Homebrew** | Installare e aggiornare con un solo comando. |

### Rumantsch

| | |
|---|---|
| 📦 **Naginas dependenzas** | Nagin pachet extern — mintga lingia che vegn exequida è en quest repository. |
| 🦅 **Swift 6 modern** | Construì cun Swift 6.4 e Xcode 27, il pli nov Swift stabil e il SDK da macOS 27, en il modus da lingua Swift 6, en il qual il compilader excluda data races; `@Observable` empè da Combine, in backend per mintga generaziun da macOS. |
| 🔒 **Mai online** | Naginas controllas d'actualisaziuns, nagina telemetria, naginas analisas. Ina controlla da la CI cumprova che l'app na cuntegna nagin code da rait. |
| 🛡️ **Mo ils dretgs necessaris** | Al emprim start mo l'Accessibladad; la registraziun dal visur pir cur ch'ina funcziun la dovra. Runtime rinforzà, logs privats. |
| 🍃 **Svelt** | Nagin polling nua che macOS tramet in eveniment, nagina observaziun da la mieur, nun che Vus la duvrais, nagut en la memoria che nagin na mussa. |
| 🪵 **Funcziuna sin macOS 27** | In agen backend per la nova trav da menu da macOS 27, ch'il `MenuBarAgent` dissegna. |
| ✅ **macOS 14 fin 27, controllà** | Mintga pull request avra l'app sin macOS 14, 15, 26 e 27 ed exequescha sin mintgin ils 371 tests unitars. |
| ✨ **Dapli funcziuns** | Profils, ordinaturs, distanziaders, modus Zen, acziuns da Cumonds svelts, ina trav da menu naira, cumonds URL, sincronisaziun dals parameters tras in ordinatur tenor giavisch. |
| 🌍 **Tschintg linguas** | Englais, tudestg, franzos, talian e rumantsch. |
| 🍺 **Homebrew l'emprim** | Installar ed actualisar cun in cumond. |

## 2. "holzBar vs. Ice and Thaw" (comparison table)

Columns: (row) · Ice 0.11.12 · Thaw 3.0 beta · holzBar. Symbols stay as they are in every language (✅ ❌ — 🔜). Links: "see the list" → https://github.com/holzcloud/holzBar/blob/main/docs/upstream-bugs.md; `docs/signing.md` → https://github.com/holzcloud/holzBar/blob/main/docs/signing.md.

### English (master)

What the original [Ice](https://github.com/jordanbaird/Ice) 0.11.12 and the other active fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta do, and what holzBar adds. 🔜 marks work in progress in this beta; — means not available or not documented.

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| **Compatibility** | | | |
| macOS 14 – 26 | ✅ | macOS 26 only | ✅ |
| **macOS 27** (new menu bar drawn by `MenuBarAgent`) | ❌ | ✅ | ✅ |
| Launched and unit tested in CI on every supported macOS | ❌ | — | ✅ 14, 15, 26 and 27 |
| **Features** | | | |
| Hidden and always-hidden sections, Ice Bar / holzBar Shelf, search, appearance | ✅ | ✅ | ✅ |
| Layout profiles | ❌ | ✅ | ✅ |
| Groups and spacers | ❌ | ✅ | ✅ |
| Folders with their own icon and colour; item images of your choice | ❌ | ✅ | ✅ |
| Choose where new items appear | ❌ | — | ✅ |
| Bar only on some displays, notch overflow | ❌ | — | ✅ |
| Black menu bar, rounded screen corners | ❌ | corners only | ✅ |
| Dashed and dotted borders, wallpaper, accent and glass tints | ❌ | ✅ | ✅ |
| Show hidden items on low battery or when offline | ❌ | — | ✅ |
| URL commands and Raycast | ❌ | ✅ | ✅ |
| Zen mode (also while presenting) | ❌ | ✅ | ✅ |
| Hotkeys per profile and per item | ❌ | ✅ | ✅ |
| Shortcuts actions (App Intents) | ❌ | ✅ | ✅ |
| Profiles bound to a display or a Space | ❌ | ✅ | ✅ |
| Open an item by letter | ❌ | ✅ | ✅ |
| Layout editor and Shelf from the keyboard, undo, VoiceOver actions | ❌ | ✅ | ✅ |
| Opened items stay up to 30 s, or open without showing the item | ❌ | ✅ | ✅ |
| Show an item briefly when it changes | ❌ | ✅ | ✅ opt-in per item |
| Export and import settings | ❌ | ✅ | ✅ |
| Settings sync: iCloud Drive or any synced folder | ❌ | ❌ | ✅ |
| Languages | English | many, through Crowdin | English, German, French, Italian, Romansh |
| Keep Live Activities visible | ❌ | — | ✅ experimental |
| Show on scroll with a mouse wheel | ❌ | — | ✅ |
| Search tolerates typos and abbreviations | ✅ (library) | ✅ | ✅ (built in) |
| Refuses hotkeys macOS cannot register, and says why | ❌ | — | ✅ |
| Input never stalls when an app hangs | ❌ | ✅ | ✅ |
| Items keep their section when an app changes its title | ❌ | ✅ | ✅ |
| Pauses while the screen is locked, settles after wake | ❌ | ✅ | ✅ |
| Look on every desktop, follows the icons, steps aside in fullscreen | ❌ | ✅ | ✅ |
| No screen-recording indicator when showing or hiding (macOS 27) | — | ✅ | ✅ |
| Hover and click on a second display (macOS 27) | — | ✅ | ✅ |
| URL commands ask before they change anything lasting; no URL ends Zen mode during a screen share | — | — | ✅ |
| Validated hotkeys, colours and numbers in imported and synced settings (no crash loop from bad settings) | ❌ | — | ✅ |
| **Privacy and permissions** | | | |
| Network connections (update checks, telemetry, analytics) | Sparkle update checks | Sparkle update checks | **none** — enforced by CI |
| Personal data (app names, item titles, paths) in logs | partly public | — | private, enforced by CI |
| Asks for Screen Recording only when a feature needs it | ❌ | — | ✅ |
| Hardened runtime (no injected code or libraries) | ✅ | ✅ | ✅ (checked by CI) |
| Settings import accepts only known keys of the right type, in range | — (no import) | — | ✅ |
| Settings import and sync can't turn sync on; the sync file carries no computer name | — (no sync) | — | ✅ |
| Menu bar item service accepts only holzBar's own code | team check only | — | team or exact code hash |
| Fix for the permissions loop | ❌ | — | ✅ |
| **Code and resources** | | | |
| Swift packages | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern and 5 from Apple) | **none** |
| Swift language mode | Swift 5 | Swift 6 | Swift 6 (data-race safety checked by the compiler), built with Swift 6.4 and Xcode 27 |
| State management | Combine | `@Observable` and Combine | `@Observable`, no Combine |
| Mouse event tap when "Show on hover" is off | always running | — | off |
| Timers and polling while nothing is shown | yes | — | only while needed |
| Settings sync checks for changes | — (no sync) | — (no sync) | when the synced folder delivers them, no polling |
| Settings migration | 6 version steps at every launch | — | once, while importing Ice settings |
| Runtime patching of AppKit (method swizzling) | yes | yes | none |
| Item images in memory | kept | — | released when unused |
| Unit tests run on every change | none | ✅ | ✅ 371 |
| App size | — | — | 16.7 MB |
| **Distribution and maintenance** | | | |
| Install and update with Homebrew | ✅ | ✅ | ✅ |
| Updates | Sparkle (dialog can hang on macOS 26) | Sparkle | Homebrew |
| Fixes from 282 open bug reports | — | — | see the list |
| Signed with a Developer ID | ✅ | — | ❌ (ad hoc; the cask handles it) |
| Stable signature, so Accessibility survives updates | ✅ | — | 🔜 (own certificate, `docs/signing.md`) |
| Build provenance attestation (`gh attestation verify`) | ❌ | — | 🔜 from the next release |

### Deutsch

Was das ursprüngliche [Ice](https://github.com/jordanbaird/Ice) 0.11.12 und der andere aktive Fork [Thaw](https://github.com/thaw-app/Thaw) 3.0 Beta können, und was holzBar dazu bringt. 🔜 markiert, was in dieser Beta noch in Arbeit ist; — heisst: nicht vorhanden oder nicht dokumentiert.

| | Ice 0.11.12 | Thaw 3.0 Beta | holzBar |
|---|:---:|:---:|:---:|
| **Kompatibilität** | | | |
| macOS 14 – 26 | ✅ | nur macOS 26 | ✅ |
| **macOS 27** (neue Menüleiste, gezeichnet von `MenuBarAgent`) | ❌ | ✅ | ✅ |
| In der CI auf jedem unterstützten macOS gestartet und getestet | ❌ | — | ✅ 14, 15, 26 und 27 |
| **Funktionen** | | | |
| Versteckte und immer versteckte Zone, Ice Bar / holzBar Shelf, Suche, Aussehen | ✅ | ✅ | ✅ |
| Layout-Profile | ❌ | ✅ | ✅ |
| Gruppen und Abstandhalter | ❌ | ✅ | ✅ |
| Ordner mit eigenem Symbol und eigener Farbe; Symbolbilder nach Wahl | ❌ | ✅ | ✅ |
| Platz für neue Symbole wählen | ❌ | — | ✅ |
| Leiste nur auf gewählten Bildschirmen, Notch-Überlauf | ❌ | — | ✅ |
| Schwarze Menüleiste, runde Bildschirmecken | ❌ | nur Ecken | ✅ |
| Gestrichelte und gepunktete Ränder, Tönung aus Hintergrundbild, Akzentfarbe und Glas | ❌ | ✅ | ✅ |
| Versteckte Symbole zeigen bei leerem Akku oder ohne Netz | ❌ | — | ✅ |
| URL-Befehle und Raycast | ❌ | ✅ | ✅ |
| Zen-Modus (auch beim Präsentieren) | ❌ | ✅ | ✅ |
| Tastenkürzel pro Profil und pro Symbol | ❌ | ✅ | ✅ |
| Kurzbefehle-Aktionen (App Intents) | ❌ | ✅ | ✅ |
| Profile an einen Bildschirm oder einen Space gebunden | ❌ | ✅ | ✅ |
| Ein Symbol per Buchstabe öffnen | ❌ | ✅ | ✅ |
| Layout-Editor und Shelf mit der Tastatur, Widerrufen, VoiceOver-Aktionen | ❌ | ✅ | ✅ |
| Geöffnete Symbole bleiben bis zu 30 s, oder öffnen, ohne das Symbol zu zeigen | ❌ | ✅ | ✅ |
| Ein Symbol kurz zeigen, wenn es sich ändert | ❌ | ✅ | ✅ pro Symbol einschaltbar |
| Einstellungen exportieren und importieren | ❌ | ✅ | ✅ |
| Einstellungen abgleichen: iCloud Drive oder ein beliebiger synchronisierter Ordner | ❌ | ❌ | ✅ |
| Sprachen | Englisch | viele, über Crowdin | Englisch, Deutsch, Französisch, Italienisch, Rätoromanisch |
| Live-Aktivitäten sichtbar lassen | ❌ | — | ✅ experimentell |
| Zeigen beim Scrollen mit dem Mausrad | ❌ | — | ✅ |
| Suche verzeiht Tippfehler und Abkürzungen | ✅ (Bibliothek) | ✅ | ✅ (eingebaut) |
| Lehnt Tastenkürzel ab, die macOS nicht registrieren kann, und sagt warum | ❌ | — | ✅ |
| Eingaben stocken nie, wenn eine App hängt | ❌ | ✅ | ✅ |
| Symbole behalten ihre Zone, wenn eine App ihren Titel ändert | ❌ | ✅ | ✅ |
| Pausiert bei gesperrtem Bildschirm, ordnet sich nach dem Aufwachen | ❌ | ✅ | ✅ |
| Aussehen auf jedem Schreibtisch, folgt den Symbolen, weicht im Vollbild | ❌ | ✅ | ✅ |
| Keine Bildschirmaufnahme-Anzeige beim Zeigen oder Verstecken (macOS 27) | — | ✅ | ✅ |
| Hover und Klick auf einem zweiten Bildschirm (macOS 27) | — | ✅ | ✅ |
| URL-Befehle fragen, bevor sie etwas Bleibendes ändern; keine URL beendet den Zen-Modus während einer Bildschirmfreigabe | — | — | ✅ |
| Geprüfte Tastenkürzel, Farben und Zahlen in importierten und abgeglichenen Einstellungen (kein Absturz in Schleife durch schlechte Einstellungen) | ❌ | — | ✅ |
| **Datenschutz und Rechte** | | | |
| Netzwerkverbindungen (Update-Prüfung, Telemetrie, Analyse) | Sparkle prüft auf Updates | Sparkle prüft auf Updates | **keine** — von der CI erzwungen |
| Persönliche Daten (App-Namen, Symboltitel, Pfade) in den Logs | teils öffentlich | — | privat, von der CI erzwungen |
| Bildschirmaufnahme erst, wenn eine Funktion sie braucht | ❌ | — | ✅ |
| Gehärtete Laufzeit (kein eingeschleuster Code, keine fremden Bibliotheken) | ✅ | ✅ | ✅ (von der CI geprüft) |
| Einstellungs-Import nimmt nur bekannte Schlüssel vom richtigen Typ und im gültigen Bereich | — (kein Import) | — | ✅ |
| Import und Abgleich können den Abgleich nicht einschalten; die Sync-Datei enthält keinen Computernamen | — (kein Abgleich) | — | ✅ |
| Der Dienst für Menüleisten-Symbole nimmt nur holzBars eigenen Code an | nur Team-Prüfung | — | Team oder exakter Code-Hash |
| Fix für die Berechtigungsschleife | ❌ | — | ✅ |
| **Code und Ressourcen** | | | |
| Swift-Pakete | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern und 5 von Apple) | **keine** |
| Swift-Sprachmodus | Swift 5 | Swift 6 | Swift 6 (der Compiler schliesst Data Races aus), gebaut mit Swift 6.4 und Xcode 27 |
| Zustandsverwaltung | Combine | `@Observable` und Combine | `@Observable`, kein Combine |
| Mausüberwachung, wenn „Show on hover“ aus ist | läuft immer | — | aus |
| Timer und Abfragen, solange nichts angezeigt wird | ja | — | nur wenn nötig |
| Abgleich bemerkt Änderungen | — (kein Abgleich) | — (kein Abgleich) | sobald der synchronisierte Ordner sie liefert, ohne Abfragen |
| Migration der Einstellungen | 6 Versionsschritte bei jedem Start | — | einmal, beim Import der Ice-Einstellungen |
| AppKit zur Laufzeit verändert (Method Swizzling) | ja | ja | nein |
| Symbolbilder im Speicher | behalten | — | freigegeben, wenn unbenutzt |
| Unit-Tests bei jeder Änderung | keine | ✅ | ✅ 371 |
| App-Grösse | — | — | 16,7 MB |
| **Verteilung und Pflege** | | | |
| Installation und Updates über Homebrew | ✅ | ✅ | ✅ |
| Updates | Sparkle (Dialog hängt unter macOS 26) | Sparkle | Homebrew |
| Behobene Fehler aus 282 offenen Meldungen | — | — | siehe Liste |
| Mit Developer ID signiert | ✅ | — | ❌ (ad hoc, das Cask regelt das) |
| Stabile Signatur, damit die Bedienungshilfen Updates überstehen | ✅ | — | 🔜 (eigenes Zertifikat, `docs/signing.md`) |
| Herkunftsnachweis des Builds (`gh attestation verify`) | ❌ | — | 🔜 ab dem nächsten Release |

### Français

Ce que font l'[Ice](https://github.com/jordanbaird/Ice) 0.11.12 d'origine et l'autre fork actif [Thaw](https://github.com/thaw-app/Thaw) 3.0 bêta, et ce qu'ajoute holzBar. 🔜 signale un travail en cours dans cette bêta ; — signifie non disponible ou non documenté.

| | Ice 0.11.12 | Thaw 3.0 bêta | holzBar |
|---|:---:|:---:|:---:|
| **Compatibilité** | | | |
| macOS 14 – 26 | ✅ | macOS 26 seulement | ✅ |
| **macOS 27** (nouvelle barre des menus dessinée par `MenuBarAgent`) | ❌ | ✅ | ✅ |
| Lancé et testé dans la CI sur chaque macOS pris en charge | ❌ | — | ✅ 14, 15, 26 et 27 |
| **Fonctions** | | | |
| Sections masquée et toujours masquée, Ice Bar / holzBar Shelf, recherche, apparence | ✅ | ✅ | ✅ |
| Profils de disposition | ❌ | ✅ | ✅ |
| Groupes et espaceurs | ❌ | ✅ | ✅ |
| Dossiers avec leur propre icône et couleur ; images d'éléments au choix | ❌ | ✅ | ✅ |
| Choisir où apparaissent les nouveaux éléments | ❌ | — | ✅ |
| Barre sur certains écrans seulement, débordement de l'encoche | ❌ | — | ✅ |
| Barre des menus noire, coins d'écran arrondis | ❌ | coins seulement | ✅ |
| Bordures en tirets et en pointillés, teintes du fond d'écran, de la couleur d'accentuation et du verre | ❌ | ✅ | ✅ |
| Afficher les éléments masqués quand la batterie est faible ou hors ligne | ❌ | — | ✅ |
| Commandes URL et Raycast | ❌ | ✅ | ✅ |
| Mode Zen (aussi pendant une présentation) | ❌ | ✅ | ✅ |
| Raccourcis clavier par profil et par élément | ❌ | ✅ | ✅ |
| Actions Raccourcis (App Intents) | ❌ | ✅ | ✅ |
| Profils liés à un écran ou à un Space | ❌ | ✅ | ✅ |
| Ouvrir un élément par une lettre | ❌ | ✅ | ✅ |
| Éditeur de disposition et Shelf au clavier, annulation, actions VoiceOver | ❌ | ✅ | ✅ |
| Les éléments ouverts restent jusqu'à 30 s, ou s'ouvrent sans être affichés | ❌ | ✅ | ✅ |
| Afficher brièvement un élément quand il change | ❌ | ✅ | ✅ à activer par élément |
| Exporter et importer les réglages | ❌ | ✅ | ✅ |
| Synchronisation des réglages : iCloud Drive ou n'importe quel dossier synchronisé | ❌ | ❌ | ✅ |
| Langues | anglais | nombreuses, via Crowdin | anglais, allemand, français, italien, romanche |
| Garder les Activités en direct visibles | ❌ | — | ✅ expérimental |
| Afficher en défilant avec une molette de souris | ❌ | — | ✅ |
| La recherche tolère les fautes de frappe et les abréviations | ✅ (bibliothèque) | ✅ | ✅ (intégrée) |
| Refuse les raccourcis que macOS ne peut pas enregistrer, et dit pourquoi | ❌ | — | ✅ |
| La saisie ne se bloque jamais quand une app ne répond plus | ❌ | ✅ | ✅ |
| Les éléments gardent leur section quand une app change son titre | ❌ | ✅ | ✅ |
| En pause quand l'écran est verrouillé, se stabilise après la sortie de veille | ❌ | ✅ | ✅ |
| Apparence sur chaque bureau, suit les icônes, s'efface en plein écran | ❌ | ✅ | ✅ |
| Pas d'indicateur d'enregistrement de l'écran en affichant ou en masquant (macOS 27) | — | ✅ | ✅ |
| Survol et clic sur un deuxième écran (macOS 27) | — | ✅ | ✅ |
| Les commandes URL demandent avant de changer quoi que ce soit de durable ; aucune URL ne met fin au mode Zen pendant un partage d'écran | — | — | ✅ |
| Raccourcis, couleurs et nombres vérifiés dans les réglages importés et synchronisés (pas de plantage en boucle dû à de mauvais réglages) | ❌ | — | ✅ |
| **Confidentialité et autorisations** | | | |
| Connexions réseau (mises à jour, télémétrie, analyse) | vérifications Sparkle | vérifications Sparkle | **aucune** — imposé par la CI |
| Données personnelles (noms d'apps, titres d'éléments, chemins) dans les journaux | en partie publiques | — | privées, imposé par la CI |
| Demande l'Enregistrement de l'écran seulement quand une fonction en a besoin | ❌ | — | ✅ |
| Runtime renforcé (aucun code ni bibliothèque injectés) | ✅ | ✅ | ✅ (vérifié par la CI) |
| L'import des réglages n'accepte que les clés connues, du bon type, dans les limites | — (pas d'import) | — | ✅ |
| L'import et la synchronisation ne peuvent pas activer la synchronisation ; le fichier de synchronisation ne contient pas le nom de l'ordinateur | — (pas de synchro) | — | ✅ |
| Le service des éléments de la barre des menus n'accepte que le code de holzBar | contrôle de l'équipe seulement | — | équipe ou empreinte exacte du code |
| Correction de la boucle d'autorisations | ❌ | — | ✅ |
| **Code et ressources** | | | |
| Paquets Swift | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern et 5 d'Apple) | **aucun** |
| Mode de langage Swift | Swift 5 | Swift 6 | Swift 6 (le compilateur exclut les accès concurrents aux données), compilé avec Swift 6.4 et Xcode 27 |
| Gestion de l'état | Combine | `@Observable` et Combine | `@Observable`, sans Combine |
| Suivi des événements de la souris quand « Show on hover » est désactivé | toujours actif | — | désactivé |
| Minuteries et interrogations quand rien n'est affiché | oui | — | seulement si nécessaire |
| La synchronisation détecte les changements | — (pas de synchro) | — (pas de synchro) | quand le dossier synchronisé les livre, sans interrogation |
| Migration des réglages | 6 étapes de version à chaque lancement | — | une fois, lors de l'import des réglages d'Ice |
| Modification d'AppKit à l'exécution (method swizzling) | oui | oui | aucune |
| Images des éléments en mémoire | conservées | — | libérées si inutilisées |
| Tests unitaires à chaque changement | aucun | ✅ | ✅ 371 |
| Taille de l'app | — | — | 16,7 Mo |
| **Distribution et maintenance** | | | |
| Installation et mises à jour avec Homebrew | ✅ | ✅ | ✅ |
| Mises à jour | Sparkle (le dialogue peut se bloquer sous macOS 26) | Sparkle | Homebrew |
| Corrections parmi 282 rapports de bogues ouverts | — | — | voir la liste |
| Signé avec un Developer ID | ✅ | — | ❌ (ad hoc ; le cask s'en charge) |
| Signature stable, pour que l'Accessibilité survive aux mises à jour | ✅ | — | 🔜 (certificat propre, `docs/signing.md`) |
| Attestation de provenance du build (`gh attestation verify`) | ❌ | — | 🔜 dès la prochaine version |

### Italiano

Cosa fanno l'[Ice](https://github.com/jordanbaird/Ice) 0.11.12 originale e l'altro fork attivo [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta, e cosa aggiunge holzBar. 🔜 indica un lavoro in corso in questa beta; — significa non disponibile o non documentato.

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| **Compatibilità** | | | |
| macOS 14 – 26 | ✅ | solo macOS 26 | ✅ |
| **macOS 27** (nuova barra dei menu disegnata da `MenuBarAgent`) | ❌ | ✅ | ✅ |
| Avviato e testato nella CI su ogni macOS supportato | ❌ | — | ✅ 14, 15, 26 e 27 |
| **Funzioni** | | | |
| Sezioni nascosta e sempre nascosta, Ice Bar / holzBar Shelf, ricerca, aspetto | ✅ | ✅ | ✅ |
| Profili di disposizione | ❌ | ✅ | ✅ |
| Gruppi e spaziatori | ❌ | ✅ | ✅ |
| Cartelle con icona e colore propri; immagini degli elementi a scelta | ❌ | ✅ | ✅ |
| Scegliere dove compaiono i nuovi elementi | ❌ | — | ✅ |
| Barra solo su alcuni schermi, overflow della tacca | ❌ | — | ✅ |
| Barra dei menu nera, angoli dello schermo arrotondati | ❌ | solo angoli | ✅ |
| Bordi tratteggiati e punteggiati, tinte da sfondo, colore d'accento e vetro | ❌ | ✅ | ✅ |
| Mostrare gli elementi nascosti con batteria scarica o senza rete | ❌ | — | ✅ |
| Comandi URL e Raycast | ❌ | ✅ | ✅ |
| Modalità Zen (anche durante una presentazione) | ❌ | ✅ | ✅ |
| Abbreviazioni da tastiera per profilo e per elemento | ❌ | ✅ | ✅ |
| Azioni di Comandi rapidi (App Intents) | ❌ | ✅ | ✅ |
| Profili legati a uno schermo o a uno Space | ❌ | ✅ | ✅ |
| Aprire un elemento con una lettera | ❌ | ✅ | ✅ |
| Editor della disposizione e Shelf da tastiera, annulla, azioni VoiceOver | ❌ | ✅ | ✅ |
| Gli elementi aperti restano fino a 30 s, o si aprono senza mostrarli | ❌ | ✅ | ✅ |
| Mostrare brevemente un elemento quando cambia | ❌ | ✅ | ✅ attivabile per elemento |
| Esportare e importare le impostazioni | ❌ | ✅ | ✅ |
| Sincronizzazione delle impostazioni: iCloud Drive o qualsiasi cartella sincronizzata | ❌ | ❌ | ✅ |
| Lingue | inglese | molte, tramite Crowdin | inglese, tedesco, francese, italiano, romancio |
| Mantenere visibili le Attività in tempo reale | ❌ | — | ✅ sperimentale |
| Mostrare scorrendo con la rotella del mouse | ❌ | — | ✅ |
| La ricerca tollera errori di battitura e abbreviazioni | ✅ (libreria) | ✅ | ✅ (integrata) |
| Rifiuta le abbreviazioni che macOS non può registrare, e spiega perché | ❌ | — | ✅ |
| L'input non si blocca mai quando un'app non risponde | ❌ | ✅ | ✅ |
| Gli elementi mantengono la sezione quando un'app cambia titolo | ❌ | ✅ | ✅ |
| In pausa con lo schermo bloccato, si assesta dopo il risveglio | ❌ | ✅ | ✅ |
| Aspetto su ogni scrivania, segue le icone, si fa da parte a schermo intero | ❌ | ✅ | ✅ |
| Nessun indicatore di registrazione dello schermo mostrando o nascondendo (macOS 27) | — | ✅ | ✅ |
| Passaggio del mouse e clic su un secondo schermo (macOS 27) | — | ✅ | ✅ |
| I comandi URL chiedono prima di cambiare qualcosa di duraturo; nessun URL termina la modalità Zen durante una condivisione dello schermo | — | — | ✅ |
| Abbreviazioni, colori e numeri verificati nelle impostazioni importate e sincronizzate (nessun crash in loop per impostazioni errate) | ❌ | — | ✅ |
| **Privacy e permessi** | | | |
| Connessioni di rete (aggiornamenti, telemetria, analisi) | controlli Sparkle | controlli Sparkle | **nessuna** — imposto dalla CI |
| Dati personali (nomi di app, titoli degli elementi, percorsi) nei log | in parte pubblici | — | privati, imposto dalla CI |
| Chiede la Registrazione schermo solo quando una funzione ne ha bisogno | ❌ | — | ✅ |
| Runtime rafforzato (nessun codice o libreria iniettati) | ✅ | ✅ | ✅ (verificato dalla CI) |
| L'importazione accetta solo chiavi note, del tipo giusto, nei limiti | — (nessuna importazione) | — | ✅ |
| Importazione e sincronizzazione non possono attivare la sincronizzazione; il file di sincronizzazione non contiene il nome del computer | — (nessuna sincronizzazione) | — | ✅ |
| Il servizio degli elementi della barra dei menu accetta solo il codice di holzBar | solo controllo del team | — | team o hash esatto del codice |
| Correzione del ciclo dei permessi | ❌ | — | ✅ |
| **Codice e risorse** | | | |
| Pacchetti Swift | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern e 5 di Apple) | **nessuno** |
| Modalità linguaggio Swift | Swift 5 | Swift 6 | Swift 6 (il compilatore esclude i data race), compilato con Swift 6.4 e Xcode 27 |
| Gestione dello stato | Combine | `@Observable` e Combine | `@Observable`, senza Combine |
| Monitoraggio degli eventi del mouse con «Show on hover» disattivato | sempre attivo | — | disattivato |
| Timer e polling quando non si mostra nulla | sì | — | solo se necessario |
| La sincronizzazione rileva le modifiche | — (nessuna sincronizzazione) | — (nessuna sincronizzazione) | quando la cartella sincronizzata le consegna, senza polling |
| Migrazione delle impostazioni | 6 passi di versione a ogni avvio | — | una volta, importando le impostazioni di Ice |
| Modifica di AppKit in esecuzione (method swizzling) | sì | sì | nessuna |
| Immagini degli elementi in memoria | conservate | — | rilasciate se inutilizzate |
| Test unitari a ogni modifica | nessuno | ✅ | ✅ 371 |
| Dimensione dell'app | — | — | 16,7 MB |
| **Distribuzione e manutenzione** | | | |
| Installazione e aggiornamenti con Homebrew | ✅ | ✅ | ✅ |
| Aggiornamenti | Sparkle (la finestra può bloccarsi su macOS 26) | Sparkle | Homebrew |
| Correzioni tra 282 segnalazioni di bug aperte | — | — | vedi l'elenco |
| Firmato con un Developer ID | ✅ | — | ❌ (ad hoc; ci pensa il cask) |
| Firma stabile, così l'Accessibilità sopravvive agli aggiornamenti | ✅ | — | 🔜 (certificato proprio, `docs/signing.md`) |
| Attestazione di provenienza della build (`gh attestation verify`) | ❌ | — | 🔜 dalla prossima versione |

### Rumantsch

Quai che l'[Ice](https://github.com/jordanbaird/Ice) 0.11.12 original ed il auter fork activ [Thaw](https://github.com/thaw-app/Thaw) 3.0 beta fan, e quai che holzBar porta ultra da quai. 🔜 marca lavur che n'è anc betg terminada en questa beta; — munta: betg disponibel u betg documentà.

| | Ice 0.11.12 | Thaw 3.0 beta | holzBar |
|---|:---:|:---:|:---:|
| **Cumpatibilitad** | | | |
| macOS 14 – 26 | ✅ | mo macOS 26 | ✅ |
| **macOS 27** (nova trav da menu dissegnada dal `MenuBarAgent`) | ❌ | ✅ | ✅ |
| Avert e testà en la CI sin mintga macOS sustegnì | ❌ | — | ✅ 14, 15, 26 e 27 |
| **Funcziuns** | | | |
| Zona zuppentada e adina zuppentada, Ice Bar / holzBar Shelf, tschertga, apparientscha | ✅ | ✅ | ✅ |
| Profils da layout | ❌ | ✅ | ✅ |
| Gruppas e distanziaders | ❌ | ✅ | ✅ |
| Ordinaturs cun agen simbol ed agena colur; maletgs dals simbols tenor giavisch | ❌ | ✅ | ✅ |
| Tscherner nua che novs simbols cumparan | ❌ | — | ✅ |
| Trav mo sin tscherts visurs, surplaina dal notch | ❌ | — | ✅ |
| Trav da menu naira, chantuns dal visur arrundads | ❌ | mo chantuns | ✅ |
| Urs stritgads e puntads, tintas dal maletg da fund, da la colur d'accent e da vaider | ❌ | ✅ | ✅ |
| Mussar simbols zuppentads cun battaria bassa u senza rait | ❌ | — | ✅ |
| Cumonds URL e Raycast | ❌ | ✅ | ✅ |
| Modus Zen (er durant ina preschentaziun) | ❌ | ✅ | ✅ |
| Cumbinaziuns da tastas per profil e per simbol | ❌ | ✅ | ✅ |
| Acziuns da Cumonds svelts (App Intents) | ❌ | ✅ | ✅ |
| Profils colliads cun in visur u in Space | ❌ | ✅ | ✅ |
| Avrir in simbol cun ina letra | ❌ | ✅ | ✅ |
| Editur da layout e Shelf cun la tastatura, revocar, acziuns da VoiceOver | ❌ | ✅ | ✅ |
| Simbols averts restan fin 30 s, u s'avran senza vegnir mussads | ❌ | ✅ | ✅ |
| Mussar curt in simbol cur ch'el sa mida | ❌ | ✅ | ✅ activabel per simbol |
| Exportar ed importar ils parameters | ❌ | ✅ | ✅ |
| Sincronisaziun dals parameters: iCloud Drive u in ordinatur sincronisà tenor giavisch | ❌ | ❌ | ✅ |
| Linguas | englais | bleras, tras Crowdin | englais, tudestg, franzos, talian, rumantsch |
| Laschar visibels las Activitads live | ❌ | — | ✅ experimental |
| Mussar cun scrollar cun la rodella da la mieur | ❌ | — | ✅ |
| La tschertga tolerescha sbagls da tippar ed abreviaziuns | ✅ (biblioteca) | ✅ | ✅ (integrada) |
| Refusa cumbinaziuns da tastas che macOS na po betg registrar, e di pertge | ❌ | — | ✅ |
| Las endataziuns na stagneschan mai cur ch'ina app na reagescha betg | ❌ | ✅ | ✅ |
| Ils simbols tegnan lur zona cur ch'ina app mida ses titel | ❌ | ✅ | ✅ |
| Fa pausa cur ch'il visur è bloccà, s'ordina suenter il sveglier | ❌ | ✅ | ✅ |
| Apparientscha sin mintga desktop, suonda ils simbols, sa retira en il modus da visur cumplain | ❌ | ✅ | ✅ |
| Nagin indicatur da registraziun dal visur cun mussar u zuppentar (macOS 27) | — | ✅ | ✅ |
| Hover e clic sin in segund visur (macOS 27) | — | ✅ | ✅ |
| Cumonds URL dumondan avant che midar insatge durabel; nagin URL na terminescha il modus Zen durant ina deliberaziun dal visur | — | — | ✅ |
| Cumbinaziuns da tastas, colurs e dumbers controllads en parameters importads e sincronisads (nagin crash en circul pervia da parameters nuschaivels) | ❌ | — | ✅ |
| **Protecziun da datas e dretgs** | | | |
| Colliaziuns da rait (actualisaziuns, telemetria, analisas) | controllas da Sparkle | controllas da Sparkle | **naginas** — garantì da la CI |
| Datas persunalas (nums d'apps, titels da simbols, vias) en ils logs | per part publicas | — | privatas, garantì da la CI |
| Dumonda la registraziun dal visur pir cur ch'ina funcziun la dovra | ❌ | — | ✅ |
| Runtime rinforzà (nagin code u nagina biblioteca injectads) | ✅ | ✅ | ✅ (controllà da la CI) |
| L'import da parameters accepta mo clavs enconuschentas dal dretg tip ed en la dretga zona | — (nagin import) | — | ✅ |
| Import e sincronisaziun na pon betg activar la sincronisaziun; la datoteca da sincronisaziun na cuntegna nagin num da computer | — (nagina sincronisaziun) | — | ✅ |
| Il servetsch dals simbols da la trav da menu accepta mo l'agen code da holzBar | mo controlla dal team | — | team u hash exact dal code |
| Correctura per la circulaziun da las permissiuns | ❌ | — | ✅ |
| **Code e resursas** | | | |
| Pachets Swift | 5 | 10 (Sparkle, AXSwift6, CompactSlider, Ifrit, LaunchAtLogin-Modern e 5 dad Apple) | **nagins** |
| Modus da lingua Swift | Swift 5 | Swift 6 | Swift 6 (il compilader excluda data races), construì cun Swift 6.4 e Xcode 27 |
| Administraziun dal stadi | Combine | `@Observable` e Combine | `@Observable`, senza Combine |
| Observaziun da la mieur cur che «Show on hover» è deactivà | adina activa | — | deactivada |
| Timers e polling cur che nagut na vegn mussà | gea | — | mo sch'igl è necessari |
| La sincronisaziun s'accorscha da midadas | — (nagina sincronisaziun) | — (nagina sincronisaziun) | cur che l'ordinatur sincronisà las furnescha, senza polling |
| Migraziun dals parameters | 6 pass da versiun a mintga start | — | ina giada, cun importar ils parameters dad Ice |
| Midar AppKit durant la runtime (method swizzling) | gea | gea | nagut |
| Maletgs dals simbols en la memoria | tegnids | — | liberads sch'els na vegnan betg duvrads |
| Tests unitars tar mintga midada | nagins | ✅ | ✅ 371 |
| Grondezza da l'app | — | — | 16,7 MB |
| **Distribuziun e mantegniment** | | | |
| Installar ed actualisar cun Homebrew | ✅ | ✅ | ✅ |
| Actualisaziuns | Sparkle (il dialog po stagnar sin macOS 26) | Sparkle | Homebrew |
| Correcturas da 282 annunzias da sbagls avertas | — | — | vesair la glista |
| Signà cun in Developer ID | ✅ | — | ❌ (ad hoc; il cask regla quai) |
| Signatura stabla, uschia che l'Accessibladad surviva actualisaziuns | ✅ | — | 🔜 (agen certificat, `docs/signing.md`) |
| Cumprova da la derivanza dal build (`gh attestation verify`) | ❌ | — | 🔜 a partir da la proxima versiun |

## 3. Feature card "Automation and sync" (replaces the current one)

- **EN** — `holzbar://` commands and ready-made Raycast scripts that ask before they change anything lasting, Zen mode and Shortcuts actions, hidden items shown automatically when the battery runs low or the network drops, settings exported or synced between Macs through iCloud Drive or any folder your Macs sync.
- **DE** — `holzbar://`-Befehle und fertige Raycast-Skripte, die fragen, bevor sie etwas Bleibendes ändern, Zen-Modus und Kurzbefehle-Aktionen, versteckte Symbole automatisch zeigen, wenn der Akku leer wird oder das Netz ausfällt, Einstellungen exportieren oder zwischen Macs abgleichen — über iCloud Drive oder einen beliebigen Ordner, den die Macs synchronisieren.
- **FR** — Commandes `holzbar://` et scripts Raycast prêts à l'emploi qui demandent avant de changer quoi que ce soit de durable, mode Zen et actions Raccourcis, éléments masqués affichés automatiquement quand la batterie faiblit ou que le réseau tombe, réglages exportés ou synchronisés entre Mac via iCloud Drive ou n'importe quel dossier que vos Mac synchronisent.
- **IT** — Comandi `holzbar://` e script Raycast pronti che chiedono prima di cambiare qualcosa di duraturo, modalità Zen e azioni di Comandi rapidi, elementi nascosti mostrati automaticamente quando la batteria si scarica o la rete cade, impostazioni esportate o sincronizzate tra Mac tramite iCloud Drive o qualsiasi cartella che i tuoi Mac sincronizzano.
- **RM** — Cumonds `holzbar://` e scripts da Raycast pronts che dumondan avant che midar insatge durabel, modus Zen ed acziuns da Cumonds svelts, simbols zuppentads mussads automaticamain cur che la battaria va a fin u che la rait croda, parameters exportads u sincronisads tranter Macs tras iCloud Drive u in ordinatur tenor giavisch che Voss Macs sincroniseschan.

## 4. Install: updating from 0.0.5 (replaces the migration subsection)

- **EN** — **Updating from 0.0.5.** 0.0.5 was published under the app's former name, as a different cask and app, so `brew upgrade` does not replace it and holzBar does not take over its settings. To keep your layout, hotkeys and appearance, export them in the old app (**Settings → Advanced → Export…**). Quit it and uninstall its cask (`brew list --cask` shows its name), install holzBar as above, grant Accessibility again, and import the file in **Settings → Advanced → Import…**. Settings of the original Ice are imported on the first launch anyway.
- **DE** — **Von 0.0.5 aktualisieren.** 0.0.5 erschien noch unter dem früheren Namen der App, als anderes Cask und andere App; `brew upgrade` ersetzt es deshalb nicht, und holzBar übernimmt seine Einstellungen nicht. Wer Layout, Tastenkürzel und Aussehen behalten will, exportiert sie in der alten App (**Settings → Advanced → Export…**). Dann die alte App beenden und ihr Cask entfernen (`brew list --cask` zeigt seinen Namen), holzBar wie oben installieren, die Bedienungshilfen erneut erlauben und die Datei unter **Settings → Advanced → Import…** importieren. Die Einstellungen des ursprünglichen Ice übernimmt holzBar beim ersten Start ohnehin.
- **FR** — **Mettre à jour depuis 0.0.5.** La 0.0.5 a été publiée sous l'ancien nom de l'app, comme un autre cask et une autre app : `brew upgrade` ne la remplace donc pas et holzBar ne reprend pas ses réglages. Pour garder disposition, raccourcis et apparence, exportez-les dans l'ancienne app (**Settings → Advanced → Export…**). Quittez-la et désinstallez son cask (`brew list --cask` affiche son nom), installez holzBar comme ci-dessus, accordez de nouveau l'Accessibilité et importez le fichier dans **Settings → Advanced → Import…**. Les réglages de l'Ice d'origine sont de toute façon importés au premier lancement.
- **IT** — **Aggiornare dalla 0.0.5.** La 0.0.5 è stata pubblicata con il nome precedente dell'app, come un altro cask e un'altra app: perciò `brew upgrade` non la sostituisce e holzBar non ne riprende le impostazioni. Per conservare disposizione, abbreviazioni e aspetto, esportali nella vecchia app (**Settings → Advanced → Export…**). Chiudila e disinstalla il suo cask (`brew list --cask` ne mostra il nome), installa holzBar come sopra, concedi di nuovo l'Accessibilità e importa il file in **Settings → Advanced → Import…**. Le impostazioni dell'Ice originale vengono comunque importate al primo avvio.
- **RM** — **Actualisar da 0.0.5.** 0.0.5 è cumparida anc sut il num pli vegl da l'app, sco auter cask ed autra app; `brew upgrade` na la remplazza perquai betg, e holzBar na surpiglia betg ses parameters. Tgi che vul tegnair layout, cumbinaziuns da tastas ed apparientscha, als exporta en la veglia app (**Settings → Advanced → Export…**). Lura terminar la veglia app ed allontanar ses cask (`brew list --cask` mussa ses num), installar holzBar sco survart, permetter danovamain l'Accessibladad ed importar la datoteca sut **Settings → Advanced → Import…**. Ils parameters da l'Ice original surpiglia holzBar en mintga cas al emprim start.

## 5. macOS 27 known limitations: new bullet

- **EN** — The privacy indicator is hidden while items are hidden: while holzBar hides any item on macOS 27, Control Centre does not show its indicator for the camera, the microphone and screen recording; the small green dot beside the clock still shows the camera. It comes back while holzBar hides no item.
- **DE** — Die Datenschutzanzeige verschwindet, solange Symbole versteckt sind: Versteckt holzBar unter macOS 27 ein Symbol, zeigt das Kontrollzentrum seine Anzeige für Kamera, Mikrofon und Bildschirmaufnahme nicht; der kleine grüne Punkt neben der Uhr zeigt die Kamera weiterhin an. Die Anzeige kehrt zurück, sobald holzBar kein Symbol mehr versteckt.
- **FR** — L'indicateur de confidentialité disparaît tant que des éléments sont masqués : quand holzBar masque un élément sous macOS 27, le Centre de contrôle n'affiche pas son indicateur pour la caméra, le micro et l'enregistrement de l'écran ; le petit point vert à côté de l'horloge signale toujours la caméra. L'indicateur revient dès que holzBar ne masque plus aucun élément.
- **IT** — L'indicatore della privacy scompare finché ci sono elementi nascosti: quando holzBar nasconde un elemento su macOS 27, Centro di Controllo non mostra il suo indicatore per fotocamera, microfono e registrazione dello schermo; il piccolo punto verde accanto all'orologio segnala comunque la fotocamera. L'indicatore torna quando holzBar non nasconde più alcun elemento.
- **RM** — L'indicatur da la protecziun da datas svanescha uschè ditg che simbols èn zuppentads: cur che holzBar zuppenta sin macOS 27 in simbol, na mussa il Center da controlla betg ses indicatur per camera, microfon e registraziun dal visur; il pitschen punct verd sper l'ura mussa vinavant la camera. L'indicatur returna uschespert che holzBar na zuppenta nagin simbol pli.

## Checklist before publishing

- [ ] CI of the Phase 7 push is green, including `compat (xcode-27)`; otherwise use "14, 15 and 26" in the selling point and the compatibility row.
- [ ] `v0.0.6-beta1` is released (status line link, zip link).
- [ ] Section 0 corrections applied in all five languages (only German and the sections above are spelled out; translate section 0's German replacements the same way).
- [ ] Nothing on the page still names the former app name except where section 0 removes it.
