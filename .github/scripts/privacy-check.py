#!/usr/bin/env python3
#
# privacy-check.py
#
# Proves two of holzBar's privacy promises (see CLAUDE.md, "Private") on the
# source tree:
#
#   network  No networking API appears in holzBar/, Shared/, MenuBarItemService/
#            or Package.swift (except the lines .github/network-allowlist.txt
#            allows), and every resolved Swift package is listed in
#            .github/allowed-packages.txt.
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
import re
import sys

SOURCE_DIRS = ("holzBar", "Shared", "MenuBarItemService")
NETWORK_ALLOWLIST = ".github/network-allowlist.txt"
ALLOWED_PACKAGES = ".github/allowed-packages.txt"
PACKAGE_RESOLVED = "holzBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

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


def normalized_location(location):
    location = location.strip().lower().rstrip("/")
    if location.endswith(".git"):
        location = location[: -len(".git")]
    return location


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

    if os.path.exists(os.path.join(root, "Package.swift")):
        text = read_text(root, "Package.swift")
        offset = text.find(".package(")
        if offset >= 0:
            annotate("Package.swift", line_of(text, offset), "Package.swift must not depend on a package")
            violations += 1

    resolved = os.path.join(root, PACKAGE_RESOLVED)
    if os.path.exists(resolved):
        allowed = {normalized_location(entry) for entry in read_list(root, ALLOWED_PACKAGES)}
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
