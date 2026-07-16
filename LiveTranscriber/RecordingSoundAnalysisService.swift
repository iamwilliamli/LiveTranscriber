import CoreMedia
import Foundation
import SoundAnalysis

enum RecordingSoundAnalysisError: LocalizedError {
    case noAudioEvents
    case analysisCancelled

    var errorDescription: String? {
        switch self {
        case .noAudioEvents:
            return String(localized: L10n.Recordings.noAudioEventsDetected)
        case .analysisCancelled:
            return String(localized: L10n.Recordings.audioEventAnalysisCancelled)
        }
    }
}

enum RecordingSoundAnalysisService {
    private static let confidenceThreshold = 0.35
    private static let mergeGapSeconds: TimeInterval = 0.75
    private static let schemaVersion = 3

    static func analyze(url: URL) async throws -> RecordingAudioEventAnalysis {
        try await Task.detached(priority: .userInitiated) {
            let observer = RecordingSoundAnalysisObserver(confidenceThreshold: confidenceThreshold)
            let analyzer = try SNAudioFileAnalyzer(url: url)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.overlapFactor = 0.5

            try analyzer.add(request, withObserver: observer)
            analyzer.analyze()

            if let error = observer.analysisError {
                throw error
            }

            let events = refinedEvents(from: observer.events)
            guard !events.isEmpty else {
                throw RecordingSoundAnalysisError.noAudioEvents
            }

            return RecordingAudioEventAnalysis(
                events: events,
                generatedAt: Date(),
                provider: "SoundAnalysis",
                schemaVersion: schemaVersion
            )
        }.value
    }

    private static func refinedEvents(from events: [RecordingAudioEvent]) -> [RecordingAudioEvent] {
        let sortedEvents = events.sorted {
            if $0.startTime == $1.startTime {
                return $0.confidence > $1.confidence
            }
            return $0.startTime < $1.startTime
        }

        var mergedEvents: [RecordingAudioEvent] = []
        for event in sortedEvents {
            guard var previous = mergedEvents.last else {
                mergedEvents.append(event)
                continue
            }

            let gap = event.startTime - previous.endTime
            if event.sourceIdentifier == previous.sourceIdentifier, gap <= mergeGapSeconds {
                previous.duration = max(previous.endTime, event.endTime) - previous.startTime
                previous.confidence = max(previous.confidence, event.confidence)
                mergedEvents[mergedEvents.count - 1] = previous
            } else {
                mergedEvents.append(event)
            }
        }

        return mergedEvents.sorted {
            if $0.startTime == $1.startTime {
                return $0.confidence > $1.confidence
            }
            return $0.startTime < $1.startTime
        }
    }
}

private final class RecordingSoundAnalysisObserver: NSObject, SNResultsObserving {
    let confidenceThreshold: Double
    var events: [RecordingAudioEvent] = []
    var analysisError: Error?

    init(confidenceThreshold: Double) {
        self.confidenceThreshold = confidenceThreshold
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let classification = result.classifications.first,
              classification.confidence >= confidenceThreshold else {
            return
        }

        let startTime = max(CMTimeGetSeconds(result.timeRange.start), 0)
        let duration = max(CMTimeGetSeconds(result.timeRange.duration), 0.1)
        guard startTime.isFinite, duration.isFinite else {
            return
        }

        let identifier = classification.identifier
        guard !Self.isExcludedClassification(identifier) else {
            return
        }

        events.append(
            RecordingAudioEvent(
                label: RecordingAudioEventLocalization.localizedLabel(for: identifier),
                confidence: classification.confidence,
                startTime: startTime,
                duration: duration,
                sourceIdentifier: identifier
            )
        )
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        analysisError = error
    }

    private static func isExcludedClassification(_ identifier: String) -> Bool {
        let tokens = classificationTokens(for: identifier)
        return tokens.contains("speech")
    }

    private static func classificationTokens(for identifier: String) -> [String] {
        identifier
            .localizedLowercase
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}

enum RecordingAudioEventLocalization {
    private static let tableName = "AudioEvents"
    private static let identifierLocale = Locale(identifier: "en_US_POSIX")

    static func localizedLabel(for identifier: String, storedLabel: String? = nil) -> String {
        let normalizedIdentifier = normalizedIdentifier(identifier)
        guard !normalizedIdentifier.isEmpty else {
            let fallback = storedLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return fallback.isEmpty
                ? String(localized: L10n.Recordings.audioEventUnknown)
                : fallback
        }

        let localized = Bundle.main.localizedString(
            forKey: normalizedIdentifier,
            value: nil,
            table: tableName
        )
        guard localized != normalizedIdentifier else {
            return String(localized: L10n.Recordings.audioEventUnknown)
        }
        return localized
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier
            .lowercased(with: identifierLocale)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
