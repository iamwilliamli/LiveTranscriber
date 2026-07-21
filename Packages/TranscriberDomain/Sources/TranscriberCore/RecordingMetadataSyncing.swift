import Foundation

public enum RecordingMetadataEntityKind: String, Codable, Hashable, Sendable {
    case recording
    case category
}

public struct RecordingMetadataEntityID: Codable, Hashable, Sendable {
    public var kind: RecordingMetadataEntityKind
    public var value: UUID

    public init(kind: RecordingMetadataEntityKind, value: UUID) {
        self.kind = kind
        self.value = value
    }
}

public enum RecordingMetadataMutationOperation: String, Codable, Hashable, Sendable {
    case upsert
    case delete
}

public struct RecordingMetadataMutation: Codable, Hashable, Sendable {
    public var entityID: RecordingMetadataEntityID
    public var operation: RecordingMetadataMutationOperation

    public init(
        entityID: RecordingMetadataEntityID,
        operation: RecordingMetadataMutationOperation
    ) {
        self.entityID = entityID
        self.operation = operation
    }
}

public protocol RecordingMetadataSyncing: Sendable {
    func setMetadataSyncEnabled(_ enabled: Bool) async

    func enqueueMetadataMutation(_ mutation: RecordingMetadataMutation) async

    func synchronizeMetadata() async
}
