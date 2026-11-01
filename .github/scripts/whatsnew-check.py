#!/usr/bin/env python3
#
# whatsnew-check.py
#
# The data check and the release gate of the What's New window. The history it
# shows is Swift code (holzBar/Core/WhatsNewHistory.swift), and strings-check.py
# does not scan holzBar/Core, so without this script nothing in CI would prove
# that the history's texts exist in the String Catalog or that a release has an
# entry at all.
#
# The script reads the history by its convention (one WhatsNewRelease call per
# release with the version on its first line, items as WhatsNewItem calls with
# symbol:, title: and detail:, fixes as WhatsNewFix calls with text:, all plain
# one-line string literals). It has two modes:
#
#   python3 .github/scripts/whatsnew-check.py
#       Checks the history file: at least one release; versions plain X.Y.Z (a
#       beta shares the entry of its stable version, so no suffix), unique,
#       strictly newest first, the oldest is 1.0.0; every release has at least
#       one item or fix; every item has a symbol, a title and a detail; every SF
#       Symbol name is lowercase ASCII with dots; no text has a backslash or an
#       interpolation; every title, detail and fix text is a key of
#       holzBar/Resources/Localizable.xcstrings with a finished translation in
#       every language of Translations/languages.json.
#
#   python3 .github/scripts/whatsnew-check.py --version 1.0.1-beta1
#       The release gate. VERSION is a release version X.Y.Z, X.Y.Z-alphaN or
#       X.Y.Z-betaN, the same format release.yml accepts. The suffix is
#       stripped, the history is checked as above, and the history must have an
#       entry for that core version with at least one item or fix. Any other
#       text fails.
#
#   python3 .github/scripts/whatsnew-check.py --self-test
#       Proves each rule on fixtures in a temporary directory; it never reads
#       the repository's real history.
#
# It runs in the strings job of .github/workflows/build.yml on every pull
# request and, with the tag's version, in .github/workflows/release.yml before
# anything is built. Every problem is printed as a GitHub annotation and makes
# the script exit with status 1. Python standard library only.

import argparse
import json
import os
import re
import sys
import tempfile

# The shared registry reader lives next to this script.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import translations  # noqa: E402

HISTORY = "holzBar/Core/WhatsNewHistory.swift"
CATALOG = "holzBar/Resources/Localizable.xcstrings"

PLAIN_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
# The format release.yml validates the tag against.
RELEASE_VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta)[0-9]+)?$")
SYMBOL_RE = re.compile(r"^[a-z0-9]+(\.[a-z0-9]+)*$")
OLDEST_VERSION = "1.0.0"

RELEASE_RE = re.compile(r"WhatsNewRelease\(\s*version:\s*")
ENTRY_RE = re.compile(r"WhatsNewItem\(|WhatsNewFix\(")
FIELD_RE = re.compile(r"\b(version|symbol|title|detail|text)\s*:\s*")


def annotate(path, line, message):
    print(f"::error file={path},line={line}::{message}")


def read_literal(text, start):
    """Reads the field value at `start`. Returns (value, problem); problem names a rule broken."""
    if text.startswith('"""', start):
        return None, "a multi-line string literal (use a plain one-line literal)"
    if not text.startswith('"', start):
        return None, "not a string literal (use a plain one-line literal)"
    end = start + 1
    while end < len(text) and text[end] not in '"\n':
        if text[end] == "\\":
            if text.startswith("\\(", end):
                return None, "an interpolation (use a plain literal)"
            return None, "a backslash or escape (use a plain literal)"
        end += 1
    if end >= len(text) or text[end] != '"':
        return None, "an unterminated string literal"
    return text[start + 1:end], None


