#!/usr/bin/env python3
#
# privacy-check.py
#
# Proves two of holzBar's privacy promises (see CLAUDE.md, "Private") on the
# source tree:
#
#   network  No networking API appears in holzBar/, Shared/, MenuBarItemService/
#            or Package.swift (except the lines .github/network-allowlist.txt
#            allows), no Package.swift depends on a package, and every Swift
#            package the Xcode project references or Package.resolved pins is
#            listed in .github/allowed-packages.txt.
#   logs     Every interpolation in a Logger call names its privacy, and no
#            interpolation makes personal data (item tags, bundle identifiers,
#            app and profile names, errors) public.
#
# It runs in the no-network job of .github/workflows/build.yml and locally:
#
#   python3 .github/scripts/privacy-check.py network
#   python3 .github/scripts/privacy-check.py logs [--root DIR]
#
# It walks the file system (not git), so it also works on an extracted copy of
# the repository. Every violation is printed as a GitHub annotation and makes
# the script exit with status 1. Python standard library only.

import argparse
import json
import os
import plistlib
import re
import string
import sys

SOURCE_DIRS = ("holzBar", "Shared", "MenuBarItemService")
NETWORK_ALLOWLIST = ".github/network-allowlist.txt"
ALLOWED_PACKAGES = ".github/allowed-packages.txt"
PACKAGE_RESOLVED = "holzBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PROJECT = "holzBar.xcodeproj/project.pbxproj"

# The Xcode project's Swift package objects. A reference names a package by its URL or
# path; a product dependency names the reference it comes from.
PACKAGE_REFERENCE_TYPES = ("XCRemoteSwiftPackageReference", "XCLocalSwiftPackageReference")
PACKAGE_PRODUCT_TYPE = "XCSwiftPackageProductDependency"
PACKAGE_LOCATION_KEYS = ("repositoryURL", "relativePath")
# The lists that attach those objects to the project and its targets.
PACKAGE_LISTS = {
    "packageReferences": PACKAGE_REFERENCE_TYPES,
    "packageProductDependencies": (PACKAGE_PRODUCT_TYPE,),
}
PACKAGE_DEPENDENCY = re.compile(r"\.package\s*\(")
SKIPPED_DIRECTORIES = {".git", ".build", "DerivedData"}

# Networking APIs, each with a short name for the message.
NETWORK_PATTERNS = [
    ("URLSession", re.compile(r"\bURLSession\b")),
    ("NSURLSession", re.compile(r"\bNSURLSession\b")),
    ("URLRequest", re.compile(r"\bURLRequest\b")),
    ("NSURLConnection", re.compile(r"\bNSURLConnection\b")),
    ("Network framework type", re.compile(r"\bNW[A-Z][A-Za-z]*\b")),
    ("Network framework C call", re.compile(r"\bnw_[a-z_]+\(")),
    ("WKWebView", re.compile(r"\bWKWebView\b")),
    ("import WebKit", re.compile(r"\bimport\s+WebKit\b")),
    ("SFSafariViewController", re.compile(r"\bSFSafariViewController\b")),
    ("CFSocket", re.compile(r"\bCFSocket")),
    ("CFStream", re.compile(r"\bCFStream(Create|Pair)")),
    ("SCNetworkReachability", re.compile(r"\bSCNetworkReachability")),
    ("getaddrinfo", re.compile(r"\bgetaddrinfo\b")),
    ("socket()", re.compile(r"\bsocket\(")),
    ("connect()", re.compile(r"\bconnect\(")),
    ("AsyncImage", re.compile(r"\bAsyncImage\b")),
    ("import Network", re.compile(r"\bimport\s+Network\b")),
]

LOG_LEVELS = r"(?:log|trace|debug|info|notice|warning|error|critical|fault)"

# A Logger call whose string literal (single- or triple-quoted) has an
# interpolation without `privacy:`. The scanner below (log_interpolations)
# finds the same and also handles raw strings and string literals inside an
# interpolation; this regex is kept as a second, independent pass.
UNANNOTATED_LOG = re.compile(
    r'\b(?:\w*[lL]ogger|Logger\.\w+)\.' + LOG_LEVELS + r'\(\s*'
    r'"(?:"")?'
    r'(?:[^"\\]|\\[^(]|\\\((?:[^()]|\([^()]*\))*?privacy:(?:[^()]|\([^()]*\))*\))*?'
    r'\\\((?:(?!privacy:)(?:[^()]|\([^()]*\)))*\)'
)

# The start of a Logger call, up to its first argument.
LOG_CALL = re.compile(r'\b(?:\w*[lL]ogger|Logger\.\w+)\.' + LOG_LEVELS + r'\(\s*')

