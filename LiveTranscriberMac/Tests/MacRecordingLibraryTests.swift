import Foundation
import TranscriberDomain
import XCTest
@testable import LiveTranscriberMac

final class MacRecordingLibraryTests: XCTestCase {
    func testFolderScanGroupsLegacyAudioAndTranscript() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacRecordingLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let recordingID = UUID()
        let stem = recordingID.uuidString.lowercased()
        try Data().write(to: rootURL.appendingPathComponent("\(stem).m4a"))
        try "[00:00:00] Test".write(
            to: rootURL.appendingPathComponent("\(stem).txt"),
            atomically: true,
            encoding: .utf8
        )

        let library = MacRecordingLibrary(initialDirectoryURL: rootURL)
        let sessions = try await library.recordingSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, recordingID)
        XCTAssertEqual(Set(sessions[0].assets.map(\.kind)), Set([.primaryAudio, .transcript]))
        let audioAsset = try XCTUnwrap(sessions[0].assets.first(where: { $0.kind.isAudio }))
        let audioURL = try await library.recordingAssetURL(
            sessionID: recordingID,
            assetID: audioAsset.id
        )
        XCTAssertEqual(audioURL.lastPathComponent, "\(stem).m4a")
    }

    func testFolderScanRejectsTranscriptOnlyGroups() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacRecordingLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try "orphan".write(
            to: rootURL.appendingPathComponent("orphan.txt"),
            atomically: true,
            encoding: .utf8
        )

        let library = MacRecordingLibrary(initialDirectoryURL: rootURL)
        let sessions = try await library.recordingSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testFolderScanUsesCaptureManifestMetadata() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacRecordingLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let plan = MacCaptureOutputPlan(
            directoryURL: rootURL,
            capturesSystemAudio: false,
            capturesMicrophone: false
        )
        try Data([0x01]).write(to: plan.videoURL)
        let result = try MacCaptureStorage.makeResult(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 2_000),
            durationSeconds: 9,
            sourceTitle: "Design Review"
        )

        let library = MacRecordingLibrary(initialDirectoryURL: rootURL)
        let sessions = try await library.recordingSessions()

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0], result.session)
    }
}
