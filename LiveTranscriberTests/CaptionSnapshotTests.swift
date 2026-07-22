import AVFAudio
import Combine
import TranscriberDomain
import XCTest
@testable import LiveTranscriber

@MainActor
final class CaptionSnapshotTests: XCTestCase {
    func testInterimSpeechTakesPresentationPriority() {
        let store = CaptionPresentationStore()
        let final = TranscriptionLine(startSeconds: 0, text: "Completed sentence", isFinal: true)
        let interim = TranscriptionLine(startSeconds: 2, text: "Current speech", isFinal: false)

        store.updateTranscript(
            finalLines: [final],
            interimLine: interim,
            sourceLanguageID: "en-US"
        )

        XCTAssertEqual(store.snapshot.originalText, "Current speech")
        XCTAssertTrue(store.snapshot.isInterim)
        XCTAssertEqual(store.snapshot.sourceLanguageID, "en-US")
    }

    func testTranslationUsesLatestFinalLine() {
        let store = CaptionPresentationStore()
        let first = TranscriptionLine(startSeconds: 0, text: "First", isFinal: true)
        let latest = TranscriptionLine(startSeconds: 1, text: "Latest", isFinal: true)

        store.updateTranscript(
            finalLines: [first, latest],
            interimLine: nil,
            sourceLanguageID: "en-US"
        )
        store.updateTranslation(
            [first.id: "Erste", latest.id: "Neueste"],
            targetLanguageID: "de-DE"
        )

        XCTAssertEqual(store.snapshot.originalText, "Latest")
        XCTAssertEqual(store.snapshot.translatedText, "Neueste")
        XCTAssertEqual(store.snapshot.targetLanguageID, "de-DE")
        XCTAssertFalse(store.snapshot.isInterim)
    }

    func testSessionStateDoesNotDiscardCaptionText() {
        let store = CaptionPresentationStore()
        let line = TranscriptionLine(startSeconds: 0, text: "Keep me", isFinal: true)
        store.updateTranscript(finalLines: [line], interimLine: nil, sourceLanguageID: "en-US")

        store.updateSessionState(.paused)

        XCTAssertEqual(store.snapshot.originalText, "Keep me")
        XCTAssertEqual(store.snapshot.sessionState, .paused)
    }
}

@MainActor
final class RecordingPlaybackTimelineTests: XCTestCase {
    func testStartingPlaybackAfterSeekDoesNotPublishEarlierTime() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-timeline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSilentWAV(to: url, duration: 7)

        let controller = RecordingPlaybackController()
        await controller.load(url: url)
        XCTAssertTrue(controller.isLoaded)

        controller.seek(to: 5.16)
        var observedTimes: [TimeInterval] = []
        let observation = controller.$currentTime.sink { time in
            observedTimes.append(time)
        }

        controller.play()
        try await Task.sleep(for: .milliseconds(600))
        controller.pause()
        withExtendedLifetime(observation) {}

        XCTAssertFalse(observedTimes.isEmpty)
        XCTAssertGreaterThanOrEqual(
            observedTimes.min() ?? 0,
            5.159,
            "Published playback times: \(observedTimes)"
        )
        controller.unload()
    }

    func testResumingAtNewSeekDoesNotRepublishPreviousPlaybackPosition() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("playback-resume-timeline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeSilentWAV(to: url, duration: 45)

        let controller = RecordingPlaybackController()
        await controller.load(url: url)
        XCTAssertTrue(controller.isLoaded)

        let transcriptLines = StoredTranscriptLine.parse(
            "[00:17:50] Previous line\n[00:37:80] Selected line"
        )
        let previousLineID = try XCTUnwrap(transcriptLines.first?.id)
        let selectedLine = try XCTUnwrap(transcriptLines.last)

        controller.seek(to: transcriptLines[0].startSeconds)
        controller.play()
        try await Task.sleep(for: .milliseconds(350))
        controller.pause()

        controller.seek(to: selectedLine.startSeconds)
        var observedTimes: [TimeInterval] = []
        var observedLineIDs: [StoredTranscriptLine.ID] = []
        let observation = controller.$currentTime.sink { time in
            observedTimes.append(time)
            if let lineID = StoredTranscriptLine.currentLineID(in: transcriptLines, time: time) {
                observedLineIDs.append(lineID)
            }
        }

        controller.play()
        try await Task.sleep(for: .milliseconds(600))
        controller.pause()
        withExtendedLifetime(observation) {}

        XCTAssertFalse(observedTimes.isEmpty)
        XCTAssertFalse(
            observedLineIDs.contains(previousLineID),
            "Highlighted transcript lines: \(observedLineIDs); published times: \(observedTimes)"
        )
        XCTAssertTrue(observedLineIDs.contains(selectedLine.id))
        XCTAssertGreaterThanOrEqual(
            observedTimes.min() ?? 0,
            selectedLine.startSeconds,
            "Published playback times: \(observedTimes)"
        )
        controller.unload()
    }

    private func writeSilentWAV(to url: URL, duration: TimeInterval) throws {
        let sampleRate = 44_100.0
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        )
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        )
        buffer.frameLength = frameCount

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
