# Background Recording Mode - Fast & Transparent Capture

## What Changed

VoiceFlow now uses **background-only recording** for press-and-hold capture. This means:

✅ **No window popups** during recording
✅ **No focus stealing** - stay in your current app
✅ **Menu bar-only feedback** - clean, minimal UI
✅ **Auto-paste when done** (if Smart Paste enabled)
✅ **Silent processing** - transcription happens in background

## How It Works

### 1. Start Recording
**Press and hold Left Control**
- Menu bar icon changes to pulsing indigo
- Elapsed time appears (e.g., "0:04")
- **You stay in your current app** - no window appears
- Optional: Quick beep sound confirms recording started

### 2. Stop Recording
**Release Left Control**
- Menu bar shows "..." with spinner (processing)
- **You stay in your current app**
- Transcription happens in background

### 3. Completion
- **Text auto-pastes** into your app (if Smart Paste enabled)
- Menu bar returns to idle state
- That's it! No windows, no interruptions

## Menu Bar States

| State | Icon | Time Display | Meaning |
|-------|------|--------------|---------|
| **Idle** | Microphone (gray) | (none) | Ready to record |
| **Recording** | Microphone (pulsing indigo) | 0:04 | Recording in progress |
| **Processing** | Spinner (indigo) | ... | Transcribing audio |

## Optimization Benefits

### Before (Original)
- Window pops up on start ❌
- Focus switches to VoiceFlow ❌
- Window shows during transcription ❌
- Must manually switch back ❌

### After (Optimized)
- No window popup ✅
- Focus stays on your app ✅
- Silent background processing ✅
- Auto-paste when ready ✅

## Settings

### Enable Smart Paste
For the best experience, enable Smart Paste:
1. Open VoiceFlow menu bar icon
2. Click "Settings..." or "Dashboard..."
3. Go to **Recording** tab
4. Enable **"Smart Paste"**
5. Grant **Accessibility permission** when prompted

### Disable Sounds (Optional)
For completely silent operation:
1. Settings → **Recording** tab
2. Disable **"Play recording sounds"**

## Troubleshooting

### Recording doesn't start
- **Check microphone permission**: System Settings → Privacy & Security → Microphone
- **Check hotkey**: Settings → confirm Left Control is configured
- **Menu bar icon**: Should be present - if not, relaunch VoiceFlow

### Auto-paste doesn't work
- **Grant accessibility permission**: Run `make reset-permissions`
- **Enable Smart Paste**: Settings → Recording → Smart Paste ON
- **Alternative**: Manually press ⌘V after transcription completes

### Popups still appearing
- This should be fixed! If you still see popups, please report:
  - What popup appears (screenshot if possible)
  - What action triggered it (start recording, stop recording, etc.)

## Performance

- **Start delay**: < 50ms (just audio recording startup)
- **CPU**: Same transcription performance regardless of UI mode
- **UX**: Zero interruptions — recording and transcription happen entirely in the background
