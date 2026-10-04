# All commands agents/humans need. The .xcodeproj is generated; never edit it by hand.
DD := build
XCB := xcodebuild -project Follow.xcodeproj -scheme Follow -destination 'platform=macOS' -derivedDataPath $(DD)
# Release version: `make release VERSION=1.2.0` (CI sets it from the tag). The build number defaults to
# the version, so Sparkle (which compares CFBundleVersion) orders releases by their tags (D28).
VERSION ?=
BUILD ?= $(VERSION)
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) $(if $(BUILD),CURRENT_PROJECT_VERSION=$(BUILD))
APP := $(DD)/Build/Products/Release/Follow.app
# Release builds are re-signed with this self-signed certificate (D30): a stable code identity, so macOS keeps
# the Microphone/Documents permissions across updates. `SIGN_ID=-` signs ad-hoc (e.g. without the certificate).
# It keeps the app's old name (D32): a new certificate would change the code identity again.
SIGN_ID ?= ProjectRecord Self-Signed
BUNDLE_ID := dev.betty.Follow
INSTALL_DIR ?= /Applications

.PHONY: gen build test run release install clean
gen:
	xcodegen generate
build: gen
	$(XCB) build
test: gen
	$(XCB) test
run: build
	open $(DD)/Build/Products/Debug/Follow.app
# Release build signed with $(SIGN_ID), zipped with ditto (keeps the signature and bundle metadata intact).
# Xcode signs ad-hoc; only the outer app is re-signed, which seals the nested frameworks as they are.
release: gen
	$(XCB) -configuration Release build $(VERSION_FLAGS)
	codesign --force --sign "$(SIGN_ID)" $(APP)
	codesign --verify --deep --strict $(APP)
	ditto -c -k --keepParent $(APP) $(DD)/Follow$(if $(VERSION),-$(VERSION)).zip
# Release build copied to /Applications, then launched. Ad-hoc signing gives every build a new
# code identity, so old Microphone/Documents grants go stale; reset them so macOS asks again.
# (TCC can't be granted from a script; click Allow on the prompts.)
install: release
	-osascript -e 'quit app "Follow"' 2>/dev/null
	rm -rf $(INSTALL_DIR)/Follow.app
	ditto $(APP) $(INSTALL_DIR)/Follow.app
	-xattr -dr com.apple.quarantine $(INSTALL_DIR)/Follow.app 2>/dev/null
	-tccutil reset Microphone $(BUNDLE_ID)
	-tccutil reset SystemPolicyDocumentsFolder $(BUNDLE_ID)
	open $(INSTALL_DIR)/Follow.app
clean:
	rm -rf $(DD) Follow.xcodeproj
