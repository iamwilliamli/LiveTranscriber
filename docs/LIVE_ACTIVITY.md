# Live Activity Design

LiveTranscriber uses ActivityKit to show recording status on the Lock Screen and in Dynamic Island.

## State Owner

`TranscriptionLiveActivityCoordinator` owns ActivityKit requests and updates. `LiveTranscriptionManager` calls it when recording state or final transcript content changes.

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

This avoids excessive ActivityKit updates while still keeping the newest stable text visible.

## Lock Screen Layout

The Lock Screen view prioritizes:

- Recording state on the top-left.
- Elapsed recording time on the top-right.
- Latest transcript in the middle.
- Language, stop action, and line count in the footer.

The timer is intentionally rendered as a top-trailing overlay on the whole Lock Screen content container so it aligns with the right edge of the card instead of the intrinsic width of the status row.

## Dynamic Island Layout

Expanded Dynamic Island:

- Leading: status dot and `Transcribe` label.
- Trailing: elapsed time.
- Bottom: status, latest transcript, language, and line count.

Compact and minimal presentations use a small status dot and compact elapsed time. The status dot ring is disabled in compact/minimal modes to avoid clipping.

