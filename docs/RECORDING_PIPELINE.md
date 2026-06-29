# Recording Processing Pipeline

This is the current audio pipeline that works well on device. File-level normalization is off by default and available behind the Developer Options loudness-processing toggle; avoid returning to input-tap gain or repeated normalization passes.

## Recording Stage

The live recorder uses Stereo Capture as the only microphone capture path. This is the verified way to save a stereo recording while still feeding mono speech input to `SpeechAnalyzer`.

Setup:

1. Configure `AVAudioSession` with `.playAndRecord`, `.default`, `.defaultToSpeaker`, and `.duckOthers`.
2. Request `preferredInputNumberOfChannels = 2` for route diagnostics, but do not rely on `AVAudioSession.maximumInputNumberOfChannels` as the source of truth.
3. Create an `AVCaptureSession`.
4. Create `AVCaptureDeviceInput(device: AVCaptureDevice.default(for: .audio))`.
5. Check `input.isMultichannelAudioModeSupported(.stereo)`.
6. Set `input.multichannelAudioMode = .stereo`.
7. Add one `AVCaptureAudioDataOutput` and receive uncompressed `CMSampleBuffer` values on a serial sample queue.

Per-buffer fan-out:

```text
CMSampleBuffer
  -> AVAudioPCMBuffer source
  -> recording converter: 48 kHz or session sample rate / stereo / Float32 / non-interleaved
     -> AudioFileWriter
  -> analyzer converter: same sample rate / mono / Float32 / non-interleaved
     -> AnalyzerInputPipeline
     -> SpeechAnalyzer
```

The stereo file path and mono analyzer path are intentionally separate. The app writes the stereo buffer first, then sends the mono buffer to the live SpeechAnalyzer pipeline.

Current target formats:

```text
recordingFormat:
  commonFormat = .pcmFormatFloat32
  sampleRate = AVAudioSession.sampleRate, fallback 48_000
  channels = 2
  interleaved = false

analyzerSourceFormat:
  commonFormat = .pcmFormatFloat32
  sampleRate = recordingFormat.sampleRate
  channels = 1
  interleaved = false
```

Important constraints:

- `AVCaptureDeviceInput.multichannelAudioMode` defaults to `.none`; it must be set to `.stereo`.
- The stereo mode only takes effect for the built-in microphone. External microphones may be ignored by the system for this property.
- If `.stereo` is unsupported, the app fails fast with `stereoCaptureUnavailable` instead of silently saving mono.
- Do not use `AVCaptureAudioDataOutput.audioSettings` on iOS; it is unavailable there. Convert the received sample buffers in app code.
- Keep this path free of real-time gain. Optional file-level normalization is the only durable loudness adjustment.

Diagnostics:

- Recording Details shows the saved file parameters, including sample rate and whether the saved file is mono or stereo.
- Xcode logs include capture setup, first-buffer format, and conversion failures for debugging.

## Speech Analyzer Pipelines

The app currently supports two live transcription pipelines. Both use `SpeechTranscriber(locale:preset:)` with `preset: .timeIndexedProgressiveTranscription`, and both retime analyzer inputs with a strictly monotonic frame-based `CMTime` accumulator.

### Compatible Pipeline

Use this as the stable default on iOS 26 and iOS 27.

```text
SpeechAnalyzer.Options:
  priority = .userInitiated
  modelRetention = .whileInUse
  ignoresResourceLimits = true on iOS 27 only

SpeechAnalyzer.prepareToAnalyze(in: analyzerInputFormat)

analyzerInputFormat:
  commonFormat = .pcmFormatInt16
  sampleRate = 16_000
  channels = 1
  interleaved = false

conversion:
  AVAudioConverter(source microphone format -> analyzerInputFormat)
```

This path intentionally avoids the iOS 27 native converter so it remains a controlled fallback when native SDK behavior changes.

### iOS 27 Native Pipeline

Use this when testing the iOS 27 Speech stack directly.

```text
SpeechAnalyzer.Options:
  priority = .userInitiated
  modelRetention = .whileInUse
  ignoresResourceLimits = true

SpeechTranscriber:
  preset = .timeIndexedProgressiveTranscription

AnalyzerInputConverter:
  converter = try await AnalyzerInputConverter.converter(compatibleWith: modules)

SpeechAnalyzer:
  try await analyzer.prepareToAnalyze(in: nil)

converter input time:
  synthetic AVAudioTime(sampleTime: accumulatedSourceFrames, atRate: sourceSampleRate)

AnalyzerInput retiming:
  bufferStartTime = accumulated CMTime by output frameLength and output sampleRate
```

The important detail is that the app does not pass `nil` audio times into the converter during live recording. It supplies a synthetic monotonic `AVAudioTime`, then rebuilds each emitted `AnalyzerInput.bufferStartTime` with exact frame-count accumulation. This avoids `Audio input timestamp overlaps or precedes prior audio input` failures when the input tap or converter emits buffers with ambiguous timestamps.

## Stop Stage

When recording stops:

1. Stop the `AVCaptureSession`.
2. Finish the analyzer pipeline and wait for SpeechAnalyzer to flush final transcript results.
3. If Developer Options > Loudness Processing is enabled, run `RecordingFileNormalizer.normalize(...)` on the saved audio file.
4. Save `audioNormalizedAt` and `audioNormalizationVersion` only when normalization succeeds.

The app briefly shows `正在增强录音音量` while normalization runs. If normalization is disabled or fails, the recording draft is still returned and can still be saved.

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

`RecordingStore.normalizeAudioIfNeeded(for:loudnessProcessingEnabled:)` runs when a recording detail view opens only if Developer Options > Loudness Processing is enabled. It only normalizes when the stored version is older than the current normalizer version.

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
8. If Loudness Processing is enabled, supported output formats are normalized and tagged with `RecordingFileNormalizer.version`.

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

When enabled, normalization is the durable file-level loudness fix. The playback gain is a small current-code boost, not a replacement for normalization.

## Explicit Non-Goals

- No input-tap gain before writing files.
- No peak-only gain calculation.
- No repeated normalization for the same version.
- No hidden repeated gain passes that rewrite already-normalized files.
