TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AppToolsRatioPatch

AppToolsRatioPatch_FILES := \
    AppToolsUI.xm \
    RatioStore.m

AppToolsRatioPatch_CFLAGS := \
    -fobjc-arc \
    -Wno-deprecated-declarations

AppToolsRatioPatch_FRAMEWORKS := \
    UIKit \
    Foundation

AppToolsRatioPatch_PRIVATE_FRAMEWORKS := \
    CoreServices

include $(THEOS_MAKE_PATH)/tweak.mk
