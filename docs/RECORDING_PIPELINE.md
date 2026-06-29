# Recording Processing Pipeline

This is the current audio pipeline that works well on device. Avoid returning to multi-stage gain where audio is amplified during recording and again during playback.

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

## Explicit Non-Goals

- No input-tap gain before writing files.
- No playback gain to compensate for quiet files.
- No peak-only gain calculation.
- No repeated normalization for the same version.

