# Changelog

All notable changes to LiveTranscriber will be documented in this file.

## Unreleased

### Added

- Added the native macOS parity foundation: live microphone transcription and translation, a `RecordingStore`-backed recordings library with search/categories/map, playback, transcript and speaker editing, AI summaries, meeting analysis, recording chat, Reminders export, transcript export (TXT/Markdown/SRT/VTT/JSON), and Apple Speech/local Whisper/Qwen3-ASR/MOSS/Gemini processing flows. Remaining release gaps are tracked in `docs/architecture/macos-parity.md`.
- Added a native macOS Settings window covering transcription language, live backend and model management, Gemini cloud configuration and usage metrics, intelligence providers, recording format, iCloud sync, privacy, help/feedback, and developer diagnostics.
- Added macOS system-audio recording to the normal Transcribe workflow: choose an app, window, or display, record system audio alone or combine it with the microphone, and save the resulting M4A in the ordinary Recordings library.
- Added a shared `SharedApp/` source layer compiled into both apps (recording store with CloudKit sync and Spotlight, all transcription engines, AI services, exports, localization, playback), plus App Intents/Shortcuts support on macOS.
- Added macOS slices to the vendored whisper.cpp and llama.cpp frameworks, built from the same pinned upstream commits as the iOS slices.

- Added saved-recording re-transcription with OpenAI file transcription, with long-form and segmented modes.
- Added OpenAI API key entry in Settings for bring-your-own-key saved-recording transcription, including Keychain storage and key clearing.
- Added speech locale release prompts before switching languages, importing audio, re-transcribing, or starting recording from a deep link when the system language allocation limit is reached.
- Added more detailed Recording Intelligence debug logs for transcript previews, prompt sizes, raw model responses, summaries, tags, and language mismatch retries.

### Changed

- Simplified the macOS sidebar to Transcribe, Recordings, and Settings; removed the separate Capture and Capture Library workflows so every recording uses one storage and metadata model.
- Prevented failed system-audio sessions from silently saving a microphone-only recording; the app now asks before using that fallback.
- Changed Recording Intelligence availability and generation to use the FoundationModels `.general` use case.
- Changed the iOS 26 Recording Intelligence path to generate semantic notes first, then combine those notes into a final summary instead of asking for JSON directly from the raw transcript.
- Changed iOS 26 summary generation to produce summaries only, without topic tags, to avoid low-quality tag generation from the text fallback path.
- Changed iOS 26 and iOS 27 prompts to infer the output language from the transcript or translated transcript, using the selected language only as a fallback hint.
- Changed iOS 27 structured FoundationModels prompts and `@Guide` descriptions to follow the transcript-derived output language.
- Changed translated transcript analysis so summaries use only fully translated transcript lines instead of mixing translated lines with untranslated original text.
- Updated README and internal design docs to describe the current local live transcription path, optional OpenAI saved-recording transcription, privacy boundary, audio formats, and current Recording Intelligence prompt flow.
- Removed the experimental realtime Whisper live transcription backend.

### Fixed

- Fixed iOS 26 summary generation returning English summaries for Chinese semantic notes by adding explicit expected-output-language prompts, language-script validation, and a retry path.
- Fixed poor iOS 26 FoundationModels summaries caused by schema/JSON-style prompting that copied or lightly rewrote noisy ASR text.
- Fixed the iOS 26 runtime dyld crash caused by iOS 27 structured FoundationModels symbols by isolating `@Generable` and `respond(...generating:)` usage in the iOS 27-only helper framework loaded behind an availability check.
- Fixed analysis of translated transcripts so the generated summary follows the translated transcript language instead of the original recording language.
- Fixed language switching/import/re-transcription flows that could fail with "too many allocated locales" by prompting the user to release older speech locales first.
- Fixed privacy and diagnostics UI copy so it reflects whether the selected transcription backend is local Apple Speech or optional OpenAI cloud transcription.
