TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GestureProPrefs

GestureProPrefs_FILES = GestureProRootListController.m
GestureProPrefs_FRAMEWORKS = UIKit
GestureProPrefs_PRIVATE_FRAMEWORKS = Preferences
GestureProPrefs_INSTALL_PATH = /Library/PreferenceBundles
GestureProPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
