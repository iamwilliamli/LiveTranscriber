# Documentation

This folder contains focused engineering notes for LiveTranscriber. Keep user-facing overview content in the root `README.md`; keep implementation decisions and debugging notes in `DEVELOPMENT_NOTES.md`.

## Files

- [Current Product and UI Design](CURRENT_DESIGN.md): Current app structure, interaction model, visual tokens, and screen-level UI behavior.
- [Recording Processing Pipeline](RECORDING_PIPELINE.md): AVCaptureSession audio capture, transcription fan-out, and stereo recording decisions.
- [Live Activity Design](LIVE_ACTIVITY.md): Lock Screen and Dynamic Island state, layout, and update policy.
- [Localization](LOCALIZATION.md): Semantic string catalog rules, Swift usage patterns, and steps for adding a new language.
- [Native macOS Architecture](architecture/macos-foundation.md): Workspace boundaries, shared domain models, storage compatibility, capture pipeline, and branch policy.
- [Planned iOS Screen Audio and Floating Captions](architecture/ios-screen-audio-captions.md): Future iOS 26 ReplayKit and iOS 27 ScreenCaptureKit capture backends, bilingual Picture in Picture captions, implementation order, and device verification gates.
- [Continuous Integration](CI.md): iOS, macOS, and shared-package verification lanes plus the Xcode 27 release gate.
- [Development Notes](../DEVELOPMENT_NOTES.md): Full project log, feature notes, tradeoffs, and TestFlight checklist.

## Current Architecture

The repository has these main runtime areas:

1. `ContentView` owns the top-level tab shell and wires shared `LiveTranscriptionManager` and `RecordingStore` instances into the recording, library, and settings views.
2. `LiveTranscriptionManager` owns the live recording session, AVCaptureSession Stereo Capture path, SpeechAnalyzer pipeline, transcript lines, elapsed timer, selected language/format, and Live Activity updates.
3. `RecordingStore` owns saved recording metadata, local app-private storage by default, optional app-private iCloud storage, SwiftData local/CloudKit private index persistence, import transcription, re-transcription, deletion, search inputs, and Apple Intelligence analysis.
4. `RecordingsView` owns the file-library UI: search, import picker, row actions, swipe actions, detail navigation, playback, transcript seek, sharing, copy, delete, re-transcribe, and summary/tag generation.
5. `AppTheme`, `AppTypography`, `EmptyStateView`, and `HapticFeedback` define the shared visual and tactile design language.
6. `LiveTranscriberWidget` renders ActivityKit content for Lock Screen and Dynamic Island.
7. `LiveTranscriberMac` owns the native macOS UI and the ScreenCaptureKit system-audio adapter; recordings and playback use the shared `RecordingStore` stack.
8. `Packages/TranscriberDomain` owns platform-neutral recording values and service boundaries used by both apps.

## Build Verification

Use the same command as the root README:

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -workspace LiveTranscriber.xcworkspace \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The complete iOS, macOS, and package commands are documented in [Continuous Integration](CI.md). App builds use Xcode's standard incremental DerivedData directory.
