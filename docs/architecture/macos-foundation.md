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

If the shared container is unavailable, the app uses `Application Support/LiveTranscriber/Recordings`; the user can also choose a recording folder. It persists a security-scoped bookmark and scans audio, video, transcript, and session-manifest assets without importing or moving them. Every resolved asset path is checked against the selected library root before playback. `MacRecordingPlayer` uses AVFoundation and downloads an iCloud placeholder on demand.

## macOS capture pipeline

The capture workspace uses the system `SCContentSharingPicker`, so capture is provider-neutral: Zoom, Teams, Meet, an individual window, one app, or a display all enter through the same `SCContentFilter`. The app excludes its own process, records an H.264 MP4 at up to 4K/30 fps with `SCRecordingOutput`, and lets the user independently enable system audio and microphone input.

System and microphone samples are also routed through separate serial `SCStreamOutput` callbacks into independent AAC/M4A writers. A successful capture therefore produces a reversible asset set instead of baking the only copy of both voices into one mix:

- `<session-id>.screen.mp4` — primary screen video and directly playable capture.
- `<session-id>.m4a` — system-audio sidecar; its legacy-compatible name also lets the current iOS file scanner discover the recording.
- `<session-id>.microphone.m4a` — microphone sidecar.
- `<session-id>.session.json` — versioned `RecordingSession` manifest joining the assets.

The manifest is committed only after the video writer finishes. Empty or failed optional audio tracks are removed and reported as a non-fatal warning; a failed capture removes every partial output. The library merges manifests with filesystem and CloudKit metadata, so a completed recording appears after refresh whether it was stored in iCloud Drive or the local fallback directory.

The macOS App ID must be associated with the existing iCloud container in Apple Developer signing configuration before CloudKit and iCloud Drive access can work outside unsigned local builds.

## Repository and branch policy

The Mac app is a second product in this repository, not a permanent platform branch. `main` is the integration and release source of truth; use short-lived `feature/ios-*`, `feature/macos-*`, and `feature/shared-*` branches according to the ownership of a change. A cross-platform feature should land its schema or protocol change in `Packages/` first, followed by independent platform adapters and UI.

The iOS baseline from before the Mac project is retained as the annotated tag `ios-baseline-before-macos-2026-07-21`. Do not keep a long-running `macOS` branch after this foundation is reviewed: that would make shared-model migrations and fixes drift between two histories.

Pull requests should keep the shared domain, iOS compatibility build, and macOS tests green. A release additionally requires a full Xcode 27 iOS build and signed device smoke tests. iOS and macOS retain separate bundle identifiers, signing/App Store records, versions, and release timing even though their source and recording schema live together.

The generated macOS project is defined by `LiveTranscriberMac/project.yml`. Regenerate it with:

```sh
xcodegen generate --spec LiveTranscriberMac/project.yml
```
