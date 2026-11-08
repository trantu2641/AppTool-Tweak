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

echo "[1/6] Extract original RootHide package"
dpkg-deb -x "$ORIGINAL" "$WORK/rootfs"
dpkg-deb -e "$ORIGINAL" "$WORK/control"

echo "[2/6] Extract compiled patch package"
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

echo "[4/6] Translate the existing Preferences plist"
ROOT_PLIST="$WORK/rootfs/Library/PreferenceBundles/AppTools.bundle/Root.plist"
if [[ -f "$ROOT_PLIST" && -f "$ROOT/localization/vi/translations.json" ]]; then
  python3 "$ROOT/scripts/localize_plist.py" \
    "$ROOT_PLIST" \
    "$ROOT/localization/vi/translations.json" \
    "$ROOT_PLIST"
  plutil -lint "$ROOT_PLIST"
else
  echo "WARNING: translation map or source Root.plist missing; original plist is preserved." >&2
fi

echo "[5/6] Prepare original package metadata"
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
# Bump the package revision so Sileo/Zebra/dpkg cannot silently keep the
# previously installed 2.9.0-vi-ratio1 package when reinstalling this build.
new_version = "2.9.0-vi-ratio2"
text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {new_version}", text, count=1)
installed_bytes = sum(
    path.stat().st_size
    for path in root.rglob("*")
    if path.is_file() and "DEBIAN" not in path.parts
)
installed_kb = math.ceil(installed_bytes / 1024)
if re.search(r"(?m)^Installed-Size:\s*", text):
    text = re.sub(
        r"(?m)^Installed-Size:\s*.*$",
        f"Installed-Size: {installed_kb}",
        text,
        count=1,
    )
else:
    text += f"\nInstalled-Size: {installed_kb}\n"
control.write_text(text, encoding="utf-8")

md5_lines = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or "DEBIAN" in path.parts:
        continue
    relative = path.relative_to(root).as_posix()
    digest = hashlib.md5(path.read_bytes()).hexdigest()
    md5_lines.append(f"{digest}  {relative}")
(debian / "md5sums").write_text("\n".join(md5_lines) + "\n", encoding="utf-8")
PYCODE

echo "[6/6] Build modified DEB"
FINAL="$OUT/com.jtisvn.apptools_2.9.0-vi-ratio2_iphoneos-arm64e.deb"
dpkg-deb --build --root-owner-group "$WORK/rootfs" "$FINAL"
dpkg-deb --info "$FINAL"
echo "Created: $FINAL"
