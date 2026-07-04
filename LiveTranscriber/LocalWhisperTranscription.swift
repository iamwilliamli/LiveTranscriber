import AVFoundation
import Foundation

enum LocalWhisperTranscriptionService {
    static let availableModels: [LocalWhisperModel] = [
        LocalWhisperModel(
            id: "tiny",
            displayName: "Tiny Multilingual",
            detail: "Fastest, lowest accuracy, supports multiple languages.",
            fileName: "ggml-tiny.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            expectedByteCount: 75 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "tiny.en",
            displayName: "Tiny English",
            detail: "Fastest English-only model.",
            fileName: "ggml-tiny.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            expectedByteCount: 75 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "base",
            displayName: "Base Multilingual",
            detail: "Recommended balance for offline transcription.",
            fileName: "ggml-base.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            expectedByteCount: 147_951_465
        ),
        LocalWhisperModel(
            id: "base.en",
            displayName: "Base English",
            detail: "Recommended balance for English-only transcription.",
            fileName: "ggml-base.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            expectedByteCount: 142 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "small",
            displayName: "Small Multilingual",
            detail: "Better quality, slower and larger.",
            fileName: "ggml-small.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            expectedByteCount: 466 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "small.en",
            displayName: "Small English",
            detail: "Better quality for English-only transcription.",
            fileName: "ggml-small.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            expectedByteCount: 466 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "medium",
            displayName: "Medium Multilingual",
            detail: "High quality, much slower and requires significantly more storage.",
            fileName: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            expectedByteCount: 1_500 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "medium.en",
            displayName: "Medium English",
            detail: "High quality for English-only transcription.",
            fileName: "ggml-medium.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            expectedByteCount: 1_500 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3-turbo-q5_0",
            displayName: "Large v3 Turbo Q5",
            detail: "Large turbo model with quantization; stronger quality with lower storage than full large.",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
            expectedByteCount: 547 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3-q5_0",
            displayName: "Large v3 Q5",
            detail: "Largest quantized multilingual model; best quality option, heaviest runtime.",
            fileName: "ggml-large-v3-q5_0.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin")!,
            expectedByteCount: 1_100 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3",
            displayName: "Large v3",
            detail: "Full large multilingual model; very large download and memory use.",
            fileName: "ggml-large-v3.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            expectedByteCount: 2_900 * 1_024 * 1_024
        )
    ]

    static let defaultModel = LocalWhisperModel(
        id: "base",
        displayName: "Base Multilingual",
        detail: "Recommended balance for offline transcription.",
        fileName: "ggml-base.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
        expectedByteCount: 147_951_465
    )

    static var modelFileNamesForLookup: [String] {
        availableModels.map(\.fileName)
    }

    static func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [TranscriptionLine] {
        progressHandler(0.05)
        let modelURL = try modelURL()
        progressHandler(0.1)

        let samples = try await Task.detached(priority: .userInitiated) {
            try LocalWhisperAudioConverter.floatPCM16kMonoSamples(from: audioURL)
        }.value

        guard !samples.isEmpty else {
            throw LocalWhisperTranscriptionError.emptyAudio
        }

        progressHandler(0.25)
        let languageCode = whisperLanguageCode(for: language)
        let lines = try await Task.detached(priority: .userInitiated) {
            try transcribeWithWhisperBridge(
                samples: samples,
                modelURL: modelURL,
                languageCode: languageCode
            )
        }.value

        progressHandler(0.95)
        guard !lines.isEmpty else {
            throw LocalWhisperTranscriptionError.emptyTranscript
        }
        progressHandler(1)
        return lines
    }

    static func modelURL() throws -> URL {
        let selectedModel = LocalWhisperModelManager.selectedModel
        if let locatedModel = try LocalWhisperModelManager.locatedModel(for: selectedModel) {
            return locatedModel.url
        }

        throw LocalWhisperTranscriptionError.missingModel
    }

    private static func whisperLanguageCode(for language: TranscriptionLanguage) -> String {
        if let code = language.locale.language.languageCode?.identifier,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code
        }

        let normalizedIdentifier = language.id.replacingOccurrences(of: "_", with: "-")
        if let code = normalizedIdentifier.split(separator: "-").first {
            return String(code)
        }
        return "auto"
    }
}

