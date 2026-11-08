# AppTool-Tweak: build repair files

These are **replacement/additional files** for the existing `trantu2641/AppTool-Tweak` repository. They are not a complete source export.

## Overlay these paths into the repository

Replace:
- `.github/workflows/build.yml`
- `RatioPatch/Makefile`
- `RatioPatch/AppToolsRatioPatch.plist`
- `RatioPatch/layout/Library/MobileSubstrate/DynamicLibraries/AppToolsRatioPatch.plist`
- `scripts/build.sh`
- `localization/vi/Root.plist` (this replaces the current plain-text mapping file with a valid Apple plist)

Add:
- `RatioPatch/control`
- `scripts/localize_plist.py`
- `localization/vi/translations.json`

Keep the existing `RatioPatch/AppToolsUI.xm`, `RatioPatch/AppRatioRuntime.xm`, `RatioPatch/RatioStore.h`, `RatioPatch/RatioStore.m`, and `original/AppTools-2.9.0.deb`.

## Build

Commit the files, then open **Actions → Build AppTools VI + Ratio → Run workflow**. The workflow installs Theos and the patched iPhoneOS 16.5 SDK, builds the patch package, injects the resulting dylib and filter into the original RootHide package, localizes the real `Root.plist`, regenerates package checksums, and uploads the modified `.deb`.

## Important scope

This repairs the build and package-assembly pipeline. It does **not** certify that the screen-ratio runtime works in every app; the viewport hooks still require on-device testing. The translation map covers the strings in the original Preferences `Root.plist`, not every hard-coded string inside the stripped `AppTool.dylib`.
