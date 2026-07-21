import Foundation
import Testing
@testable import TranscriberDomain

@Suite("Recording assets")
struct RecordingAssetTests {
    @Test("Legacy recordings receive deterministic audio and transcript assets")
    func legacyMigration() {
        let migrated = LegacyRecordingAssetMigration.migrate(
            nil,
            audioFileName: "recording.m4a",
            transcriptFileName: "recording.txt",
            durationSeconds: 42
        )

        #expect(migrated.map(\.id) == [
            LegacyRecordingAssetMigration.primaryAudioID,
            LegacyRecordingAssetMigration.transcriptID,
        ])
        #expect(migrated[0].kind == .primaryAudio)
        #expect(migrated[0].durationSeconds == 42)
        #expect(migrated[1].kind == .transcript)
    }

    @Test("Legacy migration is idempotent and updates renamed files")
    func idempotentMigration() {
        let initial = LegacyRecordingAssetMigration.migrate(
            nil,
            audioFileName: "old.m4a",
            transcriptFileName: "old.txt",
            durationSeconds: 10
        )
        let migrated = LegacyRecordingAssetMigration.migrate(
            initial,
            audioFileName: "new.m4a",
            transcriptFileName: "new.txt",
            durationSeconds: 12
        )

        #expect(migrated.count == 2)
        #expect(migrated[0].relativePath == "new.m4a")
        #expect(migrated[0].durationSeconds == 12)
        #expect(migrated[1].relativePath == "new.txt")
    }

    @Test("Legacy migration preserves unrelated assets of the same kind")
    func preservesUnrelatedSameKindAsset() {
        let importedAudio = RecordingAsset(
            id: "imported.primary-audio",
            kind: .primaryAudio,
            relativePath: "imported.m4a"
        )
        let migrated = LegacyRecordingAssetMigration.migrate(
            [importedAudio],
            audioFileName: "legacy.m4a",
            transcriptFileName: "legacy.txt",
            durationSeconds: 24
        )

        #expect(migrated.first == importedAudio)
        #expect(migrated.contains(where: {
            $0.id == LegacyRecordingAssetMigration.primaryAudioID
                && $0.relativePath == "legacy.m4a"
        }))
        #expect(migrated.count == 3)
    }

    @Test("Session resolves an explicit primary asset")
    func primaryAssetResolution() {
        let systemAudio = RecordingAsset(
            id: "system",
            kind: .systemAudio,
            relativePath: "system.m4a"
        )
        let screenVideo = RecordingAsset(
            id: "screen",
            kind: .screenVideo,
            relativePath: "screen.mov"
        )
        let session = RecordingSession(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 0),
            title: "Meeting",
            durationSeconds: 30,
            assets: [systemAudio, screenVideo],
            primaryAssetID: screenVideo.id
        )

        #expect(session.primaryAsset == screenVideo)
    }

    @Test(
        "Only sandbox-relative paths are accepted",
        arguments: [
            ("capture/video.mov", true),
            ("recording.m4a", true),
            ("../outside.m4a", false),
            ("/absolute/file.m4a", false),
            ("   ", false),
        ]
    )
    func safeRelativePaths(path: String, expected: Bool) {
        let asset = RecordingAsset(
            id: "fixture",
            kind: .attachment,
            relativePath: path
        )
        #expect(asset.isSafeRelativePath == expected)
    }
}