struct LocalWhisperModel: Identifiable, Equatable {
    var id: String
    var displayName: String
    var detail: String
    var fileName: String
    var downloadURL: URL
    var expectedByteCount: Int64

    var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedByteCount, countStyle: .file)
    }
}

struct LocalWhisperModelStatus: Equatable {
    enum Location: Equatable {
        case applicationSupport
        case bundle
        case missing
    }

    var location: Location
    var model: LocalWhisperModel
    var byteCount: Int64?

    var isAvailable: Bool {
        location != .missing
    }

    var isUserInstalled: Bool {
        location == .applicationSupport
    }

    var statusText: String {
        switch location {
        case .applicationSupport, .bundle:
            return String(localized: L10n.LocalWhisper.modelReady)
        case .missing:
            return String(localized: L10n.LocalWhisper.modelNotInstalled)
        }
    }

    var detailText: String {
        switch location {
        case .applicationSupport:
            let sizeText = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? String(localized: L10n.Common.unknown)
            return localizedFormat(L10n.LocalWhisper.modelDownloadedDetailFormat, model.displayName, sizeText)
        case .bundle:
            let sizeText = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? String(localized: L10n.Common.unknown)
            return localizedFormat(L10n.LocalWhisper.modelBundledDetailFormat, model.displayName, sizeText)
        case .missing:
            return localizedFormat(L10n.LocalWhisper.modelMissingDetailFormat, model.displayName, model.expectedSizeText)
        }
    }

    private func localizedFormat(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        String(format: String(localized: resource), arguments: arguments)
    }
}

enum LocalWhisperModelManager {
    private static let selectedModelIDDefaultsKey = "localWhisper.selectedModelID"

    static var availableModels: [LocalWhisperModel] {
        LocalWhisperTranscriptionService.availableModels
    }

    static var selectedModel: LocalWhisperModel {
        let storedID = UserDefaults.standard.string(forKey: selectedModelIDDefaultsKey)
        return model(withID: storedID) ?? LocalWhisperTranscriptionService.defaultModel
    }

    static func selectModel(_ model: LocalWhisperModel) {
        UserDefaults.standard.set(model.id, forKey: selectedModelIDDefaultsKey)
    }

    static func model(withID id: String?) -> LocalWhisperModel? {
        guard let id else {
            return nil
        }
        return availableModels.first { $0.id == id }
    }

    static func currentStatus() -> LocalWhisperModelStatus {
        status(for: selectedModel)
    }

    static func status(for model: LocalWhisperModel) -> LocalWhisperModelStatus {
        let fileManager = FileManager.default

        if let directory = try? modelDirectory() {
            let url = directory.appendingPathComponent(model.fileName)
            if fileManager.fileExists(atPath: url.path) {
                return LocalWhisperModelStatus(
                    location: .applicationSupport,
                    model: model,
                    byteCount: fileSize(at: url)
                )
            }
        }

        let bundleName = (model.fileName as NSString).deletingPathExtension
        let bundleExtension = (model.fileName as NSString).pathExtension
        if let url = Bundle.main.url(forResource: bundleName, withExtension: bundleExtension) {
            return LocalWhisperModelStatus(
                location: .bundle,
                model: model,
                byteCount: fileSize(at: url)
            )
        }

        return LocalWhisperModelStatus(location: .missing, model: model, byteCount: nil)
    }

    static func locatedModel(for model: LocalWhisperModel) throws -> (url: URL, status: LocalWhisperModelStatus)? {
        let fileManager = FileManager.default
        let directory = try modelDirectory()
        let userModelURL = directory.appendingPathComponent(model.fileName)
        if fileManager.fileExists(atPath: userModelURL.path) {
            return (userModelURL, status(for: model))
        }

        let bundleName = (model.fileName as NSString).deletingPathExtension
        let bundleExtension = (model.fileName as NSString).pathExtension
        if let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: bundleExtension) {
            return (bundleURL, status(for: model))
        }

