import AVFoundation
import Combine
import CoreMedia
import Foundation
import OSLog
import Speech

private let liveTranscriptionLogger = Logger(subsystem: "com.reddownloader.LiveTranscriber", category: "LiveTranscription")

private func liveAudioFormatSummary(_ format: AVAudioFormat) -> String {
    let channels = format.channelCount == 1 ? "mono" : "\(format.channelCount) ch"
    let interleaving = format.isInterleaved ? "interleaved" : "non-interleaved"
    return "\(liveAudioSampleRateText(format.sampleRate)) / \(channels) / \(liveAudioCommonFormatName(format.commonFormat)) / \(interleaving)"
}

private func liveAudioSampleRateText(_ sampleRate: Double) -> String {
    guard sampleRate.isFinite, sampleRate > 0 else {
        return "unknown Hz"
    }

    let kilohertz = sampleRate / 1_000
    if kilohertz.rounded() == kilohertz {
        return "\(Int(kilohertz)) kHz"
    }
    return String(format: "%.1f kHz", kilohertz)
}

private func liveAudioCommonFormatName(_ commonFormat: AVAudioCommonFormat) -> String {
    switch commonFormat {
    case .pcmFormatFloat32:
        return "Float32 PCM"
    case .pcmFormatFloat64:
        return "Float64 PCM"
    case .pcmFormatInt16:
        return "Int16 PCM"
    case .pcmFormatInt32:
        return "Int32 PCM"
    case .otherFormat:
        return "Other PCM"
    @unknown default:
        return "Unknown PCM"
    }
}

@MainActor
final class LiveFinalTranscriptStore: ObservableObject {
    @Published private(set) var lines: [TranscriptionLine] = []
    @Published private(set) var revision = 0

    func publish(_ lines: [TranscriptionLine], incrementsRevision: Bool) {
        self.lines = lines
        if incrementsRevision {
            revision &+= 1
        }
    }

    func reset() {
        lines = []
        revision = 0
    }
}

@MainActor
final class LiveInterimTranscriptStore: ObservableObject {
    @Published private(set) var line: TranscriptionLine?

    func publish(_ line: TranscriptionLine?) {
        self.line = line
    }

    func reset() {
        line = nil
    }
}

@MainActor
final class RecordingElapsedClock: ObservableObject {
    @Published private(set) var elapsedSeconds = 0

    func updateElapsedSeconds(_ seconds: Int) {
        guard elapsedSeconds != seconds else {
            return
        }
        elapsedSeconds = seconds
    }
}

