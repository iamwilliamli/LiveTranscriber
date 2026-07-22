# LiveTranscriber

<p align="center">
  <img src="docs/assets/readme-poster.png" alt="LiveTranscriber README poster" />
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> · <strong>English</strong> ·
  <a href="https://testflight.apple.com/join/gsu9xa9k">TestFlight Beta</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%2026%2B%20%7C%20macOS%2015%2B-black">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-blue">
  <img alt="Local first" src="https://img.shields.io/badge/privacy-local--first-green">
  <img alt="License" src="https://img.shields.io/badge/license-source--available-orange">
</p>

LiveTranscriber is a local-first recording and transcription project. The iOS app is the current shipping product: record on your iPhone, read the transcript as it appears, translate while recording, then turn saved audio into searchable notes with local transcription, summaries, and tags. A native macOS companion is developed in the same repository for meeting-window, system-audio, and microphone capture.

It uses Apple Speech for the default live transcription path, supports optional Local Whisper for offline high-accuracy re-transcription, and can generate summaries and topic tags with Apple Intelligence or a downloaded Qwen3 1.7B Q4 GGUF model through embedded llama.cpp. This makes it useful on devices where Apple Intelligence is unavailable, including China-region iPhones and other unsupported configurations.

## Highlights

| Moment | What LiveTranscriber does |
| --- | --- |
| While recording | Saves audio and shows live transcript lines immediately. |
| While listening | Translates confirmed transcript text with Apple's Translation framework. |
| After recording | Re-transcribes saved audio with Apple Speech or Local Whisper, or explicitly processes it with Gemini Cloud. |
| For notes | Generates summaries and tags with Apple Intelligence, local Qwen3, or Gemini Cloud. |
| For recall | Searches names, languages, transcript text, summaries, and tags. |
| For privacy | Keeps recordings local by default, with optional private iCloud sync. |

## Core Workflow

1. **Record and transcribe live.** Start recording, choose language and WAV/M4A format from the recorder, and watch transcript lines appear as the audio is captured.
2. **Translate during recording.** Use live transcript translation for confirmed lines while the recording is still running.
3. **Save a structured recording.** Add a title, manual tags, generated title/tags, and optional location metadata.
4. **Improve the transcript locally.** After recording, choose Local Whisper and select any downloaded model for higher-accuracy offline re-transcription.
5. **Summarize on device.** Use Apple Intelligence when available, or use local Qwen3 summaries and tags when Apple Intelligence is not available.
6. **Search later.** Find recordings by file name, language, transcript body, summary, or tags.

## Current Features

### Native macOS Companion

- Native SwiftUI macOS app, not a Catalyst wrapper.
- Provider-neutral ScreenCaptureKit picker for a display, app, or individual meeting window, including Zoom, Teams, and Meet.
- H.264 MP4 capture up to 4K/30 fps, with independent AAC sidecars for system audio and microphone input.
- Versioned multi-asset session manifests shared with the iOS domain model.
- Reads and plays the shared iCloud recording library, with a local Application Support fallback and security-scoped folder access.

### Recording

- Native SwiftUI app with Recording, Recordings, and Settings tabs.
- Stereo Capture using `AVCaptureSession` and `AVCaptureDeviceInput.multichannelAudioMode = .stereo`.
- WAV and M4A output, configurable from the recorder card and Settings.
- Pause/resume, elapsed timer, input status, Live Activity, Dynamic Island, and Home Screen widget support.
- Consistent haptic feedback for primary actions, menus, navigation, analysis, playback, and blocked states.

### Transcription and Translation

- Default Apple Speech live transcription through `SpeechAnalyzer` and `SpeechTranscriber`.
- Optional Local Whisper Live beta for offline realtime transcription with a selected downloaded model.
- Import audio from Files or the iOS share/Open In menu.
- Offline imported-audio transcription with progress and failure states.
- Saved-recording re-transcription with Apple Speech or Local Whisper, plus explicitly confirmed Gemini Cloud processing.
- EchoScript-inspired Gemini flow: upload original audio only after confirmation, generate a verbatim speaker-labeled timeline with color-coded speaker chips in the transcript UI, then create summary and meeting intelligence. The pre-Gemini transcript remains restorable.
- Live and saved transcript translation using Apple's Translation framework.

### Saved Recordings

- Timestamped transcript lines that can seek playback.
- Recording detail view with playback controls, transcript seek, translation, copy, share, edit, lock/unlock, delete, and audio parameter inspection.
- Recording map for recordings saved with location metadata.
- Search across file names, languages, transcript previews, full transcript text, summaries, and tags.
- Local app-private storage by default, with optional app-private iCloud file sync and private CloudKit index sync.

### Intelligence

- Selectable summary engine: Automatic, Apple Intelligence, Local Qwen3, or Gemini Cloud.
- Dedicated Gemini Cloud submenu in Intelligence Settings with an enable switch, Keychain-backed API key, model name, and locally tracked request/input/output/thinking/cached/total token usage.
- Tap Analyze to use the Settings default; long-press Analyze to choose a provider for that run.
- Local Qwen3 1.7B Q4_K_M GGUF summaries and tags through embedded llama.cpp.
- Summary model download/delete controls in Settings.
- Save-sheet title/tag generation for new recordings.

