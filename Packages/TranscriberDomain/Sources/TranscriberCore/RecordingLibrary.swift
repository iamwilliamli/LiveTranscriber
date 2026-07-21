import Foundation
import TranscriberDomain

public enum RecordingLibraryError: Error, Equatable, Sendable {
    case recordingNotFound(UUID)
    case assetNotFound(String)
    case unsafeAssetPath(String)
}

public protocol RecordingLibraryReading: Sendable {
    func recordingSessions() async throws -> [RecordingSession]

    func recordingSession(withID id: RecordingSession.ID) async throws -> RecordingSession?

    func recordingAssetURL(
        sessionID: RecordingSession.ID,
        assetID: RecordingAsset.ID
    ) async throws -> URL
}

public protocol RecordingLibraryWriting: Sendable {
    func upsertRecordingSession(_ session: RecordingSession) async throws

    func removeRecordingSession(withID id: RecordingSession.ID) async throws
}

public protocol RecordingLibrary: RecordingLibraryReading, RecordingLibraryWriting {}
