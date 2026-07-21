import Foundation
import TranscriberDomain
import XCTest
@testable import LiveTranscriberMac

final class MacCaptureModelsTests: XCTestCase {
    func testOutputPlanUsesOneStableSessionStem() {
        let sessionID = UUID()
        let directoryURL = URL(fileURLWithPath: "/recordings", isDirectory: true)
        let plan = MacCaptureOutputPlan(
            sessionID: sessionID,
            directoryURL: directoryURL,
            capturesSystemAudio: true,
            capturesMicrophone: true
        )
        let stem = sessionID.uuidString.lowercased()

        XCTAssertEqual(plan.videoURL.lastPathComponent, "\(stem).screen.mp4")
        XCTAssertEqual(plan.systemAudioURL?.lastPathComponent, "\(stem).m4a")
        XCTAssertEqual(plan.microphoneAudioURL?.lastPathComponent, "\(stem).microphone.m4a")
        XCTAssertEqual(plan.manifestURL.lastPathComponent, "\(stem).session.json")
    }

    func testCaptureResultWritesAReadableSessionManifest() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCaptureModelsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let plan = MacCaptureOutputPlan(
            directoryURL: rootURL,
            capturesSystemAudio: true,
            capturesMicrophone: false
        )
        try Data([0x01]).write(to: plan.videoURL)
        try Data([0x02]).write(to: try XCTUnwrap(plan.systemAudioURL))

        let result = try MacCaptureStorage.makeResult(
            plan: plan,
            startedAt: Date(timeIntervalSince1970: 1_000),
            durationSeconds: 24,
            sourceTitle: "Zoom"
        )
        let decoded = try RecordingSessionPayloadDecoder.decode(
            Data(contentsOf: result.manifestURL)
        )

        XCTAssertEqual(decoded, result.session)
        XCTAssertEqual(decoded.id, plan.sessionID)
        XCTAssertEqual(decoded.primaryAsset?.kind, .screenVideo)
        XCTAssertEqual(Set(decoded.assets.map(\.kind)), Set([.screenVideo, .systemAudio]))
    }
}