# Expressions that carry personal data and must not be logged publicly.
PERSONAL_DATA = [
    ("item.logString", re.compile(r"\bitem\.logString\b")),
    ("app.logString", re.compile(r"\bapp\.logString\b")),
    ("destination.logString", re.compile(r"\bdestination\.logString\b")),
    (".tag", re.compile(r"\.tag\b")),
    ("namespace", re.compile(r"namespace", re.IGNORECASE)),
    ("bundleID", re.compile(r"bundleID")),
    ("bundleIdentifier", re.compile(r"bundleIdentifier")),
    ("localizedName", re.compile(r"localizedName")),
    ("profile.name", re.compile(r"\bprofile\.name\b")),
    ("ownerName", re.compile(r"ownerName")),
    ("names", re.compile(r"\bnames\b")),
    ("tag", re.compile(r"\btags?\b")),
    ("excluded items", re.compile(r"\bexcluded\b")),
    ("error", re.compile(r"\berror\b(?!\.code)")),
    ("window title", re.compile(r"\b(?:title|windowTitle|kCGWindowName)\b")),
]

PUBLIC = re.compile(r"privacy:\s*\.public\b")


def annotate(path, line, message):
    print(f"::error file={path},line={line}::{message}")


def read_list(root, relative):
    path = os.path.join(root, relative)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as file:
        lines = [line.strip() for line in file]
    return [line for line in lines if line and not line.startswith("#")]


def swift_files(root):
    for directory in SOURCE_DIRS:
        base = os.path.join(root, directory)
        for current, dirs, files in os.walk(base):
            dirs.sort()
            for name in sorted(files):
                if name.endswith(".swift"):
                    full = os.path.join(current, name)
                    yield os.path.relpath(full, root).replace(os.sep, "/")
    if os.path.exists(os.path.join(root, "Package.swift")):
        yield "Package.swift"


def read_text(root, relative):
    with open(os.path.join(root, relative), encoding="utf-8") as file:
        return file.read()


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


class PlistError(ValueError):
    pass


# CoreFoundation's characters of an unquoted string in an old-style property list.
UNQUOTED = frozenset(string.ascii_letters + string.digits + "_$/:.-")
ESCAPES = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v"}


class OldStylePlist:
    """Reads an old-style (OpenStep) property list the way CoreFoundation, and so Xcode, does.

    A project matched as text let a package through: comments are allowed between any two
    tokens, and strings may be quoted or escaped, so `isa /* c */ = XC...;` is a package
    reference to Xcode and none to a regular expression.
    """

    def __init__(self, text):
        self.text = text
        self.index = 0

    def parse(self):
        value = self.value()
        if self.skip() < len(self.text):
            raise PlistError(f"unexpected text at line {line_of(self.text, self.index)}")
        return value

    def skip(self):
        """Skips white space and comments; returns the index of the next token."""
        text = self.text
        while self.index < len(text):
            character = text[self.index]
            if character.isspace():
                self.index += 1
            elif text.startswith("//", self.index):
                end = text.find("\n", self.index)
                self.index = len(text) if end < 0 else end + 1
            elif text.startswith("/*", self.index):
                end = text.find("*/", self.index + 2)
                if end < 0:
                    raise PlistError("unterminated comment")
                self.index = end + 2
            else:
                break
        return self.index

    def expect(self, character):
        if self.skip() >= len(self.text) or self.text[self.index] != character:
            raise PlistError(f"expected {character!r} at line {line_of(self.text, self.index)}")
        self.index += 1

    def peek(self):
        return self.text[self.index] if self.skip() < len(self.text) else ""

    def value(self):
        character = self.peek()
        if character == "{":
            self.index += 1
            dictionary = {}
            while self.peek() != "}":
                key = self.string()
                self.expect("=")
                dictionary[key] = self.value()
                if self.peek() != "}":
                    self.expect(";")
            self.index += 1
            return dictionary
        if character == "(":
            self.index += 1
            array = []
            while self.peek() != ")":
                array.append(self.value())
                if self.peek() != ")":
                    self.expect(",")
            self.index += 1
            return array
        if character == "<":
            end = self.text.find(">", self.index)
            if end < 0:
                raise PlistError("unterminated data")
            digits = "".join(self.text[self.index + 1:end].split())
            self.index = end + 1
            try:
                return bytes.fromhex(digits)
            except ValueError as error:
                raise PlistError(str(error)) from error
        return self.string()

    def string(self):
        text = self.text
        character = self.peek()
        if character in "\"'":
            self.index += 1
            parts = []
            while self.index < len(text) and text[self.index] != character:
                if text[self.index] == "\\" and self.index + 1 < len(text):
                    parts.append(self.escaped())
                else:
                    parts.append(text[self.index])
                    self.index += 1
            if self.index >= len(text):
                raise PlistError("unterminated string")
            self.index += 1
            return "".join(parts)
        start = self.index
        while self.index < len(text) and text[self.index] in UNQUOTED:
            self.index += 1
        if self.index == start:
            raise PlistError(f"expected a string at line {line_of(text, start)}")
        return text[start:self.index]

    def escaped(self):
        text = self.text
        self.index += 1
        character = text[self.index]
        self.index += 1
        if character in "01234567":
            digits = character
            while len(digits) < 3 and self.index < len(text) and text[self.index] in "01234567":
                digits += text[self.index]
                self.index += 1
            return chr(int(digits, 8))
        if character == "U":
            digits = ""
            while len(digits) < 4 and self.index < len(text) and text[self.index] in string.hexdigits:
                digits += text[self.index]
                self.index += 1
            return chr(int(digits, 16)) if digits else "U"
        return ESCAPES.get(character, character)


