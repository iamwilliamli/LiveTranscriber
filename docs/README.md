# Documentation

This folder contains focused engineering notes for LiveTranscriber. Keep user-facing overview content in the root `README.md`; keep implementation decisions and debugging notes in `DEVELOPMENT_NOTES.md`.

## Files

- [Recording Processing Pipeline](RECORDING_PIPELINE.md): Audio capture, transcription fan-out, and normalization decisions.
- [Live Activity Design](LIVE_ACTIVITY.md): Lock Screen and Dynamic Island state, layout, and update policy.
- [Development Notes](../DEVELOPMENT_NOTES.md): Full project log, feature notes, tradeoffs, and TestFlight checklist.

## Current Architecture

The app has three main runtime areas:

1. `LiveTranscriptionManager` owns the live recording session, audio engine, SpeechAnalyzer pipeline, transcript lines, and Live Activity updates.
2. `RecordingStore` owns saved recording metadata, iCloud Drive storage, import transcription, normalization, deletion, and Apple Intelligence analysis.
3. `LiveTranscriberWidget` renders ActivityKit content for Lock Screen and Dynamic Island.

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

