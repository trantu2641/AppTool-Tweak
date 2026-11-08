TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AppToolsRatioPatch

AppToolsRatioPatch_FILES := Tweak.xm RatioManager.m
AppToolsRatioPatch_CFLAGS := -fobjc-arc
AppToolsRatioPatch_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
