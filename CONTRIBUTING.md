# Contributing to LiveTranscriber

Thanks for considering a contribution.

## License

By submitting a pull request, patch, issue attachment, or other contribution,
you agree that your contribution is licensed under the
LiveTranscriber Source Available License 1.0 in `LICENSE`.

You also grant William Li a perpetual, worldwide, non-exclusive, royalty-free,
irrevocable license to use, copy, modify, publish, distribute, sublicense, and
relicense your contribution, including for commercial purposes.

Do not submit code or assets that you do not have the right to license under
these terms.

## Commercial Forks

Commercial forks and derivative apps are allowed only if they follow the
commercial attribution requirement in `LICENSE` and `NOTICE`.

Attribution-free, private-label, or white-label commercial use requires a
separate written license from William Li.

## Development Notes

- Keep the app local-first and privacy-preserving.
- Prefer native Apple frameworks over server-side services.
- Preserve localization when adding user-facing text.
- Use the typed `L10n.*` localization pattern for SwiftUI text, such as
  `L10n.Settings.recordingFormat`, instead of inline localized string literals.
- Keep UI changes consistent with the existing compact SwiftUI design.
- Do not attach private recordings or transcripts to public issues or pull
  requests unless you are comfortable making them public.