def read_plist(data):
    """Reads a property list in any format Xcode reads a project in."""
    if data.startswith(b"bplist") or data.lstrip().startswith(b"<"):
        try:
            return plistlib.loads(data)
        except Exception as error:
            raise PlistError(str(error)) from error
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as error:
        raise PlistError(str(error)) from error
    try:
        return json.loads(text)
    except ValueError:
        return OldStylePlist(text).parse()


def normalized_location(location):
    location = location.strip().lower().rstrip("/")
    if location.endswith(".git"):
        location = location[: -len(".git")]
    return location


def package_manifests(root):
    for current, dirs, files in os.walk(root):
        dirs[:] = sorted(name for name in dirs if name not in SKIPPED_DIRECTORIES)
        if "Package.swift" in files:
            yield os.path.relpath(os.path.join(current, "Package.swift"), root).replace(os.sep, "/")


def check_project(root, allowed, has_resolved):
    """Checks the Swift packages of the Xcode project; returns the number of violations.

    xcodebuild resolves a project's packages by itself when Package.resolved is missing, so
    the project's own references are checked, and need the pins to be committed.
    """
    with open(os.path.join(root, PROJECT), "rb") as file:
        data = file.read()
    text = data.decode("utf-8", errors="replace")
    try:
        project = read_plist(data)
    except (PlistError, RecursionError) as error:
        annotate(PROJECT, 1, f"The project could not be read as a property list ({error}), so its packages cannot be checked")
        return 1
    objects = project.get("objects") if isinstance(project, dict) else None
    if not isinstance(objects, dict):
        annotate(PROJECT, 1, "The project has no objects, so its packages cannot be checked")
        return 1

    def line(identifier):
        offset = text.find(identifier)
        return line_of(text, offset) if offset >= 0 else 1

    violations = 0
    for identifier, entry in objects.items():
        if not isinstance(entry, dict):
            continue
        kind = entry.get("isa")
        if kind in PACKAGE_REFERENCE_TYPES:
            locations = [
                normalized_location(entry[key])
                for key in PACKAGE_LOCATION_KEYS
                if isinstance(entry.get(key), str)
            ]
            for location in locations or ["(no URL or path)"]:
                if location not in allowed:
                    annotate(PROJECT, line(identifier), f"Package {location} is not in {ALLOWED_PACKAGES}")
                    violations += 1
            if not has_resolved:
                annotate(PROJECT, line(identifier), f"A package is referenced without a committed {PACKAGE_RESOLVED}")
                violations += 1
        elif kind == PACKAGE_PRODUCT_TYPE:
            # A product without a reference comes from a local package added as a folder; its
            # location is not in the project, so it cannot be checked against the list.
            reference = entry.get("package")
            package = objects.get(reference) if isinstance(reference, str) else None
            if not isinstance(package, dict) or package.get("isa") not in PACKAGE_REFERENCE_TYPES:
                annotate(PROJECT, line(identifier), "A package product names no package reference, so its package cannot be checked")
                violations += 1
        for key, kinds in PACKAGE_LISTS.items():
            members = entry.get(key, [])
            for member in members if isinstance(members, list) else [members]:
                target = objects.get(member) if isinstance(member, str) else None
                if not isinstance(target, dict) or target.get("isa") not in kinds:
                    annotate(PROJECT, line(identifier), f"{key} lists {member!r}, which is not a {' or '.join(kinds)}")
                    violations += 1

    # Nothing is allowed today, so any mention of a package object fails, read or not.
    if not allowed and not violations:
        for kind in (*PACKAGE_REFERENCE_TYPES, PACKAGE_PRODUCT_TYPE):
            offset = text.find(kind)
            if offset >= 0:
                annotate(PROJECT, line_of(text, offset), f"The project mentions {kind}, and {ALLOWED_PACKAGES} allows no package")
                violations += 1
    return violations


