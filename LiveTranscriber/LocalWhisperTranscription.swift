import AVFoundation
import Foundation
import zlib

enum LocalWhisperTranscriptionService {
    static let availableModels: [LocalWhisperModel] = [
        LocalWhisperModel(
            id: "tiny",
            fileName: "ggml-tiny.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            expectedByteCount: 75 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "tiny.en",
            fileName: "ggml-tiny.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            expectedByteCount: 75 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "base",
            fileName: "ggml-base.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            expectedByteCount: 147_951_465
        ),
        LocalWhisperModel(
            id: "base.en",
            fileName: "ggml-base.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            expectedByteCount: 142 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "small",
            fileName: "ggml-small.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            expectedByteCount: 466 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "small.en",
            fileName: "ggml-small.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            expectedByteCount: 466 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "medium",
            fileName: "ggml-medium.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            expectedByteCount: 1_500 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "medium.en",
            fileName: "ggml-medium.en.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            expectedByteCount: 1_500 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3-turbo-q5_0",
            fileName: "ggml-large-v3-turbo-q5_0.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin")!,
            expectedByteCount: 547 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3-q5_0",
            fileName: "ggml-large-v3-q5_0.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin")!,
            expectedByteCount: 1_100 * 1_024 * 1_024
        ),
        LocalWhisperModel(
            id: "large-v3",
            fileName: "ggml-large-v3.bin",
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            expectedByteCount: 2_900 * 1_024 * 1_024
        )
    ]

    static let defaultModel = LocalWhisperModel(
        id: "base",
        fileName: "ggml-base.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
        expectedByteCount: 147_951_465
    )

    static var modelFileNamesForLookup: [String] {
        availableModels.map(\.fileName)
    }

    static func supportedLanguages(for model: LocalWhisperModel) -> [TranscriptionLanguage] {
        if model.isEnglishOnly {
            return [TranscriptionLanguage(id: "en")]
        }

        return whisperMultilingualLanguageIDs
            .map { TranscriptionLanguage(id: $0) }
            .sorted { first, second in
                first.displayName.localizedCaseInsensitiveCompare(second.displayName) == .orderedAscending
            }
    }

    static func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        model: LocalWhisperModel? = nil,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [TranscriptionLine] {
        progressHandler(0.05)
        let modelURL = try modelURL(for: model ?? LocalWhisperModelManager.selectedModel)
        progressHandler(0.1)

        let samples = try await Task.detached(priority: .userInitiated) {
            try LocalWhisperAudioConverter.floatPCM16kMonoSamples(from: audioURL)
        }.value

        guard !samples.isEmpty else {
            throw LocalWhisperTranscriptionError.emptyAudio
        }

        progressHandler(0.25)
        let languageCode = languageCode(for: language)
        let lines = try await Task.detached(priority: .userInitiated) {
            try transcribeWithWhisperBridge(
                samples: samples,
                modelURL: modelURL,
                languageCode: languageCode
            ) { progress in
                progressHandler(0.25 + progress * 0.65)
            }
        }.value

        progressHandler(0.95)
        guard !lines.isEmpty else {
            throw LocalWhisperTranscriptionError.emptyTranscript
        }
        progressHandler(1)
        return lines
    }

    static func modelURL() throws -> URL {
        try modelURL(for: LocalWhisperModelManager.selectedModel)
    }

    static func modelURL(for model: LocalWhisperModel) throws -> URL {
        if let locatedModel = try LocalWhisperModelManager.locatedModel(for: model) {
            return locatedModel.url
        }

        throw LocalWhisperTranscriptionError.missingModel
    }

    static func languageCode(for language: TranscriptionLanguage) -> String {
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

    private static let whisperMultilingualLanguageIDs: [String] = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo",
        "br", "bs", "ca", "cs", "cy", "da", "de", "el", "en", "es",
        "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja",
        "jw", "ka", "kk", "km", "kn", "ko", "la", "lb", "ln", "lo",
        "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt",
        "ro", "ru", "sa", "sd", "si", "sk", "sl", "sn", "so", "sq",
        "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh"
    ]
}

struct LocalWhisperModel: Identifiable, Equatable {
    var id: String
    var fileName: String
    var downloadURL: URL
    var expectedByteCount: Int64

    var displayName: String {
        String(localized: displayNameResource)
    }

    var detail: String {
        String(localized: detailResource)
    }

    var isEnglishOnly: Bool {
        id.hasSuffix(".en")
    }

