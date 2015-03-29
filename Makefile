include theos/makefiles/common.mk
export ARCHS= armv7 arm64
TWEAK_NAME = Wave
Wave_FILES = Tweak.xm
Wave_FRAMEWORKS = IOKit UIKit
Wave_PRIVATE_FRAMEWORKS = BackBoardServices
ADDITIONAL_OBJCFLAGS = -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
