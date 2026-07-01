# Current Product and UI Design

This document summarizes the current implementation-facing design of LiveTranscriber. It reflects the latest SwiftUI code, not an aspirational design spec.

## Product Shape

LiveTranscriber is a native iOS 26+ utility for local recording, live transcription, saved-recording review, and lightweight transcript intelligence. iOS 27 devices can use an optional Native Speech Pipeline from Developer Options. Live recording uses the AVCaptureSession Stereo Capture path.

The app is organized as three tabs:

1. `TranscriptionView`: live recording and current transcript.
2. `RecordingsView`: saved recording library, search, import, playback, transcript review, sharing, re-transcription, and summary/tag generation.
3. `SettingsView`: transcription language, recording format, storage status, and developer diagnostics.

The product should feel like a focused system tool. It avoids marketing-style layouts, waveform decoration, and explanatory UI copy. The main interface favors direct controls, system symbols, native navigation, and compact information density.

## Visual System

Shared tokens live in `AppTheme`:

- Radius: `cornerRadius = 8`, `compactCornerRadius = 7`.
- Primary brand red: `AppTheme.brand`.
- Recording/destructive red: `AppTheme.danger`.
- Info blue, success green, warning amber, and purple are available for semantic state.
- Backgrounds use system grouped colors: grouped, card, and elevated backgrounds.
- Borders use separator opacity; card shadows are intentionally light.

Typography is centralized in `AppTypography`:

- Reddit Sans is used across SwiftUI and configured into UIKit appearances.
- Navigation bars, tab items, bar buttons, text fields, segmented controls, and search fields inherit the app font.
- Numeric timers and timestamps use monospaced digits.

Iconography uses SF Symbols throughout. Primary controls use familiar symbols such as `mic.fill`, `pause.fill`, `stop.fill`, `square.and.arrow.down`, `square.and.arrow.up`, `doc.on.doc`, `sparkles`, and `arrow.triangle.2.circlepath`.

## Navigation

`ContentView` creates a `TabView` with shared state objects:

- `LiveTranscriptionManager` is shared by recording, file library, and settings so language/format state stays consistent.
- `RecordingStore` is shared by recording and library so saved files appear immediately after recording stops.
- `RecordingStore` keeps audio/transcript files in the local app-private recordings directory by default and uses SwiftData for the recording index. When the user enables iCloud storage in Settings and the ubiquity container is available, files sync through the app-private ubiquity container and the index syncs through a CloudKit private database.
- The app reloads recordings on launch and when returning to foreground.
- The app handles `livetranscriber://stop-recording` from Live Activity and saves the resulting draft.
- The app handles `livetranscriber://record`, `livetranscriber://recordings`, and `livetranscriber://settings` for Widget quick links.

## Recording Screen

The recording screen uses a grouped background with two card surfaces and a bottom floating recording dock.

The top card shows:

- Real-time transcription title and current status.
- Large elapsed timer.
- Current recording format badge.
- Language menu.
- Transcript line count.
- Saved-file confirmation and error text when present.

The transcript card shows newest transcript lines first. Final lines use the brand red timestamp pill; interim lines use warning amber.

The floating dock has two states:

- Idle/preparing: a full-width red capsule button for starting recording, with a spinner while preparing.
- Recording: a material capsule with pause/resume and stop buttons.

Language switching is disabled while recording or preparing.

After tapping stop, the app presents a save sheet instead of immediately playing a drop animation. The sheet contains an editable recording name, a tags entry, duration, and an optional location toggle with a map preview. Saving writes the audio file, transcript, and metadata together; discarding removes the temporary audio draft and clears the transcript.

## Recording Library

The library uses native navigation, `List`, search, row cards, context menus, and swipe actions.

Search matches:

- Audio file name.
- Language name.
- Unified tags, combining user-edited tags and Apple Intelligence topic tags.
- Transcript preview.
- Full transcript file text.
- Apple Intelligence summary.

Rows show:

- Recording date/time and audio file name.
- Language and transcript line count.
- Duration when idle.
- Import/re-transcription progress or failure state when active.
- Summary/tag preview when available.
- Transcript preview otherwise.
- Unified tags and a location marker when available.

Actions are intentionally discoverable but not always visible:

- Toolbar map button opens a map of recordings that include location metadata.
- Toolbar import button opens the Files picker.
- Import then asks for transcription language.
- Leading swipe action runs analysis.
- Trailing swipe action deletes.
- Context menu supports copy transcript, analyze/re-analyze, re-transcribe, and delete.
- Row re-transcription menu is disabled while transcription is already running.

## Recording Detail

The detail screen is a scroll view of compact cards:

- Header card: file name, date/time, duration, language.
- Playback card: play/pause, seek slider, elapsed/duration text, and playback error state.
- Intelligence card: summary, generation timestamp, and analyze/re-analyze action. Topic tags generated by Apple Intelligence are merged into the recording's unified tags instead of being shown as a separate tag group.
- Transcript card: import/re-transcription status and timestamped transcript rows.

Tapping a transcript row seeks playback to that line's start timestamp. The current transcript row is highlighted based on playback position.

Toolbar actions:

- Top-right more menu opens audio parameters in a sheet: sample rate, channel count, encoding, processing format, bit depth, duration, frame count, and file size.
- The same menu also supports sharing audio or transcript, re-transcribing with a selected language, copying transcript text, generating or refreshing Apple Intelligence summary/tags, and deleting the recording.
- Audio files can be imported through the in-app file picker or through iOS document handoff/share flows such as Voice Memos exports.

## Settings

Settings are grouped into card surfaces:

- Transcription: language menu, disabled while recording/preparing.
- Recording: WAV/M4A format picker.
- Files: recording count, storage location, iCloud storage toggle/status, and iCloud upload progress counts for saved recordings.

The current default format is WAV. M4A is available for smaller AAC files.

Microphone mode is not user-selectable. Stereo Capture uses `AVCaptureSession`, sets `AVCaptureDeviceInput.multichannelAudioMode = .stereo`, saves stereo audio, and downmixes the same captured buffers to mono for SpeechAnalyzer.

Privacy shows the app's local-processing boundary, no developer server/analytics/tracking policy, local-by-default storage behavior, optional app-private iCloud storage behavior, SwiftData/CloudKit private index behavior, and the purpose of microphone, speech recognition, camera purpose-string, and background audio permissions.

Developer Options show device/system information, active speech pipeline, supported pipeline types, and runtime analyzer input format.

## Widgets

The Widget extension contains two surfaces:

- Home Screen widget: a static quick-access widget with small, medium, and large layouts. It links to recording, saved files, and settings without reading private recording data.
- Live Activity: the lock screen and Dynamic Island recording surface. It shows elapsed time, latest final transcript text, language, line count, and the stop action.

## Haptics

`HapticFeedback` maps product events to UIKit haptics and rate-limits repeated events. It covers navigation, menu selection, primary actions, recording start/pause/resume/stop/save, playback toggle, transcript seek, copy, import, re-transcription, analysis, delete, blocked actions, warnings, and failures.

## Design Constraints

- Keep the interface native, quiet, and utility-focused.
- Prefer system controls and SF Symbols over custom decorative visuals.
- Keep cards compact; do not nest cards inside cards.
- Keep destructive/recording actions visually clear with red.
- Keep text readable under localization; use truncation, line limits, and minimum scale where needed.
- Keep Live Activity text stable by updating only on state changes and final transcript segments.
