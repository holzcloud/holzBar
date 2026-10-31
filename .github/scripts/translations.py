#!/usr/bin/env python3
#
# translations.py
#
# The review tool of holzBar's translations. holzBar speaks the languages of
# Translations/languages.json (the registry); this script keeps the three String
# Catalogs in holzBar/Resources honest and lets a person who knows a language
# review it in rounds. It never connects to anything: it reads and writes files.
#
#   codes             print the registry's language codes, the source first
#   roundtrip-check   prove that the tool writes the catalogs exactly as Xcode does
#   export CODE       write a sheet (csv or json) of one language's texts
#   apply CODE FILE   validate corrected sheets, write the catalogs, and with
#                     --reviewer record the round in Translations/reviews/CODE.json
#   add-strings FILE  add new English keys with their translations in every language
#   status            strings, reviewed share, copies of English, changed strings
#   report            translations that are much longer than the English
#   self-test         every rule above, proven on fixtures in a temporary folder
#
# A language is called reviewed only for the strings a review round really
# covered. The ledger holds, per string, a hash of the English text together with
# the translation as it stood after the round; a string whose English text or
# translation changed afterwards no longer matches and is unreviewed again.
# Everything else is machine-made.
#
# strings-check.py imports the rules of this file, so the check in CI and the
# tool cannot disagree. Python standard library only; no syntax newer than 3.9.

import argparse
import contextlib
import copy
import csv
import datetime
import hashlib
import io
import json
import os
import re
import sys
import tempfile
import unicodedata

CLDR_VERSION = "49"

RESOURCES = "holzBar/Resources"
CATALOGS = ("Localizable", "InfoPlist", "AppShortcuts")
REGISTRY = "Translations/languages.json"
REVIEWS = "Translations/reviews"
PROJECT = "holzBar.xcodeproj/project.pbxproj"

MAX_SHEET_BYTES = 5 * 1024 * 1024
HASH_LENGTH = 16
COPY_WORDS = 3  # a copy of the English is an error only above this many words
LONG_RATIO = 1.4  # German is the design concept's yardstick
REPORT_MIN_ENGLISH = 4  # shorter English texts ("OK") say nothing about layout
MAX_REVIEWER = 80

CATEGORY_ORDER = ("zero", "one", "two", "few", "many", "other")

# Plural categories per language, from Unicode CLDR 49 "Language Plural Rules"
# (unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html), read
# on 2026-10-31. Each value is (needed, allowed): `needed` are the categories an
# integer count uses (`other` always: a catalog needs it as the fallback), and
# `allowed` are all categories CLDR defines for the language. French, Italian,
# Spanish and Portuguese add `many` for exact millions; Czech adds `many` for
# fractions. A catalog may carry an allowed category but must carry every needed
# one.
_OO = frozenset({"one", "other"})
_OMO = frozenset({"one", "many", "other"})
_OFMO = frozenset({"one", "few", "many", "other"})
_O = frozenset({"other"})
PLURALS = {
    "en": (_OO, _OO),
    "de": (_OO, _OO),
    "fr": (_OO, _OMO),
    "it": (_OO, _OMO),
    "es": (_OO, _OMO),
    "pt-BR": (_OO, _OMO),
    "rm": (_OO, _OO),
    "nl": (_OO, _OO),
    "sv": (_OO, _OO),
    "hu": (_OO, _OO),
    "tr": (_OO, _OO),
    "pl": (_OFMO, _OFMO),
    "ru": (_OFMO, _OFMO),
    "uk": (_OFMO, _OFMO),
    "cs": (frozenset({"one", "few", "other"}), _OFMO),
    "id": (_O, _O),
    "ja": (_O, _O),
    "ko": (_O, _O),
    "zh-Hans": (_O, _O),
    "zh-Hant": (_O, _O),
}

