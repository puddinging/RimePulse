.PHONY: build run clean install bundle test

APP_NAME = RimePulse
BUILD_DIR = .build
INSTALL_DIR = /usr/local/bin
BUNDLE_DIR = $(HOME)/Applications/$(APP_NAME).app

build:
	swift build

run: build
	$(BUILD_DIR)/debug/$(APP_NAME)

release:
	swift build -c release

test: build
	swift Tests/run_tests.swift

clean:
	swift package clean

install: release
	cp $(BUILD_DIR)/release/$(APP_NAME) $(INSTALL_DIR)/$(APP_NAME)

# 打包为 .app bundle（可选，用于 Finder / Login Items）
bundle: release
	mkdir -p $(BUNDLE_DIR)/Contents/MacOS $(BUNDLE_DIR)/Contents/Resources
	cp $(BUILD_DIR)/release/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/
	cp Resources/AppIcon.icns $(BUNDLE_DIR)/Contents/Resources/
	/usr/libexec/PlistBuddy -c "Add :CFBundleName string $(APP_NAME)" \
		-c "Add :CFBundleIdentifier string com.jiefeng.rimepulse" \
		-c "Add :CFBundleVersion string 1.0" \
		-c "Add :CFBundleExecutable string $(APP_NAME)" \
		-c "Add :CFBundleIconFile string AppIcon" \
		-c "Add :LSUIElement bool true" \
		$(BUNDLE_DIR)/Contents/Info.plist 2>/dev/null || true
	@echo "Bundle created at $(BUNDLE_DIR)"