def parse_history(text):
    """Splits the history into releases: [{version, line, entries: [{kind, line, fields}]}].

    A field is (value, line) or (None, line) when the literal broke the convention;
    `problems` collects (line, message) for the latter.
    """
    problems = []
    releases = []
    starts = [match for match in RELEASE_RE.finditer(text)]
    for index, match in enumerate(starts):
        chunk_end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
        chunk = text[match.start():chunk_end]
        base = match.start()

        def line_at(offset):
            return text.count("\n", 0, base + offset) + 1

        value, problem = read_literal(chunk, match.end() - match.start())
        if problem:
            problems.append((line_at(0), f"version is {problem}"))
        entries = []
        entry_matches = list(ENTRY_RE.finditer(chunk))
        for position, entry in enumerate(entry_matches):
            stop = entry_matches[position + 1].start() if position + 1 < len(entry_matches) else len(chunk)
            segment = chunk[entry.start():stop]
            fields = {}
            for field in FIELD_RE.finditer(segment):
                name = field.group(1)
                offset = entry.start() + field.end()
                literal, problem = read_literal(chunk, offset)
                where = line_at(offset)
                if problem:
                    problems.append((where, f"{name} is {problem}"))
                if name in fields:
                    problems.append((where, f"{name} is given twice in one entry"))
                fields[name] = (literal, where)
            entries.append({"kind": "item" if entry.group(0).startswith("WhatsNewItem") else "fix",
                            "line": line_at(entry.start()), "fields": fields})
        releases.append({"version": value, "line": line_at(0), "entries": entries})
    return releases, problems


def catalog_problems(catalog, key, codes):
    """Why `key` is not a finished catalog entry in each language of `codes` (empty: it is)."""
    strings = catalog.get("strings", {})
    if key not in strings:
        return [f'"{key}" has no key in {CATALOG}']
    localizations = strings[key].get("localizations", {})
    problems = []
    for code in codes:
        unit = localizations.get(code, {}).get("stringUnit")
        if not isinstance(unit, dict) or unit.get("state") != "translated" or not str(unit.get("value", "")).strip():
            problems.append(f'"{key}" has no finished translation in {code}')
    return problems


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def check_history(root):
    """Returns the list of problems with the history file; empty when it is sound."""
    history_path = os.path.join(root, HISTORY)
    text = translations.read_text(history_path)
    registry = translations.read_registry(root)
    codes = translations.target_codes(registry)
    catalog = translations.read_json(os.path.join(root, CATALOG))
    releases, problems = parse_history(text)
    messages = [f"line {line}: {message}" for line, message in problems]

    if not releases:
        messages.append(f"{HISTORY}: no release found (WhatsNewRelease(version: ...) per release)")
        return messages

    seen = set()
    previous = None
    for release in releases:
        version = release["version"]
        where = f"line {release['line']}"
        if version is None:
            continue
        if not PLAIN_VERSION_RE.match(version):
            messages.append(f"{where}: version \"{version}\" must be plain X.Y.Z (a beta shares the entry of its stable version)")
            continue
        if version in seen:
            messages.append(f"{where}: version {version} appears twice")
        seen.add(version)
        if previous is not None and version_key(version) >= version_key(previous):
            messages.append(f"{where}: version {version} must come before {previous} (strictly newest first)")
        previous = version

        if not release["entries"]:
            messages.append(f"{where}: release {version} has no item or fix")
        for entry in release["entries"]:
            names = ("symbol", "title", "detail") if entry["kind"] == "item" else ("text",)
            for name in names:
                if name not in entry["fields"]:
                    messages.append(f"line {entry['line']}: release {version} has an entry without {name}")
            for name, (literal, line) in entry["fields"].items():
                if literal is None:
                    continue
                if name == "symbol":
                    if not SYMBOL_RE.match(literal):
                        messages.append(f'line {line}: symbol "{literal}" must be lowercase ASCII with dots')
                elif name in ("title", "detail", "text"):
                    for problem in catalog_problems(catalog, literal, codes):
                        messages.append(f"line {line}: {problem}")

    versions = [release["version"] for release in releases if release["version"] and PLAIN_VERSION_RE.match(release["version"])]
    if versions and versions[-1] != OLDEST_VERSION:
        messages.append(f"the oldest release is {versions[-1]}, it must be {OLDEST_VERSION}")
    return messages


