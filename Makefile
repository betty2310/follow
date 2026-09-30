# All commands agents/humans need. The .xcodeproj is generated; never edit it by hand.
DD := build
XCB := xcodebuild -project ProjectRecord.xcodeproj -scheme ProjectRecord -destination 'platform=macOS' -derivedDataPath $(DD)

.PHONY: gen build test run clean
gen:
	xcodegen generate
build: gen
	$(XCB) build
test: gen
	$(XCB) test
run: build
	open $(DD)/Build/Products/Debug/ProjectRecord.app
clean:
	rm -rf $(DD) ProjectRecord.xcodeproj
