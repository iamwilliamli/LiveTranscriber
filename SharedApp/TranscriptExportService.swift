import Foundation

enum TranscriptExportFormat: String, CaseIterable, Identifiable {
    case txt
    case markdown
    case srt
    case vtt
    case json

    var id: String {
        rawValue
    }

    var fileExtension: String {
        switch self {
        case .txt:
            return "txt"
        case .markdown:
            return "md"
        case .srt:
            return "srt"
        case .vtt:
            return "vtt"
        case .json:
            return "json"
        }
    }
}

enum TranscriptExportError: LocalizedError {
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            return String(localized: L10n.Recordings.exportEmptyTranscript)
        }
    }
}

struct TranscriptExportService {
    static func export(
        item: RecordingItem,
        transcript: String,
        format: TranscriptExportFormat
    ) throws -> URL {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw TranscriptExportError.emptyTranscript
        }

        let lines = ExportTranscriptLine.parse(transcript)
        let content = try content(for: item, transcript: trimmedTranscript, lines: lines, format: format)
        let directory = try exportDirectory()
        let fileURL = directory.appendingPathComponent("\(safeBaseName(for: item)).\(format.fileExtension)")

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private static func content(
        for item: RecordingItem,
        transcript: String,
        lines: [ExportTranscriptLine],
        format: TranscriptExportFormat
    ) throws -> String {
        switch format {
        case .txt:
            return lines.isEmpty ? transcript : lines.map(\.text).joined(separator: "\n")
        case .markdown:
            return markdown(for: item, transcript: transcript, lines: lines)
        case .srt:
            return subtitle(lines: lines, format: .srt)
        case .vtt:
            return subtitle(lines: lines, format: .vtt)
        case .json:
            return try json(for: item, transcript: transcript, lines: lines)
        }
    }

    private static func markdown(
        for item: RecordingItem,
        transcript: String,
        lines: [ExportTranscriptLine]
    ) -> String {
        var sections: [String] = []
        sections.append("# \(displayName(for: item))")

        var metadata: [String] = [
            "- Date: \(DateFormatter.exportDate.string(from: item.createdAt))",
            "- Duration: \(formattedDuration(TimeInterval(item.durationSeconds)))",
            "- Language: \(item.languageName)"
        ]
        if !item.combinedTags.isEmpty {
            metadata.append("- Tags: \(item.combinedTags.joined(separator: ", "))")
        }
        if let projectName = item.projectName {
            metadata.append("- Folder / Project: \(projectName)")
        }
        if let categoryName = item.categoryName {
            metadata.append("- Category: \(categoryName)")
        }
        sections.append(metadata.joined(separator: "\n"))

        if let keyPoints = item.keyPoints {
            sections.append("## Key Points\n\n\(keyPoints)")
        }

        if let intelligence = item.intelligence, !intelligence.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## Summary\n\n\(intelligence.summary)")
        }

        if let analysis = item.meetingAnalysis {
            sections.append(meetingAnalysisMarkdown(analysis))
        }

        let transcriptBody: String
        if lines.isEmpty {
            transcriptBody = transcript
        } else {
            transcriptBody = lines
                .map { "- `\($0.timeText)` \($0.text)" }
                .joined(separator: "\n")
        }
        sections.append("## Transcript\n\n\(transcriptBody)")