    var expectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedByteCount, countStyle: .file)
    }

    var coreMLEncoderDirectoryName: String {
        "\(coreMLEncoderModelStem)-encoder.mlmodelc"
    }

    var coreMLEncoderArchiveFileName: String {
        "\(coreMLEncoderDirectoryName).zip"
    }

    var coreMLEncoderDownloadURL: URL {
        Self.modelRepositoryBaseURL.appendingPathComponent(coreMLEncoderArchiveFileName)
    }

    var expectedCoreMLEncoderArchiveByteCount: Int64 {
        switch coreMLEncoderModelStem {
        case "ggml-tiny", "ggml-tiny.en":
            return 15 * 1_024 * 1_024
        case "ggml-base", "ggml-base.en":
            return 38 * 1_024 * 1_024
        case "ggml-small", "ggml-small.en":
            return 163 * 1_024 * 1_024
        case "ggml-medium", "ggml-medium.en":
            return 568 * 1_024 * 1_024
        case "ggml-large-v3-turbo":
            return 1_170 * 1_024 * 1_024
        case "ggml-large-v3":
            return 1_180 * 1_024 * 1_024
        default:
            return 1
        }
    }

    var coreMLEncoderExpectedSizeText: String {
        ByteCountFormatter.string(fromByteCount: expectedCoreMLEncoderArchiveByteCount, countStyle: .file)
    }

    private var coreMLEncoderModelStem: String {
        var stem = (fileName as NSString).deletingPathExtension
        if let range = stem.range(of: #"-q\d+_\d+$"#, options: .regularExpression) {
            stem.removeSubrange(range)
        }
        return stem
    }

    private static let modelRepositoryBaseURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/")!

    private var displayNameResource: LocalizedStringResource {
        switch id {
        case "tiny":
            return L10n.LocalWhisper.modelTinyTitle
        case "tiny.en":
            return L10n.LocalWhisper.modelTinyEnglishTitle
        case "base":
            return L10n.LocalWhisper.modelBaseTitle
        case "base.en":
            return L10n.LocalWhisper.modelBaseEnglishTitle
        case "small":
            return L10n.LocalWhisper.modelSmallTitle
        case "small.en":
            return L10n.LocalWhisper.modelSmallEnglishTitle
        case "medium":
            return L10n.LocalWhisper.modelMediumTitle
        case "medium.en":
            return L10n.LocalWhisper.modelMediumEnglishTitle
        case "large-v3-turbo-q5_0":
            return L10n.LocalWhisper.modelLargeV3TurboQ5Title
        case "large-v3-q5_0":
            return L10n.LocalWhisper.modelLargeV3Q5Title
        case "large-v3":
            return L10n.LocalWhisper.modelLargeV3Title
        default:
            return L10n.LocalWhisper.modelBaseTitle
        }
    }

    private var detailResource: LocalizedStringResource {
        switch id {
        case "tiny":
            return L10n.LocalWhisper.modelTinyDetail
        case "tiny.en":
            return L10n.LocalWhisper.modelTinyEnglishDetail
        case "base":
            return L10n.LocalWhisper.modelBaseDetail
        case "base.en":
            return L10n.LocalWhisper.modelBaseEnglishDetail
        case "small":
            return L10n.LocalWhisper.modelSmallDetail
        case "small.en":
            return L10n.LocalWhisper.modelSmallEnglishDetail
        case "medium":
            return L10n.LocalWhisper.modelMediumDetail
        case "medium.en":
            return L10n.LocalWhisper.modelMediumEnglishDetail
        case "large-v3-turbo-q5_0":
            return L10n.LocalWhisper.modelLargeV3TurboQ5Detail
        case "large-v3-q5_0":
            return L10n.LocalWhisper.modelLargeV3Q5Detail
        case "large-v3":
            return L10n.LocalWhisper.modelLargeV3Detail
        default:
            return L10n.LocalWhisper.modelBaseDetail
        }
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

struct LocalWhisperCoreMLEncoderStatus: Equatable {
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
            return localizedFormat(L10n.LocalWhisper.coreMLEncoderDownloadedDetailFormat, model.displayName, sizeText)
        case .bundle:
            let sizeText = byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? String(localized: L10n.Common.unknown)
            return localizedFormat(L10n.LocalWhisper.coreMLEncoderBundledDetailFormat, model.displayName, sizeText)
        case .missing:
            return localizedFormat(L10n.LocalWhisper.coreMLEncoderMissingDetailFormat, model.displayName, model.coreMLEncoderExpectedSizeText)
        }
    }

    private func localizedFormat(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        String(format: String(localized: resource), arguments: arguments)
    }
}

