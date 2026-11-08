# AppTools Safe Mode mitigation patch

Replace these files in the repository:

- `RatioPatch/Makefile`
- `RatioPatch/AppToolsUI.xm`
- `RatioPatch/AppRatioRuntime.xm`
- `RatioPatch/AppToolsRatioPatch.plist`
- `RatioPatch/layout/Library/MobileSubstrate/DynamicLibraries/AppToolsRatioPatch.plist`

## What this change does

- Removes `AppRatioRuntime.xm` from the compiled tweak. The previous runtime globally hooked `UIScreen.bounds`, `UIScreen.applicationFrame` and `UIWindow.layoutSubviews`, which is unsafe to run broadly in SpringBoard and can cause Safe Mode.
- Restricts the patch filter to `com.apple.springboard`, rather than injecting the same dylib into the broad `com.apple.UIKit` filter as well.
- Replaces the global `%hook UIViewController` with a hook scoped to the AppTools private `ATPopupViewController` class.
- Keeps the per-Bundle-ID ratio selection UI and persistence, including automatic, presets and manual width/height.

## Important limitation

This is a crash-risk reduction / UI-and-storage build, not a complete working screen-ratio engine. It intentionally does not alter the actual target app's display geometry. A separate target-app component must be designed and injected only into the selected app after the selected Bundle ID path and the exact AppTools action-sheet API have been verified. Do not re-enable the old `UIScreen` / `UIWindow` hooks.

## Build

Keep the original `RatioPatch/RatioStore.h`, `RatioPatch/RatioStore.m`, `RatioPatch/AppToolsRatioCommon.h`, `RatioPatch/control`, package layout and build workflow. Replace the listed files, commit, then run GitHub Actions. Test on a secondary device first.
