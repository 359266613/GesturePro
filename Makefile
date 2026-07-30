ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

export DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GesturePro

GesturePro_FILES = Hooks/Main.xm Sources/AxsConfig.m Sources/AxsGestureRecognizer.m Sources/AxsActionExecutor.m
GesturePro_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations -I./Headers -I./Sources
GesturePro_FRAMEWORKS = UIKit Foundation CoreMotion

include $(THEOS_MAKE_PATH)/tweak.mk

# --- 设置面板子项目 ---
SUBPROJECTS += GestureProprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