        return sections.joined(separator: "\n\n")
    }

    private static func meetingAnalysisMarkdown(_ analysis: RecordingMeetingAnalysis) -> String {
        var sections: [String] = []
        sections.append("## Meeting Analysis")

        if let summary = analysis.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            sections.append("### Summary\n\n- \(summary)")
        }

        if !analysis.actionItems.isEmpty {
            let lines = analysis.actionItems.map { item in
                let metadata = [item.owner, item.dueDate].compactMap(\.self).joined(separator: ", ")
                return metadata.isEmpty ? "- \(item.task)" : "- \(item.task) (\(metadata))"
            }
            sections.append("### Action Items\n\n\(lines.joined(separator: "\n"))")
        }

        if !analysis.decisions.isEmpty {
            let lines = analysis.decisions.map { item in
                if let rationale = item.rationale, !rationale.isEmpty {
                    return "- \(item.decision) - \(rationale)"
                }
                return "- \(item.decision)"
            }
            sections.append("### Decisions\n\n\(lines.joined(separator: "\n"))")
        }

        if !analysis.openQuestions.isEmpty {
            let lines = analysis.openQuestions.map { item in
                if let owner = item.owner, !owner.isEmpty {
                    return "- \(item.question) (\(owner))"
                }
                return "- \(item.question)"
            }
            sections.append("### Open Questions\n\n\(lines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    private enum SubtitleFormat {
        case srt
        case vtt
    }

    private static func subtitle(lines: [ExportTranscriptLine], format: SubtitleFormat) -> String {
        guard !lines.isEmpty else {
            return format == .vtt ? "WEBVTT\n" : ""
        }

        var blocks: [String] = []
        if format == .vtt {
            blocks.append("WEBVTT\n")
        }

        for (index, line) in lines.enumerated() {
            let endSeconds = inferredEndSeconds(for: index, lines: lines)
            let timing: String
            switch format {
            case .srt:
                timing = "\(subtitleTimestamp(line.startSeconds, separator: ",")) --> \(subtitleTimestamp(endSeconds, separator: ","))"
                blocks.append("\(index + 1)\n\(timing)\n\(line.text)")
            case .vtt:
                timing = "\(subtitleTimestamp(line.startSeconds, separator: ".")) --> \(subtitleTimestamp(endSeconds, separator: "."))"
                blocks.append("\(timing)\n\(line.text)")
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func json(
        for item: RecordingItem,
        transcript: String,
        lines: [ExportTranscriptLine]
    ) throws -> String {
        let payload = TranscriptExportPayload(
            recording: .init(
                id: item.id.uuidString,
                title: displayName(for: item),
                createdAt: ISO8601DateFormatter().string(from: item.createdAt),
                durationSeconds: TimeInterval(item.durationSeconds),
                languageID: item.languageID,
                languageName: item.languageName,
                audioFileName: item.displayFileName,
                tags: item.combinedTags,
                projectName: item.projectName,
                categoryName: item.categoryName,
                keyPoints: item.keyPoints
            ),
            summary: item.intelligence?.summary,
            meetingAnalysis: item.meetingAnalysis,
            transcript: lines.isEmpty ? nil : lines.map {
                .init(startSeconds: $0.startSeconds, timeText: $0.timeText, text: $0.text)
            },
            text: lines.isEmpty ? transcript : nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func inferredEndSeconds(for index: Int, lines: [ExportTranscriptLine]) -> TimeInterval {
        guard lines.indices.contains(index) else {
            return 0
        }
        if lines.indices.contains(index + 1) {
            return max(lines[index].startSeconds + 0.75, lines[index + 1].startSeconds)
        }
        return lines[index].startSeconds + 3
    }

    private static func subtitleTimestamp(_ seconds: TimeInterval, separator: String) -> String {
        let clampedSeconds = max(0, seconds)
        let totalMilliseconds = Int((clampedSeconds * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d%@%03d", hours, minutes, seconds, separator, milliseconds)
    }

    private static func exportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveTranscriberExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func displayName(for item: RecordingItem) -> String {
        item.displayName
    }

    private static func safeBaseName(for item: RecordingItem) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let baseName = displayName(for: item)
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(baseName)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "LiveTranscriber Export" : cleaned
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ExportTranscriptLine: Hashable {
    let startSeconds: TimeInterval
    let timeText: String
    let text: String

    static func parse(_ transcript: String) -> [ExportTranscriptLine] {
        transcript
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> ExportTranscriptLine? in
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

                return ExportTranscriptLine(startSeconds: seconds, timeText: timeText, text: text)
            }
            .sorted { $0.startSeconds < $1.startSeconds }
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
}

private struct TranscriptExportPayload: Encodable {
    struct Recording: Encodable {
        let id: String
        let title: String
        let createdAt: String
        let durationSeconds: TimeInterval
        let languageID: String
        let languageName: String
        let audioFileName: String
        let tags: [String]
        let projectName: String?
        let categoryName: String?
        let keyPoints: String?
    }

    struct Line: Encodable {
        let startSeconds: TimeInterval
        let timeText: String
        let text: String
    }

    let recording: Recording
    let summary: String?
    let meetingAnalysis: RecordingMeetingAnalysis?
    let transcript: [Line]?
    let text: String?
}

private extension DateFormatter {
    static let exportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