@MainActor
final class LiveTranscriptionManager: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isPreparing = false
    @Published private(set) var statusText = String(localized: L10n.RecordingStatus.ready)
    @Published private(set) var errorText: String?
    let finalTranscriptStore = LiveFinalTranscriptStore()
    let interimTranscriptStore = LiveInterimTranscriptStore()
    let elapsedClock = RecordingElapsedClock()
    private(set) var elapsedSeconds: Int = 0
    private(set) var inputLevel: Float = 0
    private(set) var inputLevelHistory: [Float] = Array(repeating: 0, count: 72)
    @Published private(set) var supportedLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @Published private(set) var speechPipelineRuntimeFormatText = String(localized: L10n.SpeechText.runtimeInputWaitingRecording)
    @Published var selectedAudioFormat: RecordingAudioFormat {
        didSet {
            UserDefaults.standard.set(selectedAudioFormat.rawValue, forKey: Self.audioFormatDefaultsKey)
        }
    }
    @Published var selectedLanguageID: String {
        didSet {
            UserDefaults.standard.set(selectedLanguageID, forKey: Self.languageDefaultsKey)
            if !isRecording && !isPreparing {
                statusText = String(localized: L10n.RecordingStatus.ready)
            }
        }
    }
    @Published var selectedSpeechPipelineMode: SpeechPipelineMode {
        didSet {
            UserDefaults.standard.set(selectedSpeechPipelineMode.rawValue, forKey: Self.speechPipelineModeDefaultsKey)
        }
    }
    @Published var selectedTranscriptionBackend: LiveTranscriptionBackend {
        didSet {
            UserDefaults.standard.set(selectedTranscriptionBackend.rawValue, forKey: Self.transcriptionBackendDefaultsKey)
            if !isRecording && !isPreparing {
                statusText = String(localized: L10n.RecordingStatus.ready)
            }
            Task { @MainActor in
                await self.refreshSupportedLanguages()
            }
        }
    }
    @Published var isOpenAITranscriptionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isOpenAITranscriptionEnabled, forKey: Self.openAITranscriptionEnabledDefaultsKey)
        }
    }
    @Published var openAIAPIKey: String {
        didSet {
            do {
                try OpenAIAPIKeyStore.save(openAIAPIKey)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private static let languageDefaultsKey = "transcription.language"
    private static let audioFormatDefaultsKey = "recording.audioFormat"
    private static let speechPipelineModeDefaultsKey = "speech.pipelineMode"
    private static let transcriptionBackendDefaultsKey = "transcription.backend"
    private static let openAITranscriptionEnabledDefaultsKey = "openai.transcription.enabled"
    private static let analyzerSampleRate: Double = 16_000
    private static let inputLevelHistoryCount = 72
    private static let inputLevelHistorySampleInterval: TimeInterval = 0.08

    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcription.audio-session", qos: .userInitiated)
    private var analyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var analyzerPipeline: AnalyzerInputPipeline?
    private var localWhisperPipeline: LiveLocalWhisperPipeline?
    private var captureRecordingPipeline: CaptureSessionRecordingPipeline?
    private var audioWriter: AudioFileWriter?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var elapsedTimerTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var activeSegmentStartedAt: Date?
    private var accumulatedRecordingSeconds: TimeInterval = 0
    private var currentAudioURL: URL?
    private var currentRecordingFormat: AVAudioFormat?
    private var smoothedInputLevel: Float = 0
    private var lastInputLevelHistorySampleAt: TimeInterval = 0
    private var finalizedLines: [TranscriptionLine] = []
    private var interimLine: TranscriptionLine?
    private var manuallyEditedFinalLineIDs = Set<TranscriptionLine.ID>()
    private var lastLiveActivitySnapshot: LiveActivitySnapshot?
    private var lastSpeechPipelineRuntimeFormat: SpeechPipelineRuntimeFormat?

    private static let liveActivityTextCharacterLimit = 700

    var selectedLanguage: TranscriptionLanguage {
        supportedLanguages.first { $0.id == selectedLanguageID } ?? TranscriptionLanguage(id: selectedLanguageID)
    }

    var currentTranscript: String {
        transcriptLines.timedTranscriptText
    }

    var plainTranscript: String {
        transcriptLines.plainTranscriptText
    }

    var transcriptLines: [TranscriptionLine] {
        displayedTranscriptLines(finalizedLines: finalizedLines, interimLine: interimLine)
    }

    var hasTranscript: Bool {
        !plainTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var speechPipelineDiagnostics: SpeechProcessingPipelineDiagnostics {
        .current(
            backend: selectedTranscriptionBackend,
            configuredMode: selectedSpeechPipelineMode,
            runtimeAnalyzerFormatText: speechPipelineRuntimeFormatText
        )
    }

    var selectedLocalWhisperLiveModel: LocalWhisperModel? {
        LocalWhisperModelManager.selectedLiveModel
    }

    init() {
        selectedLanguageID = UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? TranscriptionLanguage.defaultLanguageID
        if let rawMode = UserDefaults.standard.string(forKey: Self.speechPipelineModeDefaultsKey),
           let storedMode = SpeechPipelineMode(rawValue: rawMode),
           storedMode.isSupportedOnCurrentOS {
            selectedSpeechPipelineMode = storedMode
        } else {
            selectedSpeechPipelineMode = .compatible
        }

        if let rawFormat = UserDefaults.standard.string(forKey: Self.audioFormatDefaultsKey),
           let storedFormat = RecordingAudioFormat(rawValue: rawFormat) {
            selectedAudioFormat = storedFormat
        } else {
            selectedAudioFormat = .defaultFormat
        }

        if let rawBackend = UserDefaults.standard.string(forKey: Self.transcriptionBackendDefaultsKey),
           let storedBackend = LiveTranscriptionBackend(rawValue: rawBackend) {
            selectedTranscriptionBackend = storedBackend
        } else {
            selectedTranscriptionBackend = .defaultBackend
        }

        isOpenAITranscriptionEnabled = UserDefaults.standard.bool(forKey: Self.openAITranscriptionEnabledDefaultsKey)
        openAIAPIKey = (try? OpenAIAPIKeyStore.load()) ?? ""
    }

    func refreshSupportedLanguages() async {
        let languages: [TranscriptionLanguage]
        if selectedTranscriptionBackend.usesLocalWhisper {
            guard let liveModel = LocalWhisperModelManager.selectedLiveModel else {
                supportedLanguages = []
                return
            }
            languages = LocalWhisperTranscriptionService.supportedLanguages(for: liveModel)
        } else {
            languages = await AppleSpeechTranscriptionSupport.supportedLanguages()
        }

        if !languages.isEmpty {
            supportedLanguages = languages
            if !languages.contains(where: { $0.id == selectedLanguageID }) {
                if let equivalent = await equivalentSupportedLanguage(for: selectedLanguageID, in: languages) {
                    selectedLanguageID = equivalent.id
                } else if let preferred = preferredSupportedLanguage(in: languages) {
                    selectedLanguageID = preferred.id
                } else if let first = languages.first {
                    selectedLanguageID = first.id
                }
            }
        }
    }

    private func equivalentSupportedLanguage(
        for languageID: String,
        in languages: [TranscriptionLanguage]
    ) async -> TranscriptionLanguage? {
        if selectedTranscriptionBackend.requiresAppleSpeech {
            return await AppleSpeechTranscriptionSupport.equivalentLanguage(
                for: languageID,
                in: languages
            )
        }

        return Self.equivalentLanguage(for: languageID, in: languages)
    }

    private func preferredSupportedLanguage(in languages: [TranscriptionLanguage]) -> TranscriptionLanguage? {
        if let exactDefault = languages.first(where: { $0.id == TranscriptionLanguage.defaultLanguageID }) {
            return exactDefault
        }
        if let equivalentDefault = Self.equivalentLanguage(for: TranscriptionLanguage.defaultLanguageID, in: languages) {
            return equivalentDefault
        }
        if let equivalentCurrent = Self.equivalentLanguage(for: Locale.current.identifier, in: languages) {
            return equivalentCurrent
        }
        return languages.first(where: { $0.id == "en" || $0.id == "en-US" })
    }

    private static func equivalentLanguage(
        for languageID: String,
        in languages: [TranscriptionLanguage]
    ) -> TranscriptionLanguage? {
        let targetLanguage = Locale(identifier: languageID).language
        guard let targetCode = targetLanguage.languageCode?.identifier else {
            return nil
        }

        return languages.first { language in
            let candidate = language.locale.language
            guard candidate.languageCode?.identifier == targetCode else {
                return false
            }

            let targetScript = targetLanguage.script?.identifier
            let candidateScript = candidate.script?.identifier
            if targetScript != nil || candidateScript != nil {
                return targetScript == candidateScript
            }
            return true
        }
    }

    func prepareSpeechLocaleForUse(
        _ language: TranscriptionLanguage,
        preservingLanguageIDs: Set<String> = []
    ) async throws -> SpeechLocalePreparation {
        let targetLocale = await Self.resolvedSpeechLocale(for: language)
        let reservedLocales = await AssetInventory.reservedLocales
        if Self.containsReservedLocale(targetLocale, in: reservedLocales) {
            return .ready
        }

        let maximumReservedLocales = AssetInventory.maximumReservedLocales
        guard maximumReservedLocales > 0 else {
            try await Self.reserveSpeechLocale(targetLocale)
            return .ready
        }

        if reservedLocales.count < maximumReservedLocales {
            try await Self.reserveSpeechLocale(targetLocale)
            return .ready
        }

        let protectedLocaleKeys = await Self.protectedSpeechLocaleKeys(
            preservingLanguageIDs: preservingLanguageIDs,
            targetLocale: targetLocale
        )
        let releaseLocales = reservedLocales.filter { locale in
            !protectedLocaleKeys.contains(Self.speechLocaleKey(locale))
        }
        guard !releaseLocales.isEmpty else {
            throw SpeechLocaleManagementError.noReleasableLanguages
        }

        return .needsRelease(
            SpeechLocaleReleaseRequest(
                targetLanguage: language,
                targetLocaleIdentifier: targetLocale.identifier,
                releaseLocaleIdentifiers: releaseLocales.map(\.identifier),
                maximumReservedLocaleCount: maximumReservedLocales
            )
        )
    }

    func releaseSpeechLocalesAndReserveTarget(_ request: SpeechLocaleReleaseRequest) async throws {
        for identifier in request.releaseLocaleIdentifiers {
            _ = await AssetInventory.release(reservedLocale: Locale(identifier: identifier))
        }

        try await Self.reserveSpeechLocale(Locale(identifier: request.targetLocaleIdentifier))
    }

    func toggleRecording() async -> RecordingDraft? {
        if isRecording || isPreparing {
            return await stopRecording()
        }
        await startRecording()
        return nil
    }

    func startRecording() async {
        guard !isRecording, !isPreparing else {
            return
        }

        isPreparing = true
        errorText = nil
        resetInputLevel(clearHistory: true)
        lastSpeechPipelineRuntimeFormat = nil
        speechPipelineRuntimeFormatText = String(localized: L10n.SpeechText.runtimeInputWaitingFirstBuffer)
        resetTranscriptStorage()
        statusText = String(localized: L10n.RecordingStatus.checkingPermissions)

        guard await requestPermissions() else {
            isPreparing = false
            return
        }

        do {
            let language = selectedLanguage
            try await startCaptureSessionRecording(language: language)
            beginElapsedTimer()

            isPreparing = false
            isRecording = true
            isPaused = false
            statusText = String(localized: L10n.RecordingStatus.recording)
            await TranscriptionLiveActivityCoordinator.start(
                startedAt: recordingStartedAt ?? Date(),
                status: statusText,
                languageName: language.displayName,
                latestText: "",
                elapsedSeconds: elapsedSeconds,
                lineCount: transcriptLines.count
            )
            resetLiveActivityUpdateTracking()
        } catch {
            if let draft = await stopRecording(endingLiveActivity: false) {
                try? FileManager.default.removeItem(at: draft.audioURL)
            }
            fail(with: String(format: String(localized: L10n.SpeechText.recordingStartFailedFormat), error.localizedDescription))
        }
    }

    private func startCaptureSessionRecording(language: TranscriptionLanguage) async throws {
        if selectedTranscriptionBackend.usesLocalWhisper {
            try await startLocalWhisperCaptureSessionRecording(language: language)
        } else {
            try await startAppleSpeechCaptureSessionRecording(language: language)
        }
    }

    private func startAppleSpeechCaptureSessionRecording(language: TranscriptionLanguage) async throws {
        statusText = String(localized: L10n.RecordingStatus.configuringAudioInput)
        try await configureAudioSession()

        let audioFormat = selectedAudioFormat
        let recordingFormat = try Self.makeCaptureSessionRecordingFormat()
        let analyzerSourceFormat = try Self.makeCaptureSessionAnalyzerSourceFormat(sampleRate: recordingFormat.sampleRate)
        let prepared = try await prepareSpeechPipeline(language: language, audioInputFormat: analyzerSourceFormat)
        statusText = String(localized: L10n.RecordingStatus.startingRecorder)
        let recordingURL = try Self.makeTemporaryRecordingURL(format: audioFormat)
        let writer = try AudioFileWriter(url: recordingURL, inputFormat: recordingFormat, outputFormat: audioFormat)
        let capturePipeline = CaptureSessionRecordingPipeline(
            recordingFormat: recordingFormat,
            analyzerSourceFormat: analyzerSourceFormat,
            writer: writer,
            analyzerPipeline: prepared.pipeline
        )

        analyzer = prepared.analyzer
        speechTranscriber = prepared.transcriber
        analyzerPipeline = prepared.pipeline
        captureRecordingPipeline = capturePipeline
        audioWriter = writer
        currentAudioURL = recordingURL
        currentRecordingFormat = recordingFormat

        startResultReader(for: prepared.transcriber)
        startAnalyzer(prepared.analyzer, stream: prepared.stream)
        try await capturePipeline.start()
    }

    private func startLocalWhisperCaptureSessionRecording(language: TranscriptionLanguage) async throws {
        statusText = String(localized: L10n.RecordingStatus.preparingLanguageModel)
        guard let liveModel = LocalWhisperModelManager.selectedLiveModel else {
            throw LocalWhisperTranscriptionError.missingLiveModel
        }
        let modelURL = try LocalWhisperTranscriptionService.modelURL(for: liveModel)
        let languageCode = LocalWhisperTranscriptionService.languageCode(for: language)

        statusText = String(localized: L10n.RecordingStatus.configuringAudioInput)
        try await configureAudioSession()

        let audioFormat = selectedAudioFormat
        let recordingFormat = try Self.makeCaptureSessionRecordingFormat()
        let localWhisperFormat = try Self.makeLocalWhisperInputFormat()
        statusText = String(localized: L10n.RecordingStatus.startingRecorder)

        let recordingURL = try Self.makeTemporaryRecordingURL(format: audioFormat)
        let writer = try AudioFileWriter(url: recordingURL, inputFormat: recordingFormat, outputFormat: audioFormat)
        let localWhisperPipeline = LiveLocalWhisperPipeline(
            inputSampleRate: localWhisperFormat.sampleRate,
            modelURL: modelURL,
            languageCode: languageCode,
            useCoreMLEncoder: LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled,
            resultHandler: { [weak self] finalLines, interimLine in
                Task { @MainActor [weak self] in
                    self?.handleLocalWhisperResult(finalLines: finalLines, interimLine: interimLine)
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.errorText = error.localizedDescription
                }
            }
        )
        let capturePipeline = CaptureSessionRecordingPipeline(
            recordingFormat: recordingFormat,
            analyzerSourceFormat: localWhisperFormat,
            writer: writer,
            analyzerPipeline: nil,
            localWhisperPipeline: localWhisperPipeline
        )

        self.localWhisperPipeline = localWhisperPipeline
        captureRecordingPipeline = capturePipeline
        audioWriter = writer
        currentAudioURL = recordingURL
        currentRecordingFormat = recordingFormat

        try await capturePipeline.start()
    }

    func pauseRecording() async {
        guard isRecording, !isPaused else {
            return
        }

        await captureRecordingPipeline?.stop()
        resetInputLevel()
        pauseElapsedTimer()
        isPaused = true
        statusText = String(localized: L10n.RecordingStatus.paused)
        await deactivateAudioSession()
        await updateLiveActivityFromCurrentState(isRecording: false)
    }

    func resumeRecording() async {
        guard isRecording, isPaused else {
            return
        }
        guard let captureRecordingPipeline else {
            fail(with: String(localized: L10n.SpeechText.recordingResumeFailed))
            return
        }

        do {
            try await configureAudioSession()
            try await captureRecordingPipeline.start()
            resumeElapsedTimer()
            isPaused = false
            statusText = String(localized: L10n.RecordingStatus.recording)
            await updateLiveActivityFromCurrentState(isRecording: true)
        } catch {
            fail(with: String(format: String(localized: L10n.SpeechText.recordingResumeFailedFormat), error.localizedDescription))
        }
    }

    @discardableResult
    func stopRecording(endingLiveActivity: Bool = true) async -> RecordingDraft? {
        guard isRecording || isPreparing || captureRecordingPipeline != nil || currentAudioURL != nil else {
            return nil
        }

        isPreparing = false
        isRecording = false
        isPaused = false
        resetInputLevel()

        let pendingCapturePipeline = captureRecordingPipeline
        captureRecordingPipeline = nil
        await pendingCapturePipeline?.stop()

        let pendingLocalWhisperPipeline = localWhisperPipeline
        localWhisperPipeline = nil
        pendingLocalWhisperPipeline?.cancel()

        analyzerPipeline?.finish()
        let pendingAnalyzerTask = analyzerTask
        let pendingResultsTask = resultsTask
        let pendingAnalyzer = analyzer

        try? await pendingAnalyzer?.finalizeAndFinishThroughEndOfInput()
        pendingAnalyzerTask?.cancel()
        pendingResultsTask?.cancel()
        _ = await pendingAnalyzerTask?.value
        _ = await pendingResultsTask?.value

        analyzerTask = nil
        resultsTask = nil
        analyzer = nil
        speechTranscriber = nil
        analyzerPipeline = nil
        localWhisperPipeline = nil
        captureRecordingPipeline = nil
        audioWriter = nil
        currentRecordingFormat = nil

        finishElapsedTimer()
        let finishedLines = transcriptLines
        let recordingURL = currentAudioURL
        currentAudioURL = nil
        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil

        statusText = hasTranscript
            ? String(localized: L10n.RecordingStatus.complete)
            : String(localized: L10n.RecordingStatus.stopped)
        await deactivateAudioSession()

        if endingLiveActivity {
            await TranscriptionLiveActivityCoordinator.end(
                status: statusText,
                languageName: selectedLanguage.displayName,
                latestText: liveActivityTranscriptText,
                elapsedSeconds: elapsedSeconds,
                lineCount: transcriptLines.count
            )
        }

        guard let recordingURL else {
            return nil
        }

        return RecordingDraft(
            audioURL: recordingURL,
            startedAt: startedAt,
            durationSeconds: elapsedSeconds,
            languageID: selectedLanguageID,
            languageName: selectedLanguage.displayName,
            lines: finishedLines
        )
    }

    func clearTranscript() {
        resetTranscriptStorage()
        errorText = nil
        if !isRecording {
            statusText = String(localized: L10n.RecordingStatus.ready)
            setElapsedSeconds(0)
            resetInputLevel(clearHistory: true)
            accumulatedRecordingSeconds = 0
            recordingStartedAt = nil
            activeSegmentStartedAt = nil
        }
    }

    func updateFinalTranscriptLine(id: TranscriptionLine.ID, text: String) {
        let cleanedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard let index = finalizedLines.firstIndex(where: { $0.id == id }) else {
            return
        }

        if cleanedText.isEmpty {
            finalizedLines.remove(at: index)
            manuallyEditedFinalLineIDs.remove(id)
        } else {
            finalizedLines[index].text = cleanedText
            finalizedLines[index].isFinal = true
            manuallyEditedFinalLineIDs.insert(id)
        }

        finalTranscriptStore.publish(finalizedLines, incrementsRevision: true)
        Task {
            await updateLiveActivityFromCurrentState()
        }
    }

    private func prepareSpeechPipeline(
        language: TranscriptionLanguage,
        audioInputFormat: AVAudioFormat
    ) async throws -> PreparedSpeechPipeline {
        statusText = String(localized: L10n.RecordingStatus.preparingLanguageModel)
        guard SpeechTranscriber.isAvailable else {
            throw LiveTranscriptionError.analyzerUnavailable
        }

        let locale = await AppleSpeechTranscriptionSupport.resolvedLocale(for: language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        let modules: [any SpeechModule] = [transcriber]

        try await ensureAssets(for: modules)

        let options = Self.makeSpeechAnalyzerOptions()
        let analyzer = SpeechAnalyzer(modules: modules, options: options)

        var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        let stream = AsyncThrowingStream<AnalyzerInput, Error> { createdContinuation in
            continuation = createdContinuation
        }

        guard let continuation else {
            throw LiveTranscriptionError.analyzerUnavailable
        }

        let formatObserver: @Sendable (SpeechPipelineRuntimeFormat) -> Void = { [weak self] observation in
            Task { @MainActor [weak self] in
                self?.handleSpeechPipelineRuntimeFormat(observation)
            }
        }

        #if HAS_IOS27_SDK
        if #available(iOS 27.0, *), selectedSpeechPipelineMode == .nativeIOS27 {
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: modules)
            try await analyzer.prepareToAnalyze(in: nil)
            let pipeline = AnalyzerInputPipeline(
                continuation: continuation,
                converter: converter,
                formatObserver: formatObserver
            )
            return PreparedSpeechPipeline(
                analyzer: analyzer,
                transcriber: transcriber,
                stream: stream,
                pipeline: pipeline
            )
        }
        #endif

        let analyzerInputFormat = try Self.makeAnalyzerInputFormat()
        try await analyzer.prepareToAnalyze(in: analyzerInputFormat)
        let pipeline = try AnalyzerInputPipeline(
            continuation: continuation,
            sourceFormat: audioInputFormat,
            analyzerFormat: analyzerInputFormat,
            formatObserver: formatObserver
        )

        return PreparedSpeechPipeline(
            analyzer: analyzer,
            transcriber: transcriber,
            stream: stream,
            pipeline: pipeline
        )
    }

    private func handleInputLevel(_ level: Float) {
        guard isRecording, !isPaused else {
            resetInputLevel()
            return
        }

        let clampedLevel = min(max(level, 0), 1)
        let response: Float = clampedLevel > smoothedInputLevel ? 0.42 : 0.16
        smoothedInputLevel += (clampedLevel - smoothedInputLevel) * response
        inputLevel = smoothedInputLevel
        appendInputLevelHistoryIfNeeded(smoothedInputLevel)
    }

    private func resetInputLevel(clearHistory: Bool = false) {
        smoothedInputLevel = 0
        inputLevel = 0
        if clearHistory {
            inputLevelHistory = Array(repeating: 0, count: Self.inputLevelHistoryCount)
            lastInputLevelHistorySampleAt = 0
        }
    }

    private func appendInputLevelHistoryIfNeeded(_ level: Float) {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastInputLevelHistorySampleAt >= Self.inputLevelHistorySampleInterval else {
            return
        }

        lastInputLevelHistorySampleAt = now
        inputLevelHistory.append(level)
        if inputLevelHistory.count > Self.inputLevelHistoryCount {
            inputLevelHistory.removeFirst(inputLevelHistory.count - Self.inputLevelHistoryCount)
        }
    }

    private static func makeAnalyzerInputFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: analyzerSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        return format
    }

    private static func makeCaptureSessionAnalyzerSourceFormat(sampleRate: Double) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        return format
    }

    private static func makeLocalWhisperInputFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: analyzerSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        return format
    }

    private static func makeCaptureSessionRecordingFormat() throws -> AVAudioFormat {
        let sessionSampleRate = AVAudioSession.sharedInstance().sampleRate
        let sampleRate = sessionSampleRate.isFinite && sessionSampleRate > 0 ? sessionSampleRate : 48_000
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        return format
    }

    private static func makeSpeechAnalyzerOptions() -> SpeechAnalyzer.Options {
        #if HAS_IOS27_SDK
        if #available(iOS 27.0, *) {
            return SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse,
                ignoresResourceLimits: true
            )
        }
        #endif

        return SpeechAnalyzer.Options(
            priority: .userInitiated,
            modelRetention: .whileInUse
        )
    }

    private func ensureAssets(for modules: [any SpeechModule]) async throws {
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .unsupported:
            throw LiveTranscriptionError.unsupportedLanguage
        case .downloading:
            statusText = String(localized: L10n.RecordingStatus.downloadingLanguageModel)
        case .supported, .installed:
            break
        @unknown default:
            break
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            statusText = String(localized: L10n.RecordingStatus.downloadingLanguageModel)
            try await request.downloadAndInstall()
        }
    }

    private func startAnalyzer(
        _ analyzer: SpeechAnalyzer,
        stream: AsyncThrowingStream<AnalyzerInput, Error>
    ) {
        analyzerTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func startResultReader(for transcriber: SpeechTranscriber) {
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    await MainActor.run {
                        self.handleSpeechTranscriptionResult(result)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    private func requestPermissions() async -> Bool {
        if selectedTranscriptionBackend.requiresAppleSpeech {
            let speechStatus = await resolvedSpeechAuthorization()
            guard speechStatus == .authorized else {
                let message = speechStatus == .restricted
                    ? String(localized: L10n.SpeechText.speechRestricted)
                    : String(localized: L10n.SpeechText.speechDenied)
                fail(with: message)
                return false
            }
        }

        guard await requestMicrophoneAuthorization() else {
            fail(with: String(localized: L10n.SpeechText.microphoneDenied))
            return false
        }

        return true
    }

    private func resolvedSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        statusText = String(localized: L10n.RecordingStatus.requestingPermission)
        return await requestSpeechAuthorization()
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            statusText = String(localized: L10n.RecordingStatus.requestingPermission)
        @unknown default:
            statusText = String(localized: L10n.RecordingStatus.requestingPermission)
        }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    private static func resolvedSpeechLocale(for language: TranscriptionLanguage) async -> Locale {
        await AppleSpeechTranscriptionSupport.resolvedLocale(for: language)
    }

    private static func reserveSpeechLocale(_ locale: Locale) async throws {
        let reservedLocales = await AssetInventory.reservedLocales
        guard !containsReservedLocale(locale, in: reservedLocales) else {
            return
        }

        try await AssetInventory.reserve(locale: locale)
    }

    private static func protectedSpeechLocaleKeys(
        preservingLanguageIDs: Set<String>,
        targetLocale: Locale
    ) async -> Set<String> {
        var keys = [Self.speechLocaleKey(targetLocale)]
        for languageID in preservingLanguageIDs {
            let locale = await resolvedSpeechLocale(for: TranscriptionLanguage(id: languageID))
            keys.append(Self.speechLocaleKey(locale))
        }
        return Set(keys)
    }

    private static func containsReservedLocale(_ locale: Locale, in reservedLocales: [Locale]) -> Bool {
        let key = speechLocaleKey(locale)
        return reservedLocales.contains { speechLocaleKey($0) == key }
    }

    private static func speechLocaleKey(_ locale: Locale) -> String {
        locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private func configureAudioSession() async throws {
        let recordingMode = RecordingAudioSessionMode.defaultMode
        let audioSessionMode = recordingMode.audioSessionMode
        let audioSessionOptions = recordingMode.audioSessionOptions
        let preferredInputChannelCount = recordingMode.preferredInputChannelCount
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playAndRecord,
                        mode: audioSessionMode,
                        options: audioSessionOptions
                    )
                    if let preferredInputChannelCount {
                        do {
                            try session.setPreferredInputNumberOfChannels(preferredInputChannelCount)
                        } catch {
                            liveTranscriptionLogger.debug("Preferred input channel count unavailable before activation: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    if let preferredInputChannelCount,
                       session.inputNumberOfChannels < preferredInputChannelCount {
                        do {
                            try session.setPreferredInputNumberOfChannels(preferredInputChannelCount)
                        } catch {
                            liveTranscriptionLogger.debug("Preferred input channel count unavailable after activation: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deactivateAudioSession() async {
        await withCheckedContinuation { continuation in
            audioSessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                continuation.resume(returning: ())
            }
        }
    }

    private func handleSpeechTranscriptionResult(_ result: SpeechTranscriber.Result) {
        handleTranscriptionResult(text: result.text, range: result.range, isFinal: result.isFinal)
    }

    private func handleLocalWhisperResult(finalLines: [TranscriptionLine], interimLine: TranscriptionLine?) {
        for line in finalLines {
            handleTranscriptionResult(
                text: AttributedString(line.text),
                range: CMTimeRange(
                    start: CMTime(seconds: line.startSeconds, preferredTimescale: 1_000),
                    duration: .invalid
                ),
                isFinal: true
            )
        }

        if let interimLine {
            handleTranscriptionResult(
                text: AttributedString(interimLine.text),
                range: CMTimeRange(
                    start: CMTime(seconds: interimLine.startSeconds, preferredTimescale: 1_000),
                    duration: .invalid
                ),
                isFinal: false
            )
        } else if !finalLines.isEmpty {
            self.interimLine = nil
            interimTranscriptStore.publish(nil)
        }
    }

    private func handleTranscriptionResult(text resultText: AttributedString, range: CMTimeRange, isFinal: Bool) {
        let text = String(resultText.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        let startSeconds = range.start.seconds.isFinite ? range.start.seconds : 0
        var line = TranscriptionLine(
            startSeconds: startSeconds,
            text: text,
            isFinal: isFinal
        )

        if isFinal {
            if let index = finalizedLines.firstIndex(where: { abs($0.startSeconds - startSeconds) < 0.1 }) {
                line.id = finalizedLines[index].id
                if !manuallyEditedFinalLineIDs.contains(line.id) {
                    finalizedLines[index] = line
                }
            } else {
                insertFinalizedLine(line)
            }
            interimLine = nil
            finalTranscriptStore.publish(finalizedLines, incrementsRevision: true)
            interimTranscriptStore.publish(nil)
        } else {
            if let existing = interimLine, abs(existing.startSeconds - startSeconds) < 0.1 {
                line.id = existing.id
            }
            interimLine = line
            interimTranscriptStore.publish(line)
        }

        if !isPaused {
            let recordingStatus = String(localized: L10n.RecordingStatus.recording)
            if statusText != recordingStatus {
                statusText = recordingStatus
            }
        }

        if isFinal {
            Task {
                await self.updateLiveActivityFromCurrentState(isRecording: self.isRecording && !self.isPaused)
            }
        }
    }

    private func insertFinalizedLine(_ line: TranscriptionLine) {
        if let lastLine = finalizedLines.last,
           lastLine.startSeconds <= line.startSeconds {
            finalizedLines.append(line)
            return
        }

        let insertionIndex = finalizedLines.firstIndex { $0.startSeconds > line.startSeconds } ?? finalizedLines.endIndex
        finalizedLines.insert(line, at: insertionIndex)
    }

    private func displayedTranscriptLines(
        finalizedLines: [TranscriptionLine],
        interimLine: TranscriptionLine?
    ) -> [TranscriptionLine] {
        guard let interimLine else {
            return finalizedLines
        }

        var lines = finalizedLines
        if let index = lines.firstIndex(where: { abs($0.startSeconds - interimLine.startSeconds) < 0.1 }) {
            if manuallyEditedFinalLineIDs.contains(lines[index].id) {
                return lines
            }
            lines[index] = interimLine
            return lines
        }

        if let lastLine = lines.last,
           lastLine.startSeconds <= interimLine.startSeconds {
            lines.append(interimLine)
            return lines
        }

        let insertionIndex = lines.firstIndex { $0.startSeconds > interimLine.startSeconds } ?? lines.endIndex
        lines.insert(interimLine, at: insertionIndex)
        return lines
    }

    private func resetTranscriptStorage() {
        finalizedLines = []
        interimLine = nil
        manuallyEditedFinalLineIDs = []
        finalTranscriptStore.reset()
        interimTranscriptStore.reset()
    }

    private func handleSpeechPipelineRuntimeFormat(_ observation: SpeechPipelineRuntimeFormat) {
        guard observation != lastSpeechPipelineRuntimeFormat else {
            return
        }

        lastSpeechPipelineRuntimeFormat = observation
        speechPipelineRuntimeFormatText = observation.displayText
    }

    private func beginElapsedTimer() {
        stopTimer()
        recordingStartedAt = Date()
        activeSegmentStartedAt = Date()
        accumulatedRecordingSeconds = 0
        setElapsedSeconds(0)
        scheduleElapsedTimer()
    }

    private func resumeElapsedTimer() {
        stopTimer()
        activeSegmentStartedAt = Date()
        scheduleElapsedTimer()
    }

    private func pauseElapsedTimer() {
        if let activeSegmentStartedAt {
            accumulatedRecordingSeconds += Date().timeIntervalSince(activeSegmentStartedAt)
        }
        activeSegmentStartedAt = nil
        setElapsedSeconds(Int(accumulatedRecordingSeconds.rounded(.down)))
        stopTimer()
    }

    private func finishElapsedTimer() {
        pauseElapsedTimer()
    }

    private func setElapsedSeconds(_ seconds: Int) {
        guard elapsedSeconds != seconds else {
            return
        }
        elapsedSeconds = seconds
        elapsedClock.updateElapsedSeconds(seconds)
    }

    private func scheduleElapsedTimer() {
        elapsedTimerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let activeSeconds: TimeInterval
                if let activeSegmentStartedAt = self.activeSegmentStartedAt {
                    activeSeconds = Date().timeIntervalSince(activeSegmentStartedAt)
                } else {
                    activeSeconds = 0
                }
                let newElapsedSeconds = Int((self.accumulatedRecordingSeconds + activeSeconds).rounded(.down))
                if newElapsedSeconds != self.elapsedSeconds {
                    self.setElapsedSeconds(newElapsedSeconds)
                }

                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    private var liveActivityTranscriptText: String {
        transcriptLines.liveActivityDisplayText(maxCharacters: Self.liveActivityTextCharacterLimit)
    }

    private func updateLiveActivityFromCurrentState() async {
        await updateLiveActivityFromCurrentState(isRecording: isRecording && !isPaused)
    }

    private func updateLiveActivityFromCurrentState(isRecording liveActivityIsRecording: Bool) async {
        let snapshot = LiveActivitySnapshot(
            status: statusText,
            languageName: selectedLanguage.displayName,
            latestText: liveActivityTranscriptText,
            elapsedSeconds: elapsedSeconds,
            lineCount: transcriptLines.count,
            isRecording: liveActivityIsRecording
        )

        guard snapshot != lastLiveActivitySnapshot else {
            return
        }

        lastLiveActivitySnapshot = snapshot
        await TranscriptionLiveActivityCoordinator.update(
            status: snapshot.status,
            languageName: snapshot.languageName,
            latestText: snapshot.latestText,
            elapsedSeconds: snapshot.elapsedSeconds,
            lineCount: snapshot.lineCount,
            isRecording: snapshot.isRecording
        )
    }

    private func resetLiveActivityUpdateTracking() {
        lastLiveActivitySnapshot = nil
    }

    private func fail(with message: String) {
        isPreparing = false
        isRecording = false
        isPaused = false
        errorText = message
        statusText = message
        stopTimer()
    }

    private static func makeTemporaryRecordingURL(format: RecordingAudioFormat) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LiveTranscriber", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return directory.appendingPathComponent("Recording_\(formatter.string(from: Date())).\(format.fileExtension)")
    }

}

private struct LiveActivitySnapshot: Equatable {
    var status: String
    var languageName: String
    var latestText: String
    var elapsedSeconds: Int
    var lineCount: Int
    var isRecording: Bool
}

struct SpeechLocaleReleaseRequest: Identifiable, Equatable {
    let id = UUID()
    var targetLanguage: TranscriptionLanguage
    var targetLocaleIdentifier: String
    var releaseLocaleIdentifiers: [String]
    var maximumReservedLocaleCount: Int

    var releaseLanguageNames: String {
        releaseLocaleIdentifiers
            .map { TranscriptionLanguage(id: $0).displayName }
            .joined(separator: ", ")
    }

    var messageText: String {
        String(
            format: String(localized: L10n.SpeechText.releaseOldLanguagesMessageFormat),
            maximumReservedLocaleCount,
            targetLanguage.displayName,
            releaseLanguageNames
        )
    }
}

enum SpeechLocalePreparation {
    case ready
    case needsRelease(SpeechLocaleReleaseRequest)
}

private enum SpeechLocaleManagementError: LocalizedError {
    case noReleasableLanguages

    var errorDescription: String? {
        switch self {
        case .noReleasableLanguages:
            return String(localized: L10n.SpeechText.noReleasableLanguages)
        }
    }
}

private extension Array where Element == TranscriptionLine {
    func liveActivityDisplayText(maxCharacters: Int) -> String {
        let lines = suffix(8)
            .map { line in
                line.text
                    .replacingOccurrences(of: "\t", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")

        guard text.count > maxCharacters, maxCharacters > 1 else {
            return text
        }
        return "…" + text.suffix(maxCharacters - 1)
    }
}

private struct PreparedSpeechPipeline {
    var analyzer: SpeechAnalyzer
    var transcriber: SpeechTranscriber
    var stream: AsyncThrowingStream<AnalyzerInput, Error>
    var pipeline: AnalyzerInputPipeline
}

private enum AnalyzerInputConversionResult {
    case inputs([AnalyzerInput])
    case noData
    case failure(Error)
}

private struct SpeechPipelineRuntimeFormat: Equatable, Sendable {
    var sourceSampleRate: Double
    var sourceChannelCount: UInt32
    var sourceCommonFormat: String
    var sourceIsInterleaved: Bool
    var analyzerSampleRate: Double
    var analyzerChannelCount: UInt32
    var analyzerCommonFormat: String
    var analyzerIsInterleaved: Bool

    init(sourceFormat: AVAudioFormat, analyzerFormat: AVAudioFormat) {
        sourceSampleRate = sourceFormat.sampleRate
        sourceChannelCount = sourceFormat.channelCount
        sourceCommonFormat = Self.commonFormatName(sourceFormat.commonFormat)
        sourceIsInterleaved = sourceFormat.isInterleaved
        analyzerSampleRate = analyzerFormat.sampleRate
        analyzerChannelCount = analyzerFormat.channelCount
        analyzerCommonFormat = Self.commonFormatName(analyzerFormat.commonFormat)
        analyzerIsInterleaved = analyzerFormat.isInterleaved
    }

    var displayText: String {
        String(
            format: String(localized: L10n.SpeechText.runtimeInputMicToAnalyzerFormat),
            Self.formatDescription(
                sampleRate: sourceSampleRate,
                channelCount: sourceChannelCount,
                commonFormat: sourceCommonFormat,
                isInterleaved: sourceIsInterleaved
            ),
            Self.formatDescription(
                sampleRate: analyzerSampleRate,
                channelCount: analyzerChannelCount,
                commonFormat: analyzerCommonFormat,
                isInterleaved: analyzerIsInterleaved
            )
        )
    }

    private static func formatDescription(
        sampleRate: Double,
        channelCount: UInt32,
        commonFormat: String,
        isInterleaved: Bool
    ) -> String {
        let channels = channelCount == 1 ? "mono" : "\(channelCount) ch"
        let interleaving = isInterleaved ? "interleaved" : "non-interleaved"
        return "\(sampleRateText(sampleRate)) / \(channels) / \(commonFormat) / \(interleaving)"
    }

    private static func sampleRateText(_ sampleRate: Double) -> String {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return "unknown Hz"
        }

        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return "\(Int(kilohertz)) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    private static func commonFormatName(_ commonFormat: AVAudioCommonFormat) -> String {
        switch commonFormat {
        case .pcmFormatFloat32:
            return "Float32 PCM"
        case .pcmFormatFloat64:
            return "Float64 PCM"
        case .pcmFormatInt16:
            return "Int16 PCM"
        case .pcmFormatInt32:
            return "Int32 PCM"
        case .otherFormat:
            return "Other PCM"
        @unknown default:
            return "Unknown PCM"
        }
    }
}

private final class AnalyzerInputTimeline: @unchecked Sendable {
    private var nextStartTime = CMTime.zero

    func consume(frameLength: AVAudioFrameCount, sampleRate: Double) -> CMTime {
        let startTime = nextStartTime
        let roundedSampleRate = Int32(max(sampleRate.rounded(), 1))
        let duration = CMTime(
            value: CMTimeValue(Int64(frameLength)),
            timescale: CMTimeScale(roundedSampleRate)
        )
        nextStartTime = CMTimeAdd(nextStartTime, duration)
        return startTime
    }
}

private final class AnalyzerSourceAudioTimeline: @unchecked Sendable {
    private var nextSampleTime: AVAudioFramePosition = 0
    private var sampleRate: Double?

    func consume(buffer: AVAudioPCMBuffer) -> AVAudioTime? {
        let bufferSampleRate = buffer.format.sampleRate
        guard buffer.frameLength > 0, bufferSampleRate > 0 else {
            return nil
        }

        if let sampleRate, sampleRate != bufferSampleRate {
            let currentSeconds = Double(nextSampleTime) / sampleRate
            nextSampleTime = AVAudioFramePosition((currentSeconds * bufferSampleRate).rounded())
            self.sampleRate = bufferSampleRate
        } else if sampleRate == nil {
            sampleRate = bufferSampleRate
        }

        let audioTime = AVAudioTime(sampleTime: nextSampleTime, atRate: bufferSampleRate)
        nextSampleTime += AVAudioFramePosition(Int64(buffer.frameLength))
        return audioTime
    }
}

private final class AnalyzerInputPipeline: @unchecked Sendable {
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let convertBuffer: (AVAudioPCMBuffer, AVAudioTime) -> AnalyzerInputConversionResult
    private let flushInputs: () -> AnalyzerInputConversionResult
    private let lock = NSLock()
    private var didFinish = false

    private init(
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        convertBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> AnalyzerInputConversionResult,
        flushInputs: @escaping () -> AnalyzerInputConversionResult,
        formatObserver: @escaping @Sendable (SpeechPipelineRuntimeFormat) -> Void
    ) {
        self.continuation = continuation
        self.convertBuffer = convertBuffer
        self.flushInputs = flushInputs
    }

    #if HAS_IOS27_SDK
    @available(iOS 27.0, *)
    convenience init(
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        converter: AnalyzerInputConverter,
        formatObserver: @escaping @Sendable (SpeechPipelineRuntimeFormat) -> Void
    ) {
        let timeline = AnalyzerInputTimeline()
        let sourceTimeline = AnalyzerSourceAudioTimeline()
        self.init(
            continuation: continuation,
            convertBuffer: { buffer, _ in
                do {
                    let inputs = try converter.convert(buffer, at: sourceTimeline.consume(buffer: buffer))
                    return Self.retimeAnalyzerInputs(
                        inputs,
                        sourceFormat: buffer.format,
                        timeline: timeline,
                        formatObserver: formatObserver
                    )
                } catch {
                    return .failure(error)
                }
            },
            flushInputs: {
                do {
                    let inputs = try converter.flush()
                    return Self.retimeAnalyzerInputs(
                        inputs,
                        sourceFormat: nil,
                        timeline: timeline,
                        formatObserver: formatObserver
                    )
                } catch {
                    return .failure(error)
                }
            },
            formatObserver: formatObserver
        )
    }
    #endif

    init(
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation,
        sourceFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat,
        formatObserver: @escaping @Sendable (SpeechPipelineRuntimeFormat) -> Void
    ) throws {
        let timeline = AnalyzerInputTimeline()
        if sourceFormat.isEquivalentForAnalyzerInput(to: analyzerFormat) {
            self.convertBuffer = { buffer, _ in
                guard let copiedBuffer = buffer.deepCopy() else {
                    return .failure(LiveTranscriptionError.invalidAudioInput)
                }
                guard copiedBuffer.frameLength > 0 else {
                    return .noData
                }
                formatObserver(SpeechPipelineRuntimeFormat(sourceFormat: buffer.format, analyzerFormat: copiedBuffer.format))
                return .inputs([
                    AnalyzerInput(
                        buffer: copiedBuffer,
                        bufferStartTime: timeline.consume(
                            frameLength: copiedBuffer.frameLength,
                            sampleRate: copiedBuffer.format.sampleRate
                        )
                    )
                ])
            }
            self.flushInputs = { .noData }
        } else {
            guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
                throw LiveTranscriptionError.invalidAudioInput
            }
            self.convertBuffer = { buffer, _ in
                Self.convertWithAVAudioConverter(
                    converter,
                    buffer: buffer,
                    analyzerFormat: analyzerFormat,
                    timeline: timeline,
                    formatObserver: formatObserver
                )
            }
            self.flushInputs = { .noData }
        }
        self.continuation = continuation
    }

    #if HAS_IOS27_SDK
    @available(iOS 27.0, *)
    private static func retimeAnalyzerInputs(
        _ inputs: [AnalyzerInput],
        sourceFormat: AVAudioFormat?,
        timeline: AnalyzerInputTimeline,
        formatObserver: @Sendable (SpeechPipelineRuntimeFormat) -> Void
    ) -> AnalyzerInputConversionResult {
        let retimedInputs = inputs.compactMap { input -> AnalyzerInput? in
            let buffer = input.buffer
            guard buffer.frameLength > 0 else {
                return nil
            }
            formatObserver(SpeechPipelineRuntimeFormat(sourceFormat: sourceFormat ?? buffer.format, analyzerFormat: buffer.format))
            return AnalyzerInput(
                buffer: buffer,
                bufferStartTime: timeline.consume(
                    frameLength: buffer.frameLength,
                    sampleRate: buffer.format.sampleRate
                )
            )
        }

        return retimedInputs.isEmpty ? .noData : .inputs(retimedInputs)
    }
    #endif

    func process(_ buffer: AVAudioPCMBuffer, audioTime: AVAudioTime) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else {
            return
        }

        switch convertBuffer(buffer, audioTime) {
        case .inputs(let inputs):
            for input in inputs {
                continuation.yield(input)
            }
        case .noData:
            return
        case .failure(let error):
            didFinish = true
            liveTranscriptionLogger.error("Analyzer input conversion failed: \(error.localizedDescription, privacy: .public)")
            continuation.finish(throwing: error)
            return
        }
    }

    private static func convertWithAVAudioConverter(
        _ converter: AVAudioConverter,
        buffer: AVAudioPCMBuffer,
        analyzerFormat: AVAudioFormat,
        timeline: AnalyzerInputTimeline,
        formatObserver: @Sendable (SpeechPipelineRuntimeFormat) -> Void
    ) -> AnalyzerInputConversionResult {
        guard buffer.format.sampleRate > 0 else {
            return .failure(LiveTranscriptionError.invalidAudioInput)
        }

        let outputCapacity = AVAudioFrameCount(
            max(
                1,
                Int(ceil(Double(buffer.frameLength) * analyzerFormat.sampleRate / buffer.format.sampleRate))
            )
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: outputCapacity) else {
            return .failure(LiveTranscriptionError.invalidAudioInput)
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil else {
            return .failure(conversionError ?? LiveTranscriptionError.invalidAudioInput)
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            guard outputBuffer.frameLength > 0 else {
                return .noData
            }
            formatObserver(SpeechPipelineRuntimeFormat(sourceFormat: buffer.format, analyzerFormat: outputBuffer.format))
            return .inputs([
                AnalyzerInput(
                    buffer: outputBuffer,
                    bufferStartTime: timeline.consume(
                        frameLength: outputBuffer.frameLength,
                        sampleRate: outputBuffer.format.sampleRate
                    )
                )
            ])
        case .error:
            return .failure(conversionError ?? LiveTranscriptionError.invalidAudioInput)
        @unknown default:
            return .failure(LiveTranscriptionError.invalidAudioInput)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else {
            return
        }

        didFinish = true
        switch flushInputs() {
        case .inputs(let inputs):
            for input in inputs {
                continuation.yield(input)
            }
        case .noData:
            break
        case .failure(let error):
            liveTranscriptionLogger.error("Analyzer input flush failed: \(error.localizedDescription, privacy: .public)")
            continuation.finish(throwing: error)
            return
        }
        continuation.finish()
    }
}

private final class CaptureSessionRecordingPipeline: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.reddownloader.live-transcription.capture-session", qos: .userInitiated)
    private let sampleQueue = DispatchQueue(label: "com.reddownloader.live-transcription.capture-audio", qos: .userInitiated)
    private let recordingFormat: AVAudioFormat
    private let analyzerSourceFormat: AVAudioFormat
    private let writer: AudioFileWriter
    private let analyzerPipeline: AnalyzerInputPipeline?
    private let localWhisperPipeline: LiveLocalWhisperPipeline?
    private let inputLevelObserver: (@Sendable (Float) -> Void)?
    private let recordingConverter: CaptureSampleBufferAudioConverter
    private let analyzerConverter: CaptureSampleBufferAudioConverter

    private var input: AVCaptureDeviceInput?
    private var deviceName = ""
    private var isConfigured = false
    private var didReportFirstFormat = false
    private var didReportConversionFailure = false
    private var lastInputLevelReportTime: UInt64 = 0

    init(
        recordingFormat: AVAudioFormat,
        analyzerSourceFormat: AVAudioFormat,
        writer: AudioFileWriter,
        analyzerPipeline: AnalyzerInputPipeline?,
        localWhisperPipeline: LiveLocalWhisperPipeline? = nil,
        inputLevelObserver: (@Sendable (Float) -> Void)? = nil
    ) {
        self.recordingFormat = recordingFormat
        self.analyzerSourceFormat = analyzerSourceFormat
        self.writer = writer
        self.analyzerPipeline = analyzerPipeline
        self.localWhisperPipeline = localWhisperPipeline
        self.inputLevelObserver = inputLevelObserver
        recordingConverter = CaptureSampleBufferAudioConverter(targetFormat: recordingFormat)
        analyzerConverter = CaptureSampleBufferAudioConverter(targetFormat: analyzerSourceFormat)
        super.init()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    guard !self.session.isRunning else {
                        continuation.resume(returning: ())
                        return
                    }

                    self.session.startRunning()
                    guard self.session.isRunning else {
                        throw LiveTranscriptionError.invalidAudioInput
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        let captureInput = try AVCaptureDeviceInput(device: device)
        guard captureInput.isMultichannelAudioModeSupported(.stereo) else {
            throw LiveTranscriptionError.stereoCaptureUnavailable
        }
        captureInput.multichannelAudioMode = .stereo

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        guard session.canAddInput(captureInput) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        session.addInput(captureInput)

        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(output) else {
            throw LiveTranscriptionError.invalidAudioInput
        }
        session.addOutput(output)

        input = captureInput
        deviceName = device.localizedName
        isConfigured = true
        liveTranscriptionLogger.debug(
            "AVCapture Stereo configured device=\(device.localizedName, privacy: .public) file=\(liveAudioFormatSummary(self.recordingFormat), privacy: .public) analyzer=\(liveAudioFormatSummary(self.analyzerSourceFormat), privacy: .public)"
        )
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        do {
            let sourceBuffer = try CaptureSampleBufferAudioConverter.makePCMBuffer(from: sampleBuffer)
            let recordingBuffer = try recordingConverter.convert(sourceBuffer)
            let analyzerBuffer = try analyzerConverter.convert(sourceBuffer)
            reportInputLevelIfNeeded(recordingBuffer)
            reportFirstFormatIfNeeded(
                sourceFormat: sourceBuffer.format,
                recordingFormat: recordingBuffer.format,
                analyzerSourceFormat: analyzerBuffer.format
            )
            writer.write(recordingBuffer)
            analyzerPipeline?.process(analyzerBuffer, audioTime: Self.audioTime(for: sampleBuffer, format: analyzerBuffer.format))
            localWhisperPipeline?.process(analyzerBuffer)
        } catch {
            reportConversionFailureIfNeeded(error)
        }
    }

    private func reportInputLevelIfNeeded(_ buffer: AVAudioPCMBuffer) {
        guard let inputLevelObserver else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastInputLevelReportTime >= 33_000_000 else {
            return
        }

        lastInputLevelReportTime = now
        inputLevelObserver(Self.normalizedInputLevel(for: buffer))
    }

    private static func normalizedInputLevel(for buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return 0
        }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                return 0
            }
            return normalizedFloatLevel(channelData: channelData, channelCount: channelCount, frameCount: frameCount)
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                return 0
            }
            return normalizedInt16Level(channelData: channelData, channelCount: channelCount, frameCount: frameCount)
        default:
            return 0
        }
    }

    private static func normalizedFloatLevel(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int
    ) -> Float {
        let stride = max(frameCount / 512, 1)
        var sum: Float = 0
        var count = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var frame = 0
            while frame < frameCount {
                let sample = samples[frame]
                sum += sample * sample
                count += 1
                frame += stride
            }
        }

        return normalizedRMS(sum: sum, count: count)
    }

    private static func normalizedInt16Level(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        channelCount: Int,
        frameCount: Int
    ) -> Float {
        let stride = max(frameCount / 512, 1)
        var sum: Float = 0
        var count = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var frame = 0
            while frame < frameCount {
                let sample = Float(samples[frame]) / Float(Int16.max)
                sum += sample * sample
                count += 1
                frame += stride
            }
        }

        return normalizedRMS(sum: sum, count: count)
    }

    private static func normalizedRMS(sum: Float, count: Int) -> Float {
        guard count > 0 else {
            return 0
        }

        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(max((decibels + 54) / 54, 0), 1)
    }

    private func reportFirstFormatIfNeeded(
        sourceFormat: AVAudioFormat,
        recordingFormat: AVAudioFormat,
        analyzerSourceFormat: AVAudioFormat
    ) {
        guard !didReportFirstFormat else {
            return
        }

        didReportFirstFormat = true
        let name = deviceName.isEmpty ? String(localized: L10n.Common.unknown) : deviceName
        liveTranscriptionLogger.debug(
            "AVCapture Stereo first buffer device=\(name, privacy: .public) source=\(liveAudioFormatSummary(sourceFormat), privacy: .public) file=\(liveAudioFormatSummary(recordingFormat), privacy: .public) analyzer=\(liveAudioFormatSummary(analyzerSourceFormat), privacy: .public)"
        )
    }

    private func reportConversionFailureIfNeeded(_ error: Error) {
        guard !didReportConversionFailure else {
            return
        }

        didReportConversionFailure = true
        liveTranscriptionLogger.error("AVCapture audio conversion failed: \(error.localizedDescription, privacy: .public)")
    }

    private static func audioTime(for sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioTime {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid,
              presentationTime.seconds.isFinite,
              format.sampleRate > 0 else {
            return AVAudioTime(sampleTime: 0, atRate: max(format.sampleRate, 1))
        }

        return AVAudioTime(
            sampleTime: AVAudioFramePosition((presentationTime.seconds * format.sampleRate).rounded()),
            atRate: format.sampleRate
        )
    }
}

private final class CaptureSampleBufferAudioConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ sourceBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard sourceBuffer.frameLength > 0 else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        if sourceBuffer.format.isEquivalentForAnalyzerInput(to: targetFormat) {
            guard let copiedBuffer = sourceBuffer.deepCopy() else {
                throw LiveTranscriptionError.invalidAudioInput
            }
            return copiedBuffer
        }

        let activeConverter: AVAudioConverter
        if let converter,
           let converterSourceFormat,
           converterSourceFormat.isEquivalentForAnalyzerInput(to: sourceBuffer.format) {
            activeConverter = converter
        } else {
            guard let newConverter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
                throw LiveTranscriptionError.invalidAudioInput
            }
            converter = newConverter
            converterSourceFormat = sourceBuffer.format
            activeConverter = newConverter
        }

        let outputCapacity = AVAudioFrameCount(
            max(
                1,
                Int(ceil(Double(sourceBuffer.frameLength) * targetFormat.sampleRate / sourceBuffer.format.sampleRate))
            )
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = activeConverter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            guard outputBuffer.frameLength > 0 else {
                throw LiveTranscriptionError.invalidAudioInput
            }
            return outputBuffer
        case .error:
            throw conversionError ?? LiveTranscriptionError.invalidAudioInput
        @unknown default:
            throw LiveTranscriptionError.invalidAudioInput
        }
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0, sampleCount <= Int32.max else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        var audioStreamDescription = streamDescription.pointee
        guard let sourceFormat = AVAudioFormat(streamDescription: &audioStreamDescription),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(sampleCount)
              ) else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(sampleCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw LiveTranscriptionError.invalidAudioInput
        }

        return buffer
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copiedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        copiedBuffer.frameLength = frameLength

        let channelCount = Int(format.channelCount)
        let frameCount = Int(frameLength)
        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let source = floatChannelData,
                  let destination = copiedBuffer.floatChannelData else {
                return nil
            }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        case .pcmFormatInt16:
            guard let source = int16ChannelData,
                  let destination = copiedBuffer.int16ChannelData else {
                return nil
            }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        case .pcmFormatInt32:
            guard let source = int32ChannelData,
                  let destination = copiedBuffer.int32ChannelData else {
                return nil
            }
            for channel in 0..<channelCount {
                destination[channel].update(from: source[channel], count: frameCount)
            }
        default:
            return nil
        }

        return copiedBuffer
    }
}

