# Current Product and UI Design

This document summarizes the current implementation-facing design of LiveTranscriber. It reflects the latest SwiftUI code, not an aspirational design spec.

## Product Shape

LiveTranscriber is a native iOS 27 utility for local recording, live transcription, saved-recording review, and lightweight transcript intelligence.

The app is organized as three tabs:

1. `TranscriptionView`: live recording and current transcript.
2. `RecordingsView`: saved recording library, search, import, playback, transcript review, sharing, re-transcription, and summary/tag generation.
3. `SettingsView`: transcription language, recording format, and storage status.

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
- The app reloads recordings on launch and when returning to foreground.
- The app handles `livetranscriber://stop-recording` from Live Activity and saves the resulting draft.

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

## Recording Library

The library uses native navigation, `List`, search, row cards, context menus, and swipe actions.

Search matches:

- Audio file name.
- Language name.
- Transcript preview.
- Full transcript file text.
- Apple Intelligence summary.
- Apple Intelligence tags.

Rows show:

- Recording date/time and audio file name.
- Language and transcript line count.
- Duration when idle.
- Import/re-transcription progress or failure state when active.
- Summary/tag preview when available.
- Transcript preview otherwise.

Actions are intentionally discoverable but not always visible:

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
- Intelligence card: summary, tags, generation timestamp, and analyze/re-analyze action.
- Transcript card: import/re-transcription status and timestamped transcript rows.

Tapping a transcript row seeks playback to that line's start timestamp. The current transcript row is highlighted based on playback position.

Toolbar actions:

- Share audio or transcript.
- Re-transcribe with a selected language.
- Copy transcript text.
- Generate or refresh Apple Intelligence summary/tags.
- Delete recording.

## Settings

Settings are grouped into card surfaces:

- Transcription: language menu, disabled while recording/preparing.
- Recording: segmented WAV/M4A format picker and detail text.
- Files: recording count and storage location.

The current default format is WAV. M4A is available for smaller AAC files.

## Haptics

`HapticFeedback` maps product events to UIKit haptics and rate-limits repeated events. It covers navigation, menu selection, primary actions, recording start/pause/resume/stop/save, playback toggle, transcript seek, copy, import, re-transcription, analysis, delete, blocked actions, warnings, and failures.

## Design Constraints

- Keep the interface native, quiet, and utility-focused.
- Prefer system controls and SF Symbols over custom decorative visuals.
- Keep cards compact; do not nest cards inside cards.
- Keep destructive/recording actions visually clear with red.
- Keep text readable under localization; use truncation, line limits, and minimum scale where needed.
- Keep Live Activity text stable by updating only on state changes and final transcript segments.
