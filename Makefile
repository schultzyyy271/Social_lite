ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Social_lite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MockEntitlementHooks
MockEntitlementHooks_FILES = Tweak.x
MockEntitlementHooks_CFLAGS = -fobjc-arc
MockEntitlementHooks_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
