# Whisp

A lightweight macOS menu bar app for voice-to-text transcription. Press and hold a key, speak, release, and your words appear as text — copied to clipboard and optionally pasted into the active app.

Supports multiple transcription engines: OpenAI Whisper, Google Gemini, local WhisperKit (CoreML), and Parakeet-MLX (Apple Silicon).

> Forked from [jacobsurber/Whisp](https://github.com/jacobsurber/Whisp), originally [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper).

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

1. Download the latest `.dmg` from [Releases](https://github.com/amirsalaar/whisp/releases)
2. Drag Whisp.app to your Applications folder
3. Launch and configure through the Dashboard

> **Note:** GitHub release DMGs are signed and notarized. If you build locally with ad-hoc signing instead, right-click the app and select **Open** on first launch.

### Build from Source

```bash
git clone https://github.com/amirsalaar/whisp.git
cd whisp

# Optional but recommended for local development builds.
# Creates a stable signing identity so macOS privacy permissions persist.
make setup-local-signing

# Build and install to /Applications/
make install

# Or just build the app bundle
make build

# Create a DMG for distribution
make dmg
```

After installing, grant or enable the permissions Whisp needs for the features you use:

- **Microphone** — requested on first recording
- **Accessibility** — enable in System Settings for Command/Option/Control press-and-hold and Smart Paste in other apps
- **Input Monitoring** — enable in System Settings for standalone **Fn / Globe** capture in other apps

If you build with ad-hoc or unsigned development builds, macOS can treat each rebuild as a new app and re-prompt for Microphone, Accessibility, or Input Monitoring. Running `make setup-local-signing` once avoids that by giving local builds a stable signing identity.

## Setup

### Transcription Providers

Configure your provider in the Dashboard (menu bar icon > Settings):

| Provider             | Requires            | Notes                                                                               |
| -------------------- | ------------------- | ----------------------------------------------------------------------------------- |
| **Local WhisperKit** | Nothing (offline)   | Models: Tiny (39 MB) to Large Turbo (1.5 GB). Downloads in Dashboard.               |
| **Parakeet-MLX**     | Apple Silicon       | English v2 or Multilingual v3 (~2.5 GB). Click "Install Dependencies" in Dashboard. |
| **OpenAI**           | API key (`sk-...`)  | Supports custom endpoints (Azure, proxies).                                         |
| **Google Gemini**    | API key (`AIza...`) | Large files auto-use Files API.                                                     |

### Semantic Correction (Optional)

Post-processing to fix transcription errors:

- **Off** (default)
- **Local MLX** — runs fully offline on Apple Silicon
- **Cloud** — uses the active cloud provider

App-aware categories (Terminal, Coding, Chat, Writing, Email) customize the correction prompt. Override prompts by placing `*_prompt.txt` files in `~/Library/Application Support/Whisp/prompts/`.

## Usage

1. **Hold** your configured key (Right Command by default) and speak
2. **Release** to stop recording — transcription starts automatically
3. Text is copied to clipboard. If Smart Paste is enabled, it's also pasted into the active app.

### Recording Modes

- **Hold** (default) — hold key to record, release to stop
- **Toggle** — press once to start, press again to stop

Configure the trigger key and mode in Dashboard > Recording.

## Building

| Command               | Description                                                              |
| --------------------- | ------------------------------------------------------------------------ |
| `make install`        | Build and install to /Applications/                                      |
| `make build`          | Build the app bundle                                                     |
| `make build-notarize` | Build and notarize both app bundles, Developer ID required               |
| `make test`           | Run test suite                                                           |
| `make dmg`            | Create local DMG from current app bundles                                |
| `make release`        | Build notarized DMG, checksum, and GitHub release, Developer ID required |
| `make clean`          | Remove build artifacts                                                   |

### Notarization

For distribution without Gatekeeper warnings, you need a `Developer ID Application` certificate available in Keychain. If you need to choose one explicitly, set `CODE_SIGN_IDENTITY` first. Then set these environment variables and run `make build-notarize`. To publish a release, `make release` uses the same credentials to notarize the DMG before uploading it to GitHub Releases:

```bash
export WHISP_APPLE_ID='your-apple-id@example.com'
export WHISP_APPLE_PASSWORD='app-specific-password'
export WHISP_TEAM_ID='your-team-id'
```

### GitHub Actions Release

Every push to `master` runs the GitHub Actions `Release` workflow and publishes a notarized DMG release.

The automatic path defaults to a patch bump unless the checked-in `VERSION` file already leads the latest release tag. In that case, the workflow reuses the pending source version so a PR can intentionally ship a specific `x.y.z`.

You can still run the workflow manually from `master` as a fallback. The manual path supports a `patch`, `minor`, or `major` bump, or an explicit `x.y.z` version.

Before building and publishing the notarized DMG, the workflow commits any needed `VERSION` bump back to `master` so the released version exists in source.

### After Installing a New Build

If Whisp is installed with a stable signature, macOS should preserve its existing Microphone, Accessibility, and Input Monitoring permissions across reinstalls.

If you are still using ad-hoc signing, or permissions already became stale from older builds, run:

```bash
make reset-permissions
```

Then re-grant the affected permissions once in System Settings.

## Privacy & Security

- **Local transcription** keeps audio entirely on-device (WhisperKit, Parakeet)
- **Cloud providers** transmit audio to OpenAI/Google for transcription
- **API keys** stored in macOS Keychain
- **History** stays local, respects your chosen retention window
- **No tracking** or analytics
- **Open source** — audit the code yourself

## Troubleshooting

**App won't open ("unidentified developer")**
Right-click > Open > confirm. Or run `xattr -cr /Applications/Whisp.app`.

**Press & Hold not working**
Command, Option, and Control require Accessibility permission: System Settings > Privacy & Security > Accessibility > add Whisp.

Fn / Globe requires Input Monitoring and may also require Keyboard > Press Globe key to be set to Do Nothing.

**Smart Paste not working**
Grant Accessibility permission (same as above). Smart Paste simulates Command+V.

**Microphone not detected**
System Settings > Privacy & Security > Microphone > enable Whisp.

**Microphone prompt or Fn permission keeps resetting after every rebuild**
Your development build is likely ad-hoc signed or unsigned. Run `make setup-local-signing`, reinstall with `make install`, then re-grant permissions once.

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

MIT License. See [LICENSE](LICENSE).

## Dependencies

- [Alamofire](https://github.com/Alamofire/Alamofire) — MIT
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) — MIT
- [MLX](https://github.com/ml-explore/mlx) & [parakeet-mlx](https://github.com/senstella/parakeet-mlx) (Python, bundled) — MIT
