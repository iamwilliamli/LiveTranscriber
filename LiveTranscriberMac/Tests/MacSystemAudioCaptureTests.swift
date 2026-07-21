import AVFoundation
import XCTest
@testable import LiveTranscriberMac

final class MacSystemAudioCaptureTests: XCTestCase {
    func testSystemAudioLiveInputDoesNotRequireMicrophonePermission() {
        let inputSource = LiveRecordingInputSource.externalAudio(
            sampleRate: 48_000,
            channelCount: 2
        )

        XCTAssertTrue(inputSource.usesExternalAudio)
        XCTAssertFalse(inputSource.requiresMicrophonePermission)
    }

    func testMicrophoneLiveInputRetainsMicrophonePermissionRequirement() {
        let inputSource = LiveRecordingInputSource.microphone

        XCTAssertFalse(inputSource.usesExternalAudio)
        XCTAssertTrue(inputSource.requiresMicrophonePermission)
    }

    @MainActor
    func testSystemAudioOnlyConfigurationExcludesMicrophoneTrack() {
        let configuration = MacSystemAudioCaptureController.makeStreamConfiguration(
            includesMicrophone: false
        )

        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertFalse(configuration.captureMicrophone)
        XCTAssertNil(configuration.microphoneCaptureDeviceID)
    }

    @MainActor
    func testCombinedConfigurationIncludesMicrophoneTrack() {
        let configuration = MacSystemAudioCaptureController.makeStreamConfiguration(
            includesMicrophone: true
        )

        XCTAssertTrue(configuration.capturesAudio)
        XCTAssertTrue(configuration.captureMicrophone)
    }

    func testMixerProducesPlayableM4AFromSystemAndMicrophoneTracks() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MacSystemAudioCaptureTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let systemURL = directoryURL.appendingPathComponent("system.caf")
        let microphoneURL = directoryURL.appendingPathComponent("microphone.caf")
        let outputURL = directoryURL.appendingPathComponent("mixed.m4a")
        try writeTone(frequency: 440, to: systemURL)
        try writeTone(frequency: 660, to: microphoneURL)

        try await MacSystemAudioMixer.mix(
            systemAudioURL: systemURL,
            microphoneAudioURL: microphoneURL,
            outputURL: outputURL
        )

        let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
        XCTAssertGreaterThan(values.fileSize ?? 0, 0)
        let asset = AVURLAsset(url: outputURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        XCTAssertFalse(tracks.isEmpty)
        XCTAssertGreaterThan(duration, 0.2)
    }

    private func writeTone(frequency: Double, to url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = AVAudioFrameCount(sampleRate / 4)
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            samples[frame] = Float(sin(2 * .pi * frequency * time) * 0.2)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
