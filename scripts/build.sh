#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL="$ROOT/original/AppTools-2.9.0.deb"
PATCH_DIR="$ROOT/RatioPatch"
WORK="$ROOT/.work"
OUT="$ROOT/dist"
PATCH_PACKAGES="$PATCH_DIR/packages"

if [[ ! -f "$ORIGINAL" ]]; then
  echo "ERROR: Missing original package: $ORIGINAL" >&2
  exit 1
fi

PATCH_DEB="$(find "$PATCH_PACKAGES" -maxdepth 1 -type f -name '*.deb' -print | sort | tail -n 1)"
if [[ -z "$PATCH_DEB" ]]; then
  echo "ERROR: No patch package found. Run make package inside RatioPatch first." >&2
  exit 1
fi

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/rootfs" "$WORK/control" "$WORK/patch" "$OUT"

echo "[1/7] Extract original AppTools RootHide package"
dpkg-deb -x "$ORIGINAL" "$WORK/rootfs"
dpkg-deb -e "$ORIGINAL" "$WORK/control"

echo "[2/7] Extract compiled RatioPatch package"
dpkg-deb -x "$PATCH_DEB" "$WORK/patch"

PATCH_DYLIB="$(find "$WORK/patch" -type f -name 'AppToolsRatioPatch.dylib' -print -quit)"
PATCH_PLIST="$(find "$WORK/patch" -type f -path '*/DynamicLibraries/AppToolsRatioPatch.plist' -print -quit)"
if [[ -z "$PATCH_DYLIB" ]]; then
  echo "ERROR: AppToolsRatioPatch.dylib not found in patch package." >&2
  find "$WORK/patch" -type f -print >&2
  exit 1
fi
if [[ -z "$PATCH_PLIST" ]]; then
  echo "ERROR: AppToolsRatioPatch.plist not found in patch package layout." >&2
  exit 1
fi

DYNAMIC="$WORK/rootfs/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYNAMIC"
cp "$PATCH_DYLIB" "$DYNAMIC/AppToolsRatioPatch.dylib"
cp "$PATCH_PLIST" "$DYNAMIC/AppToolsRatioPatch.plist"
plutil -lint "$DYNAMIC/AppToolsRatioPatch.plist"

echo "[3/7] Register the new dylib with RootHide"
# The original AppTool.dylib is accompanied by this RootHide marker symlink.
# Without the matching .roothidepatch sidecar, RootHide may leave the new
# dylib on disk but never inject it into SpringBoard/UIKit. Mirror the exact
# marker target used by the original AppTools package.
ORIGINAL_MARKER="$DYNAMIC/AppTool.dylib.roothidepatch"
MARKER_TARGET="/usr/lib/DynamicPatches/AutoPatches.dylib"
if [[ -L "$ORIGINAL_MARKER" ]]; then
  MARKER_TARGET="$(readlink "$ORIGINAL_MARKER")"
fi
ln -sfn "$MARKER_TARGET" "$DYNAMIC/AppToolsRatioPatch.dylib.roothidepatch"
if [[ ! -L "$DYNAMIC/AppToolsRatioPatch.dylib.roothidepatch" ]]; then
  echo "ERROR: Failed to create the RootHide marker symlink." >&2
  exit 1
fi

# Verify the loader files all exist before proceeding.
test -s "$DYNAMIC/AppToolsRatioPatch.dylib"
test -s "$DYNAMIC/AppToolsRatioPatch.plist"
echo "RootHide marker: AppToolsRatioPatch.dylib.roothidepatch -> $(readlink "$DYNAMIC/AppToolsRatioPatch.dylib.roothidepatch")"

echo "[4/7] Translate the existing Preferences plist"
ROOT_PLIST="$WORK/rootfs/Library/PreferenceBundles/AppTools.bundle/Root.plist"
TRANSLATIONS="$ROOT/localization/vi/translations.json"
if [[ -f "$ROOT_PLIST" && -f "$TRANSLATIONS" ]]; then
  python3 "$ROOT/scripts/localize_plist.py" \
    "$ROOT_PLIST" \
    "$TRANSLATIONS" \
    "$ROOT_PLIST"
  plutil -lint "$ROOT_PLIST"
else
  echo "WARNING: translation map or source Root.plist missing; original plist is preserved." >&2
fi

echo "[5/7] Prepare package metadata"
mkdir -p "$WORK/rootfs/DEBIAN"
cp -a "$WORK/control/." "$WORK/rootfs/DEBIAN/"
python3 - "$WORK/rootfs" <<'PYCODE'
import hashlib
import math
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
debian = root / "DEBIAN"
control = debian / "control"
text = control.read_text(encoding="utf-8")
if not re.search(r"(?m)^Version:\s*", text):
    raise SystemExit("Original package control has no Version field")
version = "2.9.0-vi-ratio3"
text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {version}", text, count=1)
installed_bytes = sum(
    path.stat().st_size
    for path in root.rglob("*")
    if path.is_file() and "DEBIAN" not in path.parts
)
installed_kb = math.ceil(installed_bytes / 1024)
if re.search(r"(?m)^Installed-Size:\s*", text):
    text = re.sub(r"(?m)^Installed-Size:\s*.*$", f"Installed-Size: {installed_kb}", text, count=1)
else:
    text += f"\nInstalled-Size: {installed_kb}\n"
control.write_text(text, encoding="utf-8")

md5_lines = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or "DEBIAN" in path.parts:
        continue
    relative = path.relative_to(root).as_posix()
    md5_lines.append(f"{hashlib.md5(path.read_bytes()).hexdigest()}  {relative}")
(debian / "md5sums").write_text("\n".join(md5_lines) + "\n", encoding="utf-8")
PYCODE

echo "[6/7] Build modified AppTools DEB"
FINAL="$OUT/com.jtisvn.apptools_2.9.0-vi-ratio3_iphoneos-arm64e.deb"
dpkg-deb --build --root-owner-group "$WORK/rootfs" "$FINAL"

echo "[7/7] Verify the final package contains the runtime and RootHide marker"
PACKAGE_LIST="$WORK/package-list.txt"
dpkg-deb -c "$FINAL" > "$PACKAGE_LIST"
grep -q 'AppToolsRatioPatch.dylib$' "$PACKAGE_LIST"
grep -q 'AppToolsRatioPatch.plist$' "$PACKAGE_LIST"
grep -q 'AppToolsRatioPatch.dylib.roothidepatch' "$PACKAGE_LIST"
dpkg-deb --info "$FINAL"
echo "Created: $FINAL"
echo "Verified files:"
grep 'AppToolsRatioPatch' "$PACKAGE_LIST"
