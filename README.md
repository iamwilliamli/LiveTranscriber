# LiveTranscriber

LiveTranscriber is an iOS 26+ local recording and live transcription app. It records audio, transcribes speech on device with Apple's Speech APIs, saves audio and transcript files, and keeps recording status visible through Lock Screen Live Activities and Dynamic Island.

The project is designed as a native iOS utility rather than a cloud transcription client. Audio and transcripts stay local by default, with iCloud Drive used for cross-device file sync.

## Current Features

- Tab-based SwiftUI app with recording, file library, and settings areas.
- Live recording with real-time transcript updates, pause/resume, elapsed timer, and haptic feedback.
- WAV and M4A recording output.
- Offline transcription for imported audio files, with language selection and progress/failure state.
- Re-transcription of saved recordings with any supported Speech locale.
- iCloud Drive storage under `Live Transcriber/Documents/Recordings/`.
- Search across file names, languages, transcript previews, full transcript text, summaries, and topic tags.
- Timestamped transcript lines for playback seeking.
- Saved recording detail view with audio playback, transcript seek, copy, and share actions.
- Lock Screen and Dynamic Island Live Activity with elapsed time, latest final transcript, language, line count, and stop action.
- Local Apple Intelligence summary and topic tag generation for saved transcripts.
- File-level loudness normalization after recording, with a small playback-side boost in the current player.
- Selectable speech processing pipelines: a stable iOS 26/27 compatible pipeline and an iOS 27 native `AnalyzerInputConverter` pipeline.
- Shared visual system based on Reddit Sans, grouped backgrounds, compact card surfaces, red recording actions, and system SF Symbols.
- Chinese and English localization.

## Speech Pipeline Modes

LiveTranscriber exposes the active speech pipeline in Settings > Developer Options.

- Compatible Pipeline: available on iOS 26 and iOS 27. Uses `SpeechTranscriber` with `preset: .timeIndexedProgressiveTranscription`, `SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse)`, `ignoresResourceLimits: true` on iOS 27, `AVAudioConverter`, and fixed analyzer input `16 kHz / mono / Int16 PCM`.
- iOS 27 Native Pipeline: available on iOS 27. Uses `SpeechTranscriber` with `preset: .timeIndexedProgressiveTranscription`, `SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .whileInUse, ignoresResourceLimits: true)`, `AnalyzerInputConverter.converter(compatibleWith: modules)`, and `SpeechAnalyzer.prepareToAnalyze(in: nil)` so the system chooses the compatible input format.

Both live pipelines use a monotonic audio timeline for `AnalyzerInput.bufferStartTime` so transcript timestamps stay stable across iOS 26 and iOS 27.

## Requirements

- Xcode beta with the iOS 27 SDK.
- iOS 26 or later device or simulator for development.
- iOS 27 is required for the Native Pipeline mode.
- Apple Speech and FoundationModels availability on the target device.
- iCloud capability configured for `iCloud.com.iamwilliamli.LiveTranscriber`.

## Build

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

For device testing, open `LiveTranscriber.xcodeproj` in Xcode and use a signing team with the iCloud and Live Activity capabilities enabled.

## Project Structure

- `LiveTranscriber/`: Main iOS app target.
- `LiveTranscriberWidget/`: ActivityKit widget extension for Lock Screen and Dynamic Island.
- `LiveTranscriber.xcodeproj/`: Xcode project and shared scheme.
- `docs/`: Focused engineering documents.
- `DEVELOPMENT_NOTES.md`: Long-form development log and implementation notes.

## Documentation

- [Documentation Index](docs/README.md)
- [Current Product and UI Design](docs/CURRENT_DESIGN.md)
- [Recording Processing Pipeline](docs/RECORDING_PIPELINE.md)
- [Live Activity Design](docs/LIVE_ACTIVITY.md)
- [Development Notes](DEVELOPMENT_NOTES.md)

## Apple Developer References

- [Speech framework](https://developer.apple.com/documentation/speech)
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AnalyzerInputConverter](https://developer.apple.com/documentation/speech/analyzerinputconverter)
- [AVAudioConverter](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)

## Privacy Model

LiveTranscriber is built around local processing. Recording, transcription, summary, and tagging use Apple system frameworks on device when available. The app does not upload audio or transcript text to third-party transcription services.
