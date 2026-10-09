#!/usr/bin/env python3
#
# sync-lint.py
#
# Keeps the settings sync engine deterministic (analysis section 4.9, item 7;
# decision D-11). The engine in holzBar/Core/Sync is a pure function of its
# state, its event and its environment: the simulator can replay a trace only
# if one seed gives one trace, and a Dictionary or Set iterates in an order
# that changes from one process to the next, so a loop over one that is not
# sorted first can change what the engine decides from one launch to another.
#
# The rules, applied to holzBar/Core/Sync/*.swift with the comments and the
# contents of string literals removed:
#
#   unsorted   Iteration over a Dictionary or a Set that is not sorted first: a
#              tuple pattern in a for loop, a loop over a name declared with a
#              Dictionary or Set type (or returned by a function declared so),
#              .keys or .values, and .forEach.
#   clock      The real clock: Date(), Date.now, .now (the environment's `now`
#              is the injected one and passes), DispatchTime.now, systemUptime,
#              mach_absolute_time, ContinuousClock, SuspendingClock, Task.sleep.
#              The files of the I/O layer (IO_LAYER: the folder reader and writer and
#              the state store) are not the engine: the reader bounds its work with a
#              deadline of the host's clock, so they are exempt from this rule alone.
#   random    Randomness: .random, UUID(), arc4random, SystemRandomNumberGenerator,
#              .shuffled, .shuffle, randomElement. The engine draws nothing: the
#              host passes in a fresh identity.
#   hashing    Hasher and hashValue, whose seed changes per process.
#
# The writer rule (analysis section 4.9, item 7), applied to every Swift file under holzBar/:
#
#   writer     A write of a synced key outside the allowed sites. The synced keys are
#              listed in .github/sync-synced-keys.txt (the unit table's keys that are not
#              local; a test keeps the list in step with the table). A write is
#              Defaults.set, Defaults.removeObject, a set, setValue or removeObject on
#              UserDefaults, or CFPreferencesSetValue, whose key is named by its Defaults.Key
#              case or its raw value. Any automatic writer of a synced key would make sync
#              publish a change no user made, so a new writer has to be reviewed and added
#              to WRITER_ALLOWED with a reason. The sync code in holzBar/Core/Sync never
#              writes preferences, apart from SyncDefaultsStore, its one gateway.
#              A write of MacOS27Layout is allowed in fewer places (LAYOUT_WRITERS): a new
#              user path of the arrangement has to send an intent (plan 28-16).
#
# A line that is safe on purpose carries the marker `sync-lint: ordered <reason>`
# in a comment on that line or on the line above; the reason says why the order
# cannot matter (a sum, a membership test, a result that is sorted afterwards).
#
# It runs in the test job of .github/workflows/build.yml and locally:
#
#   python3 .github/scripts/sync-lint.py [--root DIR]
#   python3 .github/scripts/sync-lint.py --self-test
#
# Every finding is printed as a GitHub annotation and makes the script exit with
# status 1. Python standard library only.

import argparse
import os
import re
import sys

SYNC_DIR = "holzBar/Core/Sync"
# The files of holzBar/Core/Sync that do file I/O for the host and are not part of the pure engine.
IO_LAYER = {"holzBar/Core/Sync/SyncFolderAccess.swift", "holzBar/Core/Sync/SyncStateStore.swift"}
MARKER = re.compile(r"sync-lint:\s*ordered\s+(\S.*)")

CLOCK = [
    (r"\bDate\(\)", "Date()"),
    (r"\bDate\.now\b", "Date.now"),
    (r"(?<!environment)(?<!self)\.now\b", ".now"),
    (r"\bDispatchTime\b", "DispatchTime"),
    (r"\bsystemUptime\b", "systemUptime"),
    (r"\bmach_absolute_time\b", "mach_absolute_time"),
    (r"\b(?:ContinuousClock|SuspendingClock)\b", "a system clock"),
    (r"\bTask\.sleep\b", "Task.sleep"),
    (r"\bCFAbsoluteTimeGetCurrent\b", "CFAbsoluteTimeGetCurrent"),
]
RANDOM = [
    (r"\.random\b", ".random"),
    (r"\bUUID\(\)", "UUID()"),
    (r"\barc4random\w*\b", "arc4random"),
    (r"\bSystemRandomNumberGenerator\b", "SystemRandomNumberGenerator"),
    (r"\.shuffled\(", ".shuffled()"),
    (r"\.shuffle\(", ".shuffle()"),
    (r"\brandomElement\(", "randomElement()"),
]
HASHING = [
    (r"\bHasher\b", "Hasher"),
    (r"\bhashValue\b", "hashValue"),
]

