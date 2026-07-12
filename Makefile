.PHONY: build test app install run diagnose clean

build:
	swift build

test:
	swift test

app:
	bash scripts/make-app.sh

install: app
	rm -rf /Applications/WindowKeeper.app
	cp -R dist/WindowKeeper.app /Applications/
	@echo "Installed. Launch it, grant Accessibility access, and optionally add"
	@echo "it to System Settings → General → Login Items."

run: build
	.build/debug/WindowKeeper

diagnose: build
	.build/debug/WindowKeeper --diagnose

clean:
	swift package clean
	rm -rf dist
