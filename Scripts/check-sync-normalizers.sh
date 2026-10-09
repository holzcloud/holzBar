#!/usr/bin/env bash
#
# Runs the sync normalizers of the app on the main actor, once, without Xcode.
#
# The normalizers of the sync unit table (`SyncModelNormalizers`) decode the app's models and so
# assume the main actor (`MainActor.assumeIsolated`); called from another thread they trap, and
# the Core package cannot test them, because it does not contain the models. This script builds the
# app module without its entry point, adds a small program that calls every normalizer on the
# main thread, and runs it. It checks that a stored default value is accepted and canonical (a
# second pass changes nothing), and that a value with an unknown field, or no JSON at all, is not
# applicable.
#
# It needs only the Command Line Tools. Everything happens in a temporary copy; nothing is
# written inside the repository. `SDK=/path/to/MacOSX.sdk` overrides the 26.5 SDK, which is the
# default for the reason given in typecheck-app.sh.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir "$work/src"
cp -R "$root/holzBar" "$work/src/holzBar"
cp -R "$root/Shared" "$work/src/Shared"
# The entry point of the app; the check has its own.
rm "$work/src/holzBar/Main/HolzBarApp.swift"

cat > "$work/AssetStubs.swift" <<'EOF'
import AppKit
import SwiftUI

// Stand-ins for the symbols Xcode generates from holzBar/Resources/Assets.xcassets.
extension ImageResource {
    static let appLogo = ImageResource(name: "AppLogo", bundle: .main)
    static let logoStroke = ImageResource(name: "LogoStroke", bundle: .main)
    static let warning = ImageResource(name: "Warning", bundle: .main)
}

extension ColorResource {
    static let defaultLayoutBar = ColorResource(name: "DefaultLayoutBarColor", bundle: .main)
}

extension Color {
    static let defaultLayoutBar = Color(.defaultLayoutBar)
}

extension NSImage {
    static let warning = NSImage(resource: .warning)
}
EOF

cat > "$work/Check.swift" <<'EOF'
import Foundation

@main
struct SyncNormalizersCheck {
    @MainActor
    static func main() {
        var failures: [String] = []
        func check(_ condition: Bool, _ what: String) {
            if !condition {
                failures.append(what)
            }
        }
        precondition(Thread.isMainThread, "the check runs on the main thread")

        let normalizers = SyncModelNormalizers.make()
        let encoder = JSONEncoder()

        // The appearance: the default configuration is applicable, canonical, and stays so.
        if let data = try? encoder.encode(MenuBarAppearanceConfigurationV2.defaultConfiguration) {
            let value = SyncValue.data(data)
            let once = normalizers.appearance(value)
            check(once != nil, "the default appearance is applicable")
            check(once.flatMap(normalizers.appearance) == once, "the appearance normalizes to itself")
            if
                let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                var unknown = raw
                unknown["aFieldOfANewerBuild"] = true
                if let changed = try? JSONSerialization.data(withJSONObject: unknown) {
                    check(normalizers.appearance(.data(changed)) == nil, "an appearance with an unknown field is not applicable")
                }
            }
        } else {
            check(false, "the default appearance encodes")
        }
        check(normalizers.appearance(.data(Data("not json".utf8))) == nil, "an appearance that is no JSON is not applicable")
        check(normalizers.appearance(.string("text")) == nil, "an appearance that is no data is not applicable")

        // The item groups: no group, and a list that is no list.
        let emptyGroups = SyncValue.data(Data("[]".utf8))
        check(normalizers.itemGroups(emptyGroups) != nil, "an empty list of groups is applicable")
        check(normalizers.itemGroups(.data(Data("{\"a\":1}".utf8))) == nil, "a dictionary is not a list of groups")

        // The holzBar icon: the default image set with the template flag.
        if let set = try? encoder.encode(ControlItemImageSet.defaultHolzBarIcon) {
            let icon = SyncValue.dictionary([SyncNormalizers.iconField: .data(set), SyncNormalizers.templateField: .bool(true)])
            let once = normalizers.holzBarIcon(icon)
            check(once != nil, "the default icon is applicable")
            check(once.flatMap(normalizers.holzBarIcon) == once, "the icon normalizes to itself")
        } else {
            check(false, "the default image set encodes")
        }
        check(normalizers.holzBarIcon(.dictionary([:])) == nil, "an empty icon is not applicable")

        if failures.isEmpty {
            print("==> The sync normalizers ran on the main actor")
        } else {
            for failure in failures {
                print("FAILED: \(failure)")
            }
            exit(1)
        }
    }
}
EOF

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find "$work/src" -name '*.swift' | sort)
files+=("$work/AssetStubs.swift" "$work/Check.swift")

swiftc -wmo -o "$work/check" \
    -parse-as-library \
    -module-name holzBar \
    -target arm64-apple-macos14.0 \
    -sdk "$sdk" \
    -swift-version 6 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "${files[@]}" 2>&1 | grep -E "error" || true

"$work/check"
