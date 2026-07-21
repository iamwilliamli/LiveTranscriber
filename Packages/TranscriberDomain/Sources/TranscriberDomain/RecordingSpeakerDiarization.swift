import Foundation

public struct RecordingSpeakerDiarization: Codable, Hashable, Sendable {
    public var segments: [RecordingSpeakerSegment]
    public var generatedAt: Date
    public var provider: String
    public var model: String
    public var schemaVersion: Int

    public init(
        segments: [RecordingSpeakerSegment],
        generatedAt: Date,
        provider: String,
        model: String,
        schemaVersion: Int
    ) {
        self.segments = segments
        self.generatedAt = generatedAt
        self.provider = provider
        self.model = model
        self.schemaVersion = schemaVersion
    }
}

public struct RecordingSpeakerSegment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var startSeconds: Double
    public var endSeconds: Double
    public var speaker: String?
    public var text: String

    public init(
        id: UUID = UUID(),
        startSeconds: Double,
        endSeconds: Double,
        speaker: String?,
        text: String
    ) {
        self.id = id
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.text = text
    }
}
