#!/usr/bin/env python3
#
# strings-check.py
#
# Proves that holzBar speaks its five languages (ICE-05): English, the source
# language, and German, French, Italian and Romansh, the languages of
# https://holzcloud.ch/holzbar.
#
#   1. Every String Catalog in holzBar/Resources parses as JSON with English as
#      its source language.
#   2. Every entry that is to be translated has a translated, non-empty German,
#      French, Italian and Romansh value (plural variations included), and each
#      translation keeps the format specifiers of its key.
#   3. Every string literal in a localisable position of holzBar's Swift code
#      (SwiftUI initialisers and modifiers, String(localized:), App Intents
#      titles, NSMenuItem titles, alert texts, tooltips, accessibility labels)
#      has an entry; each interpolation \(...) stands for a format specifier.
#
# It runs in the strings job of .github/workflows/build.yml and locally:
#
#   python3 .github/scripts/strings-check.py
#   python3 .github/scripts/strings-check.py --list   # the keys the code uses
#
# Every problem is printed as a GitHub annotation and makes the script exit
# with status 1. Python standard library only.

import argparse
import json
import os
import re
import sys

RESOURCES = "holzBar/Resources"
SOURCE_DIR = "holzBar"
LANGUAGES = ("de", "fr", "it", "rm")

# A format specifier as Xcode writes it into a catalog key.
SPECIFIER = r"%(?:\d+\$)?(?:@|lld|llu|ld|lu|d|u|lf|f|g)"
SPECIFIER_RE = re.compile(SPECIFIER)

# Where a string literal is localised. Each pattern ends right before the
# opening quote of the literal.
POSITIONS = [
    r"\b(?:Text|Toggle|Button|Label|Menu|ColorPicker|TextField|Picker|Section|LabeledContent|Stepper|HolzBarSection|HolzBarPicker)\(\s*",
    r"\.(?:annotation|help|navigationTitle|accessibilityLabel|accessibilityHint|alert|confirmationDialog)\(\s*",
    r"\.accessibilityAction\(\s*named:\s*",
    r"\bString\(\s*localized:\s*",
    r"\bLocalizedStringResource\(\s*",
    r"\bLocalizedStringKey\(\s*",
    r"\bNSMenuItem\(\s*title:\s*",
    r"\b(?:messageText|informativeText|toolTip|title|prompt|message)\s*=\s*",
    r"\baddButton\(\s*withTitle:\s*",
    r"\bsetAccessibilityLabel\(\s*",
    r"\bAcknowledgementsGroup\(\s*title:\s*",
    # App Intents
    r"\bstatic let title: LocalizedStringResource\s*=\s*",
    r"\bTypeDisplayRepresentation\s*=\s*",
    r"@Parameter\(\s*title:\s*",
    r"\bshortTitle:\s*",
    r"^\s*\.\w+:\s*",  # caseDisplayRepresentations entries such as `.hidden: "Hidden",`
]
POSITION_RE = re.compile("(?:" + "|".join(POSITIONS) + r')(?=#?")', re.MULTILINE)

# Computed properties whose string literals are localised keys.
KEY_BLOCK_RE = re.compile(r"(?:var \w+: LocalizedStringKey|-> LocalizedStringKey|var localizedStringResource: LocalizedStringResource)\s*\{")

# Files whose literals in the positions above are not shown to the user.
IGNORED_FILES = {
    "holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift",  # the overlay's window title
}

# Positions that are only localisable in some files: the generic `title =`,
# `message =` and `prompt =` assignments and dictionary entries.
GENERIC_POSITION_RE = re.compile(r"^(?:\b(?:title|prompt|message)\s*=\s*|\s*\.\w+:\s*)$", re.MULTILINE)
GENERIC_POSITION_FILES = {
    "holzBar/Main/HolzBarIntents.swift",
    "holzBar/Utilities/SettingsBackup.swift",
    "holzBar/MenuBar/MenuBarItems/ItemIconStore.swift",
    "holzBar/MenuBar/Groups/MenuBarItemGroups.swift",
}