enum LocalWhisperModelManager {
    private static let selectedModelIDDefaultsKey = "localWhisper.selectedModelID"
    private static let selectedLiveModelIDDefaultsKey = "localWhisper.live.selectedModelID"
    private static let coreMLEncoderLoadingEnabledDefaultsKey = "localWhisper.coreMLEncoder.loadingEnabled"

    static var availableModels: [LocalWhisperModel] {
        LocalWhisperTranscriptionService.availableModels
    }

    static var selectedModel: LocalWhisperModel {
        let storedID = UserDefaults.standard.string(forKey: selectedModelIDDefaultsKey)
        return model(withID: storedID) ?? LocalWhisperTranscriptionService.defaultModel
    }

    static var selectedLiveModel: LocalWhisperModel? {
        let storedID = UserDefaults.standard.string(forKey: selectedLiveModelIDDefaultsKey)
        return model(withID: storedID)
    }

    static var isCoreMLEncoderLoadingEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: coreMLEncoderLoadingEnabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: coreMLEncoderLoadingEnabledDefaultsKey)
        }
    }

    static func selectModel(_ model: LocalWhisperModel) {
        UserDefaults.standard.set(model.id, forKey: selectedModelIDDefaultsKey)
    }

    static func selectLiveModel(_ model: LocalWhisperModel) {
        UserDefaults.standard.set(model.id, forKey: selectedLiveModelIDDefaultsKey)
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

    static func currentLiveStatus() -> LocalWhisperModelStatus? {
        selectedLiveModel.map { status(for: $0) }
    }

    static func currentCoreMLEncoderStatus() -> LocalWhisperCoreMLEncoderStatus {
        coreMLEncoderStatus(for: selectedModel)
    }

    static func currentLiveCoreMLEncoderStatus() -> LocalWhisperCoreMLEncoderStatus? {
        selectedLiveModel.map { coreMLEncoderStatus(for: $0) }
    }

    static func downloadedStatuses() -> [LocalWhisperModelStatus] {
        availableModels
            .map { status(for: $0) }
            .filter(\.isUserInstalled)
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

    static func coreMLEncoderStatus(for model: LocalWhisperModel) -> LocalWhisperCoreMLEncoderStatus {
        let fileManager = FileManager.default

        if let directory = try? modelDirectory() {
            let encoderURL = directory.appendingPathComponent(model.coreMLEncoderDirectoryName, isDirectory: true)
            if fileManager.fileExists(atPath: encoderURL.path) {
                return LocalWhisperCoreMLEncoderStatus(
                    location: .applicationSupport,
                    model: model,
                    byteCount: byteCount(at: encoderURL)
                )
            }
        }

        let bundleName = (model.coreMLEncoderDirectoryName as NSString).deletingPathExtension
        let bundleExtension = (model.coreMLEncoderDirectoryName as NSString).pathExtension
        if let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: bundleExtension) {
            return LocalWhisperCoreMLEncoderStatus(
                location: .bundle,
                model: model,
                byteCount: byteCount(at: bundleURL)
            )
        }

        return LocalWhisperCoreMLEncoderStatus(location: .missing, model: model, byteCount: nil)
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

    static func downloadCoreMLEncoder(
        for model: LocalWhisperModel,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> LocalWhisperCoreMLEncoderStatus {
        let directory = try modelDirectory()
        let destinationURL = directory.appendingPathComponent(model.coreMLEncoderDirectoryName, isDirectory: true)
        let stagingRootURL = directory.appendingPathComponent("\(model.coreMLEncoderDirectoryName).extracting-\(UUID().uuidString)", isDirectory: true)

        let downloadedURL = try await LocalWhisperModelDownloader.download(
            from: model.coreMLEncoderDownloadURL,
            progressHandler: progressHandler
        )
        defer {
            try? FileManager.default.removeItem(at: downloadedURL)
            try? FileManager.default.removeItem(at: stagingRootURL)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        let extractedDirectory = try LocalWhisperCoreMLEncoderZipExtractor.extract(
            zipURL: downloadedURL,
            expectedRootDirectoryName: model.coreMLEncoderDirectoryName,
            to: stagingRootURL
        )

        guard fileManager.fileExists(atPath: extractedDirectory.appendingPathComponent("model.mil").path),
              fileManager.fileExists(atPath: extractedDirectory.appendingPathComponent("metadata.json").path) else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: extractedDirectory, to: destinationURL)
        try? (destinationURL as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)

        progressHandler(1)
        return coreMLEncoderStatus(for: model)
    }

    static func deleteDownloadedModel(_ model: LocalWhisperModel) throws -> LocalWhisperModelStatus {
        let fileManager = FileManager.default
        let directory = try modelDirectory()
        let url = directory.appendingPathComponent(model.fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        let encoderURL = directory.appendingPathComponent(model.coreMLEncoderDirectoryName, isDirectory: true)
        let isEncoderSharedByAvailableModel = availableModels.contains { otherModel in
            otherModel.id != model.id
                && otherModel.coreMLEncoderDirectoryName == model.coreMLEncoderDirectoryName
                && status(for: otherModel).isAvailable
        }
        if !isEncoderSharedByAvailableModel, fileManager.fileExists(atPath: encoderURL.path) {
            try fileManager.removeItem(at: encoderURL)
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

    private static func byteCount(at url: URL) -> Int64? {
        let fileManager = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
              values.isDirectory == true else {
            return fileSize(at: url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }
        return total
    }
}

enum LocalWhisperTranscriptionError: LocalizedError {
    case runtimeUnavailable
    case missingSymbol(String)
    case missingModel
    case missingLiveModel
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
        case .missingLiveModel:
            return String(localized: L10n.LocalWhisper.missingLiveModel)
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

private enum LocalWhisperCoreMLEncoderZipExtractor {
    private struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var localHeaderOffset: UInt64
    }

    private static let localFileHeaderSignature: UInt32 = 0x0403_4B50
    private static let centralDirectoryHeaderSignature: UInt32 = 0x0201_4B50
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let storedCompressionMethod: UInt16 = 0
    private static let deflatedCompressionMethod: UInt16 = 8
    private static let chunkSize = 64 * 1_024

    static func extract(
        zipURL: URL,
        expectedRootDirectoryName: String,
        to destinationRoot: URL
    ) throws -> URL {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer {
            try? handle.close()
        }

        let entries = try centralDirectoryEntries(in: handle)
        let fileManager = FileManager.default
        let rootURL = destinationRoot.appendingPathComponent(expectedRootDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        for entry in entries {
            guard entry.name == expectedRootDirectoryName || entry.name.hasPrefix("\(expectedRootDirectoryName)/") else {
                continue
            }
            guard !entry.name.contains(".."), !entry.name.hasPrefix("/") else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }

            let destinationURL = destinationRoot.appendingPathComponent(entry.name)
            guard isDescendant(destinationURL, of: destinationRoot) else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }

            if entry.name.hasSuffix("/") {
                try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                continue
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            fileManager.createFile(atPath: destinationURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? outputHandle.close()
            }

            let dataOffset = try localFileDataOffset(for: entry, in: handle)
            try handle.seek(toOffset: dataOffset)
            switch entry.compressionMethod {
            case storedCompressionMethod:
                try copyStoredEntry(from: handle, to: outputHandle, byteCount: entry.compressedSize)
            case deflatedCompressionMethod:
                try inflateDeflatedEntry(
                    from: handle,
                    to: outputHandle,
                    compressedSize: entry.compressedSize,
                    expectedUncompressedSize: entry.uncompressedSize
                )
            default:
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }
        }

        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }
        return rootURL
    }

    private static func centralDirectoryEntries(in handle: FileHandle) throws -> [Entry] {
        let fileSize = try handle.seekToEnd()
        let searchLength = min(Int(fileSize), 65_557)
        try handle.seek(toOffset: fileSize - UInt64(searchLength))
        let tailData = handle.readData(ofLength: searchLength)

        guard let eocdOffsetInTail = lastOffset(of: endOfCentralDirectorySignature, in: tailData),
              eocdOffsetInTail + 22 <= tailData.count else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }

        let entryCount = Int(readUInt16(tailData, at: eocdOffsetInTail + 10))
        let centralDirectoryOffset = UInt64(readUInt32(tailData, at: eocdOffsetInTail + 16))
        try handle.seek(toOffset: centralDirectoryOffset)

        var entries: [Entry] = []
        for _ in 0..<entryCount {
            let fixedHeader = handle.readData(ofLength: 46)
            guard fixedHeader.count == 46,
                  readUInt32(fixedHeader, at: 0) == centralDirectoryHeaderSignature else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }

            let flags = readUInt16(fixedHeader, at: 8)
            guard flags & 0x0001 == 0 else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }

            let compressionMethod = readUInt16(fixedHeader, at: 10)
            let compressedSize = UInt64(readUInt32(fixedHeader, at: 20))
            let uncompressedSize = UInt64(readUInt32(fixedHeader, at: 24))
            let fileNameLength = Int(readUInt16(fixedHeader, at: 28))
            let extraFieldLength = Int(readUInt16(fixedHeader, at: 30))
            let fileCommentLength = Int(readUInt16(fixedHeader, at: 32))
            let localHeaderOffset = UInt64(readUInt32(fixedHeader, at: 42))
            let nameData = handle.readData(ofLength: fileNameLength)
            guard nameData.count == fileNameLength,
                  let name = String(data: nameData, encoding: .utf8) else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }

            if extraFieldLength + fileCommentLength > 0 {
                _ = handle.readData(ofLength: extraFieldLength + fileCommentLength)
            }

            entries.append(
                Entry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
        }

        return entries
    }

    private static func localFileDataOffset(for entry: Entry, in handle: FileHandle) throws -> UInt64 {
        try handle.seek(toOffset: entry.localHeaderOffset)
        let localHeader = handle.readData(ofLength: 30)
        guard localHeader.count == 30,
              readUInt32(localHeader, at: 0) == localFileHeaderSignature else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }

        let fileNameLength = UInt64(readUInt16(localHeader, at: 26))
        let extraFieldLength = UInt64(readUInt16(localHeader, at: 28))
        return entry.localHeaderOffset + 30 + fileNameLength + extraFieldLength
    }

    private static func copyStoredEntry(
        from inputHandle: FileHandle,
        to outputHandle: FileHandle,
        byteCount: UInt64
    ) throws {
        var remaining = byteCount
        while remaining > 0 {
            let readCount = min(Int(remaining), chunkSize)
            let data = inputHandle.readData(ofLength: readCount)
            guard !data.isEmpty else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }
            outputHandle.write(data)
            remaining -= UInt64(data.count)
        }
    }

    private static func inflateDeflatedEntry(
        from inputHandle: FileHandle,
        to outputHandle: FileHandle,
        compressedSize: UInt64,
        expectedUncompressedSize: UInt64
    ) throws {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }
        defer {
            inflateEnd(&stream)
        }

        var remaining = compressedSize
        var didFinish = false
        var totalOutput: UInt64 = 0
        var outputBuffer = [UInt8](repeating: 0, count: chunkSize)
        let outputBufferCapacity = outputBuffer.count

        while remaining > 0 && !didFinish {
            let readCount = min(Int(remaining), chunkSize)
            let inputData = inputHandle.readData(ofLength: readCount)
            guard !inputData.isEmpty else {
                throw LocalWhisperTranscriptionError.modelDownloadFailed
            }
            remaining -= UInt64(inputData.count)

            try inputData.withUnsafeBytes { inputRawBuffer in
                guard let inputBaseAddress = inputRawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    throw LocalWhisperTranscriptionError.modelDownloadFailed
                }

                stream.next_in = UnsafeMutablePointer(mutating: inputBaseAddress)
                stream.avail_in = uInt(inputData.count)

                while stream.avail_in > 0 && !didFinish {
                    let status = outputBuffer.withUnsafeMutableBytes { outputRawBuffer -> Int32 in
                        stream.next_out = outputRawBuffer.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(outputBufferCapacity)
                        return inflate(&stream, Z_NO_FLUSH)
                    }

                    let produced = outputBufferCapacity - Int(stream.avail_out)
                    if produced > 0 {
                        outputHandle.write(Data(outputBuffer.prefix(produced)))
                        totalOutput += UInt64(produced)
                    }

                    if status == Z_STREAM_END {
                        didFinish = true
                    } else if status != Z_OK {
                        throw LocalWhisperTranscriptionError.modelDownloadFailed
                    }
                }
            }
        }

        guard didFinish, totalOutput == expectedUncompressedSize else {
            throw LocalWhisperTranscriptionError.modelDownloadFailed
        }
    }

    private static func isDescendant(_ url: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func lastOffset(of signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else {
            return nil
        }

        for offset in stride(from: data.count - 4, through: 0, by: -1) {
            if readUInt32(data, at: offset) == signature {
                return offset
            }
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
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
    languageCode: String,
    progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
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
        languageCode: languageCode.isEmpty ? "auto" : languageCode,
        useCoreMLEncoder: LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled,
        progressHandler: progressHandler
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
