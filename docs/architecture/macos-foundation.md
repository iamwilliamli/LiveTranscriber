# Native macOS foundation

Live Transcriber is managed as one repository with two native application projects in one workspace:

- `LiveTranscriber.xcodeproj` owns the existing iOS and Widget targets.
- `LiveTranscriberMac/LiveTranscriberMac.xcodeproj` owns the native macOS app.
- `LiveTranscriber.xcworkspace` is the development entry point for both products.
- `TranscriberDomain` owns Foundation-only shared value types.
- `TranscriberCore` owns Foundation-only service protocols and depends on `TranscriberDomain`.

The macOS app is not a Catalyst target and does not compile the iOS source directory. Platform-independent behavior lives in two shared layers; platform capture and presentation code remain in their respective app targets.

## SharedApp layer

`SharedApp/` holds the platform-independent application tier that both app targets compile directly (target membership, not a package): the `RecordingStore` data layer with its SwiftData index, CloudKit metadata sync, and Spotlight donation; every transcription engine (Apple Speech, local Whisper, Qwen3-ASR, MOSS multi-speaker, Gemini cloud); the live transcription manager; AI services (meeting analysis, local summaries, recording chat); export and Reminders services; the shared `L10n` catalog (`Semantic.xcstrings`, `AudioEvents.xcstrings`); and shared presentation models (transcript storage parsing, category catalog, playback controller, theme, typography, fonts).

Target-membership sharing was chosen over a package because the tier is ~16k lines of `internal` API surface used pervasively by both UIs; packaging it would require a sweeping `public` migration with no behavioral benefit. `Packages/` remains the home for Foundation-only domain types and service contracts, and new cross-platform schema work should continue to land there first.

Files in `SharedApp/` must compile for both platforms: UIKit/AppKit access is allowed only behind `#if canImport` or `#if os` guards, iOS 27-gated FoundationModels code uses the `HAS_IOS27_SDK` compilation condition with `#available(iOS 27.0, macOS 27.0, *)` checks, and each app supplies its own stand-ins for platform-only services (`HapticFeedback` and the Live Activity coordinator have macOS stubs in `LiveTranscriberMac/Sources/MacSupportStubs.swift`).

## Boundary rules

1. Shared packages must not import UIKit or AppKit unless the package is explicitly platform-specific.
2. iOS microphone capture stays behind an iOS adapter built on `AVAudioSession`.
3. macOS system-audio source selection and audio capture stay behind a macOS adapter built on ScreenCaptureKit and AVFoundation.
4. Recording metadata is versioned independently from either UI.
5. A recording can own multiple typed assets; no shared API should assume one audio file per recording.
6. Both apps must build from `main` before it can be released.

## Shared service boundaries

`TranscriberCore` deliberately describes capabilities without importing AVFoundation, CloudKit, SwiftData, UIKit, or AppKit:

- `RecordingTranscribing` accepts an audio URL and returns shared transcript lines plus optional speaker diarization.
- `RecordingLibraryReading` and `RecordingLibraryWriting` describe session discovery, asset resolution, and persistence independently of the backing store.
- `RecordingMetadataSyncing` accepts typed recording/category mutations without exposing CloudKit records.

The current application adapters are `MOSSRecordingTranscriber`, `RecordingStore`, and `RecordingMetadataCloudSync`. Both products consume the same store and file formats; only their live-capture and presentation adapters are platform-specific.

## Recording asset compatibility

`RecordingSession` and `RecordingAsset` are versioned in `TranscriberDomain`. The iOS `RecordingItem` keeps `audioFileName` and `transcriptFileName` as compatibility aliases while persisting an asset manifest alongside them. Records created before the manifest existed are upgraded in memory to deterministic `legacy.primary-audio` and `legacy.transcript` assets, then written back through the existing SwiftData and CloudKit payload paths. Older clients continue to ignore the additive `assets` field.

## Shared recording library

The macOS app instantiates the same `RecordingStore` implementation as iOS. It therefore uses the same local/iCloud storage preference, `iCloud.com.iamwilliamli.LiveTranscriber` ubiquity container, CloudKit metadata, SwiftData index, `Data/Recordings` layout, migration behavior, and recording identity. There is no second Mac-only capture library or manifest index.

