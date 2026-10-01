# All commands agents/humans need. The .xcodeproj is generated; never edit it by hand.
DD := build
XCB := xcodebuild -project ProjectRecord.xcodeproj -scheme ProjectRecord -destination 'platform=macOS' -derivedDataPath $(DD)
# Release version: `make release VERSION=1.2.0 BUILD=42` (CI sets these from the tag and run number).
VERSION ?=
BUILD ?=
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) $(if $(BUILD),CURRENT_PROJECT_VERSION=$(BUILD))
APP := $(DD)/Build/Products/Release/ProjectRecord.app

.PHONY: gen build test run release clean
gen:
	xcodegen generate
build: gen
	$(XCB) build
test: gen
	$(XCB) test
run: build
	open $(DD)/Build/Products/Debug/ProjectRecord.app
# Release build, ad-hoc signed, zipped with ditto (keeps the signature and bundle metadata intact).
release: gen
	$(XCB) -configuration Release build $(VERSION_FLAGS)
	ditto -c -k --keepParent $(APP) $(DD)/ProjectRecord$(if $(VERSION),-$(VERSION)).zip
clean:
	rm -rf $(DD) ProjectRecord.xcodeproj
