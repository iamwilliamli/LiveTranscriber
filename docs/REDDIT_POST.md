# Reddit Launch Draft

Title idea:

I am releasing LiveTranscriber, a local-first iOS recording and transcription app, as source-available

Post:

I built LiveTranscriber, a local-first iOS 26+ recording and live transcription app using Apple's Speech APIs, Live Activities, Dynamic Island, widgets, iCloud private container sync, and on-device Apple Intelligence summaries where available.

I am releasing the source so people can learn from it, fork it, and keep developing it. The project is source-available rather than OSI-open-source because I want to preserve commercial attribution rights: commercial forks are allowed, but they must visibly credit the original app and project in-app.

Required commercial attribution:

Based on LiveTranscriber by William Li
Original project: https://github.com/iamwilliamli/LiveTranscriber

White-label or attribution-free commercial use requires separate permission.

I would love help improving the transcription pipeline, iCloud sync, Apple Intelligence summary behavior, localization, and overall iOS polish.

Repo:
https://github.com/iamwilliamli/LiveTranscriber

Notes:

- Local-first: no developer servers, no analytics, no ads, no tracking.
- Audio and transcripts stay in the app-private container by default.
- iCloud sync uses the user's private iCloud container when enabled.
- Built with SwiftUI, Speech, AVFoundation, ActivityKit, WidgetKit, SwiftData, CloudKit, and FoundationModels.

