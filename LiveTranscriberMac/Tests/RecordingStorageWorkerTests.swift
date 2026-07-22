import AVFoundation
import Foundation
import XCTest
@testable import LiveTranscriberMac

final class RecordingStorageWorkerTests: XCTestCase {
    func testPreparingReadableLocalFileReportsCheckingThenAvailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingStoragePreparationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = root.appendingPathComponent("recording.m4a")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        let stateRecorder = RecordingFilePreparationStateRecorder()
        let worker = RecordingStorageWorker()

        let preparedURL = try await worker.prepareFileForAccess(
            at: audioURL,
            isEnabled: true,
            stateHandler: { state in
                await stateRecorder.append(state)
            }
        )

        XCTAssertEqual(preparedURL, audioURL)
        let states = await stateRecorder.states
        XCTAssertEqual(states, [.checking, .available])
    }

    func testPreparingMissingFileReturnsExplicitFailure() async throws {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "missing-recording-\(UUID().uuidString).m4a"
        )
        let worker = RecordingStorageWorker()

        do {
            _ = try await worker.prepareFileForAccess(
                at: missingURL,
                isEnabled: true,
                stateHandler: nil
            )
            XCTFail("Expected a missing-file error")
        } catch let error as RecordingFilePreparationError {
            XCTAssertEqual(error, .fileMissing)
        }
    }

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

    func testNamedFileCleanupRemovesRecordingAssetsWithoutTouchingOtherFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingStorageCleanupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let assets = root.appendingPathComponent("Assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let audioURL = root.appendingPathComponent("recording.m4a")
        let transcriptURL = root.appendingPathComponent("recording.txt")
        let assetURL = assets.appendingPathComponent("waveform.json")
        let unrelatedURL = root.appendingPathComponent("keep.json")
        try Data([0, 1, 2, 3]).write(to: audioURL)
        try "transcript".write(to: transcriptURL, atomically: true, encoding: .utf8)
        try "waveform".write(to: assetURL, atomically: true, encoding: .utf8)
        try "keep".write(to: unrelatedURL, atomically: true, encoding: .utf8)

        let worker = RecordingStorageWorker()
        await worker.removeFiles(
            namedRelativePaths: [
                "recording.m4a",
                "recording.txt",
                "Assets/waveform.json",
            ],
            in: [root]
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: transcriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: assetURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    func testWAVWriterPersistsInterleavedIntegerPCMThatAVAssetCanPlay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "AudioFileWriterTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("stereo.wav")
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: 4_800
            )
        )
        buffer.frameLength = buffer.frameCapacity

        let writer = try AudioFileWriter(
            url: url,
            inputFormat: inputFormat,
            outputFormat: .wav
        )
        _ = try writer.write(buffer)
        _ = writer.finish()

        let writtenFile = try AVAudioFile(forReading: url)
        XCTAssertTrue(writtenFile.fileFormat.isInterleaved)
        XCTAssertEqual(writtenFile.fileFormat.channelCount, 2)
        XCTAssertEqual(writtenFile.length, 4_800)
        let streamDescription = writtenFile.fileFormat.streamDescription.pointee
        XCTAssertEqual(streamDescription.mBitsPerChannel, 24)
        XCTAssertEqual(streamDescription.mFormatFlags & kAudioFormatFlagIsFloat, 0)

        let asset = AVURLAsset(url: url)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)
    }

    @MainActor
    func testPlaybackPreparationUsesBoundedTwoHundredMillisecondWindow() {
        XCTAssertEqual(
            RecordingPlaybackController.playbackPreparationFrameCount(
                remainingFrames: 172_800_000,
                sampleRate: 48_000
            ),
            9_600
        )
        XCTAssertEqual(
            RecordingPlaybackController.playbackPreparationFrameCount(
                remainingFrames: 4_800,
                sampleRate: 48_000
            ),
            4_800
        )
        XCTAssertEqual(
            RecordingPlaybackController.playbackPreparationFrameCount(
                remainingFrames: 0,
                sampleRate: 48_000
            ),
            0
        )
    }

    @MainActor
    func testPlaybackControllerPlaysExistingFloatWAVThroughAVAudioFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlaybackCompatibilityTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("legacy-float.wav")
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 2,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 48_000
            )
        )
        buffer.frameLength = buffer.frameCapacity

        var legacyWriter: AVAudioFile? = try AVAudioFile(
            forWriting: sourceURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: Int(format.channelCount),
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try legacyWriter?.write(from: buffer)
        legacyWriter = nil

        let controller = RecordingPlaybackController()
        await controller.load(url: sourceURL)
        XCTAssertTrue(controller.isLoaded)
        XCTAssertNil(controller.errorText)
        XCTAssertEqual(controller.duration, 1, accuracy: 0.001)

        controller.play()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.isPlaying)
        controller.seek(to: 0.5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.isPlaying)
        controller.pause()
        XCTAssertGreaterThanOrEqual(controller.currentTime, 0.49)
        controller.unload()
        XCTAssertFalse(controller.isLoaded)
        XCTAssertNil(controller.currentItem)

        // A new detail can begin loading immediately after navigation. The
        // controller must await the queued teardown instead of racing the old
        // AVAudioPlayerNode from MainActor.
        await controller.load(url: sourceURL)
        XCTAssertTrue(controller.isLoaded)
        XCTAssertNil(controller.errorText)
        controller.unload()
    }
}

private actor RecordingFilePreparationStateRecorder {
    private(set) var states: [RecordingFilePreparationState] = []

    func append(_ state: RecordingFilePreparationState) {
        states.append(state)
    }
}
