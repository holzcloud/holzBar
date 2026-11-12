#!/usr/bin/env bash
#
# Proves the design-system rules of `.swiftlint.yml` on fixture files, with the repository's
# own configuration: the three design rules (`design_raw_font`, `design_raw_color`,
# `design_corner_radius`), which apply everywhere outside `UI/Design/`, and the settings-kit
# rules (`design_settings_*`), which apply to Settings screens only.
#
# It copies `.swiftlint.yml` into a temporary tree and writes fixtures there. A file under
# `holzBar/Settings/` holds one line of every forbidden pattern, old and new; the settings-kit
# lines are also written into a file of the Appearance editor folder and a hub module's
# `…SettingsView.swift` (both reported), and into a hub runtime file, a Permissions file and
# `UI/Design/` (none reported). Another file under `holzBar/Settings/` holds the allowed
# forms. Then it runs SwiftLint over the tree and requires exactly the expected violations:
# the count of every design rule is pinned, and every `design_*` rule of the configuration
# must have a failing line in the Settings fixture, so a mistake in a regular expression, a
# scope or an exclusion fails here, before CI.
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

mkdir -p "$work/holzBar/Settings" "$work/holzBar/UI/Design" \
    "$work/holzBar/MenuBar/Appearance/MenuBarAppearanceEditor" \
    "$work/holzBar/MenuBar/NotchHub/Timers" "$work/holzBar/Permissions"
cp "$root/.swiftlint.yml" "$work/.swiftlint.yml"

forbidden_lines() {
    cat <<'EOF'
            .font(.system(size: 10))
            .foregroundStyle(Color(red: 0, green: 0, blue: 0))
            .background(Color("name"))
            .cornerRadius(4)
EOF
}

settings_forbidden_lines() {
    cat <<'EOF'
            .background(RoundedRectangle(cornerRadius: 6))
            .clipShape(.rect(cornerRadius: 6))
            .toggleStyle(.switch)
            .toggleStyle(.checkbox)
            .overlay(Toggle("Bad", isOn: .constant(true)))
            .overlay(HolzBarForm { EmptyView() })
            .overlay(HolzBarGroupBox { EmptyView() })
            .overlay(HolzBarSection { EmptyView() })
            .annotation("Bad")
            .overlay(caption(Text("Bad")))
            .overlay(SettingsGroup("Bad") { EmptyView() })
EOF
}

# write_fixture PATH NAME FUNCTION...: a view named NAME whose text carries the lines of every
# FUNCTION, in order.
write_fixture() {
    local path="$1" name="$2"
    shift 2
    {
        printf '//\n//  %s.swift\n//  holzBar\n//\n\nimport SwiftUI\n\n' "$name"
        printf 'struct %s: View {\n    var body: some View {\n        Text(verbatim: "%s")\n' "$name" "$name"
        for lines in "$@"; do
            "$lines"
        done
        printf '    }\n}\n'
    } > "$work/$path"
}

write_fixture holzBar/Settings/Bad.swift Bad forbidden_lines settings_forbidden_lines
write_fixture holzBar/UI/Design/Ok.swift Ok forbidden_lines settings_forbidden_lines
write_fixture holzBar/MenuBar/Appearance/MenuBarAppearanceEditor/BadEditor.swift BadEditor settings_forbidden_lines
write_fixture holzBar/MenuBar/NotchHub/Timers/TimersSettingsView.swift TimersSettingsView settings_forbidden_lines
write_fixture holzBar/MenuBar/NotchHub/Timers/TimersRuntime.swift TimersRuntime settings_forbidden_lines
write_fixture holzBar/Permissions/Quiet.swift Quiet settings_forbidden_lines

cat > "$work/holzBar/Settings/Fine.swift" <<'EOF'
//
//  Fine.swift
//  holzBar
//

import SwiftUI

/// Never write `.font(.system(size: 10))` or `Color(red: 0, green: 0, blue: 0)` here, nor
/// `HolzBarForm`, `HolzBarGroupBox`, `HolzBarSection` or `.toggleStyle(.switch)`.
struct Fine: View {
    let cgColor: CGColor
    let nsColor: NSColor
    let title: String
    let entry: SettingsEntry
    @State private var isOn = false

