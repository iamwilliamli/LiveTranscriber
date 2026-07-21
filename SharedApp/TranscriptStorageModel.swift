import Foundation
import SwiftUI
import TranscriberDomain

struct StoredTranscriptLine: Identifiable, Hashable {
    let id: String
    let startSeconds: TimeInterval
    let timeText: String
    let text: String
    let speaker: String?
    let spokenText: String

    static func parse(
        _ transcript: String,
        speakerDiarization: RecordingSpeakerDiarization? = nil
    ) -> [StoredTranscriptLine] {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { offset, rawLine -> StoredTranscriptLine? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("["),
                      let closingBracket = line.firstIndex(of: "]") else {
                    return nil
                }

                let timeText = String(line[line.index(after: line.startIndex)..<closingBracket])
                let textStart = line.index(after: closingBracket)
                let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                guard let seconds = parseSeconds(timeText), !text.isEmpty else {
                    return nil
                }

                return StoredTranscriptLine(
                    id: "\(offset)-\(timeText)",
                    startSeconds: seconds,
                    timeText: timeText,
                    text: text,
                    speaker: nil,
                    spokenText: text
                )
            }

        let sortedLines = lines.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.id < $1.id
            }
            return $0.startSeconds < $1.startSeconds
        }

        return applyingSpeakerMetadata(to: sortedLines, speakerDiarization: speakerDiarization)
    }

    static func currentLineID(in lines: [StoredTranscriptLine], time: TimeInterval) -> StoredTranscriptLine.ID? {
        guard !lines.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = lines.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if lines[midIndex].startSeconds <= time {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }

        let index = lowerBound - 1
        guard lines.indices.contains(index) else {
            return nil
        }
        return lines[index].id
    }

    private static func parseSeconds(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let centiseconds = Int(parts[2]),
              minutes >= 0,
              (0..<60).contains(seconds),
              (0..<100).contains(centiseconds) else {
            return nil
        }

        return TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100
    }

    private static func applyingSpeakerMetadata(
        to lines: [StoredTranscriptLine],
        speakerDiarization: RecordingSpeakerDiarization?
    ) -> [StoredTranscriptLine] {
        let segments = (speakerDiarization?.segments ?? []).sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.endSeconds < $1.endSeconds
            }
            return $0.startSeconds < $1.startSeconds
        }
        var nextSegmentIndex = 0

        return lines.enumerated().map { offset, line in
            let matchedSegment: RecordingSpeakerSegment?
            if segments.count == lines.count {
                matchedSegment = segments[offset]
            } else if segments.indices.contains(nextSegmentIndex) {
                while segments.indices.contains(nextSegmentIndex + 1),
                      abs(segments[nextSegmentIndex + 1].startSeconds - line.startSeconds)
                        < abs(segments[nextSegmentIndex].startSeconds - line.startSeconds) {
                    nextSegmentIndex += 1
                }

                if abs(segments[nextSegmentIndex].startSeconds - line.startSeconds) <= 0.75 {
                    matchedSegment = segments[nextSegmentIndex]
                    nextSegmentIndex += 1
                } else {
                    matchedSegment = nil
                }
            } else {
                matchedSegment = nil
            }

            let expectedSpeaker = TranscriptSpeakerNaming.normalizedID(matchedSegment?.speaker)
            let parsedContent = speakerContent(from: line.text, expectedSpeaker: expectedSpeaker)
            let speaker = expectedSpeaker ?? parsedContent.speaker
            let spokenText = parsedContent.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)

            return StoredTranscriptLine(
                id: line.id,
                startSeconds: line.startSeconds,
                timeText: line.timeText,
                text: line.text,
                speaker: speaker,
                spokenText: spokenText.isEmpty ? line.text : spokenText
            )
        }
    }

    private static func speakerContent(
        from text: String,
        expectedSpeaker: String?
    ) -> (speaker: String?, spokenText: String) {
        if let expectedSpeaker {
            for separator in [":", "："] {
                let prefix = expectedSpeaker + separator
                if let range = text.range(of: prefix, options: [.anchored, .caseInsensitive]) {
                    return (
                        expectedSpeaker,
                        String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
            return (expectedSpeaker, text)
        }

        guard let separatorIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return (nil, text)
        }
        let candidate = String(text[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranscriptSpeakerNaming.numberedIndex(candidate) != nil else {
            return (nil, text)
        }

        return (
            candidate,
            String(text[text.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum TranscriptSpeakerNaming {
    static func normalizedID(_ speaker: String?) -> String? {
        guard let speaker else {
            return nil
        }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func numberedIndex(_ speaker: String) -> Int? {
        let parts = speaker.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Speaker") == .orderedSame,
              let index = Int(parts[1]),
              index >= 0 else {
            return nil
        }
        return index
    }

    static func displayName(for speaker: String, presentationIndex: Int) -> String {
        guard numberedIndex(speaker) != nil else {
            return speaker
        }
        return localizedFormat(L10n.Recordings.transcriptSpeakerFormat, presentationIndex + 1)
    }
}

struct TranscriptSpeakerPresentation: Identifiable {
    let id: String
    let displayName: String
    let paletteIndex: Int

    var tint: Color {
        TranscriptSpeakerPalette.tint(for: paletteIndex)
    }

    static func makePresentations(for lines: [StoredTranscriptLine]) -> [TranscriptSpeakerPresentation] {
        var seen = Set<String>()
        var speakers: [TranscriptSpeakerPresentation] = []

        for speaker in lines.compactMap(\.speaker) {
            let comparisonKey = speaker.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            guard seen.insert(comparisonKey).inserted else {
                continue
            }

            speakers.append(
                TranscriptSpeakerPresentation(
                    id: speaker,
                    displayName: TranscriptSpeakerNaming.displayName(
                        for: speaker,
                        presentationIndex: speakers.count
                    ),
                    paletteIndex: speakers.count
                )
            )
        }
        return speakers
    }
}

enum TranscriptSpeakerPalette {
    private static let colors: [Color] = [
        AppTheme.info,
        AppTheme.purple,
        AppTheme.success,
        AppTheme.brand,
        Color.teal,
        Color.pink,
        AppTheme.warning,
        Color.indigo
    ]

    static func tint(for index: Int) -> Color {
        colors[index % colors.count]
    }
}