private extension AVAudioFormat {
    func isEquivalentForAnalyzerInput(to other: AVAudioFormat) -> Bool {
        commonFormat == other.commonFormat &&
        sampleRate == other.sampleRate &&
        channelCount == other.channelCount &&
        isInterleaved == other.isInterleaved
    }
}

private final class LiveLocalWhisperPipeline: @unchecked Sendable {
    typealias ResultHandler = @Sendable (_ finalLines: [TranscriptionLine], _ interimLine: TranscriptionLine?) -> Void
    typealias ErrorHandler = @Sendable (_ error: Error) -> Void

    private let queue = DispatchQueue(label: "com.reddownloader.live-transcription.local-whisper", qos: .userInitiated)
    private let inputSampleRate: Double
    private let modelURL: URL
    private let languageCode: String
    private let useCoreMLEncoder: Bool
    private let resultHandler: ResultHandler
    private let errorHandler: ErrorHandler
    private let chunkFrameCount: Int
    private let stateLock = NSLock()

    private var bufferedSamples: [Float] = []
    private var bufferedStartFrame = 0
    private var isFinished = false
    private var isCancelled = false

    init(
        inputSampleRate: Double,
        modelURL: URL,
        languageCode: String,
        useCoreMLEncoder: Bool,
        resultHandler: @escaping ResultHandler,
        errorHandler: @escaping ErrorHandler
    ) {
        self.inputSampleRate = inputSampleRate
        self.modelURL = modelURL
        self.languageCode = languageCode
        self.useCoreMLEncoder = useCoreMLEncoder
        self.resultHandler = resultHandler
        self.errorHandler = errorHandler
        chunkFrameCount = max(1, Int((inputSampleRate * 8).rounded()))
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard !cancelled else {
            return
        }
        guard buffer.frameLength > 0,
              buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeMutableBufferPointer { destination in
            guard let baseAddress = destination.baseAddress else {
                return
            }
            baseAddress.update(from: channelData[0], count: frameCount)
        }

        queue.async {
            guard !self.isFinished, !self.cancelled else {
                return
            }

            self.bufferedSamples.append(contentsOf: samples)
            self.runAvailableChunks()
        }
    }

