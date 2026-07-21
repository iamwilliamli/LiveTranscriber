# MLXAudio MOSS runtime

This is the minimal MLXAudio source subset required by LiveTranscriber's
on-device MOSS Transcribe Diarize backend. It was taken from the iPhone-tested
package in `OpenMOSS/MOSS-Transcribe-Diarize` and retains its Apache 2.0 license.
The vendored upstream snapshot is based on `soniqo/mlx-audio-swift` commit
`6ea59e549294151256b98b1cdbb346ba946d12d0` (2026-07-20).

The MOSS-specific iOS changes include conditional quantization of modules that
actually have packed scales, a bounded MLX cache, chunk timestamp offsets, and
speaker-segment parsing. Unrelated TTS, codec, VAD, and ASR implementations are
intentionally omitted from the Swift target to keep build time and app size
bounded.

Model weights are not bundled here. LiveTranscriber downloads
`vanch007/mlx-MOSS-Transcribe-Diarize-4bit` on demand into Application Support.
