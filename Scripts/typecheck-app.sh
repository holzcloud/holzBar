#!/usr/bin/env bash
#
# Type-checks the whole holzBar app module without Xcode, with only the Command Line Tools.
#
# It runs `swiftc -emit-sil -wmo` over `holzBar/` and `Shared/` with the app's Swift flags.
# Xcode generates the asset symbols (`ImageResource.appLogo`, `ColorResource.defaultLayoutBar`,
# ...) from `holzBar/Resources/Assets.xcassets`; without Xcode they do not exist, so a stub
# file defines them. Everything happens in a temporary copy; nothing is written inside the
# repository.
#
# The Command Line Tools ship no `PreviewsMacros` plugin, so every `#Preview` block would be an
# error, and a macro error stops the compiler before its SIL diagnostics (region-based
# isolation and others). The temporary copy therefore drops the `#Preview` blocks.
#
# The 26.5 SDK is the default because the Command Line Tools lack the SwiftUI macro plugin
# for the 27 SDK, so the 27 SDK cannot expand `@Observable` and friends. Override it with
# `SDK=/path/to/MacOSX.sdk`.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir "$work/src"
cp -R "$root/holzBar" "$work/src/holzBar"
cp -R "$root/Shared" "$work/src/Shared"

# The Command Line Tools have no PreviewsMacros plugin ("plugin for module 'PreviewsMacros' not
# found"), and macro errors would hide the compiler's SIL diagnostics. Drop every top-level
# `#Preview` block, from its line up to and including the next line that is exactly `}`, from
# the copy only. A file may continue after its preview (an extension), so it is not truncated.
find "$work/src" -name '*.swift' -exec perl -0777 -pi -e 's/^#Preview.*?^\}(?:\n|\z)//gms' {} +

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

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find "$work/src" -name '*.swift' | sort)
files+=("$work/AssetStubs.swift")

swiftc -emit-sil -wmo -o /dev/null \
    -parse-as-library \
    -module-name holzBar \
    -target arm64-apple-macos14.0 \
    -sdk "$sdk" \
    -swift-version 6 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    "${files[@]}"

echo "==> holzBar type-checks"
