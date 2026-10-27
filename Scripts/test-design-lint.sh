#!/usr/bin/env bash
#
# Proves the design-system rules of `.swiftlint.yml` (`design_raw_font`, `design_raw_color`,
# `design_corner_radius`) on fixture files, with the repository's own configuration.
#
# It copies `.swiftlint.yml` into a temporary tree and writes three fixtures there: a file
# under `holzBar/Settings/` with one line of every forbidden pattern, a file under
# `holzBar/Settings/` with the allowed forms (the user-colour conversions, a theme token and
# comments that mention the patterns), and a file under `holzBar/UI/Design/` with the
# forbidden patterns again, where they are allowed. Then it runs SwiftLint over the tree and
# requires exactly the expected violations, so a mistake in a regular expression or in an
# exclusion fails here, before CI.
#
# Needs the portable SwiftLint of exactly the version pinned in `.github/workflows/lint.yml`
# at `$HOME/.cache/holzbar/swiftlint-<version>/swiftlint` (the `portable_swiftlint.zip` of
# that release from https://github.com/realm/SwiftLint/releases), and the Command Line Tools
# for SourceKit. Nothing is written inside the repository.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

version="$(sed -n 's/.*ghcr.io\/realm\/swiftlint:\([0-9.]*\)@.*/\1/p' "$root/.github/workflows/lint.yml")"
swiftlint="$HOME/.cache/holzbar/swiftlint-$version/swiftlint"
if [ -z "$version" ] || [ ! -x "$swiftlint" ] || [ "$("$swiftlint" version)" != "$version" ]; then
    echo "FAIL: the pinned SwiftLint ${version:-?} is missing at $swiftlint" >&2
    echo "Unpack portable_swiftlint.zip of release ${version:-?} from" >&2
    echo "https://github.com/realm/SwiftLint/releases into $(dirname "$swiftlint")." >&2
    exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/holzBar/Settings" "$work/holzBar/UI/Design"
cp "$root/.swiftlint.yml" "$work/.swiftlint.yml"

forbidden_lines() {
    cat <<'EOF'
            .font(.system(size: 10))
            .foregroundStyle(Color(red: 0, green: 0, blue: 0))
            .background(Color("name"))
            .cornerRadius(4)
EOF
}

{
    printf '//\n//  Bad.swift\n//  holzBar\n//\n\nimport SwiftUI\n\n'
    printf 'struct Bad: View {\n    var body: some View {\n        Text(verbatim: "Bad")\n'
    forbidden_lines
    printf '    }\n}\n'
} > "$work/holzBar/Settings/Bad.swift"

cat > "$work/holzBar/Settings/Fine.swift" <<'EOF'
//
//  Fine.swift
//  holzBar
//

import SwiftUI

/// Never write `.font(.system(size: 10))` or `Color(red: 0, green: 0, blue: 0)` here.
struct Fine: View {
    let cgColor: CGColor
    let nsColor: NSColor

    var body: some View {
        // `.font(.system(size: 10))` and `.cornerRadius(4)` in a comment are fine.
        Text(verbatim: "Fine")
            .font(HolzBarTheme.Typography.body)
            .foregroundStyle(Color(cgColor: cgColor))
            .background(Color(nsColor: nsColor))
            .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
    }
}
EOF

{
    printf '//\n//  Ok.swift\n//  holzBar\n//\n\nimport SwiftUI\n\n'
    printf 'struct Ok: View {\n    var body: some View {\n        Text(verbatim: "Ok")\n'
    forbidden_lines
    printf '    }\n}\n'
} > "$work/holzBar/UI/Design/Ok.swift"

report="$work/report.json"
(
    cd "$work"
    TOOLCHAIN_DIR=/Library/Developer/CommandLineTools "$swiftlint" lint \
        --config .swiftlint.yml --reporter json --no-cache --quiet > "$report" || true
)

python3 -I - "$report" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as handle:
        violations = json.load(handle)
except (OSError, ValueError) as error:
    print(f"FAIL: SwiftLint produced no JSON report: {error}")
    sys.exit(1)

design = [v for v in violations if v.get("rule_id", "").startswith("design_")]
failed = False


def check(condition, text):
    global failed
    print(("ok: " if condition else "FAIL: ") + text)
    failed = failed or not condition


def count(rule):
    return sum(1 for v in design if v["rule_id"] == rule)


check(len(design) == 4, f"exactly four design violations are reported (found {len(design)})")
check(count("design_raw_font") == 1, "one raw system font is reported")
check(count("design_raw_color") == 2, "two raw colours are reported (a component colour and a named one)")
check(count("design_corner_radius") == 1, "one corner radius is reported")
check(
    all(v["file"].endswith("/holzBar/Settings/Bad.swift") for v in design),
    "every design violation is in the Settings fixture",
)
check(
    not any(v["file"].endswith("/Fine.swift") for v in design),
    "the allowed forms (Color(cgColor:), Color(nsColor:), a token, comments) are not reported",
)
check(
    not any("/UI/Design/" in v["file"] for v in design),
    "the same patterns under UI/Design are not reported",
)
check(
    all(v["severity"] == "Error" for v in design),
    "the design rules are errors",
)
sys.exit(1 if failed else 0)
PY

echo "==> the design rules behave as specified"