    func cancel() {
        stateLock.lock()
        isCancelled = true
        isFinished = true
        stateLock.unlock()
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !self.cancelled else {
                    continuation.resume()
                    return
                }
                self.isFinished = true
                self.runRemainingChunk()
                continuation.resume()
            }
        }
    }

    private func runAvailableChunks() {
        while !cancelled, bufferedSamples.count >= chunkFrameCount {
            runInference(frameCount: chunkFrameCount)
        }
    }

    private func runRemainingChunk() {
        guard !bufferedSamples.isEmpty else {
            resultHandler([], nil)
            return
        }
        runInference(frameCount: bufferedSamples.count)
    }

    private func runInference(frameCount requestedFrameCount: Int) {
        guard !cancelled else {
            return
        }
        guard !bufferedSamples.isEmpty else {
            return
        }

        let frameCount = min(max(requestedFrameCount, 0), bufferedSamples.count)
        guard frameCount > 0 else {
            return
        }

        let chunkStartFrame = bufferedStartFrame
        let chunkSamples = Array(bufferedSamples[0..<frameCount])
        let chunkStartSeconds = Double(chunkStartFrame) / inputSampleRate

        do {
            let segments = try transcribe(chunkSamples)
            guard !cancelled else {
                return
            }
            var finalLines: [TranscriptionLine] = []

            for segment in segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    continue
                }

                finalLines.append(TranscriptionLine(
                    startSeconds: chunkStartSeconds + max(segment.startSeconds, 0),
                    text: text,
                    isFinal: true
                ))
            }

            resultHandler(finalLines, nil)
            bufferedSamples.removeFirst(frameCount)
            bufferedStartFrame += frameCount
        } catch {
            if !cancelled {
                errorHandler(error)
            }
        }
    }

    private var cancelled: Bool {
        stateLock.lock()
        let value = isCancelled
        stateLock.unlock()
        return value
    }

    private func transcribe(_ samples: [Float]) throws -> [LocalWhisperBridgeSegment] {
        guard !samples.isEmpty else {
            return []
        }

        let sampleData = samples.withUnsafeBufferPointer { buffer -> Data in
            guard let baseAddress = buffer.baseAddress else {
                return Data()
            }
            return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.stride)
        }

        return try LocalWhisperBridge.transcribeSamples(
            sampleData,
            modelPath: modelURL.path,
            languageCode: languageCode.isEmpty ? "auto" : languageCode,
            useCoreMLEncoder: useCoreMLEncoder
        )
    }
}

