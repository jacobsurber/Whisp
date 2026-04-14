# VoiceFlow

A lightweight macOS menu bar app for voice-to-text transcription. Press and hold a key, speak, release, and your words appear as text — copied to clipboard and optionally pasted into the active app.

Supports multiple transcription engines: OpenAI Whisper, Google Gemini, local WhisperKit (CoreML), and Parakeet-MLX (Apple Silicon).

> Forked from [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper).

## Features

- **Press & Hold recording** — hold a modifier key (Right Command by default) to record, release to transcribe. Enabled by default.
- **Multiple engines** — OpenAI Whisper, Google Gemini, offline WhisperKit (CoreML), and Parakeet-MLX with built-in model management
- **Semantic correction** — optional post-processing with local MLX or cloud to fix typos, punctuation, and filler words, with app-aware categories
- **Smart Paste** — auto-pastes transcribed text into the active app and restores your clipboard
- **Privacy-first** — local modes keep audio on-device; API keys stored in macOS Keychain; no analytics
- **History & usage stats** — opt-in transcription history with search, retention policies, and productivity insights

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon strongly recommended; **required** for Parakeet and local MLX correction
- Swift 5.9+ (if building from source)
- API keys for cloud providers (OpenAI or Gemini); none needed for local engines

## Installation

### Download from Releases

1. Download the latest `.dmg` from [Releases](https://github.com/jacobsurber/VoiceFlow/releases)
2. Drag VoiceFlow.app to your Applications folder
3. Launch and configure through the Dashboard

> **Note:** The app is ad-hoc signed. On first launch, right-click the app and select **Open**, then confirm the dialog. You only need to do this once.

### Build from Source

```bash
git clone https://github.com/jacobsurber/VoiceFlow.git
cd VoiceFlow

# Build and install to /Applications/
make install

# Or just build the app bundle
make build

# Create a DMG for distribution
make dmg
```

After installing, grant permissions when prompted:
- **Microphone** — requested on first recording
- **Accessibility** — required for Press & Hold to work in other apps (System Settings > Privacy & Security > Accessibility)

## Setup

### Transcription Providers

Configure your provider in the Dashboard (menu bar icon > Settings):

| Provider | Requires | Notes |
|----------|----------|-------|
| **Local WhisperKit** | Nothing (offline) | Models: Tiny (39 MB) to Large Turbo (1.5 GB). Downloads in Dashboard. |
| **Parakeet-MLX** | Apple Silicon | English v2 or Multilingual v3 (~2.5 GB). Click "Install Dependencies" in Dashboard. |
| **OpenAI** | API key (`sk-...`) | Supports custom endpoints (Azure, proxies). |
| **Google Gemini** | API key (`AIza...`) | Large files auto-use Files API. |

### Semantic Correction (Optional)

Post-processing to fix transcription errors:
- **Off** (default)
- **Local MLX** — runs fully offline on Apple Silicon
- **Cloud** — uses the active cloud provider

App-aware categories (Terminal, Coding, Chat, Writing, Email) customize the correction prompt. Override prompts by placing `*_prompt.txt` files in `~/Library/Application Support/VoiceFlow/prompts/`.

## Usage

1. **Hold** your configured key (Right Command by default) and speak
2. **Release** to stop recording — transcription starts automatically
3. Text is copied to clipboard. If Smart Paste is enabled, it's also pasted into the active app.

### Recording Modes

- **Hold** (default) — hold key to record, release to stop
- **Toggle** — press once to start, press again to stop

Configure the trigger key and mode in Dashboard > Recording.

## Building

| Command | Description |
|---------|-------------|
| `make install` | Build and install to /Applications/ |
| `make build` | Build the app bundle |
| `make build-notarize` | Build and notarize (requires Apple Developer account) |
| `make test` | Run test suite |
| `make dmg` | Create DMG for distribution |
| `make clean` | Remove build artifacts |

### Notarization

For distribution without Gatekeeper warnings, set these environment variables and run `make build-notarize`:

```bash
export VOICEFLOW_APPLE_ID='your-apple-id@example.com'
export VOICEFLOW_APPLE_PASSWORD='app-specific-password'
export VOICEFLOW_TEAM_ID='your-team-id'
```

### After Installing a New Build

Since we use ad-hoc code signing, macOS invalidates Accessibility permissions when the binary changes. After each install:

1. System Settings > Privacy & Security > Accessibility
2. Remove VoiceFlow, then re-add `/Applications/VoiceFlow.app`
3. Ensure the toggle is ON

## Privacy & Security

- **Local transcription** keeps audio entirely on-device (WhisperKit, Parakeet)
- **Cloud providers** transmit audio to OpenAI/Google for transcription
- **API keys** stored in macOS Keychain
- **History** stays local, respects your chosen retention window
- **No tracking** or analytics
- **Open source** — audit the code yourself

## Troubleshooting

**App won't open ("unidentified developer")**
Right-click > Open > confirm. Or run `xattr -cr /Applications/VoiceFlow.app`.

**Press & Hold not working**
Grant Accessibility permission: System Settings > Privacy & Security > Accessibility > add VoiceFlow.

**Smart Paste not working**
Grant Accessibility permission (same as above). Smart Paste simulates Command+V.

**Microphone not detected**
System Settings > Privacy & Security > Microphone > enable VoiceFlow.

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License. See [LICENSE](LICENSE).

## Dependencies

- [Alamofire](https://github.com/Alamofire/Alamofire) — MIT
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT
- [MLX](https://github.com/ml-explore/mlx) & [parakeet-mlx](https://github.com/senstella/parakeet-mlx) (Python, bundled) — MIT
