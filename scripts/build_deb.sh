#!/bin/bash

set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ORIGINAL_DEB="$ROOT_DIR/original/AppTools-2.9.0.deb"
WORK="$ROOT_DIR/.build"

rm -rf "$WORK"

mkdir -p "$WORK/original"
mkdir -p "$WORK/debian"

echo "[1/6] Extract original deb..."

dpkg-deb -x "$ORIGINAL_DEB" "$WORK/original"

dpkg-deb -e "$ORIGINAL_DEB" "$WORK/debian"

echo "[2/6] Build RatioPatch..."

cd "$ROOT_DIR/RatioPatch"

make clean || true
make package FINALPACKAGE=1

PATCH_DEB=$(find "$ROOT_DIR/RatioPatch/packages" \
    -name "*.deb" \
    -type f \
    | head -n 1)

if [ -z "$PATCH_DEB" ]; then
    echo "ERROR: RatioPatch deb not found"
    exit 1
fi

echo "[3/6] Extract patch package..."

mkdir -p "$WORK/patch"

dpkg-deb -x "$PATCH_DEB" "$WORK/patch"

echo "[4/6] Inject dylib..."

find "$WORK/patch" \
    -type f \
    -name "*.dylib" \
    -exec cp {} \
    "$WORK/original/Library/MobileSubstrate/DynamicLibraries/" \;

PATCH_PLIST=$(find "$WORK/patch" \
    -type f \
    -name "*.plist" \
    | head -n 1)

if [ -n "$PATCH_PLIST" ]; then

    cp "$PATCH_PLIST" \
       "$WORK/original/Library/MobileSubstrate/DynamicLibraries/"
fi

echo "[5/6] Update package metadata..."

CONTROL="$WORK/debian/control"

if [ -f "$CONTROL" ]; then

    sed -i \
        's/^Package: .*/Package: com.jtisvn.apptools/' \
        "$CONTROL"

    sed -i \
        's/^Version: .*/Version: 2.9.0-ratio1/' \
        "$CONTROL"
fi

echo "[6/6] Build final deb..."

mkdir -p "$ROOT_DIR/dist"

rm -f "$ROOT_DIR/dist/"*.deb

dpkg-deb \
    -b \
    "$WORK/original" \
    "$ROOT_DIR/dist/AppTools-2.9.0-Ratio.deb"

echo
echo "===================================="
echo "Build successful"
echo "===================================="
echo
echo "$ROOT_DIR/dist/AppTools-2.9.0-Ratio.deb"
