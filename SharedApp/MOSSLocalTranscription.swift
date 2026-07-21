import AudioCommon
import Foundation
import MLXAudioCore
@preconcurrency import MLXAudioSTT
import TranscriberCore
import TranscriberDomain

struct MOSSLocalModelStatus: Equatable {
    let isAvailable: Bool
    let hasStoredFiles: Bool
    let byteCount: Int64?

    var statusText: String {
        String(localized: isAvailable ? L10n.MOSSLocal.modelReady : L10n.MOSSLocal.modelNotInstalled)
    }

    var detailText: String {
        if isAvailable, let byteCount {
            return String(
                format: String(localized: L10n.MOSSLocal.modelDownloadedDetailFormat),
                ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            )
        }

        if hasStoredFiles, let byteCount {
            return String(
                format: String(localized: L10n.MOSSLocal.partialDownloadDetailFormat),
                ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            )
        }

        return String(
            format: String(localized: L10n.MOSSLocal.modelMissingDetailFormat),
            MOSSLocalModelManager.expectedSizeText
        )
    }
}

enum MOSSDecoderSegmentDuration: Int, CaseIterable, Identifiable {
    static let defaultsKey = "moss_local.decoder_segment_duration_seconds"
    static var defaultValue: MOSSDecoderSegmentDuration {
        MOSSDecoderDeviceRecommendation.current.duration
    }

    case seconds30 = 30
    case seconds60 = 60
    case seconds90 = 90
    case seconds120 = 120
    case seconds180 = 180
    case seconds300 = 300
    case seconds600 = 600
    case seconds900 = 900
    case seconds1200 = 1_200

    var id: Int { rawValue }

    var seconds: Float {
        Float(rawValue)
    }

    var displayName: String {
        String.localizedStringWithFormat(
            String(localized: L10n.MOSSLocal.decoderSegmentDurationSecondsFormat),
            rawValue
        )
    }

    static var selected: MOSSDecoderSegmentDuration {
        guard let storedValue = UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber else {
            return defaultValue
        }
        return MOSSDecoderSegmentDuration(rawValue: storedValue.intValue) ?? defaultValue
    }

    static var mobileOptions: [MOSSDecoderSegmentDuration] {
        allCases.filter { $0.rawValue <= MOSSDecoderSegmentDuration.seconds300.rawValue }
    }
}

enum MOSSDecoderMaximumOutputTokens: Int, CaseIterable, Identifiable {
    static let defaultsKey = "moss_local.decoder_maximum_output_tokens"
    static let defaultValue = MOSSDecoderMaximumOutputTokens.tokens2048

    case tokens1024 = 1_024
    case tokens2048 = 2_048
    case tokens4096 = 4_096
    case tokens8192 = 8_192

    var id: Int { rawValue }

    var displayName: String {
        String.localizedStringWithFormat(
            String(localized: L10n.MOSSLocal.decoderMaximumOutputTokensFormat),
            rawValue
        )
    }

    static var selected: MOSSDecoderMaximumOutputTokens {
        guard let storedValue = UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber else {
            return defaultValue
        }
        return MOSSDecoderMaximumOutputTokens(rawValue: storedValue.intValue) ?? defaultValue
    }
}

struct MOSSDecoderDeviceRecommendation: Equatable {
    let duration: MOSSDecoderSegmentDuration
    let physicalMemoryBytes: UInt64

    static var current: MOSSDecoderDeviceRecommendation {
        let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
        return MOSSDecoderDeviceRecommendation(
            duration: recommendedDuration(forPhysicalMemoryBytes: physicalMemoryBytes),
            physicalMemoryBytes: physicalMemoryBytes
        )
    }

    static func recommendedDuration(forPhysicalMemoryBytes byteCount: UInt64) -> MOSSDecoderSegmentDuration {
        let gibibyte: UInt64 = 1_073_741_824
        switch byteCount {
        case ..<(5 * gibibyte):
            return .seconds30
        case ..<(7 * gibibyte):
            return .seconds90
        case ..<(10 * gibibyte):
            return .seconds120
        default:
            return .seconds180
        }
    }

