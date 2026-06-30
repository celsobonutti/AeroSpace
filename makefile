# makefile is used to make :make command in vim work out of the box
.PHONY: \
	build-debug.sh \
	test.sh \
	swift-test.sh \
	format.sh \
	lint.sh

build-debug.sh:
	./build-debug.sh

test.sh:
	./test.sh

swift-test.sh:
	./swift-test.sh

format.sh:
	./format.sh

lint.sh:
	./lint.sh

RELEASE_APP := .xcode-build/Build/Products/Release/AeroSpace.app

.PHONY: release install

# Build an ad-hoc-signed Release AeroSpace.app (no Apple cert needed).
# Output: $(RELEASE_APP)
release:
	xcodebuild -project AeroSpace.xcodeproj -scheme AeroSpace -configuration Release \
		-derivedDataPath .xcode-build -destination 'generic/platform=macOS' \
		CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
		clean build

# Build, then replace /Applications/AeroSpace.app and relaunch it.
install: release
	-osascript -e 'quit app "AeroSpace"' 2>/dev/null
	-pkill -f AeroSpaceApp
	-pkill -x AeroSpace
	rm -rf /Applications/AeroSpace.app
	cp -R $(RELEASE_APP) /Applications/
	open /Applications/AeroSpace.app
	@echo "Installed. If tiling stops working, re-grant Accessibility: System Settings > Privacy & Security > Accessibility."
