import Foundation
import Testing
@testable import TranscriberDomain

@Suite("Recording session payload compatibility")
struct RecordingSessionPayloadDecoderTests {
    @Test("Current session payloads decode without migration")
    func currentPayload() throws {
        let session = RecordingSession(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            title: "Current",
            durationSeconds: 12,
            languageIdentifier: "en",
            assets: [
                RecordingAsset(
                    id: "mixed",
                    kind: .mixedAudio,
                    relativePath: "mixed.m4a"
                ),
            ],
            primaryAssetID: "mixed"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try RecordingSessionPayloadDecoder.decode(encoder.encode(session))
        #expect(decoded == session)
    }

    @Test("iOS RecordingItem payloads become shared sessions")
    func legacyIOSPayload() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "createdAt": "2026-07-21T12:00:00Z",
          "durationSeconds": 42,
          "languageID": "zh-Hans",
          "displayName": "Weekly sync",
          "audioFileName": "\(id.uuidString.lowercased()).m4a",
          "transcriptFileName": "\(id.uuidString.lowercased()).txt",
          "transcriptPreview": "Ignored by the shared decoder"
        }
        """

        let session = try RecordingSessionPayloadDecoder.decode(Data(json.utf8))
        #expect(session.id == id)
        #expect(session.title == "Weekly sync")
        #expect(session.languageIdentifier == "zh-Hans")
        #expect(session.assets.map(\.id) == [
            LegacyRecordingAssetMigration.primaryAudioID,
            LegacyRecordingAssetMigration.transcriptID,
        ])
        #expect(session.primaryAsset?.relativePath.hasSuffix(".m4a") == true)
    }
}
