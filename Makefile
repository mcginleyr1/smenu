APP = build/smenu.app
# A stable identity keeps the Accessibility grant across rebuilds; use SIGN=- for ad-hoc.
SIGN ?= Apple Development

.PHONY: app icon run install clean

app:
	swift build -c release
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/smenu $(APP)/Contents/MacOS/smenu
	cp Info.plist $(APP)/Contents/Info.plist
	cp AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(SIGN)" $(APP)

icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns -o AppIcon.icns build/AppIcon.iconset

run: app
	open $(APP)

install: app
	rm -rf /Applications/smenu.app
	cp -R $(APP) /Applications/smenu.app

clean:
	rm -rf .build build
