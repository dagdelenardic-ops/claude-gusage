.PHONY: build app zip dmg release release-artifacts verify-release install clean

build:
	cd macos && swift build -c release

# Cut a signed, auto-updatable release and push the Sparkle feed.
# Usage: make release VERSION=1.1.2
release:
	@test -n "$(VERSION)" || (echo "Usage: make release VERSION=1.1.2" && exit 1)
	bash macos/scripts/release.sh $(VERSION)

app:
	bash macos/scripts/build.sh

zip:
	bash macos/scripts/build.sh --zip
	bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip

dmg:
	bash macos/scripts/build.sh --dmg
	bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.dmg

release-artifacts:
	bash macos/scripts/build.sh --zip --dmg
	bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip
	bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.dmg

verify-release:
	bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip
	if [ -f macos/ClaudeUsageBar.dmg ]; then bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.dmg; fi

install: app
	rm -rf /Applications/ClaudeUsageBar.app
	cp -R macos/ClaudeUsageBar.app /Applications/

clean:
	cd macos && swift package clean
	rm -rf macos/ClaudeUsageBar.app macos/ClaudeUsageBar.zip macos/ClaudeUsageBar.dmg
