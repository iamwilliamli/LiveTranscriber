# Native macOS foundation

Live Transcriber is managed as one repository with two native application projects in one workspace:

- `LiveTranscriber.xcodeproj` owns the existing iOS and Widget targets.
- `LiveTranscriberMac/LiveTranscriberMac.xcodeproj` owns the native macOS app.
- `LiveTranscriber.xcworkspace` is the development entry point for both products.
- `Packages/TranscriberDomain` owns Foundation-only shared value types; speaker diarization is the first model moved across this boundary.

The macOS app is not a Catalyst target and does not compile the iOS source directory. Platform-independent behavior will move incrementally into local packages under `Packages/`; platform capture and presentation code remain in their respective app targets.

## Boundary rules

1. Shared packages must not import UIKit or AppKit unless the package is explicitly platform-specific.
2. iOS microphone capture stays behind an iOS adapter built on `AVAudioSession`.
3. macOS screen, window, system-audio, and microphone capture stays behind a macOS adapter built on ScreenCaptureKit and AVFoundation.
4. Recording metadata is versioned independently from either UI.
5. A recording can own multiple typed assets; no shared API should assume one audio file per recording.
6. Both apps must build from `main` before it can be released.

## Recording asset compatibility

`RecordingSession` and `RecordingAsset` are versioned in `TranscriberDomain`. The iOS `RecordingItem` keeps `audioFileName` and `transcriptFileName` as compatibility aliases while persisting an asset manifest alongside them. Records created before the manifest existed are upgraded in memory to deterministic `legacy.primary-audio` and `legacy.transcript` assets, then written back through the existing SwiftData and CloudKit payload paths. Older clients continue to ignore the additive `assets` field.

The generated macOS project is defined by `LiveTranscriberMac/project.yml`. Regenerate it with:

```sh
xcodegen generate --spec LiveTranscriberMac/project.yml
```
