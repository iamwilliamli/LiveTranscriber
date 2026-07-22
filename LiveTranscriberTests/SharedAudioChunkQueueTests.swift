import AVFoundation
import XCTest
@testable import LiveTranscriber

final class SharedAudioChunkQueueTests: XCTestCase {
    private var rootURL: URL!
    private var directory: SharedAudioChunkDirectory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveTranscriberScreenAudioTests-\(UUID().uuidString)", isDirectory: true)
        directory = SharedAudioChunkDirectory(rootURL: rootURL)
        try directory.prepare()
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        directory = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testReadyChunksAreReturnedInSequenceOrder() throws {
        let metadata = try directory.beginSession()
        let payload = Data(repeating: 1, count: 64)

        XCTAssertTrue(try directory.commitChunk(payload, sessionID: metadata.sessionID, sequence: 12))
        XCTAssertTrue(try directory.commitChunk(payload, sessionID: metadata.sessionID, sequence: 2))
        XCTAssertTrue(try directory.commitChunk(payload, sessionID: metadata.sessionID, sequence: 7))

        let sequences = try directory.readyChunkURLs(sessionID: metadata.sessionID)
            .compactMap(SharedAudioChunkDirectory.sequence(from:))
        XCTAssertEqual(sequences, [2, 7, 12])
    }

    func testCommitUsesReadySuffixAndLeavesNoTemporaryFile() throws {
        let metadata = try directory.beginSession()
        XCTAssertTrue(
            try directory.commitChunk(
                Data(repeating: 2, count: 32),
                sessionID: metadata.sessionID,
                sequence: 0
            )
        )

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory.sessionDirectoryURL(for: metadata.sessionID),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(entries.filter { $0.lastPathComponent.hasSuffix(".pcm.ready") }.count, 1)
        XCTAssertTrue(entries.allSatisfy { !$0.lastPathComponent.hasSuffix(".tmp") })
    }

    func testBackpressureRejectsChunksPastLimit() throws {
        let metadata = try directory.beginSession()
        let payload = Data(repeating: 3, count: 16)

        XCTAssertTrue(
            try directory.commitChunk(
                payload,
                sessionID: metadata.sessionID,
                sequence: 0,
                maximumReadyChunks: 1
            )
        )
        XCTAssertFalse(
            try directory.commitChunk(
                payload,
                sessionID: metadata.sessionID,
                sequence: 1,
                maximumReadyChunks: 1
            )
        )
    }

    func testInvalidPCMIsRejected() throws {
        let metadata = try directory.beginSession()
        XCTAssertThrowsError(
            try directory.commitChunk(
                Data([0x01]),
                sessionID: metadata.sessionID,
                sequence: 0
            )
        )
        XCTAssertThrowsError(
            try directory.commitChunk(
                Data([0x01, 0x02]),
                sessionID: metadata.sessionID,
                sequence: 1
            )
        )
        XCTAssertThrowsError(try SystemAudioPCMNormalizer.buffer(from: Data([0x01])))
        XCTAssertThrowsError(try SystemAudioPCMNormalizer.buffer(from: Data([0x01, 0x02])))
    }

    func testTransportPCMUses48kStereoFloatInsideAppAndInterleavedInt16OnDisk() throws {
        let format = SystemAudioPCMNormalizer.targetFormat
        XCTAssertEqual(format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 2)

        guard let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3),
              let channels = input.floatChannelData else {
            return XCTFail("Could not allocate the test PCM buffer")
        }
        input.frameLength = 3
        channels[0][0] = -1
        channels[0][1] = 0
        channels[0][2] = 1
        channels[1][0] = 1
        channels[1][1] = 0.5
        channels[1][2] = -0.5

        let data = try SystemAudioPCMNormalizer.data(from: input)
        XCTAssertEqual(data.count, 3 * 2 * MemoryLayout<Int16>.size)
        data.withUnsafeBytes { rawBuffer in
            let interleaved = rawBuffer.bindMemory(to: Int16.self)
            XCTAssertEqual(interleaved[0], -Int16.max)
            XCTAssertEqual(interleaved[1], Int16.max)
            XCTAssertEqual(interleaved[2], 0)
            XCTAssertEqual(interleaved[3], Int16((0.5 * Float(Int16.max)).rounded()))
        }

