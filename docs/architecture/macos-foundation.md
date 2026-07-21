# Native macOS foundation

Live Transcriber is managed as one repository with two native application projects in one workspace:

- `LiveTranscriber.xcodeproj` owns the existing iOS and Widget targets.
- `LiveTranscriberMac/LiveTranscriberMac.xcodeproj` owns the native macOS app.
- `LiveTranscriber.xcworkspace` is the development entry point for both products.
- `TranscriberDomain` owns Foundation-only shared value types.
- `TranscriberCore` owns Foundation-only service protocols and depends on `TranscriberDomain`.

The macOS app is not a Catalyst target and does not compile the iOS source directory. Platform-independent behavior will move incrementally into local packages under `Packages/`; platform capture and presentation code remain in their respective app targets.

## Boundary rules

1. Shared packages must not import UIKit or AppKit unless the package is explicitly platform-specific.
2. iOS microphone capture stays behind an iOS adapter built on `AVAudioSession`.
3. macOS screen, window, system-audio, and microphone capture stays behind a macOS adapter built on ScreenCaptureKit and AVFoundation.
4. Recording metadata is versioned independently from either UI.
5. A recording can own multiple typed assets; no shared API should assume one audio file per recording.
6. Both apps must build from `main` before it can be released.

## Shared service boundaries

`TranscriberCore` deliberately describes capabilities without importing AVFoundation, CloudKit, SwiftData, UIKit, or AppKit:

- `RecordingTranscribing` accepts an audio URL and returns shared transcript lines plus optional speaker diarization.
- `RecordingLibraryReading` and `RecordingLibraryWriting` describe session discovery, asset resolution, and persistence independently of the backing store.
- `RecordingMetadataSyncing` accepts typed recording/category mutations without exposing CloudKit records.

The current iOS adapters are `MOSSRecordingTranscriber`, `RecordingStore`, and `RecordingMetadataCloudSync`. The macOS app can provide different capture and storage implementations while consuming the same contracts.

## Recording asset compatibility

`RecordingSession` and `RecordingAsset` are versioned in `TranscriberDomain`. The iOS `RecordingItem` keeps `audioFileName` and `transcriptFileName` as compatibility aliases while persisting an asset manifest alongside them. Records created before the manifest existed are upgraded in memory to deterministic `legacy.primary-audio` and `legacy.transcript` assets, then written back through the existing SwiftData and CloudKit payload paths. Older clients continue to ignore the additive `assets` field.

## macOS library access

The macOS app reads the same `iCloud.com.iamwilliamli.LiveTranscriber` ubiquity container as iOS. It loads `LTRecordingV2` metadata from the existing private CloudKit zone, decodes both current `RecordingSession` payloads and legacy iOS `RecordingItem` payloads, then merges that metadata with files under `Data/Recordings`. The two legacy iCloud locations remain readable while older installations migrate.

Library access is read-only in this phase. If the shared container is unavailable, the user can choose a recording folder; the app persists a security-scoped bookmark and scans audio, video, and transcript assets without importing or moving them. Every resolved asset path is checked against the selected library root before playback. `MacRecordingPlayer` uses AVFoundation and downloads an iCloud placeholder on demand.

The macOS App ID must be associated with the existing iCloud container in Apple Developer signing configuration before CloudKit and iCloud Drive access can work outside unsigned local builds.

The generated macOS project is defined by `LiveTranscriberMac/project.yml`. Regenerate it with:

```sh
xcodegen generate --spec LiveTranscriberMac/project.yml
```