SORTED_WORDS = ("sorted", "enumerated()", "zip(", ".indices", ".reversed()", "ordered(")

# What a declaration says about the order of what it holds. A type is read from its text: Set<...>,
# Dictionary<...> and [Key: Value] are unordered, [Element] and Array<...> are ordered, anything
# else (an inferred type) is unknown.
DECL_NAME_TYPE = re.compile(r"(?<![\w.])(\w+)\s*:\s*(?:inout\s+)?(.*)")
DECL_INIT = re.compile(r"\b(?:let|var)\s+(\w+)\s*=\s*(.*)")
DECL_ANY = re.compile(r"\b(?:let|var)\s+(\w+)\b")
DECL_FUNC = re.compile(r"\bfunc\s+(\w+)\b")
RETURNS = re.compile(r"->\s*(.*)")
FUNC_LINE = re.compile(r"\bfunc\s+\w+")

UNORDERED = "unordered"
ORDERED = "ordered"
UNKNOWN = "unknown"
BINDING = re.compile(r"\b(?:let|var)\s+(\w+)\b")


def classify_type(text):
    """UNORDERED, ORDERED or None for the type that starts the text."""
    text = text.strip()
    depth = 0
    end = len(text)
    for index, character in enumerate(text):
        if character in "([{<":
            depth += 1
        elif character in ")]}>":
            if depth == 0:
                end = index
                break
            depth -= 1
        elif character in ",={" and depth == 0:
            end = index
            break
    text = text[:end].strip().rstrip("?").strip()
    if text.startswith(("Set<", "Dictionary<")):
        return UNORDERED
    if text.startswith("Array<"):
        return ORDERED
    if text.startswith("["):
        inner = re.sub(r"\([^()]*\)", "()", text[1:-1] if text.endswith("]") else text[1:])
        if re.sub(r"\[[^\[\]]*\]", "[]", inner).count(":") > 0:
            return UNORDERED
        return ORDERED
    return None


def classify_initializer(text):
    text = text.strip()
    if "sorted" in text or "map(" in text:
        return None
    if text.startswith(("Set(", "Set<", "Dictionary(", "Dictionary<")) or text.startswith("[:]"):
        return UNORDERED
    if text.startswith("Array("):
        return ORDERED
    if text.startswith("[") and not text.startswith("[:"):
        return classify_type(text)
    return None


def annotate(path, line, message):
    print(f"::error file={path},line={line}::{message}")


def strip(text):
    """The text with comments and string contents blanked, character for character, and the
    lines a marker covers (its own line and the next)."""
    out = []
    marked = set()
    i = 0
    line = 1
    state = None
    block_depth = 0

    def note_marker(at):
        end = text.find("\n", at)
        end = len(text) if end < 0 else end
        if MARKER.search(text[at:end]):
            marked.add(line)
            marked.add(line + 1)

    while i < len(text):
        c = text[i]
        two = text[i:i + 2]
        if state is None:
            if two == "//":
                end = text.find("\n", i)
                end = len(text) if end < 0 else end
                note_marker(i)
                out.append(" " * (end - i))
                i = end
                continue
            if two == "/*":
                state = "block"
                block_depth = 1
                note_marker(i)
                out.append("  ")
                i += 2
                continue
            if text[i:i + 3] == '"""':
                state = "multi"
                out.append('"""')
                i += 3
                continue
            if c == '"':
                state = "string"
                out.append('"')
                i += 1
                continue
            out.append(c)
            if c == "\n":
                line += 1
            i += 1
        elif state == "block":
            if two == "/*":
                block_depth += 1
                out.append("  ")
                i += 2
                continue
            if two == "*/":
                block_depth -= 1
                out.append("  ")
                i += 2
                if block_depth == 0:
                    state = None
                continue
            if c == "\n":
                line += 1
                note_marker(i + 1)
            out.append("\n" if c == "\n" else " ")
            i += 1
        elif state == "string":
            if c == "\\" and i + 1 < len(text):
                out.append("  ")
                i += 2
                continue
            if c == '"':
                state = None
                out.append('"')
            elif c == "\n":
                state = None
                out.append("\n")
                line += 1
            else:
                out.append(" ")
            i += 1
        else:  # a multi-line string literal
            if text[i:i + 3] == '"""':
                state = None
                out.append('"""')
                i += 3
                continue
            out.append("\n" if c == "\n" else " ")
            if c == "\n":
                line += 1
            i += 1
    return "".join(out), marked


