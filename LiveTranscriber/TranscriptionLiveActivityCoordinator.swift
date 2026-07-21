import ActivityKit
import Foundation

@MainActor
enum TranscriptionLiveActivityCoordinator {
    private static var updateTask: Task<Void, Never>?
    private static var updateGeneration = 0

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

        await finishPendingUpdate()
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

        updateGeneration += 1
        let generation = updateGeneration
        let previousTask = updateTask
        let task = Task { @MainActor in
            await previousTask?.value
            guard !Task.isCancelled else {
                return
            }

            for activity in Activity<TranscriptionActivityAttributes>.activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
        updateTask = task
        await task.value
        if generation == updateGeneration {
            updateTask = nil
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

        await finishPendingUpdate()
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
            placeholderText: String(localized: L10n.RecordingStatus.waitingForSpeech),
            elapsedSeconds: elapsedSeconds,
            timerReferenceDate: Date(timeIntervalSinceNow: -TimeInterval(max(elapsedSeconds, 0))),
            lineCount: lineCount,
            isRecording: isRecording
        )
    }

    private static func finishPendingUpdate() async {
        let generation = updateGeneration
        await updateTask?.value
        if generation == updateGeneration {
            updateTask = nil
        }
    }
}
