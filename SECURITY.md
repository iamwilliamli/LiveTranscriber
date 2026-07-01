# Security Policy

LiveTranscriber is an early-stage, source-available iOS app. Security and
privacy reports are welcome, especially around recording storage, transcript
handling, file import, iCloud sync, and unintended data disclosure.

## Supported Versions

The `main` branch is the active development version. Tagged releases may receive
security fixes at the maintainer's discretion while the project is still before
its first stable release.

## Reporting a Vulnerability

Please do not publish exploitable details before the maintainer has had a chance
to review and respond.

Use GitHub's private vulnerability reporting if it is available for this
repository. If private reporting is not available, open a GitHub issue with a
non-sensitive summary and note that you have details to share privately. Do not
post private recordings, transcripts, account identifiers, secrets, or working
exploit details in public issues.

Helpful reports include:

- Affected commit, branch, or tag.
- Device model and iOS version.
- Clear impact description.
- Minimal reproduction steps.
- Sanitized logs or screenshots when useful.
- Whether the issue affects local-only storage, iCloud sync, file import, or
  transcription output.

## Scope

In scope:

- Unintended upload, sharing, or exposure of audio or transcript data.
- Recording files or transcript files written to unexpected public locations.
- iCloud sync behavior that exposes another user's data.
- Permission bypasses or misleading microphone/privacy behavior.
- File import handling issues with a plausible security or privacy impact.

Out of scope:

- General feature requests.
- Performance issues without a security or privacy impact.
- UI polish bugs.
- Reports based only on unsupported modified builds.
