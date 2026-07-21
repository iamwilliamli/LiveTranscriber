import AudioCommon
import Foundation
@preconcurrency import Qwen3ASR
@preconcurrency import SpeechVAD
import TranscriberDomain

struct Qwen3ASRModelStatus: Equatable {
    let isAvailable: Bool
    let hasStoredFiles: Bool
    let byteCount: Int64?

    var statusText: String {
        String(localized: isAvailable ? L10n.Qwen3ASR.modelReady : L10n.Qwen3ASR.modelNotInstalled)
    }

    var detailText: String {
        if isAvailable, let byteCount {
            return String(
                format: String(localized: L10n.Qwen3ASR.modelDownloadedDetailFormat),
                ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            )
        }

        if hasStoredFiles, let byteCount {
            return String(
                format: String(localized: L10n.Qwen3ASR.partialDownloadDetailFormat),
                ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            )
        }

        return String(
            format: String(localized: L10n.Qwen3ASR.modelMissingDetailFormat),
            Qwen3ASRModelManager.expectedSizeText
        )
    }
}

enum Qwen3ASRDeveloperConfiguration {
    static let streamingLongAudioDefaultsKey = "qwen3ASR.developer.streamingLongAudioEnabled"

    /// Defaults to false when the preference has never been written.
    static var isStreamingLongAudioEnabled: Bool {
        UserDefaults.standard.bool(forKey: streamingLongAudioDefaultsKey)
    }
}

enum Qwen3ASRModelManager {
    static let modelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    static let vadModelID = "aufklarer/Silero-VAD-v6.2.1-MLX"
    static let expectedByteCount: Int64 = 708 * 1_024 * 1_024

