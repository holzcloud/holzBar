# Translations

## Languages

holzBar is written in English and translated into the nineteen languages below. The app follows your Mac's language; **System Settings → General → Language & Region → Applications** lets you pick another one for holzBar alone.

<!-- languages:start -->
| Code | English name | Native name | Status |
| --- | --- | --- | --- |
| `de` | German | Deutsch | machine-made |
| `fr` | French | Français | machine-made |
| `it` | Italian | Italiano | machine-made |
| `rm` | Romansh | Rumantsch | machine-made |
| `es` | Spanish | Español | machine-made |
| `pt-BR` | Portuguese (Brazil) | Português (Brasil) | machine-made |
| `ja` | Japanese | 日本語 | machine-made |
| `zh-Hans` | Chinese (Simplified) | 简体中文 | machine-made |
| `ko` | Korean | 한국어 | machine-made |
| `ru` | Russian | Русский | machine-made |
| `nl` | Dutch | Nederlands | machine-made |
| `pl` | Polish | Polski | machine-made |
| `cs` | Czech | Čeština | machine-made |
| `hu` | Hungarian | Magyar | machine-made |
| `sv` | Swedish | Svenska | machine-made |
| `tr` | Turkish | Türkçe | machine-made |
| `id` | Indonesian | Bahasa Indonesia | machine-made |
| `uk` | Ukrainian | Українська | machine-made |
| `zh-Hant` | Chinese (Traditional) | 繁體中文 | machine-made |
<!-- languages:end -->

A date in the status column means a native speaker went through every string that existed on that day. Strings added or changed afterwards are machine-made until the next review round.

## What machine-made and reviewed mean

- **Machine-made**: the text was written by a language model, with a glossary built from Apple's own wording (`Translations/glossary.json`) and checked by script. No person who speaks the language has gone through it yet. All nineteen translations are machine-made today.
- **Reviewed through a date**: a review round covered every string that existed on that date, and a person who knows the language corrected what needed it. The record of such a round lives in `Translations/reviews/<code>.json`: for each string it covered, a short hash of the English text and the translation as it stood after the round. A string whose English text or translation changes later no longer matches the record and counts as unreviewed again.

No document calls a language reviewed for strings that no round covered.

## How a language is checked

Every pull request runs `python3 .github/scripts/strings-check.py`. For each of the three String Catalogs (`Localizable`, `InfoPlist` and `AppShortcuts`) it checks that:

- every text exists in every language of `Translations/languages.json`, and no catalog holds a language the registry lacks;
- format specifiers (`%@`, `%lld`) and the `${applicationName}` placeholder of the Shortcuts phrases are kept;
- plural forms are the ones the language's grammar needs (Unicode CLDR: for example one, few, many and other in Russian, Ukrainian and Polish, only other in Japanese);
- no sentence of more than three words is a copy of the English;
- the Xcode project's list of languages (`knownRegions`) and the table above agree with the registry.

These checks cannot judge style, tone or whether a word is the one a native speaker would choose. That is what a review round is for.

## Review a language

You can offer to review one language. You need a spreadsheet program and a GitHub account.

1. Open an issue with the form **Translation review** and say which language you know and how well.
2. The maintainer attaches a spreadsheet of the strings not yet reviewed: one row per text, with the English next to the current translation and a comment column. It opens in any spreadsheet program (UTF-8, comma separated).
3. Read the **translation** column and correct what is wrong. Check the meaning and the tone, that the words match the glossary's terms for the menu bar, Shelf, profile, rule and the like, that a title will fit on its button, and that placeholders such as `%@`, `%lld` and `${applicationName}` are untouched. The English column must not change. Write doubts into the comment column.
4. Save the file in the same format and attach it to the issue.

Nothing needs an account other than GitHub. A name is published only if you say so: the issue form asks whether the project may name you, and "do not name me" always works.

## Run a review round

For the maintainer. Put the language's code (for example `de` or `pt-BR`) where the commands say `CODE`.

```sh
# the strings not yet reviewed, as a sheet for the reviewer
python3 .github/scripts/translations.py export CODE --unreviewed --format csv --out CODE.csv

# the corrected sheet, back into the catalogs; the reviewer as written, or anonymous
python3 .github/scripts/translations.py apply CODE CODE-corrected.csv --reviewer "Name"

# the table above, and the check
python3 .github/scripts/translations.py status
python3 .github/scripts/translations.py status --markdown --write docs/translations.md
python3 .github/scripts/strings-check.py
```

`apply` refuses a changed English column, a lost or invented placeholder, a wrong plural form and an empty translation, and writes nothing then. With `--reviewer` it records the round in the language's ledger and sets the review date in `Translations/languages.json` once the ledger covers every string. Then commit the catalogs, the ledger, the registry and this page.

New texts reach all nineteen languages with `python3 .github/scripts/translations.py add-strings FILE`, which checks specifiers, placeholders and plural forms.

## Privacy and licence

A sheet holds the app's texts and no personal data. A corrected sheet is a contribution under the project's GPL-3.0 licence, like any other change. The tool only reads and writes files and never connects to the network, and neither does the app.
