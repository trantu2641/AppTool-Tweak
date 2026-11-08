TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AppToolsRatioPatch

# Safe-mode mitigation:
# Do NOT compile AppRatioRuntime.xm here. It globally hooks UIScreen.bounds,
# UIScreen.applicationFrame and UIWindow.layoutSubviews, which can destabilize
# SpringBoard and apps. The target-app ratio engine must be implemented and
# tested as a separate, narrowly injected component before being enabled.
AppToolsRatioPatch_FILES := \
    AppToolsUI.xm \
    RatioStore.m

AppToolsRatioPatch_CFLAGS := \
    -fobjc-arc \
    -Wno-deprecated-declarations

AppToolsRatioPatch_FRAMEWORKS := UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