    var physicalMemoryText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(clamping: physicalMemoryBytes),
            countStyle: .memory
        )
    }
}

enum MOSSLocalModelManager {
    static let modelID = "vanch007/mlx-MOSS-Transcribe-Diarize-4bit"

    // Sizes are pinned to the repository revision used by the bundled MLX
    // implementation. Exact sizes also let us reject interrupted downloads.
    private static let requiredFileSizes: [String: Int64] = [
        "added_tokens.json": 707,
        "chat_template.jinja": 4_762,
        "config.json": 2_543,
        "generation_config.json": 107,
        "merges.txt": 1_671_853,
        "mlx_conversion.json": 339,
        "model.safetensors": 960_434_705,
        "preprocessor_config.json": 315,
        "processor_config.json": 292,
        "special_tokens_map.json": 613,
        "tokenizer.json": 11_423_222,
        "tokenizer_config.json": 474,
        "vocab.json": 2_776_833,
    ]

    static let expectedByteCount = requiredFileSizes.values.reduce(Int64(0), +)

    static var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedByteCount, countStyle: .file)
    }

    static func currentStatus() -> MOSSLocalModelStatus {
        guard let directory = try? modelDirectory() else {
            return MOSSLocalModelStatus(isAvailable: false, hasStoredFiles: false, byteCount: nil)
        }

        let byteCount = recursiveByteCount(at: directory)
        return MOSSLocalModelStatus(
            isAvailable: requiredFilesAreComplete(in: directory),
            hasStoredFiles: byteCount > 0,
            byteCount: byteCount > 0 ? byteCount : nil
        )
    }

    static func download(
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> MOSSLocalModelStatus {
        let directory = try modelDirectory()
        let files = requiredFileSizes.keys.sorted { lhs, rhs in
            if lhs == "model.safetensors" { return false }
            if rhs == "model.safetensors" { return true }
            return lhs < rhs
        }

        progressHandler(0)
        try await HuggingFaceDownloader.downloadFilesByteWeighted(
            modelId: modelID,
            to: directory,
            files: files,
            expectedSizes: requiredFileSizes
        ) { progress, _, _, _ in
            progressHandler(min(max(progress, 0), 1))
        }

        let status = currentStatus()
        guard status.isAvailable else {
            throw MOSSLocalTranscriptionError.incompleteModelDownload
        }
        progressHandler(1)
        return status
    }

    static func deleteDownloadedModel() throws -> MOSSLocalModelStatus {
        let root = try modelRootDirectory(createIfNeeded: false)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return currentStatus()
        }

        try FileManager.default.removeItem(at: root)
        Task {
            await MOSSLocalRuntime.shared.unloadModel()
        }
        return currentStatus()
    }

    static func modelDirectory() throws -> URL {
        try HuggingFaceDownloader.getCacheDirectory(
            for: modelID,
            basePath: modelRootDirectory(createIfNeeded: true),
            cacheDirName: "MOSSLocal"
        )
    }

    private static func modelRootDirectory(createIfNeeded: Bool) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw MOSSLocalTranscriptionError.modelStorageUnavailable
        }

        let root = applicationSupport
            .appendingPathComponent("LiveTranscriber", isDirectory: true)
            .appendingPathComponent("MOSSLocal", isDirectory: true)

        if createIfNeeded {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var excludedRoot = root
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? excludedRoot.setResourceValues(resourceValues)
        }
        return root
    }

    private static func requiredFilesAreComplete(in directory: URL) -> Bool {
        requiredFileSizes.allSatisfy { fileName, expectedSize in
            let fileURL = directory.appendingPathComponent(fileName)
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && Int64(values.fileSize ?? 0) == expectedSize
        }
    }

    private static func recursiveByteCount(at directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

struct MOSSLocalTranscriptionResult: Sendable {
    let lines: [TranscriptionLine]
    let diarization: RecordingSpeakerDiarization
}

enum MOSSLocalTranscriptionService {
    static func transcribe(
        audioURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> MOSSLocalTranscriptionResult {
        guard MOSSLocalModelManager.currentStatus().isAvailable else {
            throw MOSSLocalTranscriptionError.missingModel
        }

        return try await MOSSLocalRuntime.shared.transcribe(
            audioURL: audioURL,
            progressHandler: progressHandler
        )
    }
}

struct MOSSRecordingTranscriber: RecordingTranscribing {
    let identifier = "moss.local"

    func transcribe(
        _ request: RecordingTranscriptionRequest,
        progressHandler: @escaping @Sendable (RecordingTranscriptionProgress) -> Void
    ) async throws -> RecordingTranscriptionResult {
        let result = try await MOSSLocalTranscriptionService.transcribe(
            audioURL: request.sourceURL
        ) { fractionCompleted in
            progressHandler(
                RecordingTranscriptionProgress(
                    fractionCompleted: fractionCompleted,
                    stage: .transcribing
                )
            )
        }
        return RecordingTranscriptionResult(
            lines: result.lines,
            speakerDiarization: result.diarization
        )
    }
}

private actor MOSSLocalRuntime {
    static let shared = MOSSLocalRuntime()

    private static let sampleRate = 16_000

    private var loadedModel: MossTranscribeDiarizeModel?

    func transcribe(
        audioURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> MOSSLocalTranscriptionResult {
        defer {
            loadedModel = nil
        }

        progressHandler(0.02)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: Self.sampleRate)
        guard audio.size > 0 else {
            throw MOSSLocalTranscriptionError.emptyAudio
        }

        let durationSeconds = Double(audio.size) / Double(Self.sampleRate)
        progressHandler(0.1)

        let directory = try MOSSLocalModelManager.modelDirectory()
        let model = try await MossTranscribeDiarizeModel.fromModelDirectory(directory)
        loadedModel = model
        progressHandler(0.28)

        // Capture the preference once so changing Settings cannot alter the
        // segmentation of a transcription that is already running.
        let decoderSegmentDuration = MOSSDecoderSegmentDuration.selected
        let decoderMaximumOutputTokens = MOSSDecoderMaximumOutputTokens.selected
        let chunkDuration = decoderSegmentDuration.seconds

        let parameters = STTGenerateParameters(
            maxTokens: decoderMaximumOutputTokens.rawValue,
            temperature: 0,
            topP: 1,
            topK: 0,
            verbose: false,
            language: nil,
            chunkDuration: chunkDuration,
            minChunkDuration: 0,
            repetitionPenalty: 1,
            repetitionContextSize: 100
        )

        let estimatedChunkCount = max(1, Int(ceil(durationSeconds / Double(chunkDuration))))
        var completedChunkCount = 0
        var finalOutput: STTOutput?

        for try await event in model.generateStream(audio: audio, generationParameters: parameters) {
            try Task.checkCancellation()
            switch event {
            case .token:
                break
            case .info:
                completedChunkCount = min(completedChunkCount + 1, estimatedChunkCount)
                progressHandler(0.28 + (Double(completedChunkCount) / Double(estimatedChunkCount)) * 0.68)
            case .result(let output):
                finalOutput = output
            }
        }

        guard let finalOutput else {
            throw MOSSLocalTranscriptionError.emptyTranscript
        }
        let result = try Self.makeResult(from: finalOutput, durationSeconds: durationSeconds)
        progressHandler(1)
        return result
    }

    func unloadModel() {
        loadedModel = nil
    }

    private static func makeResult(
        from output: STTOutput,
        durationSeconds: Double
    ) throws -> MOSSLocalTranscriptionResult {
        let rawSegments = output.segments ?? []
        var parsedSegments = rawSegments.compactMap { item -> ParsedSegment? in
            let start = numericValue(item["start"])
            let end = numericValue(item["end"])
            let rawText = item["text"] as? String ?? ""
            let speaker = (item["speaker_id"] as? String) ?? speakerLabel(in: rawText)
            let text = strippingSpeakerLabel(from: rawText)

            guard let start,
                  start.isFinite,
                  !text.isEmpty else {
                return nil
            }
            return ParsedSegment(
                start: start,
                end: end?.isFinite == true ? end : nil,
                rawSpeaker: speaker,
                text: text
            )
        }

        if parsedSegments.isEmpty {
            parsedSegments = parseTaggedTranscript(output.text)
        }
        guard !parsedSegments.isEmpty else {
            throw MOSSLocalTranscriptionError.emptyTranscript
        }

        parsedSegments.sort {
            if $0.start == $1.start { return ($0.end ?? $0.start) < ($1.end ?? $1.start) }
            return $0.start < $1.start
        }

        var speakerNames: [String: String] = [:]
        var lines: [TranscriptionLine] = []
        var diarizationSegments: [RecordingSpeakerSegment] = []
        lines.reserveCapacity(parsedSegments.count)
        diarizationSegments.reserveCapacity(parsedSegments.count)

        for segment in parsedSegments {
            let maximumStart = max(durationSeconds - 0.01, 0)
            let start = min(max(segment.start, 0), maximumStart)
            let end = min(max(segment.end ?? start, start), durationSeconds)
            let speaker = segment.rawSpeaker.map { rawSpeaker in
                let key = rawSpeaker.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                if let existing = speakerNames[key] {
                    return existing
                }
                let name = "Speaker \(speakerNames.count)"
                speakerNames[key] = name
                return name
            }
            let lineText = speaker.map { "\($0): \(segment.text)" } ?? segment.text

            lines.append(
                TranscriptionLine(startSeconds: start, text: lineText, isFinal: true)
            )
            diarizationSegments.append(
                RecordingSpeakerSegment(
                    startSeconds: start,
                    endSeconds: end,
                    speaker: speaker,
                    text: segment.text
                )
            )
        }

        return MOSSLocalTranscriptionResult(
            lines: lines,
            diarization: RecordingSpeakerDiarization(
                segments: diarizationSegments,
                generatedAt: Date(),
                provider: "mossLocal",
                model: MOSSLocalModelManager.modelID,
                schemaVersion: 1
            )
        )
    }

    private static func parseTaggedTranscript(_ text: String) -> [ParsedSegment] {
        let pattern = #"\[(\d+(?:[\.,]\d+)?)\]\[(S\d+)\](.*?)\[(\d+(?:[\.,]\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let source = text as NSString
        return regex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        ).compactMap { match in
            guard match.numberOfRanges == 5,
                  let start = timestampValue(source.substring(with: match.range(at: 1))),
                  let end = timestampValue(source.substring(with: match.range(at: 4))) else {
                return nil
            }
            let spokenText = source.substring(with: match.range(at: 3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spokenText.isEmpty else { return nil }
            return ParsedSegment(
                start: start,
                end: end,
                rawSpeaker: source.substring(with: match.range(at: 2)),
                text: spokenText
            )
        }
    }

    private static func speakerLabel(in text: String) -> String? {
        let pattern = #"^\s*\[(S\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(location: 0, length: (text as NSString).length)
              ),
              match.numberOfRanges == 2 else {
            return nil
        }
        return (text as NSString).substring(with: match.range(at: 1))
    }

    private static func strippingSpeakerLabel(from text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*\[?S\d+\]?\s*[:：-]?\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timestampValue(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private struct ParsedSegment {
        let start: Double
        let end: Double?
        let rawSpeaker: String?
        let text: String
    }
}

private enum MOSSLocalTranscriptionError: LocalizedError {
    case missingModel
    case incompleteModelDownload
    case modelStorageUnavailable
    case emptyAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return String(localized: L10n.MOSSLocal.modelRequired)
        case .incompleteModelDownload:
            return String(localized: L10n.MOSSLocal.incompleteDownload)
        case .modelStorageUnavailable:
            return String(localized: L10n.MOSSLocal.storageUnavailable)
        case .emptyAudio:
            return String(localized: L10n.MOSSLocal.emptyAudio)
        case .emptyTranscript:
            return String(localized: L10n.MOSSLocal.emptyTranscript)
        }
    }
}