private final class AudioFileWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let lock = NSLock()

    init(url: URL, inputFormat: AVAudioFormat, outputFormat: RecordingAudioFormat) throws {
        file = try AVAudioFile(
            forWriting: url,
            settings: Self.settings(for: outputFormat, inputFormat: inputFormat),
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? file.write(from: buffer)
    }

    static func settings(
        for outputFormat: RecordingAudioFormat,
        inputFormat: AVAudioFormat
    ) -> [String: Any] {
        let sampleRate = inputFormat.sampleRate
        let channelCount = Int(inputFormat.channelCount)

        switch outputFormat {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: !inputFormat.isInterleaved
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: min(max(channelCount, 1), 2) * 64_000
            ]
        }
    }
}

private enum RecordingAudioSessionMode {
    case captureStereo

    var audioSessionMode: AVAudioSession.Mode {
        switch self {
        case .captureStereo:
            return .default
        }
    }

    var audioSessionOptions: AVAudioSession.CategoryOptions {
        switch self {
        case .captureStereo:
            return [.defaultToSpeaker, .duckOthers]
        }
    }

    var preferredInputChannelCount: Int? {
        switch self {
        case .captureStereo:
            return 2
        }
    }

    static var defaultMode: RecordingAudioSessionMode {
        .captureStereo
    }
}

