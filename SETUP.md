# VoiceInk RU — Setup

Russian fork of [Beingpax/VoiceInk-iOS](https://github.com/Beingpax/VoiceInk-iOS) with **GigaAM-v2 RNNT** as a fully-offline on-device Russian transcription engine. Same custom keyboard, same flow — speak, get text inserted in any app.

## What's different from upstream

| Area | Upstream | This fork |
|---|---|---|
| Local STT | Whisper.cpp (English-leaning) | + **GigaAM-v2 RNNT** Russian SOTA (8.42% WER) |
| Bundle ID | `com.prakashjoshipax.VoiceInk` | `lol.egor.voiceink-ru` |
| Display name | "Voice Ink" | "VoiceInk RU" |
| Icon | Original | Generated, purple/amber mic |
| Engine size | ~150 MB | +241 MB downloaded on first GigaAM use |
| Provider menu | Cloud + Whisper local | + `GigaAM (Russian, on-device)` |

## One-time Xcode setup (~5 min, manual)

After `git clone https://github.com/lyfar/ios-voiceink-ru` and `open VoiceInk-ios.xcodeproj`:

### 1. Drop in sherpa-onnx framework

GigaAM inference runs through [`k2-fsa/sherpa-onnx`](https://github.com/k2-fsa/sherpa-onnx). The framework isn't in this repo (74 MB binary).

```bash
cd /tmp
curl -L -o sherpa.tar.bz2 \
  https://github.com/k2-fsa/sherpa-onnx/releases/latest/download/sherpa-onnx-v1.13.1-ios-no-tts.tar.bz2
tar xjf sherpa.tar.bz2
cp -R sherpa-onnx-*-ios-no-tts/sherpa-onnx.xcframework \
  ~/Sites/ios-voiceink-ru/Frameworks/
```

In Xcode:
- File → Add Files → select `Frameworks/sherpa-onnx.xcframework`
- Project navigator → VoiceInk-ios target → General → "Frameworks, Libraries, and Embedded Content" → set sherpa-onnx.xcframework to **"Embed & Sign"**

### 2. Bridging header

The sherpa-onnx release includes `SherpaOnnx-Bridging-Header.h`. Copy it into the project root:

```bash
cp /tmp/sherpa-onnx-*-ios-no-tts/SherpaOnnx-Bridging-Header.h \
  ~/Sites/ios-voiceink-ru/VoiceInk-ios/
```

In Xcode:
- VoiceInk-ios target → Build Settings → search "bridging" → set **Objective-C Bridging Header** = `VoiceInk-ios/SherpaOnnx-Bridging-Header.h`

### 3. Signing (already wired in pbxproj)

Bundle IDs are already set:
- App: `lol.egor.voiceink-ru`
- Keyboard ext: `lol.egor.voiceink-ru.keyboard`
- Tests: `lol.egor.voiceink-ru.tests` / `lol.egor.voiceink-ru.uitests`

Team ID is `5C5L6DFJGS` (Egor Lyfar Apple Dev). If you sign as someone else:
```
sed -i '' 's|5C5L6DFJGS|<YOUR_TEAM_ID>|g' VoiceInk-ios.xcodeproj/project.pbxproj
```

App Group `group.lol.egor.voiceink-ru` — add it in Apple Developer Portal under your team, then re-sync provisioning profiles.

### 4. Build & run

```bash
xcodebuild -project VoiceInk-ios.xcodeproj -scheme VoiceInk-ios \
  -destination 'platform=iOS,name=Egor iPhone' build
```

Or hit **Cmd+R** in Xcode with the iPhone connected.

### 5. First launch

- Open app → Settings → Local Models → "GigaAM (русский, оффлайн)" → tap "Скачать модель (241 МБ)".
- Wait ~30s on Wi-Fi.
- Settings → set provider to `GigaAM (Russian, on-device)`.
- Trigger custom keyboard (in any text field, switch to VoiceInk RU keyboard, tap red Record).
- Speak Russian.
- Text appears.

## CI / signed IPA build

`.github/workflows/build-ios.yml` runs on every push to main:
- macOS-15 runner with Xcode 26
- Imports signing cert + provisioning profile from GH secrets
- `xcodebuild archive` → `xcodebuild -exportArchive` (ad-hoc distribution)
- Uploads IPA to Cloudflare R2
- Updates `manifest.plist` on `beta.voice.egor.lol`

Required GH secrets (Settings → Secrets → Actions):
- `APPLE_CERT_P12_BASE64` — exported developer cert .p12 file, base64-encoded
  - Export from Keychain Access → "Apple Development: Egor Lyfar (5C5L6DFJGS)" → right click → Export → .p12 with password
  - `base64 -i cert.p12 | pbcopy` → paste into the secret
- `APPLE_CERT_P12_PASSWORD` — password you set when exporting the .p12
- `APPLE_PROVISIONING_PROFILE_BASE64` — ad-hoc provisioning profile, base64
  - Generate at https://developer.apple.com/account → Profiles → ad-hoc with bundle id `lol.egor.voiceink-ru`
  - Add your iPhone UDID to the device list first
  - `base64 -i VoiceInk-RU.mobileprovision | pbcopy`
- `APPLE_PROVISIONING_PROFILE_KEYBOARD_BASE64` — same as above but for the keyboard extension (`lol.egor.voiceink-ru.keyboard`)
- `KEYCHAIN_PASSWORD` — any random string, e.g. `openssl rand -hex 16 | pbcopy`
- `CLOUDFLARE_API_TOKEN` — token with R2 + DNS edit on egor.lol. Already in `~/secrets/cloudflare/sound-healing.env` — copy that value
- `CLOUDFLARE_ACCOUNT_ID` — `deec3c68003b1e10d5027984c23bd0ff`

The R2 bucket `voice-ink-ru-beta` and custom domain `beta.voice.egor.lol` are already provisioned (one-time done).

## Install IPA on iPhone (OTA)

Open in iPhone Safari: <https://beta.voice.egor.lol/>
Tap "Install" → iOS prompts to install from `itms-services://...`

Trust prompt: Settings → General → VPN & Device Management → trust the dev cert (one-time).

## Troubleshooting

- **Keyboard doesn't show up after install**: Settings → General → Keyboards → Add New Keyboard → VoiceInk RU. Then in any text field, tap the globe icon and switch.
- **Recording starts but transcription empty**: check that GigaAM model is fully downloaded (Settings → Local Models → GigaAM).
- **CI build fails on signing**: check Team ID match between cert and pbxproj. Re-export provisioning profile after adding new device UDID.

## Architecture summary

```
User PTT (custom keyboard)
  → AudioRecorder writes m4a to App Group container
  → main app picks up via Darwin notification
  → AVAudioConverter normalizes m4a → 16k mono float32 PCM
  → GigaAMTranscriptionService.transcribe(pcm:)
  → sherpa-onnx OfflineRecognizer + GigaAM ONNX (encoder/decoder/joiner)
  → text inserted into focus field via UITextDocumentProxy
```

Total round trip on iPhone 15 Pro: ~250-400 ms for a 3-second utterance.