def scopes(lines):
    """For every line the number of the `func` line that encloses it (0 outside any function)."""
    result = [0] * len(lines)
    stack = []  # (function line, depth inside its body)
    depth = 0
    pending = None
    for index, line in enumerate(lines):
        number = index + 1
        if FUNC_LINE.search(line):
            pending = number
            result[index] = number
        elif pending is not None:
            result[index] = pending
        else:
            result[index] = stack[-1][0] if stack else 0
        for character in line:
            if character == "{":
                depth += 1
                if pending is not None:
                    stack.append((pending, depth))
                    pending = None
            elif character == "}":
                if stack and stack[-1][1] == depth:
                    stack.pop()
                depth -= 1
    return result


def declarations(lines):
    """What the declarations say: member names (outside any function) and per function, as UNORDERED or ORDERED, and the
    functions that return an unordered collection."""
    scope = scopes(lines)
    members = {}
    local = {}
    functions = set()
    for index, line in enumerate(lines):
        function = scope[index]
        table = local.setdefault(function, {}) if function else members
        if function:
            # A name bound in the function (a pattern, a loop variable, a parameter) hides a member of the same name.
            for match in BINDING.finditer(line):
                table.setdefault(match.group(1), UNKNOWN)
            for match in re.finditer(r"\bfor\s+(\w+)\s+in\b", line):
                table.setdefault(match.group(1), UNKNOWN)
        for match in DECL_NAME_TYPE.finditer(line):
            kind = classify_type(match.group(2))
            if function:
                table.setdefault(match.group(1), kind or UNKNOWN)
            if kind and not re.match(r"\s*(?:case|default)\b", line):
                table[match.group(1)] = kind
        for match in DECL_INIT.finditer(line):
            kind = classify_initializer(match.group(2))
            if kind:
                table[match.group(1)] = kind
        found = DECL_FUNC.search(line)
        if found:
            returns = RETURNS.search(line)
            if returns and classify_type(returns.group(1)) == UNORDERED:
                functions.add(found.group(1))
    return scope, members, local, functions


def collect_names(stripped_files):
    """Member names and function names declared unordered anywhere in the engine (a loop in one file reads a
    property another file declares)."""
    names = set()
    functions = set()
    for text in stripped_files:
        _, members, _, found = declarations(text.splitlines())
        names.update(name for name, kind in members.items() if kind == UNORDERED)
        functions.update(found)
    return names, functions


FOR_LOOP = re.compile(r"\bfor\s+(.+?)\s+in\s+(.+?)(?:\s+where\b.*)?\s*\{?\s*$")


def has_sorted(text):
    return any(word in text for word in SORTED_WORDS)


def iterates_unordered(expression, names, functions, local, tuple_pattern):
    """Whether `for ... in expression` runs over a Dictionary or a Set that is not sorted first. For a tuple pattern a
    collection of unknown type counts too, since a tuple pattern is how a Dictionary is usually taken apart."""
    expression = re.sub(r"\b(?:try|await)\b[?!]?", "", expression).strip()
    if re.search(r"\.(?:keys|values)\b", expression):
        return True
    call = re.match(r"^([\w.]+)\(", expression)
    if call:
        return call.group(1).split(".")[-1] in functions
    path = re.match(r"^[\w.]+", expression)
    if not path:
        return False
    components = path.group(0).split(".")
    if len(components) == 1 and components[0] in local:
        return local[components[0]] == UNORDERED or (tuple_pattern and local[components[0]] == UNKNOWN)
    if components[-1] in names:
        return True
    return tuple_pattern