enum SpeechPipelineMode: String, CaseIterable, Identifiable {
    case compatible
    case nativeIOS27

    var id: String {
        rawValue
    }

    var title: String {
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .compatible:
            return L10n.SpeechText.compatiblePipelineTitle
        case .nativeIOS27:
            return L10n.SpeechText.nativePipelineTitle
        }
    }

    var detail: String {
        String(localized: detailResource)
    }

    var detailResource: LocalizedStringResource {
        switch self {
        case .compatible:
            return L10n.SpeechText.compatiblePipelineDetail
        case .nativeIOS27:
            return L10n.SpeechText.nativePipelineDetail
        }
    }

    var isSupportedOnCurrentOS: Bool {
        switch self {
        case .compatible:
            return true
        case .nativeIOS27:
            #if HAS_IOS27_SDK
            if #available(iOS 27.0, *) {
                return true
            }
            #endif
            return false
        }
    }
}

struct SpeechProcessingPipelineDiagnostics: Equatable {
    var configuredPipelineName: String
    var activePipelineName: String
    var supportedPipelinesText: String
    var analyzerFormatText: String
    var runtimeAnalyzerFormatText: String

    static func current(
        backend: LiveTranscriptionBackend,
        configuredMode: SpeechPipelineMode,
        runtimeAnalyzerFormatText: String
    ) -> SpeechProcessingPipelineDiagnostics {
        if backend.usesLocalWhisper {
            return SpeechProcessingPipelineDiagnostics(
                configuredPipelineName: backend.title,
                activePipelineName: String(localized: L10n.SpeechText.activeLocalWhisper),
                supportedPipelinesText: String(localized: L10n.SpeechText.supportedPipelinesLocalWhisper),
                analyzerFormatText: String(localized: L10n.SpeechText.localWhisperInput16K),
                runtimeAnalyzerFormatText: String(localized: L10n.SpeechText.localWhisperInput16K)
            )
        }

        #if HAS_IOS27_SDK
        if #available(iOS 27.0, *), configuredMode == .nativeIOS27 {
            return SpeechProcessingPipelineDiagnostics(
                configuredPipelineName: configuredMode.title,
                activePipelineName: String(localized: L10n.SpeechText.activeNativeCompatibleWith),
                supportedPipelinesText: String(localized: L10n.SpeechText.supportedPipelinesIOS27),
                analyzerFormatText: String(localized: L10n.SpeechText.analyzerAdaptiveIOS27),
                runtimeAnalyzerFormatText: runtimeAnalyzerFormatText
            )
        }

