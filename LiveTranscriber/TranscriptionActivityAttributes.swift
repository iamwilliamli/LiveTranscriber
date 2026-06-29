import ActivityKit
import Foundation

struct TranscriptionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var languageName: String
        var latestText: String
        var placeholderText: String
        var elapsedSeconds: Int
        var timerReferenceDate: Date
        var lineCount: Int
        var isRecording: Bool

        var elapsedText: String {
            Self.formatTimestamp(elapsedSeconds)
        }

        var displayText: String {
            latestText.isEmpty ? placeholderText : latestText
        }

        var compactStatusSymbol: String {
            isRecording ? "waveform" : "checkmark"
        }

        private static func formatTimestamp(_ seconds: Int) -> String {
            let safeSeconds = max(seconds, 0)
            let hours = safeSeconds / 3600
            let minutes = (safeSeconds % 3600) / 60
            let seconds = safeSeconds % 60

            if hours > 0 {
                return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var startedAt: Date
}
