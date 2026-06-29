import ActivityKit
import Foundation

@MainActor
enum TranscriptionLiveActivityCoordinator {
    static func start(
        startedAt: Date,
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let state = contentState(
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: true
        )

        for activity in Activity<TranscriptionActivityAttributes>.activities {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }

        do {
            _ = try Activity<TranscriptionActivityAttributes>.request(
                attributes: TranscriptionActivityAttributes(startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            return
        }
    }

    static func update(
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int,
        isRecording: Bool
    ) async {
        let state = contentState(
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: isRecording
        )

        for activity in Activity<TranscriptionActivityAttributes>.activities {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end(
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int
    ) async {
        let state = contentState(
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: false
        )

        for activity in Activity<TranscriptionActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(8))
            )
        }
    }

    private static func contentState(
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int,
        isRecording: Bool
    ) -> TranscriptionActivityAttributes.ContentState {
        TranscriptionActivityAttributes.ContentState(
            status: status,
            languageName: languageName,
            latestText: latestText,
            placeholderText: String(localized: "等待语音"),
            elapsedSeconds: elapsedSeconds,
            timerReferenceDate: Date(timeIntervalSinceNow: -TimeInterval(max(elapsedSeconds, 0))),
            lineCount: lineCount,
            isRecording: isRecording
        )
    }
}
