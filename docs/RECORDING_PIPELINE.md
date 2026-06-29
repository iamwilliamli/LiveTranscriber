# Recording Processing Pipeline

This is the current audio pipeline that works well on device. File-level normalization remains the main loudness strategy; avoid returning to input-tap gain or repeated normalization passes.

## Recording Stage

1. Configure `AVAudioSession` with `.playAndRecord` and `.voiceChat`.
2. Use options `.allowBluetoothHFP`, `.defaultToSpeaker`, and `.duckOthers`.
3. Install an `AVAudioEngine` input tap.
4. For each input `AVAudioPCMBuffer`, copy the raw buffer into two paths:
   - Write one raw copy directly to `AudioFileWriter`.
   - Send the other raw copy to `AnalyzerInputPipeline` / `SpeechAnalyzer`.
5. Do not apply real-time gain before writing the file.
6. Do not apply real-time gain before sending audio to SpeechAnalyzer.

The core reason is stability: the saved file should not clip, and transcription should receive audio that matches the microphone signal as closely as possible.

## Stop Stage

When recording stops:

1. Remove the input tap and stop the audio engine.
2. Finish the analyzer pipeline and wait for SpeechAnalyzer to flush final transcript results.
3. Run `RecordingFileNormalizer.normalize(...)` on the saved audio file.
4. Save `audioNormalizedAt` and `audioNormalizationVersion` on the recording item.

The app briefly shows `正在增强录音音量` while normalization runs. If normalization fails, the recording draft is still returned and can still be saved.

## Normalization

Current normalizer version:

```swift
RecordingFileNormalizer.version = 2
```

Core parameters:

```text
targetActiveRMS = 0.20
maximumGain = 16
limiterCeiling = 0.94
activeSampleThreshold = 0.012
minimumActiveRMS = 0.006
frameCapacity = 8192
```

The normalizer computes gain from active speech samples instead of whole-file RMS or single peak level. This keeps short loud peaks from making the entire voice recording too quiet.

## Replacement Strategy

Normalization writes to a temporary sibling file first:

```text
.normalized-UUID.ext
```

After writing succeeds, the original file is replaced through a backup-based swap. If replacement fails, the code attempts to restore the original file.

## Existing Recordings

`RecordingStore.normalizeAudioIfNeeded(for:)` runs when a recording detail view opens. It only normalizes when the stored version is older than the current normalizer version.

Do not repeatedly normalize an already-normalized file at the same version. Repeated gain passes can reintroduce distortion.

## Imported and Re-Transcribed Recordings

Imported recordings enter the same library model as live recordings:

1. The Files picker accepts `UTType.audio`.
2. The user chooses a transcription language.
3. `RecordingStore` creates a placeholder `RecordingItem` with `RecordingImportStatus`.
4. The source file is copied into the recordings directory and an empty transcript file is created.
5. `ImportedRecordingTranscriptionService` reads the file in frames and feeds `SpeechAnalyzer` / `SpeechTranscriber`.
6. Progress is reported as the audio file is consumed.
7. The finished timed transcript replaces the empty `.txt` file.
8. Supported output formats are normalized and tagged with `RecordingFileNormalizer.version`.

Re-transcription reuses the stored audio file, replaces the transcript text, updates language metadata, clears existing summary/tags, and clears `importStatus` when complete.

Failed import or re-transcription work is represented by `RecordingImportStatus(isFailed: true)` so the list and detail screens can keep the failed item visible.

## Playback

Playback is handled by `RecordingPlaybackController` in `RecordingsView`.

Current behavior:

- Uses `AVAudioEngine + AVAudioPlayerNode`.
- Inserts an `AVAudioUnitEQ` with `globalGain = 3`.
- Supports play, pause, unload, and seek.
- Updates current playback time roughly every 120 ms.
- Tapping a saved transcript row seeks to that row's timestamp.

Normalization is still the durable file-level loudness fix. The playback gain is a small current-code boost, not a replacement for normalization.

## Explicit Non-Goals

- No input-tap gain before writing files.
- No peak-only gain calculation.
- No repeated normalization for the same version.
- No hidden repeated gain passes that rewrite already-normalized files.
