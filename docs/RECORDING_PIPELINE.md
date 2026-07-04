# Recording Processing Pipeline

This is the current audio pipeline that works well on device. The recorder does not apply real-time gain or post-save audio rewriting; it preserves the captured audio and keeps playback adjustment limited to the player.

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
  -> live transcription converter:
     same sample rate / mono / Float32 / non-interleaved
       -> AnalyzerInputPipeline
       -> SpeechAnalyzer
```

The stereo file path and mono transcription path are intentionally separate. The app writes the stereo buffer first, then sends the mono buffer to the Apple live transcription pipeline.

Current target formats:

```text
recordingFormat:
  commonFormat = .pcmFormatFloat32
  sampleRate = AVAudioSession.sampleRate, fallback 48_000
  channels = 2
  interleaved = false

Apple analyzerSourceFormat:
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
- Keep this path free of real-time gain and file rewrites.

Diagnostics:

- Recording Details shows the saved file parameters, including sample rate and whether the saved file is mono or stereo.
- Xcode logs include capture setup, first-buffer format, and conversion failures for debugging.

## Live Transcription Backend

Live recording uses the Apple on-device backend:

- Apple On-Device: the default local path using `SpeechAnalyzer` and `SpeechTranscriber`.

Saved recordings can still be manually re-transcribed with OpenAI file transcription from the recording detail menu. That path uploads the selected saved recording file only after explicit user action and is not part of live microphone transcription.

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

## OpenAI Saved-Recording Re-Transcription

OpenAI is used only for manual re-transcription of saved recordings. The user supplies their own OpenAI API key in Settings; the key is stored in Keychain and used directly from the iPhone when the user chooses an OpenAI transcription action.

- Long-form mode: `gpt-4o-transcribe`, JSON response, one transcript block starting at 0 seconds.
- Segmented mode: `whisper-1`, `verbose_json`, `timestamp_granularities[]=segment`, preserving segment timestamps from the API response.
- Standard developer-owned OpenAI API keys must not be bundled into the app.

## Stop Stage

When recording stops:

1. Stop the `AVCaptureSession`.
2. Finish the Apple analyzer pipeline and wait for SpeechAnalyzer to flush final transcript results.
3. Return a recording draft with the captured audio URL, transcript lines, language metadata, and elapsed duration.
4. Let `TranscriptionView` present the save sheet before the draft is committed to the library.

## Imported and Re-Transcribed Recordings

Imported recordings enter the same library model as live recordings:

1. The Files picker accepts `UTType.audio`.
2. The user chooses a transcription language.
3. `RecordingStore` creates a placeholder `RecordingItem` with `RecordingImportStatus`.
4. The source file is copied into the recordings directory and an empty transcript file is created.
5. `ImportedRecordingTranscriptionService` reads the file in frames and feeds `SpeechAnalyzer` / `SpeechTranscriber`.
6. Progress is reported as the audio file is consumed.
7. The finished timed transcript replaces the empty `.txt` file.

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

## Explicit Non-Goals

- No input-tap gain before writing files.
- No post-save audio rewriting pass.
- No hidden gain passes that rewrite saved audio files.