def lint_text(path, raw, names, functions):
    stripped, marked = strip(raw)
    findings = []
    lines = stripped.splitlines()
    scope, _, local, _ = declarations(lines)

    def report(number, rule, message):
        if number in marked:
            return
        findings.append((path, number, f"{rule}: {message}"))

    for number, line in enumerate(lines, start=1):
        for rule, table in (("clock", CLOCK), ("random", RANDOM), ("hashing", HASHING)):
            if rule == "clock" and path in IO_LAYER:
                continue
            for pattern, label in table:
                if re.search(pattern, line):
                    report(number, rule, f"{label} makes the engine depend on something other than its inputs")
        loop = FOR_LOOP.search(line)
        if loop and not line.lstrip().startswith("//"):
            pattern, expression = loop.group(1), loop.group(2)
            if not has_sorted(expression):
                tuple_pattern = pattern.strip().startswith("(")
                if iterates_unordered(expression, names, functions, local.get(scope[number - 1], {}), tuple_pattern):
                    report(number, "unsorted", "a for loop iterates a Dictionary or a Set that is not sorted first")
        if re.search(r"\.forEach\b", line) and not has_sorted(line):
            report(number, "unsorted", ".forEach iterates in an unspecified order when it is called on a Dictionary or a Set")
        if not loop and not has_sorted(line):
            # .keys and .values are the unordered sequence of a Dictionary; a property of that name (`snapshot.values`)
            # is the Dictionary itself and is not flagged unless something walks it.
            walked = re.search(r"\.(?:keys|values)\s*\.\s*(?:map|filter|compactMap|flatMap|reduce|first|last|joined|prefix|dropFirst|lazy|enumerated|forEach)\b", line)
            if walked:
                report(number, "unsorted", ".keys or .values is walked in an order the language does not specify")
    return findings


# MARK: The writer rule

APP_DIR = "holzBar"
SYNCED_KEYS_FILE = ".github/sync-synced-keys.txt"
DEFAULTS_FILE = "holzBar/Core/Defaults.swift"
SYNC_GATEWAY = "holzBar/Core/Sync/SyncDefaultsStore.swift"

# The files that may write a synced key, each with the reason. A path ending in "/" is a directory.
# A file is allowed when it is the setter of a setting, owns the setting, applies an explicit action of
# the user, or is the sync code's own apply. Add a file here only after deciding which of these it is.
WRITER_ALLOWED = [
    ("holzBar/Settings/Models/", "allowed: the settings models write their own setting in its setter"),
    ("holzBar/MenuBar/Spacers/MenuBarSpacers.swift", "allowed: owns SpacerCount and SpacerWidth, written by the user's choice"),
    ("holzBar/MenuBar/Groups/MenuBarItemGroups.swift", "allowed: owns ItemGroups, written when the user edits a group"),
    ("holzBar/MenuBar/Appearance/MenuBarAppearanceManager.swift", "allowed: owns the appearance, written when the user changes it"),
    ("holzBar/MenuBar/RevealRules/RevealRules.swift", "allowed: owns RevealRules, written when the user edits a rule"),
    ("holzBar/MenuBar/MenuBarItems/ItemIconStore.swift", "allowed: the setter of ItemIcons, the user's choice of an icon"),
    ("holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift", "allowed: the setter of RevealOnChangeItems, the user's mark"),
    ("holzBar/MenuBar/MacOS27/Concealer27.swift", "allowed: owns the macOS 27 arrangement and the applications it knows"),
    ("holzBar/MenuBar/Profiles/LayoutProfiles.swift", "allowed: saves, renames and deletes profiles and applies one"),
    ("holzBar/Utilities/SettingsBackup.swift", "allowed: Import, an explicit action of the user"),
    ("holzBar/Utilities/Migration.swift", "allowed: the one-time import of an earlier app's settings"),
    (SYNC_GATEWAY, "allowed: the sync code's own apply"),
]

