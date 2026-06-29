# Documentation

This folder contains focused engineering notes for LiveTranscriber. Keep user-facing overview content in the root `README.md`; keep implementation decisions and debugging notes in `DEVELOPMENT_NOTES.md`.

## Files

- [Current Product and UI Design](CURRENT_DESIGN.md): Current app structure, interaction model, visual tokens, and screen-level UI behavior.
- [Recording Processing Pipeline](RECORDING_PIPELINE.md): Audio capture, transcription fan-out, and normalization decisions.
- [Live Activity Design](LIVE_ACTIVITY.md): Lock Screen and Dynamic Island state, layout, and update policy.
- [Development Notes](../DEVELOPMENT_NOTES.md): Full project log, feature notes, tradeoffs, and TestFlight checklist.

## Current Architecture

The app has three main runtime areas:

1. `ContentView` owns the top-level tab shell and wires shared `LiveTranscriptionManager` and `RecordingStore` instances into the recording, library, and settings views.
2. `LiveTranscriptionManager` owns the live recording session, audio engine, SpeechAnalyzer pipeline, transcript lines, elapsed timer, selected language/format, and Live Activity updates.
3. `RecordingStore` owns saved recording metadata, iCloud Drive storage, local fallback storage, import transcription, re-transcription, normalization, deletion, search inputs, and Apple Intelligence analysis.
4. `RecordingsView` owns the file-library UI: search, import picker, row actions, swipe actions, detail navigation, playback, transcript seek, sharing, copy, delete, re-transcribe, and summary/tag generation.
5. `AppTheme`, `AppTypography`, `EmptyStateView`, and `HapticFeedback` define the shared visual and tactile design language.
6. `LiveTranscriberWidget` renders ActivityKit content for Lock Screen and Dynamic Island.

## Build Verification

Use the same command as the root README:

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -quiet \
  -project LiveTranscriber.xcodeproj \
  -scheme LiveTranscriber \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/LiveTranscriberDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```