def check_version(root, value):
    """The release gate: `value` is the tag's version; the history must have its entry."""
    if not RELEASE_VERSION_RE.fullmatch(value):
        return [f'"{value}" has the wrong format; expected X.Y.Z, X.Y.Z-alphaN or X.Y.Z-betaN']
    core = value.split("-")[0]
    messages = check_history(root)
    releases, _problems = parse_history(translations.read_text(os.path.join(root, HISTORY)))
    for release in releases:
        if release["version"] == core:
            if not release["entries"]:
                messages.append(f"the What's New entry for {core} has no item or fix")
            return messages
    messages.append(f"{HISTORY} has no What's New entry for {core} (release {value}); add it before tagging")
    return messages


# --- self-test --------------------------------------------------------------


def render_history(releases, raw=None):
    """Writes a history file in the convention; `raw` replaces it wholesale."""
    if raw is not None:
        return raw
    lines = ["nonisolated enum WhatsNewHistory {", "    static let releases: [WhatsNewRelease] = ["]
    for release in releases:
        lines.append(f'        WhatsNewRelease(version: "{release["version"]}",')
        if release.get("items"):
            lines.append("            new: [")
            for symbol, title, detail in release["items"]:
                lines.append("                WhatsNewItem(")
                lines.append(f'                    symbol: "{symbol}",')
                lines.append(f'                    title: "{title}",')
                lines.append(f'                    detail: "{detail}"')
                lines.append("                ),")
            lines.append("            ],")
        if release.get("fixes"):
            lines.append("            fixed: [")
            for text in release["fixes"]:
                lines.append(f'                WhatsNewFix(text: "{text}"),')
            lines.append("            ]")
        lines.append("        ),")
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def keys_of(releases):
    keys = []
    for release in releases:
        for _symbol, title, detail in release.get("items", []):
            keys += [title, detail]
        keys += release.get("fixes", [])
    return keys


