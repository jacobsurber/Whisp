# VoiceFlow Build Guide

Quick reference for building and installing VoiceFlow.

## Quick Start

```bash
# Build and install to /Applications/
make install
```

That's it! The app will be installed to `/Applications/VoiceFlow.app`.

## Development Workflow

### Building for Testing
```bash
# Quick development build
swift build

# Run directly without installing
swift run
```

### Installing to Applications
```bash
# Build and install in one command
make install

# Or manually:
./scripts/install-voiceflow.sh
```

### Cleaning Build Artifacts
```bash
make clean
```

## After Installing

**Important:** Since we use ad-hoc code signing, you must re-grant permissions after each install:

1. **Accessibility Permission** (for Smart Paste):
   - Open **System Settings → Privacy & Security → Accessibility**
   - Remove VoiceFlow (click `-`)
   - Add `/Applications/VoiceFlow.app` (click `+`)
   - Ensure toggle is **ON**

2. **Microphone Permission**:
   - Will be requested on first recording
   - Allow when prompted

## Architecture

The build script creates a standard macOS app bundle:

```
VoiceFlow.app/
├── Contents/
│   ├── MacOS/
│   │   └── VoiceFlow          # Main executable
│   ├── Resources/
│   │   ├── *.py               # Python ML scripts
│   │   ├── ml/                # ML modules
│   │   └── bin/
│   │       └── uv             # Python package manager
│   └── Info.plist             # App metadata
```

## Troubleshooting

### App won't launch
- Check code signature: `codesign -dvvv /Applications/VoiceFlow.app`
- Re-run: `make install`

### Permissions reset after update
- This is expected with ad-hoc signing
- Re-grant accessibility permission (see above)

### Build fails
```bash
# Clean and rebuild
make clean
make install
```

## Build Targets

- `make install` - Build and install to /Applications/ (recommended)
- `make build` - Build the app bundle only
- `make test` - Run test suite
- `make clean` - Remove all build artifacts
- `make help` - Show all available targets

## Version Updates

To update the version:
1. Edit `VERSION` file
2. Update version in `scripts/install-voiceflow.sh` (CFBundleShortVersionString)
3. Rebuild: `make install`
