#!/bin/bash
#
# Runs SwiftLint (strict, the repository's .swiftlint.yml) on Linux, without a Mac.
#
# Needs the portable Linux build of the pinned SwiftLint version
# (https://github.com/realm/SwiftLint/releases, `swiftlint_linux_amd64.zip`) as
# `$SWIFTLINT`, and a Swift toolchain for Linux whose `usr/lib` is on `LD_LIBRARY_PATH`
# (SwiftLint loads `libsourcekitdInProc.so` from it). CI runs the same checks in the official
# image; this finds the violations before a push.

set -euo pipefail

cd "$(dirname "$0")/.."
"${SWIFTLINT:-swiftlint}" lint --strict "$@"
