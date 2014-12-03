include theos/makefiles/common.mk

TWEAK_NAME = TouchPassword
TouchPassword_FILES = Tweak.xm TouchEvents.xm STUtils/STKeychain.m
TouchPassword_FRAMEWORKS = Security UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