# The files that may write the macOS 27 arrangement (MacOS27Layout), each of them a user path or an owner.
LAYOUT_WRITERS = [
    "holzBar/MenuBar/MacOS27/Concealer27.swift",
    "holzBar/MenuBar/Profiles/LayoutProfiles.swift",
    "holzBar/Utilities/SettingsBackup.swift",
    "holzBar/Utilities/Migration.swift",
    SYNC_GATEWAY,
]
LAYOUT_KEY = "MacOS27Layout"
LAYOUT_MESSAGE = (
    "a new writer of MacOS27Layout; the user paths of the arrangement are the move in the Layout pane "
    "(Concealer27.setSection), a profile the user applies (LayoutProfiles.apply) and Import "
    "(SettingsBackup.apply), and each sends an intent (plan 28-16); add this writer there, or to LAYOUT_WRITERS "
    "with its reason"
)

WRITE_CALL = re.compile(
    r"(?:\bDefaults|\b\w*[dD]efaults\w*|\bstandard)\s*\.\s*(?:set|removeObject|setValue)\s*\("
    r"|\bCFPreferencesSet(?:App)?Value\s*\("
)
CASE_DECLARATION = re.compile(r'\bcase\s+(\w+)\s*=\s*"([^"]+)"')


def is_allowed(path, table):
    return any(path == prefix or (prefix.endswith("/") and path.startswith(prefix)) for prefix, _ in table)


def case_names(defaults_text, synced):
    """The Swift case name of every synced raw key, from the declaration `case name = "Raw"` of Defaults.Key."""
    return {name: raw for name, raw in CASE_DECLARATION.findall(defaults_text) if raw in synced}


