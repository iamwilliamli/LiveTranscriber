import Foundation

public struct TranscriptionLanguage: Identifiable, Codable, Hashable, Sendable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public var locale: Locale {
        Locale(identifier: id)
    }

    public var displayName: String {
        let current = Locale.current
        let name = current.localizedString(forIdentifier: id) ?? id
        return name.capitalized(with: current)
    }

    public var shortName: String {
        locale.language.languageCode?.identifier.uppercased() ?? id
    }

    public var baseLanguage: TranscriptionLanguage {
        guard let languageCode = locale.language.languageCode?.identifier,
              !languageCode.isEmpty,
              languageCode != "und" else {
            return self
        }
        return TranscriptionLanguage(id: languageCode)
    }

    public static func baseLanguageOptions(
        from languages: [TranscriptionLanguage],
        including languageID: String? = nil
    ) -> [TranscriptionLanguage] {
        var candidates = languages
        if let languageID,
           !languageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(TranscriptionLanguage(id: languageID))
        }

        var seenLanguageIDs = Set<String>()
        return candidates
            .compactMap { language -> TranscriptionLanguage? in
                let baseLanguage = language.baseLanguage
                let normalizedID = baseLanguage.id.lowercased()
                guard seenLanguageIDs.insert(normalizedID).inserted else {
                    return nil
                }
                return baseLanguage
            }
            .sorted { first, second in
                let comparison = first.displayName.localizedStandardCompare(second.displayName)
                if comparison == .orderedSame {
                    return first.id < second.id
                }
                return comparison == .orderedAscending
            }
    }

    public static let fallbackOptions: [TranscriptionLanguage] = [
        TranscriptionLanguage(id: "en-US"),
        TranscriptionLanguage(id: "zh-Hans"),
        TranscriptionLanguage(id: "zh-Hant"),
        TranscriptionLanguage(id: "ja-JP"),
        TranscriptionLanguage(id: "ko-KR"),
        TranscriptionLanguage(id: "fr-FR"),
        TranscriptionLanguage(id: "de-DE"),
        TranscriptionLanguage(id: "es-ES"),
    ]

    public static var defaultLanguageID: String {
        if let identifier = Locale.current.language.languageCode?.identifier,
           identifier.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en-US"
    }
}

public struct TranscriptionLine: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var startSeconds: Double
    public var text: String
    public var isFinal: Bool

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        text: String,
        isFinal: Bool
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.text = text
        self.isFinal = isFinal
    }

    public var timestampText: String {
        Self.formatTranscriptTimestamp(startSeconds)
    }

    public static func formatElapsedSeconds(_ seconds: Double) -> String {
        let safeSeconds = max(Int(seconds.rounded(.down)), 0)
        return "\(safeSeconds)s"
    }

    public static func formatTranscriptTimestamp(_ seconds: Double) -> String {
        let safeCentiseconds = max(Int((seconds * 100).rounded()), 0)
        let minutes = safeCentiseconds / 6_000
        let wholeSeconds = (safeCentiseconds % 6_000) / 100
        let centiseconds = safeCentiseconds % 100
        return String(format: "%02d:%02d:%02d", minutes, wholeSeconds, centiseconds)
    }

    public static func formatTimestamp(_ seconds: Double) -> String {
        let safeSeconds = max(Int(seconds.rounded(.down)), 0)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

public extension Array where Element == TranscriptionLine {
    var timedTranscriptText: String {
        map { "[\($0.timestampText)] \($0.text)" }
            .joined(separator: "\n")
    }

    var plainTranscriptText: String {
        map(\.text).joined(separator: "\n")
    }
}