    static var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedByteCount, countStyle: .file)
    }

    static func currentStatus() -> Qwen3ASRModelStatus {
        guard let asrDirectory = try? modelDirectory(for: modelID),
              let vadDirectory = try? modelDirectory(for: vadModelID) else {
            return Qwen3ASRModelStatus(isAvailable: false, hasStoredFiles: false, byteCount: nil)
        }

        let byteCount = recursiveByteCount(at: asrDirectory) + recursiveByteCount(at: vadDirectory)
        return Qwen3ASRModelStatus(
            isAvailable: requiredASRFilesExist(in: asrDirectory) && requiredVADFilesExist(in: vadDirectory),
            hasStoredFiles: byteCount > 0,
            byteCount: byteCount > 0 ? byteCount : nil
        )
    }

    static func download(
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Qwen3ASRModelStatus {
        let asrDirectory = try modelDirectory(for: modelID)
        let vadDirectory = try modelDirectory(for: vadModelID)

        progressHandler(0)
        try await HuggingFaceDownloader.downloadWeights(
            modelId: modelID,
            to: asrDirectory,
            additionalFiles: ["vocab.json", "merges.txt", "tokenizer_config.json"]
        ) { progress in
            progressHandler(min(max(progress, 0), 1) * 0.98)
        }

        try await HuggingFaceDownloader.downloadWeights(
            modelId: vadModelID,
            to: vadDirectory
        ) { progress in
            progressHandler(0.98 + min(max(progress, 0), 1) * 0.02)
        }

        let status = currentStatus()
        guard status.isAvailable else {
            throw Qwen3ASRTranscriptionError.incompleteModelDownload
        }
        progressHandler(1)
        return status
    }

    static func deleteDownloadedModel() throws -> Qwen3ASRModelStatus {
        let root = try modelRootDirectory(createIfNeeded: false)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return currentStatus()
        }

        try FileManager.default.removeItem(at: root)
        return currentStatus()
    }

    static func modelDirectory(for modelID: String) throws -> URL {
        try HuggingFaceDownloader.getCacheDirectory(
            for: modelID,
            basePath: modelRootDirectory(createIfNeeded: true)
        )
    }

    private static func modelRootDirectory(createIfNeeded: Bool) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw Qwen3ASRTranscriptionError.modelStorageUnavailable
        }

        let root = applicationSupport
            .appendingPathComponent("LiveTranscriber", isDirectory: true)
            .appendingPathComponent("Qwen3ASR", isDirectory: true)

        if createIfNeeded {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var excludedRoot = root
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? excludedRoot.setResourceValues(resourceValues)
        }
        return root
    }

    private static func requiredASRFilesExist(in directory: URL) -> Bool {
        requiredFilesExist(
            in: directory,
            fileNames: ["config.json", "vocab.json", "merges.txt"]
        )
    }

    private static func requiredVADFilesExist(in directory: URL) -> Bool {
        requiredFilesExist(in: directory, fileNames: ["config.json"])
    }

    private static func requiredFilesExist(in directory: URL, fileNames: [String]) -> Bool {
        let fileManager = FileManager.default
        guard HuggingFaceDownloader.weightsExist(in: directory) else {
            return false
        }
        return fileNames.allSatisfy { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
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

enum Qwen3ASRTranscriptionService {
    static func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [TranscriptionLine] {
        guard Qwen3ASRModelManager.currentStatus().isAvailable else {
            throw Qwen3ASRTranscriptionError.missingModel
        }

        let languageCode = languageCode(for: language)
        let lines: [TranscriptionLine]

        if Qwen3ASRDeveloperConfiguration.isStreamingLongAudioEnabled {
            progressHandler(0.03)
            lines = try await Qwen3ASRRuntime.shared.transcribeStreaming(
                audioURL: audioURL,
                languageCode: languageCode
            ) { progress in
                progressHandler(0.03 + min(max(progress, 0), 1) * 0.92)
            }
        } else {
            progressHandler(0.03)
            let samples = try await Task.detached(priority: .userInitiated) {
                try LocalWhisperAudioConverter.floatPCM16kMonoSamples(from: audioURL)
            }.value

            guard !samples.isEmpty else {
                throw Qwen3ASRTranscriptionError.emptyAudio
            }

            progressHandler(0.12)
            lines = try await Qwen3ASRRuntime.shared.transcribe(
                samples: samples,
                languageCode: languageCode
            ) { progress in
                progressHandler(0.12 + min(max(progress, 0), 1) * 0.83)
            }
        }

        guard !lines.isEmpty else {
            throw Qwen3ASRTranscriptionError.emptyTranscript
        }
        progressHandler(1)
        return lines
    }

    private static func languageCode(for language: TranscriptionLanguage) -> String? {
        if let code = language.locale.language.languageCode?.identifier,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code
        }

        let normalizedIdentifier = language.id.replacingOccurrences(of: "_", with: "-")
        return normalizedIdentifier.split(separator: "-").first.map(String.init)
    }
}

private actor Qwen3ASRRuntime {
    static let shared = Qwen3ASRRuntime()

    private static let sampleRate = 16_000
    private static let maximumChunkDuration: Double = 10
    private static let boundaryPadding: Double = 0.12
    private static let streamingPCMWindowDuration: TimeInterval = 30
    private static let streamingRecentAudioDuration: Double = 2

    private static var maximumChunkSampleCount: Int {
        Int(maximumChunkDuration * Double(sampleRate))
    }

    private static var boundaryPaddingSampleCount: Int {
        Int((boundaryPadding * Double(sampleRate)).rounded())
    }

    private static var streamingRecentAudioSampleCount: Int {
        Int(streamingRecentAudioDuration * Double(sampleRate))
    }

    private var asrModel: Qwen3ASRModel?
    private var vadModel: SileroVADModel?

    func transcribe(
        samples: [Float],
        languageCode: String?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionLine] {
        defer { unloadModels() }

        let (loadedASR, loadedVAD) = try await loadModels(progressHandler: progressHandler)

        progressHandler(0.31)
        let speechSegments = loadedVAD.detectSpeech(
            audio: samples,
            sampleRate: Self.sampleRate,
            config: .sileroDefault
        )
        let chunks = makeChunks(
            speechSegments: speechSegments,
            sampleCount: samples.count
        )

        guard !chunks.isEmpty else {
            throw Qwen3ASRTranscriptionError.emptyTranscript
        }

        var lines: [TranscriptionLine] = []
        lines.reserveCapacity(chunks.count)

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let chunkSamples = Array(samples[chunk.sampleRange])
            let text = loadedASR.transcribe(
                audio: chunkSamples,
                sampleRate: Self.sampleRate,
                language: languageCode,
                maxTokens: 448
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                lines.append(
                    TranscriptionLine(
                        startSeconds: chunk.startSeconds,
                        text: text,
                        isFinal: true
                    )
                )
            }

            let completedFraction = Double(index + 1) / Double(chunks.count)
            progressHandler(0.31 + completedFraction * 0.69)
        }

        return lines
    }

    func transcribeStreaming(
        audioURL: URL,
        languageCode: String?,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranscriptionLine] {
        defer { unloadModels() }

        let (loadedASR, loadedVAD) = try await loadModels(progressHandler: progressHandler)
        loadedVAD.resetState()
        let vadProcessor = StreamingVADProcessor(model: loadedVAD, config: .sileroDefault)
        var audioState = Qwen3ASRStreamingAudioState()
        var lines: [TranscriptionLine] = []

        func transcribe(_ span: Qwen3ASRStreamingAudioSpan) throws {
            try Task.checkCancellation()
            let text = loadedASR.transcribe(
                audio: span.samples,
                sampleRate: Self.sampleRate,
                language: languageCode,
                maxTokens: 448
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                lines.append(
                    TranscriptionLine(
                        startSeconds: Double(span.startSample) / Double(Self.sampleRate),
                        text: text,
                        isFinal: true
                    )
                )
            }
        }

        func transcribeInBoundedChunks(_ span: Qwen3ASRStreamingAudioSpan) throws {
            var offset = 0
            while offset < span.samples.count {
                let end = min(offset + Self.maximumChunkSampleCount, span.samples.count)
                try transcribe(
                    Qwen3ASRStreamingAudioSpan(
                        startSample: span.startSample + offset,
                        samples: Array(span.samples[offset..<end])
                    )
                )
                offset = end
            }
        }

        func handle(_ events: [VADEvent]) throws {
            for event in events {
                switch event {
                case .speechStarted(let time):
                    let detectedStart = Int((Double(time) * Double(Self.sampleRate)).rounded(.down))
                    audioState.beginSpeech(
                        at: max(detectedStart - Self.boundaryPaddingSampleCount, 0)
                    )

                case .speechEnded(let segment):
                    let detectedEnd = Int((Double(segment.endTime) * Double(Self.sampleRate)).rounded(.up))
                    if let finalSpan = audioState.finishSpeech(
                        at: detectedEnd + Self.boundaryPaddingSampleCount
                    ) {
                        try transcribeInBoundedChunks(finalSpan)
                    }
                }
            }
        }

        progressHandler(0.31)
        try LocalWhisperAudioConverter.forEachFloatPCM16kMonoWindow(
            from: audioURL,
            windowDuration: Self.streamingPCMWindowDuration
        ) { window, completedSampleCount, estimatedTotalSampleCount in
            var offset = 0
            while offset < window.count {
                try Task.checkCancellation()
                let end = min(offset + SileroVADModel.chunkSize, window.count)
                let vadChunk = Array(window[offset..<end])
                audioState.append(vadChunk)
                try handle(vadProcessor.process(samples: vadChunk))

                while let fullSpan = audioState.popFullChunk(
                    sampleCount: Self.maximumChunkSampleCount
                ) {
                    try transcribe(fullSpan)
                }
                offset = end
            }

            audioState.trimRecentAudio(keepingLast: Self.streamingRecentAudioSampleCount)
            let totalForProgress = max(estimatedTotalSampleCount, completedSampleCount, 1)
            let completedFraction = min(
                Double(completedSampleCount) / Double(totalForProgress),
                1
            )
            progressHandler(0.31 + completedFraction * 0.66)
        }

        guard audioState.totalSampleCount > 0 else {
            throw Qwen3ASRTranscriptionError.emptyAudio
        }

        try handle(vadProcessor.flush())
        if let remainingSpan = audioState.finishSpeech(at: audioState.totalSampleCount) {
            try transcribeInBoundedChunks(remainingSpan)
        }
        progressHandler(1)
        return lines
    }

    private func loadModels(
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> (Qwen3ASRModel, SileroVADModel) {
        progressHandler(0.02)
        let asrDirectory = try Qwen3ASRModelManager.modelDirectory(for: Qwen3ASRModelManager.modelID)
        let vadDirectory = try Qwen3ASRModelManager.modelDirectory(for: Qwen3ASRModelManager.vadModelID)

        let loadedASR = try await Qwen3ASRModel.fromPretrained(
            modelId: Qwen3ASRModelManager.modelID,
            cacheDir: asrDirectory,
            offlineMode: true
        ) { progress, _ in
            progressHandler(0.02 + min(max(progress, 0), 1) * 0.23)
        }
        asrModel = loadedASR

        let loadedVAD = try await SileroVADModel.fromPretrained(
            modelId: Qwen3ASRModelManager.vadModelID,
            cacheDir: vadDirectory,
            offlineMode: true
        ) { progress, _ in
            progressHandler(0.25 + min(max(progress, 0), 1) * 0.05)
        }
        vadModel = loadedVAD
        return (loadedASR, loadedVAD)
    }

    private func unloadModels() {
        asrModel?.unload()
        vadModel?.unload()
        asrModel = nil
        vadModel = nil
    }

    private func makeChunks(
        speechSegments: [SpeechSegment],
        sampleCount: Int
    ) -> [AudioChunk] {
        let audioDuration = Double(sampleCount) / Double(Self.sampleRate)
        var paddedSegments: [(start: Double, end: Double)] = []

        for segment in speechSegments {
            let start = max(Double(segment.startTime) - Self.boundaryPadding, 0)
            let end = min(Double(segment.endTime) + Self.boundaryPadding, audioDuration)
            guard end > start else {
                continue
            }

            if let last = paddedSegments.last, start <= last.end {
                paddedSegments[paddedSegments.count - 1].end = max(last.end, end)
            } else {
                paddedSegments.append((start: start, end: end))
            }
        }

        var chunks: [AudioChunk] = []

        for segment in paddedSegments {
            var start = segment.start

            while start < segment.end {
                let end = min(start + Self.maximumChunkDuration, segment.end)
                let startSample = min(max(Int((start * Double(Self.sampleRate)).rounded(.down)), 0), sampleCount)
                let endSample = min(max(Int((end * Double(Self.sampleRate)).rounded(.up)), startSample), sampleCount)
                if endSample > startSample {
                    chunks.append(
                        AudioChunk(
                            startSeconds: Double(startSample) / Double(Self.sampleRate),
                            sampleRange: startSample..<endSample
                        )
                    )
                }
                start = end
            }
        }

        return chunks
    }
}

private struct AudioChunk: Sendable {
    let startSeconds: Double
    let sampleRange: Range<Int>
}

private struct Qwen3ASRStreamingAudioSpan {
    let startSample: Int
    let samples: [Float]
}

private struct Qwen3ASRStreamingAudioState {
    private(set) var totalSampleCount = 0
    private var recentStartSample = 0
    private var recentSamples: [Float] = []
    private var activeStartSample: Int?
    private var activeSamples: [Float] = []

    mutating func append(_ samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        recentSamples.append(contentsOf: samples)
        if activeStartSample != nil {
            activeSamples.append(contentsOf: samples)
        }
        totalSampleCount += samples.count
    }

    mutating func beginSpeech(at requestedStartSample: Int) {
        guard activeStartSample == nil else {
            return
        }

        let startSample = min(
            max(requestedStartSample, recentStartSample),
            totalSampleCount
        )
        activeStartSample = startSample
        let recentOffset = min(max(startSample - recentStartSample, 0), recentSamples.count)
        activeSamples = Array(recentSamples[recentOffset...])
    }

    mutating func popFullChunk(sampleCount: Int) -> Qwen3ASRStreamingAudioSpan? {
        guard sampleCount > 0,
              let startSample = activeStartSample,
              activeSamples.count >= sampleCount else {
            return nil
        }

        let span = Qwen3ASRStreamingAudioSpan(
            startSample: startSample,
            samples: Array(activeSamples.prefix(sampleCount))
        )
        activeSamples.removeFirst(sampleCount)
        activeStartSample = startSample + sampleCount
        return span
    }

    mutating func finishSpeech(at requestedEndSample: Int) -> Qwen3ASRStreamingAudioSpan? {
        guard let startSample = activeStartSample else {
            return nil
        }

        let endSample = min(max(requestedEndSample, startSample), totalSampleCount)
        let desiredSampleCount = min(max(endSample - startSample, 0), activeSamples.count)
        let samples = Array(activeSamples.prefix(desiredSampleCount))
        activeStartSample = nil
        activeSamples.removeAll(keepingCapacity: true)

        guard !samples.isEmpty else {
            return nil
        }
        return Qwen3ASRStreamingAudioSpan(startSample: startSample, samples: samples)
    }

    mutating func trimRecentAudio(keepingLast sampleCount: Int) {
        let excessSampleCount = max(recentSamples.count - max(sampleCount, 0), 0)
        guard excessSampleCount > 0 else {
            return
        }
        recentSamples.removeFirst(excessSampleCount)
        recentStartSample += excessSampleCount
    }
}

private enum Qwen3ASRTranscriptionError: LocalizedError {
    case missingModel
    case incompleteModelDownload
    case modelStorageUnavailable
    case emptyAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return String(localized: L10n.Qwen3ASR.modelRequired)
        case .incompleteModelDownload:
            return String(localized: L10n.Qwen3ASR.incompleteDownload)
        case .modelStorageUnavailable:
            return String(localized: L10n.Qwen3ASR.storageUnavailable)
        case .emptyAudio:
            return String(localized: L10n.Qwen3ASR.emptyAudio)
        case .emptyTranscript:
            return String(localized: L10n.Qwen3ASR.emptyTranscript)
        }
    }
}