def check_network(root):
    allowlist = []
    for entry in read_list(root, NETWORK_ALLOWLIST):
        path, separator, token = entry.partition(":")
        if separator:
            allowlist.append((path.strip(), token.strip()))

    violations = 0
    for path in swift_files(root):
        text = read_text(root, path)
        for number, line in enumerate(text.splitlines(), start=1):
            for name, pattern in NETWORK_PATTERNS:
                if not pattern.search(line):
                    continue
                allowed = any(
                    path == allowed_path and token in line
                    for allowed_path, token in allowlist
                )
                if not allowed:
                    annotate(path, number, f"Networking API ({name}); holzBar never connects to the network")
                    violations += 1

    # Every Package.swift, not only the root one: a local package the project links pulls
    # in whatever its own manifest depends on.
    for path in package_manifests(root):
        text = read_text(root, path)
        match = PACKAGE_DEPENDENCY.search(text)
        if match:
            annotate(path, line_of(text, match.start()), "Package.swift must not depend on a package")
            violations += 1

    allowed = {normalized_location(entry) for entry in read_list(root, ALLOWED_PACKAGES)}
    resolved = os.path.join(root, PACKAGE_RESOLVED)
    if os.path.exists(os.path.join(root, PROJECT)):
        violations += check_project(root, allowed, os.path.exists(resolved))

    if os.path.exists(resolved):
        with open(resolved, encoding="utf-8") as file:
            pins = json.load(file).get("pins", [])
        for pin in pins:
            location = normalized_location(pin.get("location", ""))
            if location not in allowed:
                annotate(PACKAGE_RESOLVED, 1, f"Package {location} is not in {ALLOWED_PACKAGES}")
                violations += 1

    if violations:
        print(f"==> {violations} network violation(s)")
        return 1
    print("==> No network code")
    return 0


def skip_nested_string(text, index):
    """Returns the index after the plain string literal that starts at `index`."""
    if text.startswith('"""', index):
        end = text.find('"""', index + 3)
        return len(text) if end < 0 else end + 3
    index += 1
    while index < len(text) and text[index] not in '"\n':
        index += 2 if text[index] == "\\" else 1
    return index + 1


def log_interpolations(text, start):
    """Yields (offset, body) for each interpolation of the string literal at `start`.

    Handles single-line, multi-line (triple-quoted) and raw (#"...") literals, and
    parentheses and string literals inside an interpolation.
    """
    hashes = 0
    while text.startswith("#", start + hashes):
        hashes += 1
    index = start + hashes
    if text.startswith('"""', index):
        closing = '"""' + "#" * hashes
        index += 3
    elif text.startswith('"', index):
        closing = '"' + "#" * hashes
        index += 1
    else:
        return
    escape = "\\" + "#" * hashes
    while index < len(text):
        if text.startswith(closing, index):
            return
        if text.startswith(escape, index):
            index += len(escape)
            if index < len(text) and text[index] == "(":
                begin = index + 1
                depth = 1
                index += 1
                while index < len(text) and depth:
                    character = text[index]
                    if character == '"':
                        index = skip_nested_string(text, index)
                        continue
                    if character == "(":
                        depth += 1
                    elif character == ")":
                        depth -= 1
                    index += 1
                yield begin - 1 - len(escape), text[begin:index - 1]
            else:
                index += 1
            continue
        index += 1


def check_logs(root):
    violations = 0
    for path in swift_files(root):
        text = read_text(root, path)
        reported = set()
        for call in LOG_CALL.finditer(text):
            for offset, body in log_interpolations(text, call.end()):
                line = line_of(text, offset)
                if "privacy:" not in body:
                    annotate(path, line, "Log interpolation without privacy: name its privacy")
                    reported.add(line)
                    violations += 1
                    continue
                public = PUBLIC.search(body)
                if not public:
                    continue
                expression = body[: public.start()]
                for name, pattern in PERSONAL_DATA:
                    if pattern.search(expression):
                        annotate(path, line, f"Personal data ({name}) logged as .public; personal data must be .private")
                        violations += 1
                        break
        for match in UNANNOTATED_LOG.finditer(text):
            line = line_of(text, match.end())
            if line not in reported:
                annotate(path, line, "Log interpolation without privacy: name its privacy")
                violations += 1

    if violations:
        print(f"==> {violations} log violation(s)")
        return 1
    print("==> Every log interpolation names its privacy")
    return 0


def main():
    default_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    parser = argparse.ArgumentParser(description="holzBar's network and log privacy checks.")
    parser.add_argument("check", choices=("network", "logs"))
    parser.add_argument("--root", default=default_root, help="repository root (default: %(default)s)")
    arguments = parser.parse_args()
    root = os.path.abspath(arguments.root)
    if arguments.check == "network":
        return check_network(root)
    return check_logs(root)


if __name__ == "__main__":
    sys.exit(main())