### Model Options

- Local Whisper saved-recording re-transcription can choose from downloaded models per run.
- Local Whisper model families: Tiny, Base, Small, Medium, Large v3 Turbo Q5, Large v3 Q5, and Large v3.
- Optional Core ML encoder downloads for Local Whisper model acceleration.
- Local Qwen summary model: `Qwen_Qwen3-1.7B-Q4_K_M.gguf`.

## Why Local Qwen Matters

Apple Intelligence is not available on every iPhone, region, language, or OS configuration. LiveTranscriber keeps summaries usable by adding a local Qwen3 path:

- The transcript stays on the phone.
- The model runs through embedded llama.cpp.
- Summary and tags work without Apple Intelligence after the GGUF model is downloaded.
- This is especially helpful for China-region iPhones and other devices where Apple Intelligence is unavailable.

## How It Works

```mermaid
flowchart TB
    user["User"]
    ui["SwiftUI App\nRecording, Library, Settings"]
    capture["AVCaptureSession\nStereo microphone capture"]
    fileWriter["Audio File Writer\nWAV / M4A"]
    appleSpeech["Apple Speech\nSpeechAnalyzer + SpeechTranscriber"]
    whisperLive["Local Whisper Live Beta\nrealtime whisper.cpp chunks"]
    liveText["Live Transcript Lines"]
    translation["Apple Translation\nlive and saved transcript translation"]
    store["RecordingStore\nmetadata, files, search"]
    localFiles["Local App-Private Container"]
    icloud["Private iCloud Container\noptional"]
    cloudKit["Private CloudKit Database\noptional"]
    detail["Recording Detail\nplayback, seek, edit, analyze"]
    localWhisper["Local Whisper\nsaved-recording re-transcription"]
    appleIntel["Apple Intelligence\nFoundationModels summary + tags"]
    localQwen["Local Qwen3 GGUF\nsummary through llama.cpp"]
    gemini["Gemini Cloud\nverbatim transcript + speaker timeline + intelligence"]
    activity["ActivityKit + WidgetKit\nLock Screen, Dynamic Island, Widget"]

    user --> ui
    ui --> capture
    capture --> fileWriter
    capture --> appleSpeech
    capture --> whisperLive
    appleSpeech --> liveText
    whisperLive --> liveText
    liveText --> ui
    liveText --> translation
    liveText --> activity
    fileWriter --> store
    liveText --> store
    store --> localFiles
    store -. "if enabled" .-> icloud
    store -. "if enabled" .-> cloudKit
    store --> detail
    detail --> localWhisper
    detail --> appleIntel
    detail --> localQwen
    detail --> gemini
    localWhisper --> store
    appleIntel --> store
    localQwen --> store
    gemini --> store
```

## Transcription Paths

| Path | Use case | Network behavior |
| --- | --- | --- |
| Apple Speech | Default live transcription, import transcription, Apple re-transcription | On-device Apple system framework |
| Local Whisper Live beta | Offline realtime transcription with a selected Whisper model | On-device after model download |
| Local Whisper saved-recording | Higher-accuracy offline pass after recording | On-device after model download |
| Gemini Cloud | Optional verbatim transcript, speaker turns, timestamps, summary, and meeting analysis | Uploads audio and the current draft only after explicit confirmation; keeps a restorable transcript backup |

## Summary Paths

| Engine | Use case | Notes |
| --- | --- | --- |
| Automatic | Best available local option | Apple Intelligence first, then Local Qwen if installed |
| Apple Intelligence | System FoundationModels summary and tags | Requires device and region availability |
| Local Qwen3 | Local summaries on unsupported devices | Uses `Qwen_Qwen3-1.7B-Q4_K_M.gguf` with embedded llama.cpp |
| Gemini Cloud | Cloud summaries, meeting analysis, and recording Q&A | Uses the user's Gemini API key; Automatic mode never selects it |

## Supported Languages

Apple live transcription, imported-audio transcription, and Apple Speech re-transcription use the languages returned by `AppleSpeechTranscriptionSupport.supportedLanguages()` on the current device. The fallback list shown before the system list loads includes English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, German, and Spanish.

Local Whisper uses model-specific language support:

- English-only models expose English only.
- Multilingual models expose Whisper's multilingual language list.

## Storage and Sync

- Local app-private storage is the default.
- Optional iCloud storage moves app-managed audio and transcript files into an app-private iCloud container.
- Recording metadata uses SwiftData locally by default.
- When iCloud storage is enabled, metadata syncs through the user's private CloudKit database.
- Downloaded Whisper, Core ML encoder, and Qwen model files are excluded from iCloud backup.

## Requirements

- Xcode beta with the iOS 27 SDK.
- iOS 26 or later device or simulator for development.
- iOS 27 is required for the Native Speech Pipeline mode.
- macOS 15 or later for the native Mac app; Screen Recording and Microphone permission are required for the corresponding capture options.
- Apple Speech availability on the target device.
- FoundationModels availability for Apple Intelligence summaries.
- Embedded whisper.cpp runtime for Local Whisper.
- Embedded llama.cpp runtime for Local Qwen summaries.
- iCloud capability configured for `iCloud.com.iamwilliamli.LiveTranscriber` when testing sync.

