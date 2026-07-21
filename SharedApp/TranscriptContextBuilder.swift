import Foundation

struct TranscriptContextProfile {
    var directCharacterLimit: Int
    var chunkCharacterLimit: Int
    var overlapCharacterLimit: Int
    var mergeCharacterLimit: Int

    static let appleSummary = TranscriptContextProfile(
        directCharacterLimit: 8_000,
        chunkCharacterLimit: 7_200,
        overlapCharacterLimit: 500,
        mergeCharacterLimit: 7_000
    )

    static let localQwenSummary = TranscriptContextProfile(
        directCharacterLimit: 3_200,
        chunkCharacterLimit: 2_600,
        overlapCharacterLimit: 250,
        mergeCharacterLimit: 3_000
    )

    static let localQwenChat = TranscriptContextProfile(
        directCharacterLimit: 1_400,
        chunkCharacterLimit: 900,
        overlapCharacterLimit: 80,
        mergeCharacterLimit: 1_600
    )
}

struct TranscriptChunk: Identifiable, Hashable {
    var id: Int { index }
    var index: Int
    var text: String
}

enum TranscriptContextBuilder {
    static func cleanedTranscript(_ transcript: String) -> String {
        transcript
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chunks(
        from transcript: String,
        profile: TranscriptContextProfile
    ) -> [TranscriptChunk] {
        let cleaned = cleanedTranscript(transcript)
        guard !cleaned.isEmpty else {
            return []
        }

        guard cleaned.count > profile.directCharacterLimit else {
            return [TranscriptChunk(index: 1, text: cleaned)]
        }

        let lines = cleaned
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return splitOversizedText(cleaned, limit: profile.chunkCharacterLimit)
        }

        var chunks: [TranscriptChunk] = []
        var currentLines: [String] = []
        var currentCount = 0

        for line in lines {
            if line.count > profile.chunkCharacterLimit {
                appendChunkIfNeeded(lines: &currentLines, count: &currentCount, chunks: &chunks)
                chunks.append(contentsOf: splitOversizedText(line, limit: profile.chunkCharacterLimit, startingAt: chunks.count + 1))
                continue
            }

            if !currentLines.isEmpty,
               currentCount + 1 + line.count > profile.chunkCharacterLimit {
                appendChunkIfNeeded(lines: &currentLines, count: &currentCount, chunks: &chunks)
                let overlapLines = trailingOverlapLines(from: chunks.last?.text ?? "", limit: profile.overlapCharacterLimit)
                currentLines = overlapLines
                currentCount = overlapLines.joined(separator: "\n").count
            }

            let separatorCount = currentLines.isEmpty ? 0 : 1
            currentLines.append(line)
            currentCount += separatorCount + line.count
        }

        appendChunkIfNeeded(lines: &currentLines, count: &currentCount, chunks: &chunks)
        return chunks.enumerated().map { offset, chunk in
            TranscriptChunk(index: offset + 1, text: chunk.text)
        }
    }

    static func numberedDigest(
        chunks: [TranscriptChunk],
        profile: TranscriptContextProfile
    ) -> String {
        var entries: [String] = []
        var totalCount = 0

        for chunk in chunks {
            let entry = "Part \(chunk.index):\n\(chunk.text)"
            let separatorCount = entries.isEmpty ? 0 : 2
            guard totalCount + separatorCount + entry.count <= profile.mergeCharacterLimit else {
                break
            }
            entries.append(entry)
            totalCount += separatorCount + entry.count
        }

        return entries.joined(separator: "\n\n")
    }

    static func boundaryDigest(
        from transcript: String,
        profile: TranscriptContextProfile
    ) -> String {
        let cleaned = cleanedTranscript(transcript)
        guard cleaned.count > profile.mergeCharacterLimit else {
            return cleaned
        }

        let prefixCount = max(profile.mergeCharacterLimit * 2 / 3, 1)
        let suffixCount = max(profile.mergeCharacterLimit - prefixCount - 80, 1)
        return """
        \(cleaned.prefix(prefixCount))

        [Middle of transcript omitted. Long-recording summary uses chunked notes when available.]

        \(cleaned.suffix(suffixCount))
        """
    }

    static func relevantChunks(
        question: String,
        transcript: String,
        profile: TranscriptContextProfile,
        maximumCount: Int
    ) -> [TranscriptChunk] {
        let chunks = chunks(from: transcript, profile: profile)
        guard chunks.count > maximumCount else {
            return chunks
        }

        let keywords = keywords(from: question)
        guard !keywords.isEmpty else {
            return Array(chunks.prefix(maximumCount))
        }

        let scored = chunks.map { chunk in
            let haystack = chunk.text.localizedLowercase
            let score = keywords.reduce(0) { partialScore, keyword in
                partialScore + (haystack.contains(keyword) ? keyword.count : 0)
            }
            return (chunk: chunk, score: score)
        }
        .sorted {
            if $0.score == $1.score {
                return $0.chunk.index < $1.chunk.index
            }
            return $0.score > $1.score
        }

        let selected = scored.prefix(maximumCount).map(\.chunk)
        if selected.allSatisfy({ chunk in
            keywords.allSatisfy { !chunk.text.localizedLowercase.contains($0) }
        }) {
            return Array(chunks.prefix(maximumCount))
        }

        return selected.sorted { $0.index < $1.index }
    }

    private static func appendChunkIfNeeded(
        lines: inout [String],
        count: inout Int,
        chunks: inout [TranscriptChunk]
    ) {
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            lines = []
            count = 0
            return
        }

        chunks.append(TranscriptChunk(index: chunks.count + 1, text: text))
        lines = []
        count = 0
    }

    private static func splitOversizedText(
        _ text: String,
        limit: Int,
        startingAt startIndex: Int = 1
    ) -> [TranscriptChunk] {
        var chunks: [TranscriptChunk] = []
        var currentIndex = text.startIndex
        var chunkIndex = startIndex

        while currentIndex < text.endIndex {
            let endIndex = text.index(currentIndex, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
            let chunkText = String(text[currentIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                chunks.append(TranscriptChunk(index: chunkIndex, text: chunkText))
                chunkIndex += 1
            }
            currentIndex = endIndex
        }

        return chunks
    }

    private static func trailingOverlapLines(from text: String, limit: Int) -> [String] {
        guard limit > 0 else {
            return []
        }

        var selected: [String] = []
        var count = 0
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            let separatorCount = selected.isEmpty ? 0 : 1
            guard count + separatorCount + line.count <= limit else {
                break
            }
            selected.insert(line, at: 0)
            count += separatorCount + line.count
        }

        return selected
    }

    private static func keywords(from question: String) -> [String] {
        let normalized = question.localizedLowercase
        let wordKeywords = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }

        if !wordKeywords.isEmpty {
            return Array(Set(wordKeywords))
        }

        let compact = normalized
            .filter { !$0.isWhitespace && !$0.isPunctuation }
        guard compact.count >= 2 else {
            return []
        }

        return stride(from: 0, to: max(compact.count - 1, 0), by: 2).compactMap { offset in
            let startIndex = compact.index(compact.startIndex, offsetBy: offset)
            let endIndex = compact.index(startIndex, offsetBy: min(3, compact.distance(from: startIndex, to: compact.endIndex)), limitedBy: compact.endIndex) ?? compact.endIndex
            let keyword = String(compact[startIndex..<endIndex])
            return keyword.count >= 2 ? keyword : nil
        }
    }
}
