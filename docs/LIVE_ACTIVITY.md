# Live Activity Design

LiveTranscriber uses ActivityKit to show recording status on the Lock Screen and in Dynamic Island.

## State Owner

`TranscriptionLiveActivityCoordinator` owns ActivityKit requests and updates. `LiveTranscriptionManager` calls it when recording state or final transcript content changes.

`ContentView` handles the Live Activity deep link:

```text
livetranscriber://stop-recording
```

The URL stops the current recording, saves the returned `RecordingDraft`, reloads the store, and plays the same haptic path as the in-app stop/save flow.

## Timing

The widget must not rely on a static elapsed-time string while recording. The content state carries `timerReferenceDate`, and the widget renders:

```swift
Text(state.timerReferenceDate, style: .timer)
```

This lets the system update elapsed time without app-driven per-second Activity updates.

When recording is paused or stopped, the widget shows fixed `elapsedText`.

## Transcript Updates

Live Activity transcript text is updated only when a transcript segment becomes final.

Policy:

- Start Activity once when recording starts.
- Update Activity once per final transcript segment.
- Do not update Activity for interim transcript changes.
- Update once on pause, resume, and stop.
- Let the system timer handle elapsed time.
- Skip duplicate updates by comparing a `LiveActivitySnapshot`.

This avoids excessive ActivityKit updates while still keeping the newest stable text visible.

The manager sends the suffix of the latest transcript lines, capped at 700 characters. The widget then trims again for each presentation:

- Lock Screen: latest trailing lines, up to 2 lines and about 220 characters.
- Expanded Dynamic Island: latest trailing lines, up to 2 lines and about 130 characters.
- Compact text helper: about 28 trailing characters.

## Lock Screen Layout

The Lock Screen view uses compact metric blocks:

- Top-left: status block with red/green status dot and current recording state.
- Top-right: fixed-width time block with the live timer.
- Middle: latest final transcript, capped to two lines.
- Footer-left: language metric block.
- Footer-right: segment count metric block and stop action while recording.

The Lock Screen content uses compact padding, secondary-system background tint, Reddit Sans, monospaced timer digits, and a red stop action while recording.

## Dynamic Island Layout

Expanded Dynamic Island:

- Leading: status metric block.
- Trailing: fixed-width time metric block.
- Bottom: latest final transcript, language metric, segment count metric, and stop action while recording.

Compact and minimal presentations use a small status glyph and compact elapsed time. The status dot ring is disabled in compact/minimal modes to avoid clipping.

Compact trailing is width-constrained for elapsed time. Expanded regions use leading/trailing horizontal padding from `LiveActivityLayout`.