    var body: some View {
        // `.font(.system(size: 10))`, `.cornerRadius(4)`, `RoundedRectangle(cornerRadius: 6)`,
        // `.rect(cornerRadius: 6)`, `.annotation("x")`, `caption(Text("x"))` and
        // `SettingsGroup("x")` in a comment are fine.
        VStack {
            Text(verbatim: "Fine")
                .font(HolzBarTheme.Typography.body)
                .foregroundStyle(Color(cgColor: cgColor))
                .background(Color(nsColor: nsColor))
                .clipShape(HolzBarTheme.shape(HolzBarTheme.Radius.card))
                .background(RoundedRectangle(cornerRadius: HolzBarTheme.Radius.list))
                .clipShape(.rect(cornerRadius: HolzBarTheme.Radius.control))
                .font(HolzBarTheme.Typography.caption)
                .overlay(SettingsToggleRow(entry, isOn: $isOn))
                .overlay(SettingsSwitch(isOn: $isOn, label: Text("Fine")))
                .overlay(HolzBarSectionHeader())
                .overlay(SettingsGroup(title) { EmptyView() })
                .overlay(SettingsGroup { EmptyView() })
                .overlay(SettingsInfoButton(Text("Fine")))
            Menu("Fine") {
                // swiftlint:disable:next design_settings_bare_toggle - a Toggle in a Menu is a checkmark item, not a switch
                Toggle("Fine", isOn: $isOn)
            }
        }
    }
}
EOF

report="$work/report.json"
(
    cd "$work"
    TOOLCHAIN_DIR=/Library/Developer/CommandLineTools "$swiftlint" lint \
        --config .swiftlint.yml --reporter json --no-cache --quiet > "$report" || true
)

python3 -I - "$report" "$work/.swiftlint.yml" <<'PY'
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


with open(sys.argv[2]) as handle:
    configured = sorted(
        line.strip().rstrip(":")
        for line in handle
        if line.startswith("  design_") and line.rstrip().endswith(":")
    )
expected_rules = {
    "design_raw_font": 1,
    "design_raw_color": 2,
    "design_corner_radius": 1,
    "design_settings_raw_radius": 6,
    "design_settings_toggle_style": 6,
    "design_settings_bare_toggle": 3,
    "design_settings_old_component": 9,
    "design_settings_annotation": 6,
    "design_settings_group_literal": 3,
}
check(configured == sorted(expected_rules), f"the configuration holds exactly the nine design rules (found {configured})")
bad = [v for v in design if v["file"].endswith("/holzBar/Settings/Bad.swift")]
for rule in configured:
    check(any(v["rule_id"] == rule for v in bad), f"{rule} has a failing line in the Settings fixture")
check(len(design) == 37, f"exactly 37 design violations are reported (found {len(design)})")
for rule, expected in expected_rules.items():
    check(count(rule) == expected, f"{rule} is reported {expected} times (found {count(rule)})")
old_rules = ("design_raw_font", "design_raw_color", "design_corner_radius")
check(
    all(v["file"].endswith("/holzBar/Settings/Bad.swift") for v in design if v["rule_id"] in old_rules),
    "every violation of the three design rules is in the Settings fixture",
)
settings = [v for v in design if v["rule_id"].startswith("design_settings_")]
for suffix in (
    "/holzBar/Settings/Bad.swift",
    "/holzBar/MenuBar/Appearance/MenuBarAppearanceEditor/BadEditor.swift",
    "/holzBar/MenuBar/NotchHub/Timers/TimersSettingsView.swift",
):
    found = sum(1 for v in settings if v["file"].endswith(suffix))
    check(found == 11, f"{suffix} has 11 settings-kit violations (found {found})")
check(
    not any(v["file"].endswith("/Fine.swift") for v in design),
    "the allowed forms (tokens, kit parts, comments, a checkmark Toggle in a Menu) are not reported",
)
check(
    not any(v["file"].endswith("/TimersRuntime.swift") or "/Permissions/" in v["file"] for v in design),
    "a hub runtime file and the Permissions window are not reported",
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
