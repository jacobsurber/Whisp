# Contributing to VoiceFlow

Thank you for your interest in contributing to VoiceFlow! This guide covers development setup, testing, and distribution.

## Development Setup

### Prerequisites

- **macOS 14.0 (Sonoma) or later**
- **Xcode 15.0+** or Swift CLI tools
- **Swift 5.9+**

### Initial Setup

```bash
git clone https://github.com/jacobsurber/VoiceFlow.git
cd VoiceFlow
swift build
```

## Development Workflow

For day-to-day development, use Swift CLI tools directly:

```bash
# Build
swift build

# Run the app (no app bundle needed)
swift run

# Run tests
swift test

# Run specific test suite
swift test --filter AudioRecorderTests

# Run tests with coverage
swift test --enable-code-coverage
```

The build scripts in `scripts/` are for creating distributable releases only. During development, `swift run` avoids signing and entitlement issues.

## Building for Distribution

### Basic Release Build

```bash
make build
```

Creates a universal binary (Apple Silicon + Intel) app bundle with icon and Info.plist.

### Signed + Notarized Build

```bash
export VOICEFLOW_APPLE_ID='your-apple-id@example.com'
export VOICEFLOW_APPLE_PASSWORD='app-specific-password'
export VOICEFLOW_TEAM_ID='your-team-id'
make build-notarize
```

Requires an [Apple Developer Program](https://developer.apple.com/programs/) membership ($99/year) and a Developer ID Application certificate.

### Code Signing

The build script auto-detects Developer ID certificates from your keychain. To verify:

```bash
# List signing identities
security find-identity -v -p codesigning

# Verify app signature
codesign --verify --verbose VoiceFlow.app

# Check Gatekeeper approval
spctl -a -v VoiceFlow.app
```

Without a Developer ID, the app gets ad-hoc signed. Recipients must right-click > Open on first launch.

## Architecture Overview

### Technology Stack
- **SwiftUI** + **AppKit** — UI and menu bar integration
- **AVFoundation** — Audio recording
- **Alamofire** — HTTP requests
- **WhisperKit** — Local transcription (CoreML)
- **Keychain** — Secure API key storage

### Project Structure
```
VoiceFlow/
├── Sources/
│   ├── App/              # AppDelegate, lifecycle, hotkeys
│   ├── Managers/         # HotKey, PressAndHold, Paste, Permissions
│   ├── Services/         # Transcription, ML, audio processing
│   ├── Stores/           # Data persistence (SwiftData, UserDefaults)
│   ├── Models/           # Data types and enums
│   ├── Views/            # SwiftUI views (Dashboard, Components)
│   ├── Utilities/        # Logger, helpers, extensions
│   ├── ml/               # Python ML daemon package
│   └── Resources/        # Assets, pyproject.toml
├── Tests/                # Unit tests + mocks
├── scripts/              # Build and automation scripts
├── Package.swift
└── Makefile
```

## Coding Standards

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- No compiler warnings — fix all before committing
- Write unit tests for new business logic
- Use Keychain for sensitive data, never hardcode API keys
- Use Swift Concurrency (`async`/`await`) for async flows
- Annotate UI code with `@MainActor`

## Common Issues

### Permission Issues After Rebuild
Ad-hoc signing means macOS invalidates Accessibility permissions on each rebuild. See [ACCESSIBILITY-FIX.md](ACCESSIBILITY-FIX.md).

### Safe-to-Ignore Warnings
These Apple framework warnings are harmless:
- `AddInstanceForFactory: No factory registered...`
- `LoudnessManager.mm: unknown value: Mac16,13`

## License

By contributing to VoiceFlow, you agree that your contributions will be licensed under the MIT License.
