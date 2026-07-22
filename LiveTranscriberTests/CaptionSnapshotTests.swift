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
