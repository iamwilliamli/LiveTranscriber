import Foundation
import Testing
@testable import TranscriberDomain

@Suite("Recording speaker diarization")
struct RecordingSpeakerDiarizationTests {
    @Test("Codable round trip preserves stable segment identity")
    func codableRoundTrip() throws {
        let segmentID = UUID(uuidString: "27B43D67-8356-4E9E-98CD-8965183674F0")!
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let source = RecordingSpeakerDiarization(
            segments: [
                RecordingSpeakerSegment(
                    id: segmentID,
                    startSeconds: 4.25,
                    endSeconds: 9.75,
                    speaker: "Speaker 0",
                    text: "Hello from the shared domain."
                ),
            ],
            generatedAt: generatedAt,
            provider: "test",
            model: "fixture",
            schemaVersion: 1
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(RecordingSpeakerDiarization.self, from: encoded)

        #expect(decoded == source)
        #expect(decoded.segments.first?.id == segmentID)
    }

    @Test("Domain schema starts at version one")
    func schemaVersion() {
        #expect(TranscriberDomainSchema.currentVersion == 1)
    }
}