Imported Finder audio or movie files and recordings created on the Mac all enter the normal `RecordingStore` save/import flow. Playback uses the shared `RecordingPlaybackController`, and the Files settings pane exposes the managed recordings folder in Finder.

## macOS system-audio recording pipeline

System audio is an input option inside the normal Transcribe screen, not a separate Capture workspace. The user can choose **Microphone Only**, **System Audio Only**, or **Microphone + System Audio**. For either system-audio mode, the system `SCContentSharingPicker` selects one display, app, or window, so audio from Zoom, Teams, Meet, a browser, or another app enters through the same provider-neutral `SCContentFilter`. Choosing a window captures audio from its owning app; choosing a display captures all Mac audio in scope.

`MacSystemAudioCaptureController` adds only ScreenCaptureKit audio outputs; it does not save screen pixels or video. In System Audio Only mode it never enables ScreenCaptureKit microphone capture, so the saved M4A contains only the selected Mac content. In the combined mode, system and microphone sample buffers are written to temporary AAC/M4A tracks on a serial queue and `MacSystemAudioMixer` combines them into one M4A. If the primary system-audio writer fails but the duplicate transcription track is usable, the app explicitly offers to save that recovered system audio instead of silently substituting another source.

For either system-audio mode, the ScreenCaptureKit `.audio` sample buffers also enter `LiveTranscriptionManager` through its external-audio input. The existing conversion, waveform, Apple Speech, and local Whisper pipelines therefore follow the selected Mac audio rather than opening the default microphone. Microphone Only keeps the original `AVCaptureSession` path. On stop, the system-only or mixed M4A replaces the duplicate transcription audio in the normal `RecordingDraft`, while its transcript, language, duration, and metadata continue through the existing save sheet and `RecordingStore.save`. Temporary staging files are removed after save or discard. The completed recording appears in the same Recordings sidebar destination as every iPhone or imported recording.

The macOS App ID must be associated with the existing iCloud container in Apple Developer signing configuration before CloudKit and iCloud Drive access can work outside unsigned local builds.

## macOS feature parity

The macOS app compiles the full `SharedApp/` stack and exposes the principal iOS workflows through native macOS UI. Its sidebar has three destinations—Transcribe, Recordings, and Settings—and system-audio recording is an input mode within Transcribe. Parity is tracked row by row in [`macos-parity.md`](macos-parity.md); the product must not be described as fully equivalent until every release-gating row there is complete. Shared UserDefaults keys, Keychain entries, and on-disk formats are intended to match across platforms. The macOS deployment target is 26.0, matching the iOS 26 minimum; the app target builds arm64 only because the MLX runtime requires Apple Silicon.

## Vendored ggml frameworks

`Vendor/whisper.xcframework` and `Vendor/llama.xcframework` carry iOS device, iOS simulator, and macOS (`macos-arm64_x86_64`) slices built from pinned upstream commits — whisper.cpp `6fc7c33b4c3a2cec83e4b65abd5e96a890480375` and llama.cpp `fdb1db877c526ec90f668eca1b858da5dba85560` — using each repository's `build-xcframework.sh`. The whisper bridge (`SharedApp/LocalWhisperBridge.m`) loads the framework with `dlopen` and mirrors its C structs, so any slice rebuild must come from the same source revision on every platform; the llama bridge compiles against `<llama/llama.h>` directly and degrades to a stub via `__has_include` when the framework is absent.

## Repository and branch policy

The Mac app is a second product in this repository, not a permanent platform branch. `main` is the integration and release source of truth; use short-lived `feature/ios-*`, `feature/macos-*`, and `feature/shared-*` branches according to the ownership of a change. A cross-platform feature should land its schema or protocol change in `Packages/` first, followed by independent platform adapters and UI.

The iOS baseline from before the Mac project is retained as the annotated tag `ios-baseline-before-macos-2026-07-21`. Do not keep a long-running `macOS` branch after this foundation is reviewed: that would make shared-model migrations and fixes drift between two histories.

Pull requests should keep the shared domain, iOS compatibility build, and macOS tests green. A release additionally requires a full Xcode 27 iOS build and signed device smoke tests. iOS and macOS retain separate bundle identifiers, signing/App Store records, versions, and release timing even though their source and recording schema live together.

The generated macOS project is defined by `LiveTranscriberMac/project.yml`. Regenerate it with:

```sh
xcodegen generate --spec LiveTranscriberMac/project.yml
```
