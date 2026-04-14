.PHONY: help build build-notarize install test clean reset-permissions release dmg

SCRIPTS := scripts

# Default target
help:
	@echo "VoiceFlow Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  install            - Build and install VoiceFlow to /Applications/ (recommended)"
	@echo "  reset-permissions  - Reset and re-grant accessibility permission (fixes Smart Paste)"
	@echo "  build              - Build the release app bundle"
	@echo "  build-notarize     - Build and notarize the app"
	@echo "  test               - Run tests"
	@echo "  clean              - Clean build artifacts"
	@echo "  dmg                - Create a DMG for distribution"
	@echo "  release            - Create a new GitHub release"

# Build and install VoiceFlow to /Applications/
install:
	$(SCRIPTS)/install-voiceflow.sh

# Reset accessibility permissions (fixes Smart Paste after rebuild)
reset-permissions:
	$(SCRIPTS)/reset-accessibility.sh

# Build the app
build:
	$(SCRIPTS)/build.sh

# Build and notarize the app
build-notarize:
	$(SCRIPTS)/build.sh --notarize

# Run tests
test:
	$(SCRIPTS)/run-tests.sh

# Clean build artifacts
clean:
	rm -rf .build
	rm -rf VoiceFlow.app
	rm -f VoiceFlow.zip
	rm -f *.dmg

# Create a DMG for distribution
dmg:
	$(SCRIPTS)/create-dmg.sh

# Create a new release
release:
	@VERSION=$$(cat VERSION | tr -d '[:space:]'); \
	echo "Creating release v$$VERSION..."; \
	if git diff --quiet && git diff --cached --quiet; then \
		$(SCRIPTS)/build.sh && \
		zip -r VoiceFlow.zip VoiceFlow.app && \
		gh release create "v$$VERSION" VoiceFlow.zip --title "v$$VERSION" --generate-notes && \
		echo "✅ Release v$$VERSION created"; \
	else \
		echo "❌ Error: Working directory is not clean. Commit or stash changes first."; \
		exit 1; \
	fi