def matching_paren(text, start):
    """The index of the parenthesis that closes the one at `start`, in text without strings and comments."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return -1


def top_level_arguments(text, begin, end):
    """The (start, end) offsets of each argument of the call whose argument list is text[begin:end]."""
    arguments = []
    depth = 0
    start = begin
    for index in range(begin, end):
        character = text[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            arguments.append((start, index))
            start = index + 1
    arguments.append((start, end))
    return arguments


def lint_writers(path, raw, synced, names):
    """The findings of the writer rule for one file: `synced` is the set of raw synced keys and `names` the map from
    the case name of a synced key to its raw value."""
    stripped, marked = strip(raw)
    findings = []
    in_core = path.startswith(SYNC_DIR + "/")
    for call in WRITE_CALL.finditer(stripped):
        open_paren = call.end() - 1
        close = matching_paren(stripped, open_paren)
        if close < 0:
            continue
        number = stripped.count("\n", 0, call.start()) + 1
        if number in marked:
            continue
        arguments = top_level_arguments(stripped, open_paren + 1, close)
        if "CFPreferencesSet" in call.group(0):
            key_arguments = arguments[:1]
        else:
            key_arguments = [(a, b) for a, b in arguments if re.match(r"\s*forKey\s*:", stripped[a:b])]
        if in_core and path != SYNC_GATEWAY:
            findings.append((path, number, "writer: the sync code in holzBar/Core/Sync never writes preferences; SyncDefaultsStore is its one gateway"))
            continue
        written = set()
        for begin, end in key_arguments:
            written.update(names[name] for name in re.findall(r"\.(\w+)", stripped[begin:end]) if name in names)
            for quote in re.finditer(r'"([^"\n]*)"', raw[begin:end]):
                # The literal counts only where the stripped text has a string, not a comment.
                if stripped[begin + quote.start()] == '"' and quote.group(1) in synced:
                    written.add(quote.group(1))
        for key in sorted(written):
            if key == LAYOUT_KEY and path not in LAYOUT_WRITERS:
                findings.append((path, number, f"writer: {LAYOUT_MESSAGE}"))
            elif key != LAYOUT_KEY and not is_allowed(path, WRITER_ALLOWED):
                findings.append((path, number, f"writer: a write of the synced key {key} outside the allowed sites; sync counts it as a change the user made"))
    return findings


def read_synced_keys(root):
    with open(os.path.join(root, SYNCED_KEYS_FILE), encoding="utf-8") as file:
        return {line.strip() for line in file if line.strip()}


def lint_all_writers(root):
    """The findings of the writer rule over holzBar/, and the allow-list entries that name nothing."""
    synced = read_synced_keys(root)
    with open(os.path.join(root, DEFAULTS_FILE), encoding="utf-8") as file:
        names = case_names(file.read(), synced)
    findings = []
    for directory, _, files in sorted(os.walk(os.path.join(root, APP_DIR))):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            full = os.path.join(directory, name)
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, encoding="utf-8") as file:
                findings.extend(lint_writers(relative, file.read(), synced, names))
    for prefix, _ in WRITER_ALLOWED:
        if not os.path.exists(os.path.join(root, prefix)):
            findings.append((prefix, 1, "writer: an allowed site that does not exist; update WRITER_ALLOWED in sync-lint.py"))
    for path in LAYOUT_WRITERS:
        if not os.path.exists(os.path.join(root, path)):
            findings.append((path, 1, "writer: a layout writer that does not exist; update LAYOUT_WRITERS in sync-lint.py"))
    return findings


WRITER_SYNCED = {"ShowOnHover", "Hotkeys", "MacOS27Layout", "ItemIcons"}
WRITER_NAMES = {"showOnHover": "ShowOnHover", "hotkeys": "Hotkeys", "macOS27Layout": "MacOS27Layout", "itemIcons": "ItemIcons"}
SETTINGS_MODEL = "holzBar/Settings/Models/GeneralSettings.swift"
SOME_FILE = "holzBar/MenuBar/Other.swift"
CONCEALER = "holzBar/MenuBar/MacOS27/Concealer27.swift"

WRITER_SELF_TEST = [
    # (should be flagged, path, snippet)
    (True, SOME_FILE, "Defaults.set(true, forKey: .showOnHover)\n"),
    (True, SOME_FILE, "Defaults.removeObject(forKey: .hotkeys)\n"),
    (True, SOME_FILE, "UserDefaults.standard.set(value, forKey: \"ShowOnHover\")\n"),
    (True, SOME_FILE, "Defaults.set(\n    layout.mapValues(\\.rawValue),\n    forKey: Defaults.Key.itemIcons\n)\n"),
    (True, SOME_FILE, "CFPreferencesSetAppValue(\"Hotkeys\" as CFString, data, kCFPreferencesCurrentApplication)\n"),
    (True, "holzBar/Core/Sync/SyncMerge.swift", "Defaults.set(1, forKey: .somethingLocal)\n"),
    (False, SETTINGS_MODEL, "Defaults.set(true, forKey: .showOnHover)\n"),
    (False, "holzBar/Settings/Models/Other.swift", "Defaults.set(true, forKey: .showOnHover)\n"),
    (False, SYNC_GATEWAY, "defaults.set(value, forKey: key)\n"),
    (False, SOME_FILE, "Defaults.set(1, forKey: .itemSections)\n"),
    (False, SOME_FILE, "let value = Defaults.bool(forKey: .showOnHover)\n"),
    (False, SOME_FILE, "Defaults.set(settings.showOnHover, forKey: .knownItemTags)\n"),
    (False, SOME_FILE, "// Defaults.set(true, forKey: .showOnHover)\nlet text = \"Defaults.set(true, forKey: .showOnHover)\"\n"),
    (False, SOME_FILE, "// sync-lint: ordered not a user setting\nDefaults.set(true, forKey: .showOnHover)\n"),
    # The arrangement is allowed in fewer places, and the message names the user paths.
    (True, SETTINGS_MODEL, "Defaults.set(layout, forKey: .macOS27Layout)\n"),
    (False, CONCEALER, "Defaults.set(layout, forKey: .macOS27Layout)\n"),
]


def writer_self_test():
    failures = 0
    for expected, path, snippet in WRITER_SELF_TEST:
        found = lint_writers(path, snippet, WRITER_SYNCED, WRITER_NAMES)
        if bool(found) != expected:
            failures += 1
            print(f"self-test failed ({'expected a finding' if expected else 'expected none'}, rule writer, {path}):\n{snippet}  found: {found}")
    layout = lint_writers(SOME_FILE, "Defaults.set(layout, forKey: .macOS27Layout)\n", WRITER_SYNCED, WRITER_NAMES)
    if not layout or "28-16" not in layout[0][2]:
        failures += 1
        print(f"self-test failed (a new writer of MacOS27Layout has to name the user paths of plan 28-16): {layout}")
    return failures


SELF_TEST = [
    # (should be flagged, rule, snippet)
    (True, "unsorted", "var registers: [Key: [Entry]] = [:]\nfor (key, entries) in registers {\n}\n"),
    (True, "unsorted", "var shown: Set<String> = []\nfor item in shown {\n}\n"),
    (True, "unsorted", "func units() -> Set<String> { [] }\nfor unit in units() {\n}\n"),
    (True, "unsorted", "for key in table.keys {\n}\n"),
    (True, "unsorted", "values.forEach { print($0) }\n"),
    (True, "unsorted", "let all = state.registers.values.map { $0.count }\n"),
    (False, "unsorted", "var registers: [Key: [Entry]] = [:]\nfor (key, entries) in registers.sorted(by: { $0.key < $1.key }) {\n}\n"),
    (False, "unsorted", "for (index, byte) in bytes.enumerated() {\n}\n"),
    (False, "unsorted", "for key in registers.keys.sorted() {\n}\n"),
    (False, "unsorted", "// sync-lint: ordered the sum does not depend on the order\nfor (key, entries) in registers {\n}\n"),
    (False, "unsorted", "for (key, entries) in registers { // sync-lint: ordered a membership test\n}\n"),
    (False, "unsorted", "let count = registers.values.count\n"),
    (False, "unsorted", "// for (key, value) in registers {\nlet text = \"for (key, value) in registers {\"\n"),
    (True, "clock", "let started = Date()\n"),
    (True, "clock", "let started = Date.now\n"),
    (True, "clock", "let started = clock.now\n"),
    (True, "clock", "let up = ProcessInfo.processInfo.systemUptime\n"),
    (False, "clock", "let started = environment.now\n"),
    (False, "clock", "let date = Date(timeIntervalSince1970: 0)\n"),
    (True, "random", "let id = UUID()\n"),
    (True, "random", "let draw = Int.random(in: 0..<4)\n"),
    (True, "random", "let order = items.shuffled()\n"),
    (True, "random", "let bits = arc4random()\n"),
    (False, "random", "// UUID() is drawn by the host\nlet id = fresh.mac\n"),
    (True, "hashing", "var hasher = Hasher()\n"),
    (True, "hashing", "let seed = value.hashValue\n"),
    (False, "hashing", "let digest = SyncDigest.of(value)\n"),
]


def self_test():
    failures = 0
    for expected, rule, snippet in SELF_TEST:
        stripped = [strip(snippet)[0]]
        names, functions = collect_names(stripped)
        found = [message for _, _, message in lint_text("fixture.swift", snippet, names, functions) if message.startswith(rule + ":")]
        if bool(found) != expected:
            failures += 1
            print(f"self-test failed ({'expected a finding' if expected else 'expected none'}, rule {rule}):\n{snippet}  found: {found}")
    failures += writer_self_test()
    if failures:
        print(f"==> {failures} self-test case(s) failed")
        return 1
    print(f"==> Sync lint self-test passed: {len(SELF_TEST) + len(WRITER_SELF_TEST) + 1} fixtures")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Determinism lint for holzBar/Core/Sync")
    parser.add_argument("--root", default=".", help="the repository root")
    parser.add_argument("--self-test", action="store_true", help="check the rules against fixtures and exit")
    arguments = parser.parse_args()
    if arguments.self_test:
        return self_test()
    directory = os.path.join(arguments.root, SYNC_DIR)
    try:
        names_on_disk = sorted(name for name in os.listdir(directory) if name.endswith(".swift"))
    except OSError as error:
        annotate(SYNC_DIR, 1, f"Cannot read the engine sources: {error}")
        return 1
    sources = {}
    for name in names_on_disk:
        with open(os.path.join(directory, name), encoding="utf-8") as file:
            sources[f"{SYNC_DIR}/{name}"] = file.read()
    names, functions = collect_names([strip(text)[0] for text in sources.values()])
    problems = 0
    for path in sorted(sources):
        for found_path, line, message in lint_text(path, sources[path], names, functions):
            annotate(found_path, line, message)
            problems += 1
    try:
        writer_findings = lint_all_writers(arguments.root)
    except OSError as error:
        annotate(SYNCED_KEYS_FILE, 1, f"Cannot read the sources for the writer rule: {error}")
        return 1
    for found_path, line, message in writer_findings:
        annotate(found_path, line, message)
        problems += 1
    if problems:
        print(f"==> {problems} Sync code rule violation(s)")
        return 1
    print("==> Sync code rules hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
