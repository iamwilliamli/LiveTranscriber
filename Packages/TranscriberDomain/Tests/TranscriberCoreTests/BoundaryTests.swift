import Foundation
import Testing
import TranscriberDomain
@testable import TranscriberCore

@Suite("Core service boundaries")
struct BoundaryTests {
    @Test("Transcription progress is always normalized")
    func normalizedProgress() {
        #expect(RecordingTranscriptionProgress(fractionCompleted: -0.5).fractionCompleted == 0)
        #expect(RecordingTranscriptionProgress(fractionCompleted: 0.4).fractionCompleted == 0.4)
        #expect(RecordingTranscriptionProgress(fractionCompleted: 2).fractionCompleted == 1)
    }

    @Test("A recording library can be consumed through the read boundary")
    func recordingLibraryReadBoundary() async throws {
        let session = RecordingSession(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            title: "Fixture",
            durationSeconds: 5,
            assets: [
                RecordingAsset(
                    id: "audio",
                    kind: .primaryAudio,
                    relativePath: "fixture.m4a"
                ),
            ],
            primaryAssetID: "audio"
        )
        let library: any RecordingLibraryReading = InMemoryRecordingLibrary(session: session)

        #expect(try await library.recordingSessions() == [session])
        #expect(try await library.recordingSession(withID: session.id) == session)
        #expect(
            try await library.recordingAssetURL(sessionID: session.id, assetID: "audio")
                == URL(fileURLWithPath: "/recordings/fixture.m4a")
        )
    }

    @Test("Metadata mutations retain entity type and operation")
    func metadataMutationRoundTrip() throws {
        let mutation = RecordingMetadataMutation(
            entityID: RecordingMetadataEntityID(kind: .recording, value: UUID()),
            operation: .delete
        )

        let data = try JSONEncoder().encode(mutation)
        #expect(try JSONDecoder().decode(RecordingMetadataMutation.self, from: data) == mutation)
    }
}

private actor InMemoryRecordingLibrary: RecordingLibraryReading {
    let session: RecordingSession

    init(session: RecordingSession) {
        self.session = session
    }

    func recordingSessions() -> [RecordingSession] {
        [session]
    }

    func recordingSession(withID id: RecordingSession.ID) -> RecordingSession? {
        id == session.id ? session : nil
    }

    func recordingAssetURL(
        sessionID: RecordingSession.ID,
        assetID: RecordingAsset.ID
    ) throws -> URL {
        guard sessionID == session.id else {
            throw RecordingLibraryError.recordingNotFound(sessionID)
        }
        guard let asset = session.assets.first(where: { $0.id == assetID }) else {
            throw RecordingLibraryError.assetNotFound(assetID)
        }
        return URL(fileURLWithPath: "/recordings").appendingPathComponent(asset.relativePath)
    }
}