        if #available(iOS 27.0, *) {
            return SpeechProcessingPipelineDiagnostics(
                configuredPipelineName: configuredMode.title,
                activePipelineName: String(localized: L10n.SpeechText.activeCompatibleAVAudioConverter),
                supportedPipelinesText: String(localized: L10n.SpeechText.supportedPipelinesIOS27),
                analyzerFormatText: String(localized: L10n.SpeechText.analyzerFixed16K),
                runtimeAnalyzerFormatText: runtimeAnalyzerFormatText
            )
        }
        #endif

        return SpeechProcessingPipelineDiagnostics(
            configuredPipelineName: configuredMode.title,
            activePipelineName: String(localized: L10n.SpeechText.activeIOS26AVAudioConverter),
            supportedPipelinesText: String(localized: L10n.SpeechText.supportedPipelinesIOS26),
            analyzerFormatText: String(localized: L10n.SpeechText.analyzerFixed16K),
            runtimeAnalyzerFormatText: runtimeAnalyzerFormatText
        )
    }
}

private enum LiveTranscriptionError: LocalizedError {
    case invalidAudioInput
    case analyzerUnavailable
    case unsupportedLanguage
    case stereoCaptureUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAudioInput:
            return String(localized: L10n.SpeechText.cannotReadMicrophone)
        case .analyzerUnavailable:
            return String(localized: L10n.SpeechText.analyzerUnavailable)
        case .unsupportedLanguage:
            return String(localized: L10n.SpeechText.unsupportedLanguage)
        case .stereoCaptureUnavailable:
            return String(localized: L10n.SpeechText.stereoUnsupported)
        }
    }
}