# A format specifier as Xcode writes it into a catalog key.
SPECIFIER = r"%(?:\d+\$)?(?:@|lld|llu|ld|lu|d|u|lf|f|g)"
SPECIFIER_RE = re.compile(SPECIFIER)
# The placeholder of App Shortcuts phrases.
PLACEHOLDER_RE = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*\}")
CODE_RE = re.compile(r"^[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-[A-Z]{2})?$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class ToolError(Exception):
    """A problem to show to the user; nothing has been written."""


# --- the shared rules -------------------------------------------------------


def specifiers(text):
    """The kinds of the format specifiers of a text; a translation may number
    them (%1$@, %2$@) to change their order."""
    return sorted(re.sub(r"\d+\$", "", found) for found in SPECIFIER_RE.findall(text.replace("%%", "")))


def placeholders(text):
    return sorted(PLACEHOLDER_RE.findall(text))


def is_sub_multiset(part, whole):
    pool = list(whole)
    for item in part:
        if item not in pool:
            return False
        pool.remove(item)
    return True


def word_count(text):
    """The words of a text: tokens with a letter, without specifiers and placeholders."""
    cleaned = PLACEHOLDER_RE.sub(" ", SPECIFIER_RE.sub(" ", text))
    return sum(1 for token in cleaned.split() if any(char.isalpha() for char in token))


def is_copy(english, translation):
    """A sentence of more than three words copied from the English text. Short
    copies (OK, Widget, Cloud) are loanwords and allowed."""
    return translation == english and word_count(english) > COPY_WORDS


def plural_rule(code):
    if code not in PLURALS:
        raise ToolError(f"no plural rule for the language {code!r}; add its CLDR row to PLURALS")
    return PLURALS[code]


def ordered_categories(categories):
    return sorted(categories, key=lambda name: CATEGORY_ORDER.index(name) if name in CATEGORY_ORDER else 99)


def plural_problems(code, forms):
    """Messages for a set of plural categories that does not fit the language."""
    needed, allowed = plural_rule(code)
    present = set(forms)
    messages = []
    lacking = needed - present
    if lacking:
        messages.append(f"the {code} plural forms lack {ordered_categories(lacking)} (CLDR {CLDR_VERSION})")
    foreign = present - allowed
    if foreign:
        messages.append(f"the {code} plural forms hold {ordered_categories(foreign)}, which {code} does not use (CLDR {CLDR_VERSION})")
    return messages


def english_side(key, entry):
    """The English text of an entry: the key, or the plural forms of `en`."""
    localization = entry.get("localizations", {}).get("en")
    if localization and "variations" in localization:
        return {name: form["stringUnit"]["value"] for name, form in localization["variations"]["plural"].items()}
    return key


def language_side(entry, code):
    """The text of an entry in a language: a string, a dict of plural forms, or None."""
    localization = entry.get("localizations", {}).get(code)
    if localization is None:
        return None
    if "variations" in localization:
        return {name: form["stringUnit"]["value"] for name, form in localization["variations"]["plural"].items()}
    if "stringUnit" in localization:
        return localization["stringUnit"].get("value", "")
    return None


def translation_problems(key, english, code, side):
    """Messages for one language's text of an entry (without the key in front)."""
    if side is None:
        return [f"has no {code} translation"]
    if isinstance(english, dict) != isinstance(side, dict):
        return [f"the {code} translation does not match the plural structure of the English text"]
    messages = []
    if isinstance(english, dict):
        messages.extend(plural_problems(code, side))
        for name, text in side.items():
            english_form = english.get(name, english.get("other", key))
            if name == "other":
                if specifiers(text) != specifiers(key):
                    messages.append(f"the {code} translation changes the format specifiers")
                if placeholders(text) != placeholders(key):
                    messages.append(f"the {code} translation changes the placeholders {placeholders(key)}")
            else:
                if not is_sub_multiset(specifiers(text), specifiers(key)):
                    messages.append(f"the {code} translation changes the format specifiers")
                if not is_sub_multiset(placeholders(text), placeholders(key)):
                    messages.append(f"the {code} translation changes the placeholders {placeholders(key)}")
            if is_copy(english_form, text):
                messages.append(f"the {code} {name} form copies the English text")
        return messages
    if specifiers(side) != specifiers(key):
        messages.append(f"the {code} translation changes the format specifiers")
    if placeholders(side) != placeholders(key):
        messages.append(f"the {code} translation changes the placeholders {placeholders(key)}")
    if is_copy(key, side):
        messages.append(f"the {code} translation copies the English text")
    return messages


# --- files ------------------------------------------------------------------


def dumps_catalog(data):
    """A catalog exactly as Xcode writes it (no key sorting)."""
    return json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n"


def dumps_plain(data):
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as file:
            return file.read()
    except (OSError, ValueError) as error:
        raise ToolError(f"{path}: {error}")


def read_json(path):
    try:
        return json.loads(read_text(path))
    except ValueError as error:
        raise ToolError(f"{path}: not JSON: {error}")


def write_all(files):
    """Writes {path: text} so that a failure leaves no half-written file: every
    text goes to a temporary file in its folder first, then each is renamed."""
    staged = []
    try:
        for path, text in files.items():
            folder = os.path.dirname(path) or "."
            os.makedirs(folder, exist_ok=True)
            handle, temporary = tempfile.mkstemp(dir=folder, prefix=".tmp-")
            staged.append((temporary, path))
            with os.fdopen(handle, "w", encoding="utf-8", newline="") as file:
                file.write(text)
        for temporary, path in staged:
            os.replace(temporary, path)
        staged = []
    finally:
        for temporary, _ in staged:
            with contextlib.suppress(OSError):
                os.remove(temporary)


def catalog_path(root, name):
    return os.path.join(root, RESOURCES, name + ".xcstrings")


def registry_path(root):
    return os.path.join(root, REGISTRY)


def ledger_path(root, code):
    return os.path.join(root, REVIEWS, code + ".json")


def read_registry(root):
    """Reads and validates the registry; raises ToolError with the first problem."""
    data = read_json(registry_path(root))
    where = REGISTRY
    if not isinstance(data, dict) or data.get("version") != 1 or data.get("source") != "en":
        raise ToolError(f"{where}: needs version 1 and source en")
    languages = data.get("languages")
    if not isinstance(languages, list) or not languages:
        raise ToolError(f"{where}: no languages")
    seen = set()
    for index, language in enumerate(languages):
        code = language.get("code") if isinstance(language, dict) else None
        if not isinstance(code, str) or not CODE_RE.match(code):
            raise ToolError(f"{where}: malformed language code {code!r}")
        if code in seen:
            raise ToolError(f"{where}: duplicate language code {code!r}")
        seen.add(code)
        if (index == 0) != (code == "en"):
            raise ToolError(f"{where}: en must be listed first, and only first, with role source")
        for field in ("englishName", "nativeName"):
            if not isinstance(language.get(field), str) or not language[field].strip():
                raise ToolError(f"{where}: {code} needs a {field}")
        if index == 0:
            if language.get("role") != "source":
                raise ToolError(f"{where}: en needs the role source")
            continue
        if code not in PLURALS:
            raise ToolError(f"{where}: {code} has no plural rule in translations.py")
        reviewed = language.get("reviewedThrough")
        if reviewed is not None and not (isinstance(reviewed, str) and DATE_RE.match(reviewed)):
            raise ToolError(f"{where}: {code} reviewedThrough must be null or a date")
        if not isinstance(language.get("note", ""), str):
            raise ToolError(f"{where}: {code} note must be text")
    return data


def target_codes(registry):
    return [language["code"] for language in registry["languages"][1:]]


def language_entry(registry, code):
    for language in registry["languages"]:
        if language["code"] == code:
            return language
    raise ToolError(f"{code!r} is not in the registry {REGISTRY}")


def known_regions(root):
    text = read_text(os.path.join(root, PROJECT))
    found = re.search(r"knownRegions = \((.*?)\);", text, re.DOTALL)
    if not found:
        raise ToolError(f"{PROJECT}: no knownRegions list")
    return [line.strip().rstrip(",").strip().strip('"') for line in found.group(1).splitlines() if line.strip()]


def region_problems(registry, regions):
    """Messages when knownRegions is not en, Base and the registry's codes."""
    expected = ["en", "Base"] + target_codes(registry)
    missing = [code for code in expected if code not in regions]
    extra = [code for code in regions if code not in expected]
    messages = []
    if missing:
        messages.append(f"knownRegions of the Xcode project lacks {missing}")
    if extra:
        messages.append(f"knownRegions of the Xcode project holds {extra}, which the registry does not list")
    return messages


class Repo:
    """The registry and the three catalogs of one root."""

    def __init__(self, root):
        self.root = root
        self.registry = read_registry(root)
        self.texts = {}
        self.catalogs = {}
        for name in CATALOGS:
            path = catalog_path(root, name)
            text = read_text(path)
            try:
                self.catalogs[name] = json.loads(text)
            except ValueError as error:
                raise ToolError(f"{path}: not a String Catalog: {error}")
            self.texts[name] = text

    def targets(self):
        return target_codes(self.registry)

    def entries(self, catalogs=None):
        """Yields (catalog, key, entry) for every translatable entry."""
        for name in CATALOGS:
            for key, entry in (catalogs or self.catalogs)[name]["strings"].items():
                if entry.get("shouldTranslate") is not False:
                    yield name, key, entry


# --- the ledger -------------------------------------------------------------


def entry_hash(english, translated):
    """16 hex digits of the SHA-256 of the canonical JSON of the pair (English
    text or forms, the language's text or forms)."""
    blob = json.dumps([english, translated], sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()[:HASH_LENGTH]


def ledger_key(catalog, key):
    return f"{catalog}|{key}"


def read_ledger(root, code):
    path = ledger_path(root, code)
    if not os.path.exists(path):
        return None
    data = read_json(path)
    if not isinstance(data, dict) or data.get("language") != code or not isinstance(data.get("strings"), dict):
        raise ToolError(f"{path}: not a review ledger of {code}")
    return data


def current_hash(repo, catalog, key, entry, code):
    side = language_side(entry, code)
    if side is None:
        return None
    return entry_hash(english_side(key, entry), side)


def unreviewed_entries(repo, code, ledger, catalogs=None):
    """The (catalog, key) pairs the ledger does not cover with a matching hash."""
    covered = ledger["strings"] if ledger else {}
    result = set()
    for catalog, key, entry in repo.entries(catalogs):
        current = current_hash(repo, catalog, key, entry, code)
        if current is None or covered.get(ledger_key(catalog, key)) != current:
            result.add((catalog, key))
    return result


# --- sheets -----------------------------------------------------------------


def sheet_rows(repo, code, catalogs=None):
    """Every row of a language, numbered from 1. A plural entry has one row per
    category the language needs or already holds."""
    needed, _ = plural_rule(code)
    rows = []
    for catalog, key, entry in repo.entries(catalogs):
        english = english_side(key, entry)
        side = language_side(entry, code)
        comment = entry.get("comment", "")
        note = "Keep every ${...} placeholder exactly once, unchanged." if "${" in key else ""
        if isinstance(english, dict):
            present = side if isinstance(side, dict) else {}
            for name in ordered_categories(needed | set(present)):
                text = f"Plural form '{name}'. {comment}".strip()
                rows.append(
                    {
                        "catalog": catalog,
                        "key": key,
                        "form": name,
                        "english": english.get(name, english.get("other", key)),
                        "translation": present.get(name, ""),
                        "comment": f"{text} {note}".strip(),
                    }
                )
        else:
            rows.append(
                {
                    "catalog": catalog,
                    "key": key,
                    "form": "",
                    "english": key,
                    "translation": side if isinstance(side, str) else "",
                    "comment": f"{comment} {note}".strip(),
                }
            )
    for number, row in enumerate(rows, 1):
        row["row"] = number
    return rows


def write_sheet(path, rows, fmt):
    if fmt == "json":
        text = dumps_plain(rows)
        write_all({path: text})
        return
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer)
    writer.writerow(["catalog", "key", "form", "english", "translation", "comment"])
    for row in rows:
        writer.writerow([row[name] for name in ("catalog", "key", "form", "english", "translation", "comment")])
    write_all({path: "﻿" + buffer.getvalue()})


def read_sheet(path):
    """Reads a returned sheet: ("rows", [dict]) or ("map", {row: text})."""
    try:
        size = os.path.getsize(path)
    except OSError as error:
        raise ToolError(f"{path}: {error}")
    if size > MAX_SHEET_BYTES:
        raise ToolError(f"{path}: over 5 MB")
    with open(path, "rb") as file:
        raw = file.read()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        raise ToolError(f"{path}: not UTF-8")
    required = ("catalog", "key", "form", "english", "translation")
    if path.lower().endswith(".csv"):
        reader = csv.DictReader(io.StringIO(text, newline=""))
        if not reader.fieldnames or not set(required) <= set(reader.fieldnames):
            raise ToolError(f"{path}: the csv needs the columns {', '.join(required)}")
        rows = []
        for number, row in enumerate(reader, 2):
            if any(row.get(name) is None for name in required):
                raise ToolError(f"{path}: line {number} is malformed")
            rows.append(row)
        return "rows", rows
    if path.lower().endswith(".json"):
        try:
            data = json.loads(text)
        except ValueError as error:
            raise ToolError(f"{path}: not JSON: {error}")
        if isinstance(data, list):
            for row in data:
                if not isinstance(row, dict) or any(not isinstance(row.get(name), str) for name in required):
                    raise ToolError(f"{path}: every row needs the text fields {', '.join(required)}")
            return "rows", data
        if isinstance(data, dict):
            result = {}
            for number, value in data.items():
                if not number.isdigit() or not isinstance(value, str):
                    raise ToolError(f"{path}: a map needs row numbers and texts, not {number!r}")
                result[int(number)] = value
            return "map", result
        raise ToolError(f"{path}: a list of rows or a map of row numbers")
    raise ToolError(f"{path}: a sheet is a .csv or a .json file")


def newlines(text):
    return text.replace("\r\n", "\n")


def check_reviewer(name):
    if name == "anonymous":
        return
    if not name.strip() or len(name) > MAX_REVIEWER or any(unicodedata.category(char).startswith("C") for char in name):
        raise ToolError("a reviewer is `anonymous` or a printable name of at most 80 characters")


def set_localization(entry, code, localization):
    """Sets one language of an entry. A new language goes where Xcode keeps it
    (sorted) when the entry is sorted, otherwise at the end."""
    localizations = entry.setdefault("localizations", {})
    if code in localizations:
        localizations[code] = localization
        return
    existing = list(localizations)
    if existing == sorted(existing):
        merged = dict(localizations)
        merged[code] = localization
        entry["localizations"] = {name: merged[name] for name in sorted(merged)}
    else:
        localizations[code] = localization


def make_localization(side):
    if isinstance(side, dict):
        return {
            "variations": {
                "plural": {
                    name: {"stringUnit": {"state": "translated", "value": side[name]}}
                    for name in ordered_categories(side)
                }
            }
        }
    return {"stringUnit": {"state": "translated", "value": side}}


def collect_updates(repo, code, paths):
    """Reads the sheets and returns ({(catalog, key, form): (text, english or None)}, problems)."""
    updates = {}
    problems = []
    for path in paths:
        kind, content = read_sheet(path)
        if kind == "map":
            rows = {row["row"]: row for row in sheet_rows(repo, code)}
            for number, text in content.items():
                row = rows.get(number)
                if row is None:
                    problems.append(f"{path}: row {number} does not exist")
                    continue
                updates[(row["catalog"], row["key"], row["form"])] = (text, None)
        else:
            for row in content:
                updates[(row["catalog"], row["key"], row["form"])] = (row["translation"], row["english"])
    return updates, problems


def apply_updates(repo, code, updates):
    """Validates updates against the catalogs. Returns (new catalogs, touched
    entries, problems); the new catalogs are deep copies, nothing is written."""
    catalogs = copy.deepcopy(repo.catalogs)
    problems = []
    grouped = {}
    for (catalog, key, form), (text, english) in updates.items():
        entry = catalogs.get(catalog, {}).get("strings", {}).get(key)
        label = f"{catalog}|{key}" + (f" [{form}]" if form else "")
        if entry is None or entry.get("shouldTranslate") is False:
            problems.append(f"{label}: not a row of the catalogs")
            continue
        source = english_side(key, entry)
        plural = isinstance(source, dict)
        if plural and form not in ordered_categories(plural_rule(code)[1]):
            problems.append(f"{label}: {code} does not use the plural category {form!r}")
            continue
        if not plural and form:
            problems.append(f"{label}: this string has no plural forms")
            continue
        expected = source.get(form, source.get("other", key)) if plural else key
        if english is not None and newlines(english) != expected:
            problems.append(f"{label}: the English column was changed")
            continue
        text = newlines(text)
        if not text.strip():
            problems.append(f"{label}: the translation is empty")
            continue
        grouped.setdefault((catalog, key), {})[form] = text
    touched = set()
    for (catalog, key), forms in grouped.items():
        entry = catalogs[catalog]["strings"][key]
        source = english_side(key, entry)
        if isinstance(source, dict):
            merged = language_side(entry, code)
            merged = dict(merged) if isinstance(merged, dict) else {}
            merged.update(forms)
            side = merged
        else:
            side = forms[""]
        found = translation_problems(key, source, code, side)
        if found:
            problems.extend(f"{catalog}|{key}: {message}" for message in found)
            continue
        set_localization(entry, code, make_localization(side))
        touched.add((catalog, key))
    return catalogs, touched, problems


# --- commands ---------------------------------------------------------------


def cmd_codes(args):
    registry = read_registry(args.root)
    for language in registry["languages"]:
        print(language["code"])
    return 0


def first_difference(old, new):
    old_lines = old.split("\n")
    new_lines = new.split("\n")
    for number, (a, b) in enumerate(zip(old_lines, new_lines), 1):
        if a != b:
            return f"line {number}: file has {a!r}, the tool writes {b!r}"
    return f"the file has {len(old_lines)} lines, the tool writes {len(new_lines)}"


def cmd_roundtrip(args):
    bad = 0
    for name in CATALOGS:
        path = catalog_path(args.root, name)
        text = read_text(path)
        try:
            written = dumps_catalog(json.loads(text))
        except ValueError as error:
            raise ToolError(f"{path}: not JSON: {error}")
        if written != text:
            print(f"roundtrip: {path} differs: {first_difference(text, written)}")
            bad += 1
    if bad:
        return 1
    print(f"roundtrip: {len(CATALOGS)} catalogs identical")
    return 0


def cmd_export(args):
    repo = Repo(args.root)
    code = args.code
    language_entry(repo.registry, code)
    if code == repo.registry["source"]:
        raise ToolError("the source language is not translated")
    rows = sheet_rows(repo, code)
    if args.unreviewed:
        keep = unreviewed_entries(repo, code, read_ledger(args.root, code))
        rows = [row for row in rows if (row["catalog"], row["key"]) in keep]
    write_sheet(args.out, rows, args.format)
    print(f"export: {len(rows)} rows of {code} written to {args.out}")
    return 0


def cmd_apply(args):
    repo = Repo(args.root)
    code = args.code
    if code == repo.registry["source"]:
        raise ToolError("the source language is not translated")
    language_entry(repo.registry, code)
    if args.reviewer is not None:
        check_reviewer(args.reviewer)
    updates, problems = collect_updates(repo, code, args.files)
    if not updates and not problems:
        raise ToolError("the sheet has no rows")
    catalogs, touched, more = apply_updates(repo, code, updates)
    problems.extend(more)
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        print(f"apply: {len(problems)} problem(s); nothing was written", file=sys.stderr)
        return 1
    files = {}
    for name in CATALOGS:
        text = dumps_catalog(catalogs[name])
        if text != repo.texts[name]:
            files[catalog_path(args.root, name)] = text
    message = f"apply: {len(touched)} strings of {code} written"
    if args.reviewer is not None:
        today = datetime.date.today().isoformat()
        ledger = read_ledger(args.root, code) or {"version": 1, "language": code, "rounds": [], "strings": {}}
        new_repo = copy.copy(repo)
        new_repo.catalogs = catalogs
        for catalog, key, entry in new_repo.entries():
            if (catalog, key) in touched or (catalog, key) in {(c, k) for (c, k, _) in updates}:
                ledger["strings"][ledger_key(catalog, key)] = current_hash(new_repo, catalog, key, entry, code)
        ledger["strings"] = dict(sorted(ledger["strings"].items()))
        ledger["rounds"].append({"date": today, "reviewer": args.reviewer, "strings": len(touched)})
        files[ledger_path(args.root, code)] = dumps_plain(ledger)
        if not unreviewed_entries(new_repo, code, ledger, catalogs):
            registry = copy.deepcopy(repo.registry)
            language_entry(registry, code)["reviewedThrough"] = today
            files[registry_path(args.root)] = dumps_plain(registry)
            message += f"; every string of {code} is now reviewed through {today}"
        message += f"; round recorded for {args.reviewer}"
    write_all(files)
    print(message)
    return 0


def cmd_add_strings(args):
    repo = Repo(args.root)
    data = read_json(args.file)
    problems = []
    catalogs = copy.deepcopy(repo.catalogs)
    targets = repo.targets()
    added = 0
    if not isinstance(data, dict):
        raise ToolError(f"{args.file}: a map of catalogs")
    for catalog, keys in data.items():
        if catalog not in CATALOGS or not isinstance(keys, dict):
            problems.append(f"{catalog}: not one of {', '.join(CATALOGS)}")
            continue
        for key, spec in keys.items():
            where = f"{catalog}|{key}"
            if not key.strip() or key in catalogs[catalog]["strings"]:
                problems.append(f"{where}: the key is empty or exists already")
                continue
            localizations = spec.get("localizations") if isinstance(spec, dict) else None
            if not isinstance(localizations, dict):
                problems.append(f"{where}: needs localizations")
                continue
            english = localizations.get("en")
            plural = isinstance(english, dict)
            wanted = set(targets) | ({"en"} if plural else set())
            if "en" in localizations and not plural:
                problems.append(f"{where}: en is for plural keys only (the key is the English text)")
                continue
            if set(localizations) != wanted:
                missing = sorted(wanted - set(localizations))
                extra = sorted(set(localizations) - wanted)
                problems.append(f"{where}: languages differ from the registry (missing {missing}, extra {extra})")
                continue
            if plural:
                found = plural_problems("en", english)
                problems.extend(f"{where}: {message}" for message in found)
            source = english if plural else key
            bad = 0
            for code in targets:
                side = localizations[code]
                if not (isinstance(side, dict) if plural else isinstance(side, str)):
                    problems.append(f"{where}: the {code} text has the wrong shape")
                    bad += 1
                    continue
                texts = side.values() if plural else [side]
                if any(not isinstance(text, str) or not text.strip() for text in texts):
                    problems.append(f"{where}: the {code} translation is empty")
                    bad += 1
                    continue
                for message in translation_problems(key, source, code, side):
                    problems.append(f"{where}: {message}")
                    bad += 1
            if bad or (plural and plural_problems("en", english)):
                continue
            entry = {}
            if isinstance(spec.get("comment"), str) and spec["comment"]:
                entry["comment"] = spec["comment"]
            entry["localizations"] = {}
            for code in sorted(localizations):
                value = localizations[code]
                entry["localizations"][code] = make_localization(value)
            catalogs[catalog]["strings"][key] = entry
            added += 1
    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        print(f"add-strings: {len(problems)} problem(s); nothing was written", file=sys.stderr)
        return 1
    files = {catalog_path(args.root, name): dumps_catalog(catalogs[name]) for name in CATALOGS if catalogs[name] != repo.catalogs[name]}
    write_all(files)
    print(f"add-strings: {added} strings added in {len(targets) + 1} languages")
    return 0


def entry_status(repo, code):
    ledger = read_ledger(repo.root, code)
    covered = ledger["strings"] if ledger else {}
    total = reviewed = copies = changed = 0
    for catalog, key, entry in repo.entries():
        total += 1
        side = language_side(entry, code)
        current = current_hash(repo, catalog, key, entry, code)
        recorded = covered.get(ledger_key(catalog, key))
        if current is not None and recorded == current:
            reviewed += 1
        elif recorded is not None and current is not None:
            changed += 1
        english = english_side(key, entry)
        if isinstance(side, str) and side == key:
            copies += 1
        elif isinstance(side, dict) and isinstance(english, dict) and side.get("other") == english.get("other"):
            copies += 1
    return total, reviewed, copies, changed


def cmd_status(args):
    repo = Repo(args.root)
    if args.markdown:
        print("| Code | English name | Native name | Status |")
        print("| --- | --- | --- | --- |")
        for language in repo.registry["languages"]:
            if language["code"] == repo.registry["source"]:
                status = "source language"
            elif language.get("reviewedThrough"):
                status = f"reviewed through {language['reviewedThrough']}"
            else:
                status = "machine-made"
            print(f"| `{language['code']}` | {language['englishName']} | {language['nativeName']} | {status} |")
        return 0
    for code in repo.targets():
        total, reviewed, copies, changed = entry_status(repo, code)
        percent = (100 * reviewed) // total if total else 0
        print(f"{code} {total} strings {percent}% reviewed {copies} copies {changed} changed")
    return 0


def cmd_report(args):
    repo = Repo(args.root)
    codes = [args.code] if args.code else repo.targets()
    for code in codes:
        language_entry(repo.registry, code)
        flagged = []
        longest = []
        for row in sheet_rows(repo, code):
            english = SPECIFIER_RE.sub("", row["english"])
            text = row["translation"]
            if not text:
                continue
            longest.append((len(text), row))
            if len(english) < REPORT_MIN_ENGLISH or (args.max_english and len(english) > args.max_english):
                continue
            ratio = len(text) / len(english)
            if ratio > args.ratio:
                flagged.append((ratio, row))
        flagged.sort(key=lambda item: -item[0])
        longest.sort(key=lambda item: -item[0])
        print(f"{code}: {len(flagged)} strings are more than {args.ratio} times as long as the English")
        for ratio, row in (flagged if args.all else flagged[:10]):
            print(f"  x{ratio:.2f} {row['catalog']}|{row['key']!r} -> {row['translation']!r}")
        print(f"{code}: the ten longest translations")
        for length, row in longest[:10]:
            print(f"  {length:4d} chars {row['catalog']}|{row['key'][:60]!r}")
    return 0


# --- the self-test ----------------------------------------------------------


FIXTURE_PROJECT = """// !$*UTF8*$!
{
	objects = {
		A = {
			isa = PBXProject;
			knownRegions = (
				en,
				Base,
				de,
				ru,
				ja,
			);
		};
	};
}
"""


def _plural(forms):
    return make_localization(forms)


def fixture_catalogs():
    def plain(**texts):
        return {code: make_localization(text) for code, text in sorted(texts.items())}

    localizable = {
        "sourceLanguage": "en",
        "strings": {
            "Hello": {"localizations": plain(de="Hallo", ru="Привет", ja="こんにちは")},
            "Save the file to disk now": {"localizations": plain(de="Datei jetzt speichern", ru="Сохранить файл на диск сейчас", ja="今すぐファイルをディスクに保存")},
            "%lld items": {
                "localizations": {
                    "de": _plural({"one": "Ein Element", "other": "%lld Elemente"}),
                    "en": _plural({"one": "One item", "other": "%lld items"}),
                    "ja": _plural({"other": "%lld 個の項目"}),
                    "ru": _plural({"one": "%lld элемент", "few": "%lld элемента", "many": "%lld элементов", "other": "%lld элемента"}),
                }
            },
            "Name: %@, size: %lld": {"localizations": plain(de="Größe: %2$lld, Name: %1$@", ru="Имя: %@, размер: %lld", ja="名前: %@、サイズ: %lld")},
            "holzBar": {"shouldTranslate": False},
        },
        "version": "1.0",
    }
    info = {
        "sourceLanguage": "en",
        "strings": {
            "NSLocationUsageDescription": {
                "comment": "Location usage description",
                "extractionState": "manual",
                "localizations": plain(de="Der Standort wird nicht gelesen.", ru="Местоположение не читается.", ja="位置情報は読み取りません。"),
            }
        },
        "version": "1.0",
    }
    shortcuts = {
        "sourceLanguage": "en",
        "strings": {
            "Open ${applicationName}": {"localizations": plain(de="${applicationName} öffnen", ru="Открыть ${applicationName}", ja="${applicationName} を開く")}
        },
        "version": "1.0",
    }
    return {"Localizable": localizable, "InfoPlist": info, "AppShortcuts": shortcuts}


def fixture_registry():
    return {
        "version": 1,
        "source": "en",
        "languages": [
            {"code": "en", "englishName": "English", "nativeName": "English", "role": "source"},
            {"code": "de", "englishName": "German", "nativeName": "Deutsch", "reviewedThrough": None, "note": ""},
            {"code": "ru", "englishName": "Russian", "nativeName": "Русский", "reviewedThrough": None, "note": ""},
            {"code": "ja", "englishName": "Japanese", "nativeName": "日本語", "reviewedThrough": None, "note": ""},
        ],
    }


def build_fixture(root):
    files = {registry_path(root): dumps_plain(fixture_registry()), os.path.join(root, PROJECT): FIXTURE_PROJECT}
    for name, data in fixture_catalogs().items():
        files[catalog_path(root, name)] = dumps_catalog(data)
    write_all(files)


def snapshot(root):
    result = {}
    for current, _, names in os.walk(root):
        for name in names:
            path = os.path.join(current, name)
            with open(path, "rb") as file:
                result[os.path.relpath(path, root)] = file.read()
    return result


def run(argv):
    """Runs main() capturing both streams; returns (status, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            status = main(argv)
        except SystemExit as exit_:
            status = exit_.code if isinstance(exit_.code, int) else 2
    return status, out.getvalue(), err.getvalue()


def self_test():
    results = {"passed": 0, "failed": 0}

    def check(name, condition):
        if condition:
            results["passed"] += 1
        else:
            results["failed"] += 1
            print(f"FAIL {name}")

    def raises(function, *args):
        try:
            function(*args)
        except ToolError:
            return True
        return False

    # The rules, on plain values.
    check("specifiers: numbering is allowed", specifiers("%2$@ %1$lld") == specifiers("%@ %lld"))
    check("specifiers: a lost specifier differs", specifiers("Name") != specifiers("%@ name"))
    check("specifiers: %% is not a specifier", specifiers("100%% sure") == [])
    check("placeholders: equal", placeholders("A ${applicationName}") == placeholders("B ${applicationName}"))
    check("placeholders: lost", placeholders("A") != placeholders("A ${applicationName}"))
    check("placeholders: invented", placeholders("A ${x} ${y}") != placeholders("A ${x}"))
    check("copy: a long sentence is a copy", is_copy("Turn off the holzBar Shelf?", "Turn off the holzBar Shelf?"))
    check("copy: a short loanword is allowed", not is_copy("OK", "OK") and not is_copy("Show all items", "Show all items"))
    check("copy: a translation is not a copy", not is_copy("Turn off the holzBar Shelf?", "Regal aus?"))
    check("words: specifiers and placeholders are not words", word_count("%lld ${applicationName} items") == 1)
    check("plural table: en", PLURALS["en"] == (frozenset({"one", "other"}), frozenset({"one", "other"})))
    check("plural table: de", PLURALS["de"][0] == frozenset({"one", "other"}))
    check("plural table: ru", PLURALS["ru"][0] == frozenset({"one", "few", "many", "other"}))
    check("plural table: pl", PLURALS["pl"][0] == frozenset({"one", "few", "many", "other"}))
    check("plural table: cs needs few, allows many", PLURALS["cs"] == (frozenset({"one", "few", "other"}), frozenset({"one", "few", "many", "other"})))
    check("plural table: ja", PLURALS["ja"] == (frozenset({"other"}), frozenset({"other"})))
    check("plural table: id", PLURALS["id"] == (frozenset({"other"}), frozenset({"other"})))
    check("plural table: rm", PLURALS["rm"][0] == frozenset({"one", "other"}))
    check("plural: complete ru is accepted", not plural_problems("ru", ["one", "few", "many", "other"]))
    check("plural: ru lacking few is refused", any("plural" in m for m in plural_problems("ru", ["one", "many", "other"])))
    check("plural: ja holding one is refused", any("plural" in m for m in plural_problems("ja", ["one", "other"])))
    check("plural: es may hold many", not plural_problems("es", ["one", "many", "other"]))
    check("plural: an unknown language has no rule", raises(plural_rule, "xx"))
    check("reviewer: anonymous", not raises(check_reviewer, "anonymous"))
    check("reviewer: a name", not raises(check_reviewer, "Ana Silva"))
    check("reviewer: too long", raises(check_reviewer, "x" * 81))
    check("reviewer: control character", raises(check_reviewer, "a\nb"))
    check("reviewer: empty", raises(check_reviewer, "  "))

    with tempfile.TemporaryDirectory() as folder:
        root = os.path.join(folder, "repo")
        build_fixture(root)
        base = snapshot(root)
        repo = Repo(root)

        # The registry and the project.
        check("registry: codes", repo.targets() == ["de", "ru", "ja"])
        status, out, _ = run(["codes", "--root", root])
        check("codes: source first", status == 0 and out.split() == ["en", "de", "ru", "ja"])
        for name, mutate in (
            ("duplicate", lambda d: d["languages"].append(dict(d["languages"][1]))),
            ("en not first", lambda d: d["languages"].reverse()),
            ("malformed code", lambda d: d["languages"][1].update(code="DE")),
            ("no plural rule", lambda d: d["languages"][1].update(code="xx")),
            ("missing name", lambda d: d["languages"][1].pop("nativeName")),
            ("bad date", lambda d: d["languages"][1].update(reviewedThrough="soon")),
        ):
            broken = fixture_registry()
            mutate(broken)
            path = os.path.join(folder, "broken", REGISTRY)
            write_all({path: dumps_plain(broken)})
            check(f"registry refuses: {name}", raises(read_registry, os.path.join(folder, "broken")))
        check("registry: a missing file is refused", raises(read_registry, os.path.join(folder, "nowhere")))
        check("regions: parsed", known_regions(root) == ["en", "Base", "de", "ru", "ja"])
        check("regions: agree", not region_problems(repo.registry, known_regions(root)))
        check("regions: a missing one is named", any("knownRegions" in m for m in region_problems(repo.registry, ["en", "Base", "de", "ru"])))
        check("regions: an extra one is named", any("knownRegions" in m for m in region_problems(repo.registry, ["en", "Base", "de", "ru", "ja", "fr"])))

        # The writer.
        status, out, _ = run(["roundtrip-check", "--root", root])
        check("roundtrip: identical catalogs", status == 0 and "3 catalogs identical" in out)
        write_all({catalog_path(root, "InfoPlist"): json.dumps(fixture_catalogs()["InfoPlist"], indent=4)})
        status, out, _ = run(["roundtrip-check", "--root", root])
        check("roundtrip: a different layout is found", status == 1 and "differs" in out)
        write_all({catalog_path(root, "InfoPlist"): base[os.path.join(RESOURCES, "InfoPlist.xcstrings")].decode("utf-8")})

        # The rules over entries.
        english = {"one": "One item", "other": "%lld items"}
        check("entry: a good plural text passes", not translation_problems("%lld items", english, "ru", {"one": "%lld э", "few": "%lld э", "many": "%lld э", "other": "%lld э"}))
        check("entry: a plural lacking a category is refused", any("plural" in m for m in translation_problems("%lld items", english, "ru", {"one": "a", "other": "%lld b"})))
        check("entry: other must keep the specifier", any("format specifiers" in m for m in translation_problems("%lld items", english, "de", {"one": "Ein", "other": "Elemente"})))
        check("entry: one may drop the specifier", not translation_problems("%lld items", english, "de", {"one": "Ein Element", "other": "%lld Elemente"}))
        check("entry: plain shape for a plural key is refused", any("plural" in m for m in translation_problems("%lld items", english, "de", "Elemente")))
        check("entry: a lost placeholder is refused", any("placeholder" in m for m in translation_problems("Open ${applicationName}", "Open ${applicationName}", "de", "Offnen")))
        check("entry: a copied sentence is refused", any("copies the English" in m for m in translation_problems("Turn off the holzBar Shelf?", "Turn off the holzBar Shelf?", "de", "Turn off the holzBar Shelf?")))
        check("entry: a missing language is named", translation_problems("Hello", "Hello", "de", None) == ["has no de translation"])

        # Export and apply.
        sheet_csv = os.path.join(folder, "de.csv")
        status, out, _ = run(["export", "de", "--format", "csv", "--out", sheet_csv, "--root", root])
        with open(sheet_csv, "rb") as file:
            raw = file.read()
        check("export: csv written with a byte order mark", status == 0 and raw.startswith(b"\xef\xbb\xbf"))
        kind, rows = read_sheet(sheet_csv)
        check("export: all rows when no ledger exists", len(rows) == 7)
        status, out, _ = run(["export", "de", "--unreviewed", "--format", "json", "--out", os.path.join(folder, "de.json"), "--root", root])
        with open(os.path.join(folder, "de.json"), encoding="utf-8") as file:
            check("export: unreviewed json holds all rows without a ledger", len(json.load(file)) == 7)
        check("export: plural rows by category", [r["form"] for r in rows if r["key"] == "%lld items"] == ["one", "other"])
        check("export: a placeholder comment", any("placeholder" in r["comment"] for r in rows if "${" in r["key"]))
        check("export: the source language is refused", run(["export", "en", "--format", "csv", "--out", sheet_csv, "--root", root])[0] == 1)
        check("export: an unknown language is refused", run(["export", "xx", "--format", "csv", "--out", sheet_csv, "--root", root])[0] == 1)

        def edit(rows_, key, **changes):
            copy_ = [dict(row) for row in rows_]
            for row in copy_:
                if row["key"] == key:
                    row.update(changes)
                    break
            return copy_

        def refuse(name, new_rows, word, extension=".csv", **options):
            path = os.path.join(folder, name + extension)
            if extension == ".csv":
                write_sheet(path, new_rows, "csv")
            else:
                write_all({path: dumps_plain(new_rows)})
            before = snapshot(root)
            command = ["apply", options.get("code", "de"), path, "--root", root]
            if "reviewer" in options:
                command += ["--reviewer", options["reviewer"]]
            status_, _, err_ = run(command)
            check(f"apply refuses {name}", status_ == 1 and word in err_ and snapshot(root) == before)

        refuse("english-changed", edit(rows, key="Hello", english="Hi"), "English column")
        refuse("specifier-lost", edit(rows, key="Name: %@, size: %lld", form="", translation="Name und Grösse"), "format specifiers")
        refuse("placeholder-lost", edit(rows, key="Open ${applicationName}", translation="Öffnen"), "placeholder")
        refuse("plural-category", edit(rows, key="%lld items", form="few", translation="%lld Elemente"), "plural category")
        refuse("empty", edit(rows, key="Hello", translation="  "), "empty")
        refuse("unknown-row", [{"catalog": "Localizable", "key": "No such text", "form": "", "english": "No such text", "translation": "Nichts", "comment": ""}], "not a row")
        refuse("copied", edit(rows, key="Save the file to disk now", translation="Save the file to disk now"), "copies the English")
        refuse("reviewer", rows, "reviewer", reviewer="x" * 81)
        refuse("form-on-plain", edit(rows, key="Hello", form="one"), "plural")
        big = os.path.join(folder, "big.csv")
        write_all({big: "catalog,key,form,english,translation\n" + "x" * (MAX_SHEET_BYTES + 1)})
        check("apply refuses a sheet over 5 MB", run(["apply", "de", big, "--root", root])[0] == 1)
        write_all({os.path.join(folder, "bad.csv"): "a,b\n1,2\n"})
        check("apply refuses a csv without the columns", run(["apply", "de", os.path.join(folder, "bad.csv"), "--root", root])[0] == 1)
        with open(os.path.join(folder, "latin.csv"), "wb") as file:
            file.write(b"catalog,key\n\xe4\xff\n")
        check("apply refuses a file that is not UTF-8", run(["apply", "de", os.path.join(folder, "latin.csv"), "--root", root])[0] == 1)

        # A csv round trip keeps commas, quotes, line breaks and non-ASCII text.
        tricky = 'Eine, "zitierte"\nZeile ü 日本'
        write_sheet(sheet_csv, edit(rows, key="Hello", translation=tricky), "csv")
        status, out, _ = run(["apply", "de", sheet_csv, "--root", root])
        after = Repo(root)
        check("apply: without a reviewer no ledger is written", status == 0 and not os.path.exists(ledger_path(root, "de")))
        check("csv round trip keeps tricky text", language_side(after.catalogs["Localizable"]["strings"]["Hello"], "de") == tricky)
        check("apply: no reviewer leaves the registry alone", read_registry(root) == fixture_registry())

        # A round with a reviewer covers every row of the sheet.
        build_fixture(root)
        run(["export", "de", "--format", "csv", "--out", sheet_csv, "--root", root])
        status, out, _ = run(["apply", "de", sheet_csv, "--reviewer", "Ana Silva", "--root", root])
        ledger = read_ledger(root, "de")
        check("round: applied with a reviewer", status == 0 and "round recorded for Ana Silva" in out)
        check("round: the ledger holds a hash per string", len(ledger["strings"]) == 6 and all(len(h) == 16 for h in ledger["strings"].values()))
        check("round: the round is recorded", ledger["rounds"][0]["reviewer"] == "Ana Silva" and ledger["rounds"][0]["strings"] == 6)
        check("round: the registry gets the date when everything is covered", language_entry(read_registry(root), "de")["reviewedThrough"] == datetime.date.today().isoformat())
        status, out, _ = run(["status", "--root", root])
        check("status: de is fully reviewed", re.search(r"^de 6 strings 100% reviewed \d+ copies 0 changed$", out, re.M) is not None)
        check("status: ru is not reviewed", re.search(r"^ru 6 strings 0% reviewed", out, re.M) is not None)
        check("status: no line for the source", not re.search(r"^en ", out, re.M))
        run(["export", "de", "--unreviewed", "--format", "json", "--out", os.path.join(folder, "rest.json"), "--root", root])
        with open(os.path.join(folder, "rest.json"), encoding="utf-8") as file:
            check("round: nothing is unreviewed afterwards", json.load(file) == [])

        # A later edit makes a string unreviewed again.
        edited = Repo(root)
        catalog = copy.deepcopy(edited.catalogs["Localizable"])
        set_localization(catalog["strings"]["Hello"], "de", make_localization("Servus"))
        write_all({catalog_path(root, "Localizable"): dumps_catalog(catalog)})
        run(["export", "de", "--unreviewed", "--format", "json", "--out", os.path.join(folder, "rest.json"), "--root", root])
        with open(os.path.join(folder, "rest.json"), encoding="utf-8") as file:
            rest = json.load(file)
        check("edit: exactly the edited string is unreviewed again", [r["key"] for r in rest] == ["Hello"])
        check("edit: status shows it as changed", " 1 changed" in run(["status", "--root", root])[1])
        check("edit: status is below 100 percent", "de 6 strings 83% reviewed" in run(["status", "--root", root])[1])
        catalog = copy.deepcopy(Repo(root).catalogs["Localizable"])
        set_localization(catalog["strings"]["Hello"], "de", make_localization("Hallo"))
        catalog["strings"]["Save the file to disk now"]["localizations"]["en"] = make_localization({"other": "x"})
        write_all({catalog_path(root, "Localizable"): dumps_catalog(catalog)})
        run(["export", "de", "--unreviewed", "--format", "json", "--out", os.path.join(folder, "rest.json"), "--root", root])
        with open(os.path.join(folder, "rest.json"), encoding="utf-8") as file:
            rest = json.load(file)
        check("edit: a changed English side is unreviewed too", {r["key"] for r in rest} == {"Save the file to disk now"})

        # A partial round does not set the date.
        build_fixture(root)
        partial = [row for row in sheet_rows(Repo(root), "ru") if row["key"] == "Hello"]
        write_sheet(sheet_csv, partial, "csv")
        run(["apply", "ru", sheet_csv, "--reviewer", "anonymous", "--root", root])
        check("round: a partial round leaves reviewedThrough null", language_entry(read_registry(root), "ru")["reviewedThrough"] is None)
        check("round: a partial round covers only its rows", len(read_ledger(root, "ru")["strings"]) == 1)

        # A json map of row numbers.
        build_fixture(root)
        mapping = os.path.join(folder, "map.json")
        write_all({mapping: json.dumps({"1": "Servus"})})
        status, _, _ = run(["apply", "de", mapping, "--root", root])
        check("map: a row number applies", status == 0 and language_side(Repo(root).catalogs["Localizable"]["strings"]["Hello"], "de") == "Servus")
        write_all({mapping: json.dumps({"999": "Servus"})})
        check("map: an unknown row number is refused", run(["apply", "de", mapping, "--root", root])[0] == 1)

        # A new language through apply: sorted position and plural forms.
        build_fixture(root)
        registry = fixture_registry()
        registry["languages"].append({"code": "pl", "englishName": "Polish", "nativeName": "Polski", "reviewedThrough": None, "note": ""})
        write_all({registry_path(root): dumps_plain(registry)})
        polish = {row["row"]: row for row in sheet_rows(Repo(root), "pl")}
        texts = {}
        for number, row in polish.items():
            texts[str(number)] = {"Hello": "Cześć"}.get(row["key"], f"Tekst {row['form'] or number} " + " ".join(re.findall(r"%\S*|\$\{\w+\}", row["english"])))
        write_all({mapping: json.dumps(texts, ensure_ascii=False)})
        status, _, err = run(["apply", "pl", mapping, "--root", root])
        after = Repo(root)
        hello = after.catalogs["Localizable"]["strings"]["Hello"]["localizations"]
        check("new language: applied", status == 0)
        check("new language: placed in the sorted position", list(hello) == ["de", "ja", "pl", "ru"])
        plural_forms = after.catalogs["Localizable"]["strings"]["%lld items"]["localizations"]["pl"]["variations"]["plural"]
        check("new language: plural categories one few many other", list(plural_forms) == ["one", "few", "many", "other"])
        removed = copy.deepcopy(after.catalogs)
        for catalog_ in removed.values():
            for entry in catalog_["strings"].values():
                entry.get("localizations", {}).pop("pl", None)
        check("new language: removing it restores the files byte for byte", all(dumps_catalog(removed[n]) == base[os.path.join(RESOURCES, n + ".xcstrings")].decode("utf-8") for n in CATALOGS))
        check("new language: the regions check names the missing region", any("knownRegions" in m for m in region_problems(after.registry, known_regions(root))))

        # add-strings.
        build_fixture(root)
        good = {
            "Localizable": {
                "Open the hub window": {
                    "comment": "A button",
                    "localizations": {"de": "Zentrale öffnen", "ru": "Открыть центр", "ja": "ハブを開く"},
                },
                "%lld files": {
                    "localizations": {
                        "en": {"one": "One file", "other": "%lld files"},
                        "de": {"one": "Eine Datei", "other": "%lld Dateien"},
                        "ru": {"one": "%lld файл", "few": "%lld файла", "many": "%lld файлов", "other": "%lld файла"},
                        "ja": {"other": "%lld 個のファイル"},
                    }
                },
            }
        }
        path = os.path.join(folder, "new.json")

        def add(spec):
            write_all({path: json.dumps(spec, ensure_ascii=False)})
            before = snapshot(root)
            status_, out_, err_ = run(["add-strings", path, "--root", root])
            return status_, err_, snapshot(root) == before

        status, err, unchanged = add(good)
        keys = list(Repo(root).catalogs["Localizable"]["strings"])
        check("add-strings: adds plain and plural keys", status == 0 and keys[-2:] == ["Open the hub window", "%lld files"])
        check("add-strings: the files still round trip", run(["roundtrip-check", "--root", root])[0] == 0)
        check("add-strings: the result passes the rules", not [m for k, e in Repo(root).catalogs["Localizable"]["strings"].items() if k in ("Open the hub window", "%lld files") for c in ("de", "ru", "ja") for m in translation_problems(k, english_side(k, e), c, language_side(e, c))])
        status, err, unchanged = add(good)
        check("add-strings: refuses a key that exists", status == 1 and "exists" in err and unchanged)
        build_fixture(root)
        broken = copy.deepcopy(good)
        del broken["Localizable"]["Open the hub window"]["localizations"]["ru"]
        status, err, unchanged = add(broken)
        check("add-strings: refuses a missing language", status == 1 and "missing ['ru']" in err and unchanged)
        broken = copy.deepcopy(good)
        broken["Localizable"]["Open the hub window"]["localizations"]["fr"] = "Ouvrir"
        status, err, unchanged = add(broken)
        check("add-strings: refuses an extra language", status == 1 and "extra ['fr']" in err and unchanged)
        broken = copy.deepcopy(good)
        broken["Localizable"]["%lld files"]["localizations"]["de"]["other"] = "Dateien"
        status, err, unchanged = add(broken)
        check("add-strings: refuses a lost specifier", status == 1 and "format specifiers" in err and unchanged)
        broken = copy.deepcopy(good)
        broken["Localizable"]["Open the hub window"]["localizations"]["de"] = "Open the hub window"
        status, err, unchanged = add(broken)
        check("add-strings: refuses a copied sentence", status == 1 and "copies the English" in err and unchanged)
        broken = copy.deepcopy(good)
        del broken["Localizable"]["%lld files"]["localizations"]["ru"]["few"]
        status, err, unchanged = add(broken)
        check("add-strings: refuses a missing plural category", status == 1 and "plural" in err and unchanged)
        broken = {"AppShortcuts": {"Close ${applicationName}": {"localizations": {"de": "Schliessen", "ru": "Закрыть ${applicationName}", "ja": "${applicationName} を閉じる"}}}}
        status, err, unchanged = add(broken)
        check("add-strings: refuses a lost placeholder", status == 1 and "placeholder" in err and unchanged)
        check("add-strings: refuses an unknown catalog", add({"Other": {}})[0] == 1)

        # status --markdown and report.
        build_fixture(root)
        status, out, _ = run(["status", "--markdown", "--root", root])
        check("status --markdown: a table with machine-made rows", status == 0 and "| `de` | German | Deutsch | machine-made |" in out and "source language" in out)
        status, out, _ = run(["report", "de", "--root", root])
        check("report: lists the ten longest", status == 0 and "ten longest" in out)
        check("report: flags a long translation", "Datei jetzt speichern" not in out and "strings are more than 1.4 times" in out)

    print(f"self-test: {results['passed']} checks passed" if not results["failed"] else f"self-test: {results['failed']} checks FAILED, {results['passed']} passed")
    return 1 if results["failed"] or results["passed"] < 40 else 0


# --- the command line -------------------------------------------------------


def make_parser():
    parser = argparse.ArgumentParser(prog="translations.py", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--root", default=".", help="the repository (default: the current directory)")
    commands = parser.add_subparsers(dest="command", required=True, metavar="command")
    commands.add_parser("codes", parents=[common], help="print the registry's language codes")
    commands.add_parser("roundtrip-check", parents=[common], help="the catalogs are reproduced byte for byte")
    export = commands.add_parser("export", parents=[common], help="write a sheet of one language")
    export.add_argument("code")
    export.add_argument("--unreviewed", action="store_true", help="only the strings the ledger does not cover")
    export.add_argument("--format", choices=("csv", "json"), default="csv")
    export.add_argument("--out", required=True)
    apply = commands.add_parser("apply", parents=[common], help="validate corrected sheets and write the catalogs")
    apply.add_argument("code")
    apply.add_argument("files", nargs="+", metavar="FILE")
    apply.add_argument("--reviewer", help="record a review round: `anonymous` or the name as the reviewer wrote it")
    add = commands.add_parser("add-strings", parents=[common], help="add new English keys with translations in every language")
    add.add_argument("file")
    status = commands.add_parser("status", parents=[common], help="strings, reviewed share, copies and changed strings per language")
    status.add_argument("--markdown", action="store_true", help="the table of docs/translations.md")
    report = commands.add_parser("report", parents=[common], help="translations that are much longer than the English")
    report.add_argument("code", nargs="?")
    report.add_argument("--ratio", type=float, default=LONG_RATIO)
    report.add_argument("--max-english", type=int, default=0, help="only English texts up to this many characters")
    report.add_argument("--all", action="store_true", help="list every flagged string, not the first ten")
    commands.add_parser("self-test", help="every rule, on fixtures in a temporary folder")
    return parser


def main(argv=None):
    args = make_parser().parse_args(argv)
    handlers = {
        "codes": cmd_codes,
        "roundtrip-check": cmd_roundtrip,
        "export": cmd_export,
        "apply": cmd_apply,
        "add-strings": cmd_add_strings,
        "status": cmd_status,
        "report": cmd_report,
    }
    if args.command == "self-test":
        return self_test()
    try:
        return handlers[args.command](args)
    except ToolError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
