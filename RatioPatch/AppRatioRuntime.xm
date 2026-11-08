/*
 * Deliberately disabled safety stub.
 *
 * The previous implementation hooked UIScreen -bounds, UIScreen
 * -applicationFrame and UIWindow -layoutSubviews in processes selected by a
 * broad filter. That code is not safe to load in SpringBoard and was a likely
 * contributor to Safe Mode.
 *
 * This file is intentionally NOT listed in RatioPatch/Makefile.
 * Do not add it back to AppToolsRatioPatch_FILES until a separate target-app
 * runtime has been implemented, filtered to the selected app, and tested.
 */
#import <Foundation/Foundation.h>

__attribute__((used))
static const char *ATRRuntimeDisabledReason =
    "Screen ratio runtime disabled pending isolated target-app implementation";
