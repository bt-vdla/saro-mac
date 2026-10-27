# Build products live outside the repo: the Desktop is iCloud-synced, and its Finder xattrs break codesign.
DERIVED := $(HOME)/Library/Developer/Xcode/DerivedData/Saro-dogfood
SCRATCH := $(HOME)/Library/Caches/saro-mac/sarokit
APP := $(DERIVED)/Build/Products/Debug/Saro.app

.PHONY: project build run test clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project Saro.xcodeproj -scheme Saro -configuration Debug -derivedDataPath "$(DERIVED)" -allowProvisioningUpdates -quiet build

run: build
	open "$(APP)"

test:
	swift test --package-path SaroKit --scratch-path "$(SCRATCH)"

clean:
	rm -rf "$(DERIVED)" "$(SCRATCH)"
