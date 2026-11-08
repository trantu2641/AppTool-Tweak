#!/bin/bash

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ORIGINAL="$ROOT/original/AppTools-2.9.0.deb"

WORK="$ROOT/.work"
OUT="$ROOT/dist"

rm -rf "$WORK"
mkdir -p "$WORK/rootfs"
mkdir -p "$WORK/control"
mkdir -p "$OUT"

echo "[1/8] Kiểm tra AppTools gốc..."

if [ ! -f "$ORIGINAL" ]; then
    echo "Không tìm thấy:"
    echo "$ORIGINAL"
    exit 1
fi

echo "[2/8] Giải nén AppTools..."

dpkg-deb -x "$ORIGINAL" "$WORK/rootfs"
dpkg-deb -e "$ORIGINAL" "$WORK/control"

echo "[3/8] Build RatioPatch..."

cd "$ROOT/RatioPatch"

make clean || true
make package FINALPACKAGE=1

PATCH_DEB="$(find "$ROOT/RatioPatch/packages" \
    -type f \
    -name "*.deb" \
    | sort \
    | tail -n 1)"

if [ -z "$PATCH_DEB" ]; then
    echo "Không tìm thấy package RatioPatch."
    exit 1
fi

echo "[4/8] Giải nén RatioPatch..."

mkdir -p "$WORK/patch"

dpkg-deb -x "$PATCH_DEB" "$WORK/patch"

echo "[5/8] Inject dylib..."

DYNAMIC="$WORK/rootfs/Library/MobileSubstrate/DynamicLibraries"

mkdir -p "$DYNAMIC"

find "$WORK/patch" \
    -type f \
    -name "*.dylib" \
    -exec cp {} "$DYNAMIC/" \;

echo "[6/8] Inject plist..."

find "$WORK/patch" \
    -type f \
    -path "*DynamicLibraries/*.plist" \
    -exec cp {} "$DYNAMIC/" \;

echo "[7/8] Việt hóa PreferenceBundle..."

if [ -f "$ROOT/localization/vi/Root.plist" ]; then

    cp "$ROOT/localization/vi/Root.plist" \
       "$WORK/rootfs/Library/PreferenceBundles/AppTools.bundle/Root.plist"

fi

echo "[8/8] Đóng gói..."

CONTROL="$WORK/control/control"

sed -i.bak \
    's/^Version:.*/Version: 2.9.0-vi-ratio1/' \
    "$CONTROL"

dpkg-deb \
    -b \
    "$WORK/rootfs" \
    "$OUT/com.jtisvn.apptools_2.9.0-vi-ratio1_iphoneos-arm64e.deb"

echo
echo "======================================"
echo "BUILD OK"
echo "======================================"

ls -lh "$OUT"
