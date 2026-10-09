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
#   random     Randomness: .random, UUID(), arc4random, SystemRandomNumberGenerator,
#              .shuffled, .shuffle, randomElement. The engine draws nothing: the
#              host passes in a fresh identity.
#   hashing    Hasher and hashValue, whose seed changes per process.
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
    if failures:
        print(f"==> {failures} self-test case(s) failed")
        return 1
    print(f"==> Sync lint self-test passed: {len(SELF_TEST)} fixtures")
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
    if problems:
        print(f"==> {problems} Sync code rule violation(s)")
        return 1
    print("==> Sync code rules hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
