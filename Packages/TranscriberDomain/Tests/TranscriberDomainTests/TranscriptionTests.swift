import Foundation
import Testing
@testable import TranscriberDomain

@Suite("Transcription values")
struct TranscriptionTests {
    @Test("Transcript timestamps preserve centiseconds")
    func transcriptTimestamp() {
        #expect(TranscriptionLine.formatTranscriptTimestamp(65.129) == "01:05:13")
        #expect(TranscriptionLine.formatTranscriptTimestamp(-4) == "00:00:00")
    }

    @Test("Playback timestamps expand to hours only when needed")
    func playbackTimestamp() {
        #expect(TranscriptionLine.formatTimestamp(65.9) == "01:05")
        #expect(TranscriptionLine.formatTimestamp(3_661) == "01:01:01")
    }

    @Test("Transcript text projections retain line order")
    func transcriptTextProjection() {
        let lines = [
            TranscriptionLine(startSeconds: 0, text: "Hello", isFinal: true),
            TranscriptionLine(startSeconds: 2.5, text: "World", isFinal: true),
        ]

        #expect(lines.timedTranscriptText == "[00:00:00] Hello\n[00:02:50] World")
        #expect(lines.plainTranscriptText == "Hello\nWorld")
    }

    @Test("Regional language identifiers collapse to unique base languages")
    func baseLanguageOptions() {
        let options = TranscriptionLanguage.baseLanguageOptions(from: [
            TranscriptionLanguage(id: "en-US"),
            TranscriptionLanguage(id: "en-GB"),
            TranscriptionLanguage(id: "de-DE"),
        ])

        #expect(Set(options.map(\.id)) == Set(["en", "de"]))
    }
}
