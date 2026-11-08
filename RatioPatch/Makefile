TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AppToolsRatioPatch

AppToolsRatioPatch_FILES := \
    AppToolsUI.xm \
    AppRatioRuntime.xm \
    DPIKeyboardFix.xm \
    RatioStore.m

AppToolsRatioPatch_CFLAGS := \
    -fobjc-arc \
    -Wno-deprecated-declarations \
    -Wno-objc-method-access

AppToolsRatioPatch_FRAMEWORKS := UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