def annotate(path, line, message):
    print(f"::error file={path},line={line}::{message}")


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def parse_literal(text, start):
    """Parses the string literal at `start` (a quote, or # before a quote).

    Returns (key, end) where key is the literal's text with each interpolation
    replaced by U+FFFC, or (None, end) for a raw string with interpolations it
    cannot read.
    """
    hashes = 0
    while text[start + hashes] == "#":
        hashes += 1
    index = start + hashes
    multiline = text.startswith('"""', index)
    delimiter = '"""' if multiline else '"'
    index += len(delimiter)
    escape = "\\" + "#" * hashes
    closing = delimiter + "#" * hashes
    parts = []
    while index < len(text):
        if text.startswith(closing, index):
            index += len(closing)
            break
        if text.startswith(escape, index):
            index += len(escape)
            char = text[index]
            if char == "(":
                depth = 1
                index += 1
                while index < len(text) and depth:
                    if text[index] == "(":
                        depth += 1
                    elif text[index] == ")":
                        depth -= 1
                    elif text[index] == '"':
                        # A string literal inside the interpolation.
                        _, index = parse_literal(text, index)
                        continue
                    index += 1
                parts.append("\ufffc")
                continue
            if char == "u" and text[index + 1] == "{":
                end = text.index("}", index)
                parts.append(chr(int(text[index + 2:end], 16)))
                index = end + 1
                continue
            if char == "\n":
                # A line continuation in a multi-line literal.
                index += 1
                while index < len(text) and text[index] in " \t":
                    index += 1
                continue
            parts.append({"n": "\n", "t": "\t", "0": "\0", "\\": "\\", '"': '"', "'": "'"}.get(char, char))
            index += 1
            continue
        parts.append(text[index])
        index += 1
    value = "".join(parts)
    if multiline:
        lines = value.split("\n")
        # Drop the line of the opening and closing delimiters and the indentation.
        if lines and not lines[0].strip():
            lines = lines[1:]
        if lines and not lines[-1].strip():
            indent = len(lines[-1])
            lines = lines[:-1]
        else:
            indent = 0
        value = "\n".join(line[indent:] for line in lines)
    return value, index


def code_keys(root):
    """Yields (path, line, key) for every localised literal in the code."""
    base = os.path.join(root, SOURCE_DIR)
    for current, dirs, files in os.walk(base):
        dirs.sort()
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            full = os.path.join(current, name)
            path = os.path.relpath(full, root).replace(os.sep, "/")
            # Core is Foundation only; the views translate its texts from the catalog.
            if path in IGNORED_FILES or path.startswith("holzBar/Core/") or "/MacOS27/Core/" in path:
                continue
            with open(full, encoding="utf-8") as file:
                text = strip_comments(file.read())
            for match in POSITION_RE.finditer(text):
                if GENERIC_POSITION_RE.match(match.group(0)) and path not in GENERIC_POSITION_FILES:
                    continue
                key, _ = parse_literal(text, match.end())
                if key is not None and is_text(key):
                    yield path, line_of(text, match.start()), key
            for match in KEY_BLOCK_RE.finditer(text):
                end = block_end(text, match.end())
                index = match.end()
                while index < end:
                    if text[index] != '"':
                        index += 1
                        continue
                    key, after = parse_literal(text, index)
                    if key is not None and is_text(key):
                        yield path, line_of(text, index), key
                    index = after


def strip_comments(text):
    """Blanks out // comments outside string literals, keeping the offsets."""
    result = []
    index = 0
    while index < len(text):
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = len(text) if end < 0 else end
            result.append(" " * (end - index))
            index = end
            continue
        if text[index] == '"' or (text[index] == "#" and text.startswith('#"', index)):
            _, end = parse_literal(text, index)
            result.append(text[index:end])
            index = end
            continue
        result.append(text[index])
        index += 1
    return "".join(result)


def block_end(text, start):
    depth = 1
    index = start
    while index < len(text) and depth:
        if text[index] == '"':
            _, index = parse_literal(text, index)
            continue
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    return index


