import Foundation

struct TranscriptionLanguage: Identifiable, Codable, Hashable {
    let id: String

    var locale: Locale {
        Locale(identifier: id)
    }

    var displayName: String {
        let current = Locale.current
        let name = current.localizedString(forIdentifier: id) ?? id
        return name.capitalized(with: current)
    }

    var shortName: String {
        locale.language.languageCode?.identifier.uppercased() ?? id
    }

    static let fallbackOptions: [TranscriptionLanguage] = [
        TranscriptionLanguage(id: "en-US"),
        TranscriptionLanguage(id: "zh-Hans"),
        TranscriptionLanguage(id: "zh-Hant"),
        TranscriptionLanguage(id: "ja-JP"),
        TranscriptionLanguage(id: "ko-KR"),
        TranscriptionLanguage(id: "fr-FR"),
        TranscriptionLanguage(id: "de-DE"),
        TranscriptionLanguage(id: "es-ES")
    ]

    static var defaultLanguageID: String {
        if let identifier = Locale.current.language.languageCode?.identifier, identifier.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en-US"
    }
}

enum RecordingAudioFormat: String, CaseIterable, Identifiable, Codable {
    case wav
    case m4a

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wav:
            return "WAV"
        case .m4a:
            return "M4A"
        }
    }

    var detail: String {
        String(localized: detailResource)
    }

    var detailResource: LocalizedStringResource {
        switch self {
        case .wav:
            return L10n.Transcription.wavDetail
        case .m4a:
            return L10n.Transcription.m4aDetail
        }
    }

    var fileExtension: String {
        rawValue
    }

    var badgeText: String {
        title
    }

    static var defaultFormat: RecordingAudioFormat {
        .wav
    }
}

struct TranscriptionLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var startSeconds: Double
    var text: String
    var isFinal: Bool

    var timestampText: String {
        Self.formatTranscriptTimestamp(startSeconds)
    }

    static func formatElapsedSeconds(_ seconds: Double) -> String {
        let safeSeconds = max(Int(seconds.rounded(.down)), 0)
        return "\(safeSeconds)s"
    }

    static func formatTranscriptTimestamp(_ seconds: Double) -> String {
        let safeCentiseconds = max(Int((seconds * 100).rounded()), 0)
        let minutes = safeCentiseconds / 6_000
        let wholeSeconds = (safeCentiseconds % 6_000) / 100
        let centiseconds = safeCentiseconds % 100
        return String(format: "%02d:%02d:%02d", minutes, wholeSeconds, centiseconds)
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        let safeSeconds = max(Int(seconds.rounded(.down)), 0)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let seconds = safeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Array where Element == TranscriptionLine {
    var timedTranscriptText: String {
        map { "[\($0.timestampText)] \($0.text)" }
            .joined(separator: "\n")
    }

    var plainTranscriptText: String {
        map(\.text).joined(separator: "\n")
    }
}