        let decoded = try SystemAudioPCMNormalizer.buffer(from: data)
        XCTAssertEqual(decoded.format.commonFormat, .pcmFormatFloat32)
        XCTAssertEqual(decoded.format.sampleRate, 48_000)
        XCTAssertEqual(decoded.format.channelCount, 2)
        XCTAssertEqual(decoded.frameLength, 3)
        guard let decodedChannels = decoded.floatChannelData else {
            return XCTFail("Could not read the decoded test PCM buffer")
        }
        XCTAssertEqual(decodedChannels[0][0], -Float(Int16.max) / 32_768, accuracy: 0.0001)
        XCTAssertEqual(decodedChannels[0][1], 0, accuracy: 0.0001)
        XCTAssertEqual(decodedChannels[0][2], Float(Int16.max) / 32_768, accuracy: 0.0001)
        XCTAssertEqual(decodedChannels[1][0], Float(Int16.max) / 32_768, accuracy: 0.0001)
        XCTAssertEqual(decodedChannels[1][1], 0.5, accuracy: 0.0001)
        XCTAssertEqual(decodedChannels[1][2], -0.5, accuracy: 0.0001)
    }

    func testM4AWriterDoesNotForceUnsupportedBitRateFor16kMono() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            return XCTFail("Could not create the 16 kHz mono test format")
        }

        let settings = AudioFileWriter.settings(for: .m4a, inputFormat: format)
        XCTAssertNil(settings[AVEncoderBitRateKey])

        let outputURL = rootURL.appendingPathComponent("screen-audio.m4a")
        let writer = try AudioFileWriter(
            url: outputURL,
            inputFormat: format,
            outputFormat: .m4a
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320) else {
            return XCTFail("Could not allocate the M4A test buffer")
        }
        buffer.frameLength = 320
        XCTAssertEqual(try writer.write(buffer), 320)
        XCTAssertEqual(writer.finish().writtenFrameCount, 320)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWAVWriterPreserves48kStereoRecordingFormat() async throws {
        let format = SystemAudioPCMNormalizer.targetFormat
        let outputURL = rootURL.appendingPathComponent("screen-audio.wav")
        let writer = try AudioFileWriter(
            url: outputURL,
            inputFormat: format,
            outputFormat: .wav
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480),
              let channels = buffer.floatChannelData else {
            return XCTFail("Could not allocate the stereo WAV test buffer")
        }
        buffer.frameLength = 480
        for frame in 0..<Int(buffer.frameLength) {
            channels[0][frame] = 0.25
            channels[1][frame] = -0.25
        }

        XCTAssertEqual(try writer.write(buffer), 480)
        XCTAssertEqual(writer.finish().writtenFrameCount, 480)

        let savedFile = try AVAudioFile(forReading: outputURL)
        XCTAssertEqual(savedFile.processingFormat.sampleRate, 48_000)
        XCTAssertEqual(savedFile.processingFormat.channelCount, 2)
        XCTAssertEqual(savedFile.length, 480)
        XCTAssertTrue(savedFile.fileFormat.isInterleaved)
        let streamDescription = savedFile.fileFormat.streamDescription.pointee
        XCTAssertEqual(streamDescription.mBitsPerChannel, 24)
        XCTAssertEqual(streamDescription.mFormatFlags & kAudioFormatFlagIsFloat, 0)

        let asset = AVURLAsset(url: outputURL)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)
    }

    @MainActor
    func testPlaybackControllerLoadsExistingFloatWAVThroughAVAudioFile() async throws {
        let format = SystemAudioPCMNormalizer.targetFormat
        let outputURL = rootURL.appendingPathComponent("existing-float.wav")
        var writer: AVAudioFile? = try AVAudioFile(
            forWriting: outputURL,
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
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800) else {
            return XCTFail("Could not allocate the Float32 WAV test buffer")
        }
        buffer.frameLength = buffer.frameCapacity
        try writer?.write(from: buffer)
        writer = nil

        let controller = RecordingPlaybackController()
        await controller.load(url: outputURL)
        XCTAssertTrue(controller.isLoaded)
        XCTAssertNil(controller.errorText)
        XCTAssertEqual(controller.duration, 0.1, accuracy: 0.001)
        controller.unload()
    }
}