def is_text(key):
    """Whether a literal is text for people: it has letters beyond placeholders."""
    return re.search(r"[A-Za-z]{2,}", key.replace("\ufffc", "")) is not None


def key_pattern(key):
    """A pattern of the catalog keys of a literal with interpolations: each one is a
    format specifier, and a percent sign of the text is written twice."""
    parts = key.split("\ufffc")
    return re.compile("^" + SPECIFIER.join(re.escape(part.replace("%", "%%")) for part in parts) + "$", re.DOTALL)


def string_units(entry):
    """Yields (language, unit) for every string unit of every localization."""
    for language, localization in entry.get("localizations", {}).items():
        stack = [localization]
        while stack:
            node = stack.pop()
            if not isinstance(node, dict):
                continue
            if "stringUnit" in node:
                yield language, node["stringUnit"]
            for value in node.values():
                if isinstance(value, dict):
                    stack.extend(value.values() if "stringUnit" not in value else [value])


def specifiers(text):
    """The kinds of the format specifiers of a text; a translation may number
    them (%1$@, %2$@) to change their order."""
    return sorted(re.sub(r"\d+\$", "", found) for found in SPECIFIER_RE.findall(text.replace("%%", "")))


def check_catalog(path, data):
    problems = 0
    if data.get("sourceLanguage") != "en":
        annotate(path, 1, "The source language must be en")
        problems += 1
    strings = data.get("strings", {})
    for key, entry in strings.items():
        if entry.get("shouldTranslate") is False:
            continue
        units = {}
        for language, unit in string_units(entry):
            units.setdefault(language, []).append(unit)
        for language in LANGUAGES:
            found = units.get(language, [])
            if not found:
                annotate(path, 1, f"{key!r} has no {language} translation")
                problems += 1
                continue
            for unit in found:
                value = unit.get("value", "")
                if unit.get("state") != "translated" or not value.strip():
                    annotate(path, 1, f"{key!r} has an unfinished {language} translation")
                    problems += 1
                elif specifiers(value) != specifiers(key) and "variations" not in entry.get("localizations", {}).get(language, {}):
                    annotate(path, 1, f"{key!r}: the {language} translation changes the format specifiers")
                    problems += 1
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--list", action="store_true", help="print the keys the code uses as JSON")
    args = parser.parse_args()
    root = args.root

    uses = list(code_keys(root))
    if args.list:
        json.dump(
            sorted({key.replace("\ufffc", "\\(…)") for _, _, key in uses}),
            sys.stdout,
            ensure_ascii=False,
            indent=1,
        )
        print()
        return 0

    problems = 0
    catalogs = {}
    directory = os.path.join(root, RESOURCES)
    names = sorted(name for name in os.listdir(directory) if name.endswith(".xcstrings"))
    if "Localizable.xcstrings" not in names:
        annotate(f"{RESOURCES}/Localizable.xcstrings", 1, "The String Catalog is missing")
        return 1
    for name in names:
        path = f"{RESOURCES}/{name}"
        try:
            with open(os.path.join(directory, name), encoding="utf-8") as file:
                catalogs[name] = json.load(file)
        except (OSError, ValueError) as error:
            annotate(path, 1, f"Not a String Catalog: {error}")
            problems += 1
            continue
        problems += check_catalog(path, catalogs[name])

    keys = set(catalogs.get("Localizable.xcstrings", {}).get("strings", {}))
    for path, line, key in uses:
        if "\ufffc" not in key and key in keys:
            continue
        pattern = key_pattern(key)
        if any(pattern.match(candidate) for candidate in keys):
            continue
        shown = key.replace("\ufffc", "\\(…)")
        annotate(path, line, f"No String Catalog entry for {shown!r}")
        problems += 1

    total = sum(len(catalog.get("strings", {})) for catalog in catalogs.values())
    if problems:
        print(f"==> {problems} String Catalog problem(s)")
        return 1
    print(f"==> String Catalogs complete: {total} strings in {1 + len(LANGUAGES)} languages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
