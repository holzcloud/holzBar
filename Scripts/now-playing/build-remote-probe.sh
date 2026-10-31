#!/bin/bash
#
# Builds the probe library (RemoteProbeDylib) of the now-playing spike for each architecture the
# Command Line Tools can build, and signs it for /usr/bin/perl to load.
#
#   build-remote-probe.sh OUT_DIR [--identity NAME]
#
# For arm64, arm64e and x86_64 (swift build --arch) it builds the dynamic library into OUT_DIR/<arch>/ and signs that
# copy ad hoc with the hardened runtime. With --identity it also writes OUT_DIR/<arch>-signed/,
# signed with that identity (a certificate in the keychain) and the hardened runtime.
# One line per architecture: BUILT arch=<arch> status=<ok|failed> signed=<adhoc|identity|->.
# Exit 0 when at least the native architecture was built.
#
# This is a throwaway spike. It touches nothing but OUT_DIR, which must not be inside the
# repository, and ships nowhere.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE="$ROOT/Scripts/now-playing"
USAGE="usage: $0 OUT_DIR [--identity NAME]"

[ $# -ge 1 ] || { echo "$USAGE" >&2; exit 2; }
OUT="$1"
shift
IDENTITY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --identity) IDENTITY="${2:-}"; [ -n "$IDENTITY" ] || { echo "error: --identity needs a name" >&2; exit 2; }; shift 2 ;;
        *) echo "$USAGE" >&2; exit 2 ;;
    esac
done

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
case "$OUT/" in
    "$ROOT"/*) echo "error: OUT_DIR must not be inside the repository" >&2; exit 2 ;;
esac

NATIVE="$(uname -m)"
NATIVE_BUILT=no

for ARCH in arm64 arm64e x86_64; do
    SCRATCH="$OUT/.build-$ARCH"
    LOG="$OUT/.build-$ARCH.log"
    STATUS=failed
    SIGNED="-"
    if swift build -c release --package-path "$PACKAGE" --product RemoteProbeDylib \
        --arch "$ARCH" --scratch-path "$SCRATCH" >"$LOG" 2>&1; then
        BIN="$(swift build -c release --package-path "$PACKAGE" --arch "$ARCH" --scratch-path "$SCRATCH" --show-bin-path 2>/dev/null)"
        # The build system may fall back to other architectures for one it cannot build, so the
        # file must contain exactly the architecture asked for.
        if [ -f "$BIN/libRemoteProbeDylib.dylib" ] && [ "$(lipo -archs "$BIN/libRemoteProbeDylib.dylib" 2>/dev/null)" = "$ARCH" ]; then
            mkdir -p "$OUT/$ARCH"
            cp "$BIN/libRemoteProbeDylib.dylib" "$OUT/$ARCH/"
            if codesign --force --options runtime -s - "$OUT/$ARCH/libRemoteProbeDylib.dylib" >>"$LOG" 2>&1; then
                STATUS=ok
                SIGNED=adhoc
                if [ -n "$IDENTITY" ]; then
                    mkdir -p "$OUT/$ARCH-signed"
                    cp "$BIN/libRemoteProbeDylib.dylib" "$OUT/$ARCH-signed/"
                    if codesign --force --options runtime -s "$IDENTITY" "$OUT/$ARCH-signed/libRemoteProbeDylib.dylib" >>"$LOG" 2>&1; then
                        SIGNED=identity
                    else
                        rm -rf "$OUT/$ARCH-signed"
                    fi
                fi
            fi
        fi
    fi
    echo "BUILT arch=$ARCH status=$STATUS signed=$SIGNED"
    if [ "$STATUS" = ok ] && [ "$ARCH" = "$NATIVE" ]; then NATIVE_BUILT=yes; fi
done

[ "$NATIVE_BUILT" = yes ] || { echo "error: the native architecture ($NATIVE) was not built; see $OUT/.build-*.log" >&2; exit 1; }