        return nil
    }

    static func modelDirectory() throws -> URL {
        let fileManager = FileManager.default
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelDirectory = supportDirectory.appendingPathComponent("WhisperModels", isDirectory: true)
        if !fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }
        return modelDirectory
    }

    static func downloadSelectedModel(
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LocalWhisperModelStatus {
        try await download(model: selectedModel, progressHandler: progressHandler)
    }

    static func download(
        model: LocalWhisperModel,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LocalWhisperModelStatus {
        let directory = try modelDirectory()
        let destinationURL = directory.appendingPathComponent(model.fileName)
        let partialURL = destinationURL.appendingPathExtension("download")

        let downloadedURL = try await LocalWhisperModelDownloader.download(
            from: model.downloadURL,
            progressHandler: progressHandler
        )
        defer {
            try? FileManager.default.removeItem(at: downloadedURL)
            try? FileManager.default.removeItem(at: partialURL)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        try fileManager.moveItem(at: downloadedURL, to: partialURL)

        let minimumValidByteCount = max(model.expectedByteCount / 2, 1)
        guard fileSize(at: partialURL).map({ $0 >= minimumValidByteCount }) == true else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: partialURL, to: destinationURL)
        try? (destinationURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)

        progressHandler(1)
        return status(for: model)
    }

    static func deleteSelectedModel() throws -> LocalWhisperModelStatus {
        try deleteDownloadedModel(selectedModel)
    }

    static func deleteDownloadedModel(_ model: LocalWhisperModel) throws -> LocalWhisperModelStatus {
        let fileManager = FileManager.default
        let directory = try modelDirectory()
        let url = directory.appendingPathComponent(model.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let partialURL = url.appendingPathExtension("download")
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        return status(for: model)
    }

    private static func fileSize(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
    }
}

enum LocalWhisperTranscriptionError: LocalizedError {
    case runtimeUnavailable
    case missingSymbol(String)
    case missingModel
    case audioConversionFailed
    case emptyAudio
    case modelDownloadFailed
    case contextCreationFailed
    case transcriptionFailed
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return String(localized: L10n.LocalWhisper.runtimeUnavailable)
        case .missingSymbol(let symbol):
            return String(format: String(localized: L10n.LocalWhisper.missingSymbolFormat), symbol)
        case .missingModel:
            return String(localized: L10n.LocalWhisper.missingModel)
        case .audioConversionFailed:
            return String(localized: L10n.LocalWhisper.audioConversionFailed)
        case .emptyAudio:
            return String(localized: L10n.LocalWhisper.emptyAudio)
        case .modelDownloadFailed:
            return String(localized: L10n.LocalWhisper.modelDownloadFailed)
        case .contextCreationFailed:
            return String(localized: L10n.LocalWhisper.contextCreationFailed)
        case .transcriptionFailed:
            return String(localized: L10n.LocalWhisper.transcriptionFailed)
        case .emptyTranscript:
            return String(localized: L10n.Import.noRecognizedText)
        }
    }
}

private final class LocalWhisperModelDownloader: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadedTemporaryURL: URL?
    private var activeTask: URLSessionDownloadTask?
    private var session: URLSession?

    private init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    static func download(
        from url: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let downloader = LocalWhisperModelDownloader(progressHandler: progressHandler)
        return try await downloader.download(from: url)
    }

    private func download(from url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                let configuration = URLSessionConfiguration.default
                configuration.allowsExpensiveNetworkAccess = true
                configuration.allowsConstrainedNetworkAccess = true
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 30 * 60

                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let task = session.downloadTask(with: request)
                activeTask = task
                task.resume()
            }
        } onCancel: {
            activeTask?.cancel()
            session?.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            progressHandler(0)
            return
        }
        progressHandler(min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveTranscriber-Whisper-\(UUID().uuidString)")
            .appendingPathExtension("bin")

        do {
            try FileManager.default.copyItem(at: location, to: temporaryURL)
            downloadedTemporaryURL = temporaryURL
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        defer {
            self.session = nil
            activeTask = nil
            session.invalidateAndCancel()
        }

        guard let continuation else {
            return
        }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
            return
        }

        if let response = task.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            continuation.resume(throwing: LocalWhisperTranscriptionError.modelDownloadFailed)
            return
        }

        guard let downloadedTemporaryURL else {
            continuation.resume(throwing: LocalWhisperTranscriptionError.modelDownloadFailed)
            return
        }

        continuation.resume(returning: downloadedTemporaryURL)
    }
}