def build_fixture(root, releases, raw=None, drop=(), untranslated=(), codes=("de", "fr")):
    """Writes a minimal tree: history, catalog and registry.

    `drop` lists (key, code) pairs left out of the catalog, `untranslated` lists
    (key, code) pairs written with a state that is not translated. A key given as
    (key, None) is missing from the catalog altogether.
    """
    languages = [{"code": "en", "englishName": "English", "nativeName": "English", "role": "source"}]
    for code in codes:
        languages.append({"code": code, "englishName": code, "nativeName": code, "reviewedThrough": None, "note": ""})
    registry = {"version": 1, "source": "en", "languages": languages}
    strings = {}
    for key in keys_of(releases):
        if (key, None) in drop:
            continue
        localizations = {}
        for code in codes:
            if (key, code) in drop:
                continue
            state = "new" if (key, code) in untranslated else "translated"
            localizations[code] = {"stringUnit": {"state": state, "value": key + " " + code}}
        strings[key] = {"localizations": localizations}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    files = {
        HISTORY: render_history(releases, raw),
        CATALOG: json.dumps(catalog),
        translations.REGISTRY: json.dumps(registry),
    }
    for relative, content in files.items():
        path = os.path.join(root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            file.write(content)


def release(version, items=None, fixes=None):
    return {"version": version, "items": items if items is not None else [], "fixes": fixes or []}


def item(symbol="sparkles", title="A title", detail="A sentence."):
    return (symbol, title, detail)


def clean():
    return [
        release("1.0.1", [item("sparkles", "New window", "It opens after an update.")]),
        release("1.0.0", [item("music.note", "Now Playing", "See what plays.")], ["A fixed thing."]),
    ]


def self_test():
    failures = []
    count = 0

    def run(name, check, expect_substring, builder):
        """`expect_substring` None means the check must pass, else it must fail with it."""
        nonlocal count
        count += 1
        with tempfile.TemporaryDirectory() as root:
            builder(root)
            try:
                messages = check(root)
            except translations.ToolError as error:
                messages = [str(error)]
        joined = " | ".join(messages)
        if expect_substring is None:
            if messages:
                failures.append(f"{name}: expected a pass, got: {joined}")
        elif not messages:
            failures.append(f"{name}: expected a failure mentioning '{expect_substring}', got a pass")
        elif expect_substring not in joined:
            failures.append(f"{name}: expected a failure mentioning '{expect_substring}', got: {joined}")

    def history_case(name, expect, releases=None, **options):
        releases = clean() if releases is None else releases
        run(name, check_history, expect, lambda root: build_fixture(root, releases, **options))

    def version_case(name, expect, value, **options):
        run(name, lambda root: check_version(root, value), expect, lambda root: build_fixture(root, clean(), **options))

    # The history file.
    history_case("a clean history passes", None)
    history_case("a duplicate version", "twice", [clean()[0], clean()[0], clean()[1]])
    history_case("an unsorted list", "newest first", [clean()[1], clean()[0]])
    history_case("a beta suffix in the history", "plain X.Y.Z", [release("1.0.1-beta1", [item()]), clean()[1]])
    history_case("an empty release", "no item or fix", [release("1.0.1"), clean()[1]])
    history_case("a symbol with a capital letter", "symbol", [release("1.0.1", [item("Sparkles")]), clean()[1]])
    history_case("a symbol with a space", "symbol", [release("1.0.1", [item("music note")]), clean()[1]])
    history_case("a backslash in a text", "backslash", [release("1.0.1", [item(detail="A \\n break.")]), clean()[1]])
    history_case("an interpolation in a text", "interpolation", [release("1.0.1", [item(title="V\\(version)")]), clean()[1]])
    history_case("a key missing from the catalog", "no key", drop={("New window", None)})
    history_case("a key lacking one language", "fr", drop={("New window", "fr")})
    history_case("a key not translated yet", "finished translation in de", untranslated={("Now Playing", "de")})
    history_case("an oldest entry that is not 1.0.0", "oldest", [clean()[0], release("0.9.0", [item("bell", "Old", "Older.")])])
    history_case("no release at all", "no release", [])
    history_case("an item without a detail", "detail", raw=render_history(clean()).replace('                    detail: "See what plays."\n', ""))
    history_case("a text that is not a literal", "string literal", raw=render_history(clean()).replace('title: "Now Playing"', "title: someTitle"))
    history_case("a fix alone is enough", None, [release("1.0.1", fixes=["Fixed it."]), clean()[1]])

    # The release gate.
    version_case("the gate accepts the stable version", None, "1.0.1")
    version_case("the gate accepts a beta of a known version", None, "1.0.1-beta1")
    version_case("the gate accepts an alpha of a known version", None, "1.0.1-alpha12")
    version_case("the gate accepts the oldest version", None, "1.0.0")
    version_case("the gate refuses a version without an entry", "1.0.2", "1.0.2")
    version_case("the gate refuses a beta without an entry", "1.0.2", "1.0.2-beta1")
    version_case("the gate refuses a leading v", "format", "v1.0.1")
    version_case("the gate refuses two parts", "format", "1.0")
    version_case("the gate refuses another suffix", "format", "1.0.1-rc1")
    version_case("the gate refuses an empty value", "format", "")
    version_case("the gate refuses a space", "format", "1.0.1 ")
    version_case("the gate refuses a newline", "format", "1.0.1\n")
    version_case("the gate refuses a broken history", "no key", "1.0.1", drop={("New window", None)})

    print(f"{count} checks run")
    for failure in failures:
        print(f"FAIL: {failure}")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description="Checks the What's New history and gates a release on it.")
    parser.add_argument("--root", default=".")
    parser.add_argument("--version", help="a release version X.Y.Z, X.Y.Z-alphaN or X.Y.Z-betaN")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    try:
        messages = check_version(args.root, args.version) if args.version is not None else check_history(args.root)
    except translations.ToolError as error:
        messages = [str(error)]
    for message in messages:
        annotate(HISTORY, 1, message)
    if messages:
        print(f"{len(messages)} problem(s) in the What's New history")
        return 1
    print("What's New history complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