## Build

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriberMac \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Both commands use Xcode's standard incremental DerivedData location. Open the root `LiveTranscriber.xcworkspace` for both platforms, then select `LiveTranscriber` for iOS or `LiveTranscriberMac` for macOS. The workspace owns both app projects and resolves their shared local Swift packages as one package graph. Device testing requires a signing team with the iCloud and Live Activity capabilities enabled; the macOS App ID must also be associated with the existing iCloud container.

## Project Structure

- `LiveTranscriber/`: Main iOS app target.
- `LiveTranscriber.xcworkspace`: Single Xcode entry point for the iOS and macOS projects.
- `LiveTranscriberWidget/`: ActivityKit widget extension for Lock Screen and Dynamic Island.
- `LiveTranscriberMac/`: Native macOS app, generated from its checked-in `project.yml`.
- `Packages/TranscriberDomain/`: Shared recording models and platform-neutral service boundaries.
- `Packages/Qwen3Speech/`: Pinned app-used subset of the Qwen3 ASR, VAD, and audio runtime, including Mac archive compatibility.
- `Vendor/`: Embedded whisper.cpp and llama.cpp XCFrameworks.
- `docs/`: Focused engineering documents.
- `DEVELOPMENT_NOTES.md`: Long-form development log and implementation notes.

## Documentation

- [Documentation Index](docs/README.md)
- [Current Product and UI Design](docs/CURRENT_DESIGN.md)
- [Recording Processing Pipeline](docs/RECORDING_PIPELINE.md)
- [Live Activity Design](docs/LIVE_ACTIVITY.md)
- [Localization](docs/LOCALIZATION.md)
- [Native macOS Architecture](docs/architecture/macos-foundation.md)
- [Continuous Integration](docs/CI.md)
- [Development Notes](DEVELOPMENT_NOTES.md)

## Community

- [TestFlight Beta](https://testflight.apple.com/join/gsu9xa9k)
- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy](SECURITY.md)
- [Bug Reports](https://github.com/iamwilliamli/LiveTranscriber/issues/new?template=bug_report.md)
- [Feature Requests](https://github.com/iamwilliamli/LiveTranscriber/issues/new?template=feature_request.md)

## Source Availability and Commercial Attribution

LiveTranscriber is source-available under the [LiveTranscriber Source Available License 1.0](LICENSE). The code is public so people can learn from it, fork it, and continue development.

This is not an OSI-approved open-source license because commercial forks have an attribution requirement. Commercial apps, services, forks, or derivative products based on this project must include visible in-app attribution:

```text
Based on LiveTranscriber by William Li
Original project: https://github.com/iamwilliamli/LiveTranscriber
```

Attribution-free, private-label, or white-label commercial use requires separate written permission from William Li. See [LICENSE](LICENSE), [NOTICE](NOTICE), and [CONTRIBUTING.md](CONTRIBUTING.md) for the full terms.

## Third-Party Licenses

Reddit Sans is included under the SIL Open Font License, Version 1.1. whisper.cpp and llama.cpp are included under the MIT License. Optional Whisper GGML models and the optional Qwen3 GGUF summary model are downloaded on demand from Hugging Face repositories controlled by their respective model publishers. See [LiveTranscriber/Fonts/OFL.txt](LiveTranscriber/Fonts/OFL.txt) and [NOTICE](NOTICE).

## Apple Developer References

- [Speech framework](https://developer.apple.com/documentation/speech)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AnalyzerInputConverter](https://developer.apple.com/documentation/speech/analyzerinputconverter)
- [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)
- [AVCaptureDeviceInput](https://developer.apple.com/documentation/avfoundation/avcapturedeviceinput)
- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Translation](https://developer.apple.com/documentation/translation)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

## Privacy Model

LiveTranscriber is built around local processing by default.

- Live recording does not use developer-operated transcription servers, third-party analytics, ads, tracking, or custom network requests.
- Apple Speech, Apple Translation, and Apple Intelligence use Apple system frameworks.
- Local Whisper transcription runs on device after the user downloads or bundles a model.
- Local Qwen summaries run on device through embedded llama.cpp after the user downloads or bundles the GGUF model.
- Gemini is used only after the user confirms **Process with Gemini Cloud** for a saved recording, or explicitly selects Gemini for a text-only intelligence action. Audio or transcript text is sent directly from the iPhone with the user's own API key; Automatic mode remains local-only.
- Gemini Interactions requests set `store: false`, and the temporary Gemini Files upload is deleted after processing on a best-effort basis.
- Files are stored in the local app-private container by default.
- Optional iCloud sync uses the user's app-private iCloud container and CloudKit private database.
- The camera is not used for photos or video. `NSCameraUsageDescription` is present because Apple static review requires it when the app uses `AVCaptureSession` / `AVCaptureDeviceInput` for microphone recording.
