import Foundation
import XCTest
@testable import LiveTranscriberMac

final class RecordingStorageWorkerTests: XCTestCase {
    func testPrepareDirectoryMigratesRecordingFilesButLeavesUnrelatedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingStorageWorkerTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = source.appendingPathComponent("recording.wav")
        let transcriptURL = source.appendingPathComponent("recording.txt")
        let unrelatedURL = source.appendingPathComponent("notes.json")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        try "hello".write(to: transcriptURL, atomically: true, encoding: .utf8)
        try "{}".write(to: unrelatedURL, atomically: true, encoding: .utf8)

        let worker = RecordingStorageWorker()
        try await worker.prepareRecordingsDirectory(
            at: destination,
            migrationSources: [source],
            audioFileExtensions: ["wav", "m4a"]
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("recording.wav").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("recording.txt").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("notes.json").path
            )
        )
    }

    func testDiscoveryReadsTranscriptMetadataWithoutRecordingStoreFileAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingStorageDiscoveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recordingID = UUID()
        let audioFileName = "\(recordingID.uuidString.lowercased()).wav"
        let audioURL = root.appendingPathComponent(audioFileName)
        let transcriptURL = root.appendingPathComponent(
            "\(recordingID.uuidString.lowercased()).txt"
        )
        try Data([0, 1, 2, 3]).write(to: audioURL)
        try "[00:00.00] Background discovery".write(
            to: transcriptURL,
            atomically: true,
            encoding: .utf8
        )

        let worker = RecordingStorageWorker()
        let snapshots = try await worker.discoverRecordingFiles(
            at: root,
            audioFileExtensions: ["wav"],
            requirementsByFileName: [
                audioFileName: RecordingStorageFileDiscoveryRequirements(
                    needsTranscript: true,
                    needsDuration: false
                ),
            ],
            tombstonedIDs: []
        )

        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.url.lastPathComponent, audioFileName)
        XCTAssertEqual(snapshot.transcript, "[00:00.00] Background discovery")
        XCTAssertNil(snapshot.durationSeconds)
    }

    func testDiscoveryExcludesTombstonedRecordings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingStorageTombstoneTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recordingID = UUID()
        let audioURL = root.appendingPathComponent(
            "\(recordingID.uuidString.lowercased()).m4a"
        )
        try Data([0, 1, 2, 3]).write(to: audioURL)

        let worker = RecordingStorageWorker()
        let snapshots = try await worker.discoverRecordingFiles(
            at: root,
            audioFileExtensions: ["m4a"],
            requirementsByFileName: [:],
            tombstonedIDs: [recordingID]
        )

        XCTAssertTrue(snapshots.isEmpty)
    }
}
