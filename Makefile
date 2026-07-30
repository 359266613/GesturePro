TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

ifeq ($(SCHEME),roothide)
    export THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootless)
    export THEOS_PACKAGE_SCHEME = rootless
else
    unexport THEOS_PACKAGE_SCHEME
endif

export DEBUG = 0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GesturePro

GesturePro_FILES = GesturePro.xm GestureProSettings.xm GestureProHelper.m
GesturePro_CFLAGS += -fobjc-arc -Wno-deprecated-declarations -fno-modules
GesturePro_CCFLAGS += -fno-modules -fno-cxx-modules
GesturePro_FRAMEWORKS += Foundation UIKit CoreMotion

ifeq ($(SCHEME),roothide)
    GesturePro_LIBRARIES += roothide
endif

THEOS_DEVICE_IP = 192.168.31.108
THEOS_DEVICE_PORT = 22

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	@echo -e "\033[31m==>\033[0m Cleaning packages…"
	@rm -rf .theos packages/*

after-package::
	@echo -e "\033[32m==>\033[0m Packaging complete."
	@if [ "$(INSTALL)" = "1" ]; then \
		DEB_FILE=$$(ls -t packages/*.deb | head -1); \
		scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -P $(THEOS_DEVICE_PORT) $${DEB_FILE} root@$(THEOS_DEVICE_IP):/tmp; \
		ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -p $(THEOS_DEVICE_PORT) root@$(THEOS_DEVICE_IP) "dpkg -i /tmp/$$(basename $${DEB_FILE}) && (command -v sbreload >/dev/null && sbreload || killall -9 SpringBoard)"; \
	fi
