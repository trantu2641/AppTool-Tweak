#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORIGINAL="$ROOT/original/AppTools-2.9.0.deb"
PATCH_DIR="$ROOT/RatioPatch"
WORK="$ROOT/.work"
OUT="$ROOT/dist"
PATCH_STAGING="$PATCH_DIR/.theos/_"

if [[ ! -f "$ORIGINAL" ]]; then
  echo "ERROR: Missing original package: $ORIGINAL" >&2
  exit 1
fi

if [[ ! -d "$PATCH_STAGING" ]]; then
  echo "ERROR: Theos staging directory not found: $PATCH_STAGING" >&2
  echo "Build RatioPatch with: make stage FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide" >&2
  exit 1
fi

PATCH_DYLIB="$(find "$PATCH_STAGING" -type f -path '*/DynamicLibraries/AppToolsRatioPatch.dylib' -print -quit)"
PATCH_PLIST="$(find "$PATCH_STAGING" -type f -path '*/DynamicLibraries/AppToolsRatioPatch.plist' -print -quit)"
if [[ -z "$PATCH_DYLIB" || -z "$PATCH_PLIST" ]]; then
  echo "ERROR: AppToolsRatioPatch.dylib or its filter plist is missing from Theos staging." >&2
  find "$PATCH_STAGING" -type f -print >&2
  exit 1
fi

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK/rootfs" "$WORK/control" "$OUT"

echo "[1/6] Extract original AppTools RootHide package"
dpkg-deb -x "$ORIGINAL" "$WORK/rootfs"
dpkg-deb -e "$ORIGINAL" "$WORK/control"

# RootHide builds must use @loader_path/.jbroot paths, not /var/jb paths.
if ! command -v otool >/dev/null 2>&1; then
  echo "ERROR: otool is required to validate RootHide load paths." >&2
  exit 1
fi
LOAD_COMMANDS="$(otool -l "$PATCH_DYLIB")"
if printf '%s\n' "$LOAD_COMMANDS" | grep -q '/var/jb/'; then
  echo "ERROR: Patch dylib still contains rootless /var/jb load paths." >&2
  printf '%s\n' "$LOAD_COMMANDS" | grep -B2 -A2 '/var/jb/' >&2 || true
  exit 1
fi
if ! printf '%s\n' "$LOAD_COMMANDS" | grep -q '@loader_path/.jbroot'; then
  echo "ERROR: Patch dylib has no RootHide .jbroot runpath. Check THEOS_PACKAGE_SCHEME=roothide." >&2
  exit 1
fi

echo "[2/6] Install the normal tweak dylib and filter plist"
DYNAMIC="$WORK/rootfs/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$DYNAMIC"
cp "$PATCH_DYLIB" "$DYNAMIC/AppToolsRatioPatch.dylib"
cp "$PATCH_PLIST" "$DYNAMIC/AppToolsRatioPatch.plist"
plutil -lint "$DYNAMIC/AppToolsRatioPatch.plist"

# A .roothidepatch symlink is for a DynamicPatches module to patch a target
# Mach-O. This is a normal injected tweak, so DO NOT add that sidecar here.
if [[ -L "$DYNAMIC/AppToolsRatioPatch.dylib.roothidepatch" ]]; then
  rm "$DYNAMIC/AppToolsRatioPatch.dylib.roothidepatch"
fi
# Preserve the original AppTool.dylib sidecar unchanged.
if [[ ! -L "$DYNAMIC/AppTool.dylib.roothidepatch" ]]; then
  echo "ERROR: Original AppTool.dylib.roothidepatch is missing from the base package." >&2
  exit 1
fi

echo "[3/6] Translate existing Preferences plist"
ROOT_PLIST="$WORK/rootfs/Library/PreferenceBundles/AppTools.bundle/Root.plist"
TRANSLATIONS="$ROOT/localization/vi/translations.json"
if [[ -f "$ROOT_PLIST" && -f "$TRANSLATIONS" ]]; then
  python3 "$ROOT/scripts/localize_plist.py" "$ROOT_PLIST" "$TRANSLATIONS" "$ROOT_PLIST"
  plutil -lint "$ROOT_PLIST"
else
  echo "WARNING: localization source missing; preserving original Root.plist." >&2
fi

echo "[4/6] Prepare original package metadata"
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
version = "2.9.0-vi-ratio6"
text = re.sub(r"(?m)^Version:\s*.*$", f"Version: {version}", text, count=1)
installed_bytes = sum(p.stat().st_size for p in root.rglob("*") if p.is_file() and "DEBIAN" not in p.parts)
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
    md5_lines.append(f"{hashlib.md5(path.read_bytes()).hexdigest()}  {path.relative_to(root).as_posix()}")
(debian / "md5sums").write_text("\n".join(md5_lines) + "\n", encoding="utf-8")
PYCODE

echo "[5/6] Build modified AppTools DEB"
FINAL="$OUT/com.jtisvn.apptools_2.9.0-vi-ratio6_iphoneos-arm64e.deb"
dpkg-deb --build --root-owner-group "$WORK/rootfs" "$FINAL"

echo "[6/6] Verify RootHide package layout"
dpkg-deb -c "$FINAL" > "$WORK/package-list.txt"
grep -q 'AppToolsRatioPatch.dylib$' "$WORK/package-list.txt"
grep -q 'AppToolsRatioPatch.plist$' "$WORK/package-list.txt"
grep -q 'AppTool.dylib.roothidepatch' "$WORK/package-list.txt"
if grep -q 'AppToolsRatioPatch.dylib.roothidepatch' "$WORK/package-list.txt"; then
  echo "ERROR: Normal tweak dylib must not carry a .roothidepatch sidecar." >&2
  exit 1
fi
dpkg-deb --info "$FINAL"
echo "Created: $FINAL"
grep -E 'AppTool\.dylib\.roothidepatch|AppToolsRatioPatch' "$WORK/package-list.txt"
