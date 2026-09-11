.DEFAULT_GOAL := help

XCODEBUILD ?= xcodebuild
BUILD_DIR ?= $(CURDIR)/build

# Local builds use ad-hoc signing; no Apple developer account is required.
# As in Debug, omit hardened runtime: its library validation rejects ad-hoc Sparkle.
XCODE_FLAGS = -project Rectangle.xcodeproj -scheme Rectangle \
	-derivedDataPath "$(BUILD_DIR)/DerivedData" \
	SYMROOT="$(BUILD_DIR)" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO

.PHONY: help debug release test

help:
	@printf '%s\n' \
	  'make debug    Build a Debug app for this Mac in build/Debug/Rectangle.app' \
	  'make release  Build a universal Release app in build/Release/Rectangle.app' \
	  'make test     Run the test suite on this Mac'

debug:
	$(XCODEBUILD) $(XCODE_FLAGS) -configuration Debug -destination 'platform=macOS' build
	@printf '\nBuilt: %s\n' "$(BUILD_DIR)/Debug/Rectangle.app"

release:
	$(XCODEBUILD) $(XCODE_FLAGS) -configuration Release -destination 'generic/platform=macOS' \
		ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
	@printf '\nBuilt: %s\n' "$(BUILD_DIR)/Release/Rectangle.app"

test:
	$(XCODEBUILD) $(XCODE_FLAGS) -configuration Debug -destination 'platform=macOS' test