private enum LocalWhisperAudioConverter {
    private static let sampleRate: Double = 16_000
    private static let outputFrameCapacity: AVAudioFrameCount = 4096

    static func floatPCM16kMonoSamples(from audioURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let inputFormat = audioFile.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw LocalWhisperTranscriptionError.audioConversionFailed
        }

        var samples: [Float] = []
        if inputFormat.sampleRate > 0 {
            let estimatedFrameCount = Int((Double(audioFile.length) / inputFormat.sampleRate * sampleRate).rounded(.up))
            samples.reserveCapacity(max(estimatedFrameCount, 0))
        }

        var readError: Error?
        var didReachEndOfInput = false
        let inputBlock: AVAudioConverterInputBlock = { packetCount, status in
            guard readError == nil else {
                status.pointee = .noDataNow
                return nil
            }

            guard !didReachEndOfInput else {
                status.pointee = .endOfStream
                return nil
            }

            let remainingFrames = max(audioFile.length - audioFile.framePosition, 0)
            guard remainingFrames > 0 else {
                didReachEndOfInput = true
                status.pointee = .endOfStream
                return nil
            }

            let requestedFrames = AVAudioFrameCount(min(Int64(packetCount), remainingFrames))
            guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: requestedFrames) else {
                readError = LocalWhisperTranscriptionError.audioConversionFailed
                status.pointee = .noDataNow
                return nil
            }

            do {
                try audioFile.read(into: inputBuffer, frameCount: requestedFrames)
            } catch {
                readError = error
                status.pointee = .noDataNow
                return nil
            }

            if inputBuffer.frameLength == 0 {
                didReachEndOfInput = true
                status.pointee = .endOfStream
                return nil
            }

            status.pointee = .haveData
            return inputBuffer
        }

        var isFinished = false
        while !isFinished {
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity
            ) else {
                throw LocalWhisperTranscriptionError.audioConversionFailed
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError, withInputFrom: inputBlock)
            if let conversionError {
                throw conversionError
            }
            if let readError {
                throw readError
            }

            if outputBuffer.frameLength > 0,
               let channelData = outputBuffer.floatChannelData?[0] {
                let frameCount = Int(outputBuffer.frameLength)
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
            }

            switch status {
            case .haveData:
                break
            case .inputRanDry:
                isFinished = didReachEndOfInput
            case .endOfStream:
                isFinished = true
            case .error:
                throw LocalWhisperTranscriptionError.audioConversionFailed
            @unknown default:
                throw LocalWhisperTranscriptionError.audioConversionFailed
            }
        }

        return samples
    }
}

private func transcribeWithWhisperBridge(
    samples: [Float],
    modelURL: URL,
    languageCode: String
) throws -> [TranscriptionLine] {
    let sampleData = samples.withUnsafeBufferPointer { buffer -> Data in
        guard let baseAddress = buffer.baseAddress else {
            return Data()
        }
        return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.stride)
    }

    let segments = try LocalWhisperBridge.transcribeSamples(
        sampleData,
        modelPath: modelURL.path,
        languageCode: languageCode.isEmpty ? "auto" : languageCode
    )

    return segments.compactMap { segment in
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        return TranscriptionLine(
            startSeconds: max(segment.startSeconds, 0),
            text: text,
            isFinal: true
        )
    }
}
