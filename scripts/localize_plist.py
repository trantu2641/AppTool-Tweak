#!/usr/bin/env python3
"""Translate display strings in AppTools' existing Root.plist without changing its schema."""
import json
import plistlib
import sys
from pathlib import Path

if len(sys.argv) != 4:
    raise SystemExit("Usage: localize_plist.py INPUT.plist TRANSLATIONS.json OUTPUT.plist")

source = Path(sys.argv[1])
translations_path = Path(sys.argv[2])
destination = Path(sys.argv[3])

with source.open("rb") as stream:
    root = plistlib.load(stream)
with translations_path.open("r", encoding="utf-8") as stream:
    translations = json.load(stream)

translated = 0

def visit(value):
    global translated
    if isinstance(value, dict):
        for key, child in list(value.items()):
            value[key] = visit(child)
        return value
    if isinstance(value, list):
        return [visit(child) for child in value]
    if isinstance(value, str) and value in translations:
        translated += 1
        return translations[value]
    return value

root = visit(root)
destination.parent.mkdir(parents=True, exist_ok=True)
with destination.open("wb") as stream:
    plistlib.dump(root, stream, fmt=plistlib.FMT_XML, sort_keys=False)

print(f"Localized {translated} string(s): {destination}")
