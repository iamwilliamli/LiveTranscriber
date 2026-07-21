import Foundation
import TranscriberDomain

public struct RecordingTranscriptionRequest: Hashable, Sendable {
    public var sourceURL: URL
    public var languageIdentifier: String?

    public init(sourceURL: URL, languageIdentifier: String? = nil) {
        self.sourceURL = sourceURL
        self.languageIdentifier = languageIdentifier
    }
}

public enum RecordingTranscriptionStage: String, Codable, Hashable, Sendable {
    case preparing
    case transcribing
    case finalizing
}

public struct RecordingTranscriptionProgress: Codable, Hashable, Sendable {
    public var fractionCompleted: Double
    public var stage: RecordingTranscriptionStage

    public init(
        fractionCompleted: Double,
        stage: RecordingTranscriptionStage = .transcribing
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.stage = stage
    }
}

public struct RecordingTranscriptionResult: Codable, Hashable, Sendable {
    public var lines: [TranscriptionLine]
    public var speakerDiarization: RecordingSpeakerDiarization?
    public var detectedLanguageIdentifier: String?

    public init(
        lines: [TranscriptionLine],
        speakerDiarization: RecordingSpeakerDiarization? = nil,
        detectedLanguageIdentifier: String? = nil
    ) {
        self.lines = lines
        self.speakerDiarization = speakerDiarization
        self.detectedLanguageIdentifier = detectedLanguageIdentifier
    }
}

public protocol RecordingTranscribing: Sendable {
    var identifier: String { get }

    func transcribe(
        _ request: RecordingTranscriptionRequest,
        progressHandler: @escaping @Sendable (RecordingTranscriptionProgress) -> Void
    ) async throws -> RecordingTranscriptionResult
}

public extension RecordingTranscribing {
    func transcribe(
        _ request: RecordingTranscriptionRequest
    ) async throws -> RecordingTranscriptionResult {
        try await transcribe(request, progressHandler: { _ in })
    }
}
