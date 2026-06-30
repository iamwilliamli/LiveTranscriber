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
final class LiveTranscriptionManager: ObservableObject {
    @Published private(set) var transcriptLines: [TranscriptionLine] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isPreparing = false
    @Published private(set) var statusText = String(localized: "准备就绪")
    @Published private(set) var errorText: String?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var inputLevelHistory: [Float] = Array(repeating: 0, count: 72)
    @Published private(set) var supportedLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @Published private(set) var speechPipelineRuntimeFormatText = String(localized: "Runtime Analyzer 输入: 等待录音")
    @Published var selectedAudioFormat: RecordingAudioFormat {
        didSet {
            UserDefaults.standard.set(selectedAudioFormat.rawValue, forKey: Self.audioFormatDefaultsKey)
        }
    }
    @Published var isLoudnessProcessingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoudnessProcessingEnabled, forKey: Self.loudnessProcessingDefaultsKey)
        }
    }
    @Published var selectedLanguageID: String {
        didSet {
            UserDefaults.standard.set(selectedLanguageID, forKey: Self.languageDefaultsKey)
            if !isRecording && !isPreparing {
                statusText = String(localized: "准备就绪")
            }
        }
    }
    @Published var selectedSpeechPipelineMode: SpeechPipelineMode {
        didSet {
            UserDefaults.standard.set(selectedSpeechPipelineMode.rawValue, forKey: Self.speechPipelineModeDefaultsKey)
        }
    }

    private static let languageDefaultsKey = "transcription.language"
    private static let audioFormatDefaultsKey = "recording.audioFormat"
    private static let loudnessProcessingDefaultsKey = "developer.loudnessProcessingEnabled"
    private static let speechPipelineModeDefaultsKey = "speech.pipelineMode"
    private static let analyzerSampleRate: Double = 16_000
    private static let inputLevelHistoryCount = 72
    private static let inputLevelHistorySampleInterval: TimeInterval = 0.08

    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcription.audio-session", qos: .userInitiated)
    private var analyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var analyzerPipeline: AnalyzerInputPipeline?
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
    private var currentAudioOutputFormat: RecordingAudioFormat?
    private var smoothedInputLevel: Float = 0
    private var lastInputLevelHistorySampleAt: TimeInterval = 0
    private var finalizedLines: [TranscriptionLine] = []
    private var interimLine: TranscriptionLine?
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

    var hasTranscript: Bool {
        !plainTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var speechPipelineDiagnostics: SpeechProcessingPipelineDiagnostics {
        .current(
            configuredMode: selectedSpeechPipelineMode,
            runtimeAnalyzerFormatText: speechPipelineRuntimeFormatText
        )
    }

    init() {
        selectedLanguageID = UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? TranscriptionLanguage.defaultLanguageID
        if let rawMode = UserDefaults.standard.string(forKey: Self.speechPipelineModeDefaultsKey),
           let storedMode = SpeechPipelineMode(rawValue: rawMode) {
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

        if UserDefaults.standard.object(forKey: Self.loudnessProcessingDefaultsKey) == nil {
            isLoudnessProcessingEnabled = false
        } else {
            isLoudnessProcessingEnabled = UserDefaults.standard.bool(forKey: Self.loudnessProcessingDefaultsKey)
        }
    }

    func refreshSupportedLanguages() async {
        let locales = await SpeechTranscriber.supportedLocales
        let languages = locales
            .map { TranscriptionLanguage(id: $0.identifier) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        if !languages.isEmpty {
            supportedLanguages = languages
            if !languages.contains(where: { $0.id == selectedLanguageID }) {
                if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: selectedLanguageID)) {
                    selectedLanguageID = equivalent.identifier
                } else if let preferred = languages.first(where: { $0.id == TranscriptionLanguage.defaultLanguageID }) {
                    selectedLanguageID = preferred.id
                } else if let first = languages.first {
                    selectedLanguageID = first.id
                }
            }
        }
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
        speechPipelineRuntimeFormatText = String(localized: "Runtime Analyzer 输入: 等待首个 buffer")
        resetTranscriptStorage()
        statusText = String(localized: "正在请求权限")

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
            statusText = String(localized: "正在录音")
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
            fail(with: String(format: String(localized: "录音启动失败: %@"), error.localizedDescription))
        }
    }

    private func startCaptureSessionRecording(language: TranscriptionLanguage) async throws {
        try await configureAudioSession()

        let audioFormat = selectedAudioFormat
        let recordingFormat = try Self.makeCaptureSessionRecordingFormat()
        let analyzerSourceFormat = try Self.makeCaptureSessionAnalyzerSourceFormat(sampleRate: recordingFormat.sampleRate)
        let prepared = try await prepareSpeechPipeline(language: language, audioInputFormat: analyzerSourceFormat)
        let recordingURL = try Self.makeTemporaryRecordingURL(format: audioFormat)
        let writer = try AudioFileWriter(url: recordingURL, inputFormat: recordingFormat, outputFormat: audioFormat)
        let inputLevelObserver: @Sendable (Float) -> Void = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.handleInputLevel(level)
            }
        }
        let capturePipeline = CaptureSessionRecordingPipeline(
            recordingFormat: recordingFormat,
            analyzerSourceFormat: analyzerSourceFormat,
            writer: writer,
            analyzerPipeline: prepared.pipeline,
            inputLevelObserver: inputLevelObserver
        )

        analyzer = prepared.analyzer
        speechTranscriber = prepared.transcriber
        analyzerPipeline = prepared.pipeline
        captureRecordingPipeline = capturePipeline
        audioWriter = writer
        currentAudioURL = recordingURL
        currentRecordingFormat = recordingFormat
        currentAudioOutputFormat = audioFormat

        startResultReader(for: prepared.transcriber)
        startAnalyzer(prepared.analyzer, stream: prepared.stream)
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
        statusText = String(localized: "已暂停")
        await deactivateAudioSession()
        await updateLiveActivityFromCurrentState(isRecording: false)
    }

    func resumeRecording() async {
        guard isRecording, isPaused else {
            return
        }
        guard let captureRecordingPipeline else {
            fail(with: String(localized: "录音恢复失败"))
            return
        }

        do {
            try await configureAudioSession()
            try await captureRecordingPipeline.start()
            resumeElapsedTimer()
            isPaused = false
            statusText = String(localized: "正在录音")
            await updateLiveActivityFromCurrentState(isRecording: true)
        } catch {
            fail(with: String(format: String(localized: "录音恢复失败: %@"), error.localizedDescription))
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
        captureRecordingPipeline = nil
        audioWriter = nil
        currentRecordingFormat = nil

        finishElapsedTimer()
        let finishedLines = transcriptLines
        let recordingURL = currentAudioURL
        let audioOutputFormat = currentAudioOutputFormat ?? selectedAudioFormat
        currentAudioURL = nil
        currentAudioOutputFormat = nil
        let startedAt = recordingStartedAt ?? Date()
        recordingStartedAt = nil

        statusText = hasTranscript ? String(localized: "转录完成") : String(localized: "已停止")
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

        let audioNormalizedAt: Date?
        if isLoudnessProcessingEnabled {
            statusText = String(localized: "正在增强录音音量")
            do {
                try await RecordingFileNormalizer.normalize(url: recordingURL, outputFormat: audioOutputFormat)
                audioNormalizedAt = Date()
            } catch {
                audioNormalizedAt = nil
            }
        } else {
            audioNormalizedAt = nil
        }
        statusText = hasTranscript ? String(localized: "转录完成") : String(localized: "已停止")

        return RecordingDraft(
            audioURL: recordingURL,
            startedAt: startedAt,
            durationSeconds: elapsedSeconds,
            languageID: selectedLanguageID,
            languageName: selectedLanguage.displayName,
            lines: finishedLines,
            audioNormalizedAt: audioNormalizedAt,
            audioNormalizationVersion: audioNormalizedAt == nil ? nil : RecordingFileNormalizer.version
        )
    }

    func clearTranscript() {
        resetTranscriptStorage()
        errorText = nil
        if !isRecording {
            statusText = String(localized: "准备就绪")
            elapsedSeconds = 0
            resetInputLevel(clearHistory: true)
            accumulatedRecordingSeconds = 0
            recordingStartedAt = nil
            activeSegmentStartedAt = nil
        }
    }

    private func prepareSpeechPipeline(
        language: TranscriptionLanguage,
        audioInputFormat: AVAudioFormat
    ) async throws -> PreparedSpeechPipeline {
        statusText = String(localized: "正在准备语言模型")
        guard SpeechTranscriber.isAvailable else {
            throw LiveTranscriptionError.analyzerUnavailable
        }

        let preferredLocale = Locale(identifier: language.id)
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale) ?? preferredLocale
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

        let pipeline: AnalyzerInputPipeline
        let formatObserver: @Sendable (SpeechPipelineRuntimeFormat) -> Void = { [weak self] observation in
            Task { @MainActor [weak self] in
                self?.handleSpeechPipelineRuntimeFormat(observation)
            }
        }
        if #available(iOS 27.0, *), selectedSpeechPipelineMode == .nativeIOS27 {
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: modules)
            try await analyzer.prepareToAnalyze(in: nil)
            pipeline = AnalyzerInputPipeline(
                continuation: continuation,
                converter: converter,
                formatObserver: formatObserver
            )
        } else {
            let analyzerInputFormat = try Self.makeAnalyzerInputFormat()
            try await analyzer.prepareToAnalyze(in: analyzerInputFormat)
            pipeline = try AnalyzerInputPipeline(
                continuation: continuation,
                sourceFormat: audioInputFormat,
                analyzerFormat: analyzerInputFormat,
                formatObserver: formatObserver
            )
        }

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
        if #available(iOS 27.0, *) {
            return SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .whileInUse,
                ignoresResourceLimits: true
            )
        }

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
            statusText = String(localized: "正在下载语言模型")
        case .supported, .installed:
            break
        @unknown default:
            break
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            statusText = String(localized: "正在下载语言模型")
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
                        self.handleTranscriptionResult(result)
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
        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            let message = speechStatus == .restricted
                ? String(localized: "语音识别受系统限制")
                : String(localized: "语音识别权限被拒绝")
            fail(with: message)
            return false
        }

        guard await requestMicrophoneAuthorization() else {
            fail(with: String(localized: "麦克风权限被拒绝"))
            return false
        }

        return true
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
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

    private func handleTranscriptionResult(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }

        let startSeconds = result.range.start.seconds.isFinite ? result.range.start.seconds : 0
        var line = TranscriptionLine(
            startSeconds: startSeconds,
            text: text,
            isFinal: result.isFinal
        )

        if result.isFinal {
            if let index = finalizedLines.firstIndex(where: { abs($0.startSeconds - startSeconds) < 0.1 }) {
                line.id = finalizedLines[index].id
                finalizedLines[index] = line
            } else {
                finalizedLines.append(line)
            }
            interimLine = nil
        } else {
            if let existing = interimLine, abs(existing.startSeconds - startSeconds) < 0.1 {
                line.id = existing.id
            }
            interimLine = line
        }

        publishLines()
        if !isPaused {
            statusText = String(localized: "正在录音")
        }

        if result.isFinal {
            Task {
                await self.updateLiveActivityFromCurrentState(isRecording: self.isRecording && !self.isPaused)
            }
        }
    }

    private func publishLines() {
        var lines = finalizedLines.sorted { $0.startSeconds < $1.startSeconds }
        if let interimLine {
            if let index = lines.firstIndex(where: { abs($0.startSeconds - interimLine.startSeconds) < 0.1 }) {
                lines[index] = interimLine
            } else {
                lines.append(interimLine)
            }
        }
        transcriptLines = lines.sorted { $0.startSeconds < $1.startSeconds }
    }

    private func resetTranscriptStorage() {
        finalizedLines = []
        interimLine = nil
        transcriptLines = []
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
        elapsedSeconds = 0
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
        elapsedSeconds = Int(accumulatedRecordingSeconds.rounded(.down))
        stopTimer()
    }

    private func finishElapsedTimer() {
        pauseElapsedTimer()
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
                    self.elapsedSeconds = newElapsedSeconds
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
            format: String(localized: "Runtime Analyzer 输入: Mic %@ -> Analyzer %@"),
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
    private let analyzerPipeline: AnalyzerInputPipeline
    private let inputLevelObserver: @Sendable (Float) -> Void
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
        analyzerPipeline: AnalyzerInputPipeline,
        inputLevelObserver: @escaping @Sendable (Float) -> Void
    ) {
        self.recordingFormat = recordingFormat
        self.analyzerSourceFormat = analyzerSourceFormat
        self.writer = writer
        self.analyzerPipeline = analyzerPipeline
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
            analyzerPipeline.process(analyzerBuffer, audioTime: Self.audioTime(for: sampleBuffer, format: analyzerBuffer.format))
        } catch {
            reportConversionFailureIfNeeded(error)
        }
    }

    private func reportInputLevelIfNeeded(_ buffer: AVAudioPCMBuffer) {
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
        let name = deviceName.isEmpty ? String(localized: "未知") : deviceName
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

enum RecordingFileNormalizer {
    static let version = 2

    private static let targetActiveRMS: Float = 0.20
    private static let maximumGain: Float = 16
    private static let limiterCeiling: Float = 0.94
    private static let activeSampleThreshold: Float = 0.012
    private static let minimumActiveRMS: Float = 0.006
    private static let frameCapacity: AVAudioFrameCount = 8_192

    static func normalize(url: URL, outputFormat: RecordingAudioFormat) async throws {
        try await Task.detached(priority: .utility) {
            try normalizeSynchronously(url: url, outputFormat: outputFormat)
        }.value
    }

    private static func normalizeSynchronously(url: URL, outputFormat: RecordingAudioFormat) throws {
        let processingFormat: AVAudioFormat
        let stats: AVAudioPCMBuffer.LevelStats
        do {
            let input = try AVAudioFile(forReading: url)
            processingFormat = input.processingFormat
            stats = try wholeFileLevelStats(file: input, format: processingFormat)
        }

        guard stats.activeSampleCount > 0, stats.activeRMS >= minimumActiveRMS else {
            return
        }

        let gain = min(max(targetActiveRMS / max(stats.activeRMS, 0.0001), 1), maximumGain)
        guard gain > 1.05 else {
            return
        }

        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".normalized-\(UUID().uuidString).\(outputFormat.fileExtension)")

        do {
            let input = try AVAudioFile(forReading: url)
            let output = try AVAudioFile(
                forWriting: temporaryURL,
                settings: AudioFileWriter.settings(for: outputFormat, inputFormat: processingFormat),
                commonFormat: processingFormat.commonFormat,
                interleaved: processingFormat.isInterleaved
            )
            try writeNormalizedAudio(input: input, output: output, format: processingFormat, gain: gain)
        }

        try replaceAudioFile(at: url, with: temporaryURL)
    }

    private static func wholeFileLevelStats(file: AVAudioFile, format: AVAudioFormat) throws -> AVAudioPCMBuffer.LevelStats {
        var sumSquares: Double = 0
        var peak: Float = 0
        var sampleCount = 0
        var activeSumSquares: Double = 0
        var activeSampleCount = 0

        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                break
            }
            let remainingFrames = AVAudioFrameCount(min(AVAudioFramePosition(frameCapacity), file.length - file.framePosition))
            try file.read(into: buffer, frameCount: remainingFrames)
            guard let stats = buffer.levelStats(activeThreshold: activeSampleThreshold) else {
                continue
            }

            let count = buffer.sampleCount
            sumSquares += Double(stats.rms * stats.rms) * Double(count)
            peak = max(peak, stats.peak)
            sampleCount += count
            activeSumSquares += Double(stats.activeRMS * stats.activeRMS) * Double(stats.activeSampleCount)
            activeSampleCount += stats.activeSampleCount
        }

        guard sampleCount > 0 else {
            return .init(rms: 0, peak: 0)
        }

        let activeRMS = activeSampleCount > 0 ? Float(sqrt(activeSumSquares / Double(activeSampleCount))) : 0
        return .init(
            rms: Float(sqrt(sumSquares / Double(sampleCount))),
            peak: peak,
            activeRMS: activeRMS,
            activeSampleCount: activeSampleCount
        )
    }

    private static func writeNormalizedAudio(
        input: AVAudioFile,
        output: AVAudioFile,
        format: AVAudioFormat,
        gain: Float
    ) throws {
        while input.framePosition < input.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                break
            }
            let remainingFrames = AVAudioFrameCount(min(AVAudioFramePosition(frameCapacity), input.length - input.framePosition))
            try input.read(into: buffer, frameCount: remainingFrames)
            buffer.applyGain(gain, limiterCeiling: limiterCeiling)
            try output.write(from: buffer)
        }
    }

    private static func replaceAudioFile(at originalURL: URL, with normalizedURL: URL) throws {
        let backupURL = originalURL
            .deletingLastPathComponent()
            .appendingPathComponent(".backup-\(UUID().uuidString).\(originalURL.pathExtension)")
        try FileManager.default.moveItem(at: originalURL, to: backupURL)
        do {
            try FileManager.default.moveItem(at: normalizedURL, to: originalURL)
            try? FileManager.default.removeItem(at: backupURL)
        } catch {
            try? FileManager.default.moveItem(at: backupURL, to: originalURL)
            try? FileManager.default.removeItem(at: normalizedURL)
            throw error
        }
    }
}

private extension AVAudioPCMBuffer {
    struct LevelStats {
        var rms: Float
        var peak: Float
        var activeRMS: Float
        var activeSampleCount: Int

        init(rms: Float, peak: Float, activeRMS: Float? = nil, activeSampleCount: Int = 0) {
            self.rms = rms
            self.peak = peak
            self.activeRMS = activeRMS ?? rms
            self.activeSampleCount = activeSampleCount
        }
    }

    var sampleCount: Int {
        Int(frameLength) * Int(format.channelCount)
    }

    func levelStats(activeThreshold: Float = 0.012) -> LevelStats? {
        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return nil
        }

        if let channelData = floatChannelData {
            return floatLevelStats(channelData: channelData, frameCount: frameCount, channelCount: channelCount, activeThreshold: activeThreshold)
        } else if let channelData = int16ChannelData {
            return int16LevelStats(channelData: channelData, frameCount: frameCount, channelCount: channelCount, activeThreshold: activeThreshold)
        }

        return nil
    }

    func applyGain(_ gain: Float, limiterCeiling: Float) {
        if let channelData = floatChannelData {
            applyFloatGain(channelData: channelData, gain: gain, limiterCeiling: limiterCeiling)
        } else if let channelData = int16ChannelData {
            applyInt16Gain(channelData: channelData, gain: gain, limiterCeiling: limiterCeiling)
        }
    }

    private func floatLevelStats(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channelCount: Int,
        activeThreshold: Float
    ) -> LevelStats {
        var sumSquares: Float = 0
        var peak: Float = 0
        var activeSumSquares: Float = 0
        var activeSampleCount = 0
        let sampleCount = interleavedSampleCount(frameCount: frameCount, channelCount: channelCount)

        withSamples(channelData: channelData, frameCount: frameCount, channelCount: channelCount) { sample in
            let value = abs(sample)
            peak = max(peak, value)
            sumSquares += sample * sample
            if value >= activeThreshold {
                activeSumSquares += sample * sample
                activeSampleCount += 1
            }
        }

        let activeRMS = activeSampleCount > 0 ? sqrt(activeSumSquares / Float(activeSampleCount)) : 0
        return LevelStats(
            rms: sqrt(sumSquares / Float(sampleCount)),
            peak: peak,
            activeRMS: activeRMS,
            activeSampleCount: activeSampleCount
        )
    }

    private func int16LevelStats(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frameCount: Int,
        channelCount: Int,
        activeThreshold: Float
    ) -> LevelStats {
        var sumSquares: Float = 0
        var peak: Float = 0
        var activeSumSquares: Float = 0
        var activeSampleCount = 0
        let sampleCount = interleavedSampleCount(frameCount: frameCount, channelCount: channelCount)

        withSamples(channelData: channelData, frameCount: frameCount, channelCount: channelCount) { sample in
            let normalized = Float(sample) / Float(Int16.max)
            let value = abs(normalized)
            peak = max(peak, value)
            sumSquares += normalized * normalized
            if value >= activeThreshold {
                activeSumSquares += normalized * normalized
                activeSampleCount += 1
            }
        }

        let activeRMS = activeSampleCount > 0 ? sqrt(activeSumSquares / Float(activeSampleCount)) : 0
        return LevelStats(
            rms: sqrt(sumSquares / Float(sampleCount)),
            peak: peak,
            activeRMS: activeRMS,
            activeSampleCount: activeSampleCount
        )
    }

    private func applyFloatGain(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        gain: Float,
        limiterCeiling: Float
    ) {
        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        let sampleCount = interleavedSampleCount(frameCount: frameCount, channelCount: channelCount)

        if format.isInterleaved {
            let samples = channelData[0]
            for sample in 0..<sampleCount {
                samples[sample] = limited(samples[sample] * gain, ceiling: limiterCeiling)
            }
        } else {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    samples[frame] = limited(samples[frame] * gain, ceiling: limiterCeiling)
                }
            }
        }
    }

    private func applyInt16Gain(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        gain: Float,
        limiterCeiling: Float
    ) {
        let frameCount = Int(frameLength)
        let channelCount = Int(format.channelCount)
        let sampleCount = interleavedSampleCount(frameCount: frameCount, channelCount: channelCount)

        if format.isInterleaved {
            let samples = channelData[0]
            for sample in 0..<sampleCount {
                samples[sample] = scaledInt16Sample(samples[sample], gain: gain, limiterCeiling: limiterCeiling)
            }
        } else {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    samples[frame] = scaledInt16Sample(samples[frame], gain: gain, limiterCeiling: limiterCeiling)
                }
            }
        }
    }

    private func withSamples(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        frameCount: Int,
        channelCount: Int,
        body: (Float) -> Void
    ) {
        if format.isInterleaved {
            let samples = channelData[0]
            for sample in 0..<interleavedSampleCount(frameCount: frameCount, channelCount: channelCount) {
                body(samples[sample])
            }
        } else {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    body(samples[frame])
                }
            }
        }
    }

    private func withSamples(
        channelData: UnsafePointer<UnsafeMutablePointer<Int16>>,
        frameCount: Int,
        channelCount: Int,
        body: (Int16) -> Void
    ) {
        if format.isInterleaved {
            let samples = channelData[0]
            for sample in 0..<interleavedSampleCount(frameCount: frameCount, channelCount: channelCount) {
                body(samples[sample])
            }
        } else {
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    body(samples[frame])
                }
            }
        }
    }

    private func interleavedSampleCount(frameCount: Int, channelCount: Int) -> Int {
        format.isInterleaved ? frameCount * channelCount : frameCount * channelCount
    }

    private func limited(_ value: Float, ceiling: Float) -> Float {
        let knee = ceiling * 0.75
        let magnitude = abs(value)
        guard magnitude > knee else {
            return value
        }

        let range = max(ceiling - knee, 0.0001)
        let over = (magnitude - knee) / range
        let compressed = knee + range * (1 - exp(-over))
        return copysign(min(compressed, ceiling), value)
    }

    private func scaledInt16Sample(_ sample: Int16, gain: Float, limiterCeiling: Float) -> Int16 {
        let normalized = Float(sample) / Float(Int16.max)
        let limitedSample = limited(normalized * gain, ceiling: limiterCeiling)
        return Int16(max(Float(Int16.min), min(Float(Int16.max), limitedSample * Float(Int16.max))))
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
        switch self {
        case .compatible:
            return String(localized: "Compatible Pipeline")
        case .nativeIOS27:
            return String(localized: "iOS 27 Native Pipeline")
        }
    }

    var detail: String {
        switch self {
        case .compatible:
            return String(localized: "使用 16 kHz mono Int16 输入，优先保证 iOS 26/27 时间戳一致")
        case .nativeIOS27:
            return String(localized: "使用 iOS 27 compatibleWith 转换器，让系统选择语音输入 Pipeline")
        }
    }

    var isSupportedOnCurrentOS: Bool {
        switch self {
        case .compatible:
            return true
        case .nativeIOS27:
            if #available(iOS 27.0, *) {
                return true
            }
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
        configuredMode: SpeechPipelineMode,
        runtimeAnalyzerFormatText: String
    ) -> SpeechProcessingPipelineDiagnostics {
        if #available(iOS 27.0, *), configuredMode == .nativeIOS27 {
            return SpeechProcessingPipelineDiagnostics(
                configuredPipelineName: configuredMode.title,
                activePipelineName: String(localized: "iOS 27 Native compatibleWith"),
                supportedPipelinesText: String(localized: "支持 Pipeline: iOS 27 Native AnalyzerInputConverter；Compatible AVAudioConverter"),
                analyzerFormatText: String(localized: "Analyzer 输入: iOS 27 系统自适应，实际 Hz 录音时由 Runtime Analyzer 输入显示"),
                runtimeAnalyzerFormatText: runtimeAnalyzerFormatText
            )
        }

        if #available(iOS 27.0, *) {
            return SpeechProcessingPipelineDiagnostics(
                configuredPipelineName: configuredMode.title,
                activePipelineName: String(localized: "iOS 27 Compatible AVAudioConverter"),
                supportedPipelinesText: String(localized: "支持 Pipeline: iOS 27 Native AnalyzerInputConverter；Compatible AVAudioConverter"),
                analyzerFormatText: String(localized: "Analyzer 输入: 16 kHz / mono / Int16 PCM"),
                runtimeAnalyzerFormatText: runtimeAnalyzerFormatText
            )
        }

        return SpeechProcessingPipelineDiagnostics(
            configuredPipelineName: configuredMode.title,
            activePipelineName: String(localized: "iOS 26 AVAudioConverter"),
            supportedPipelinesText: String(localized: "支持 Pipeline: iOS 26 AVAudioConverter fallback"),
            analyzerFormatText: String(localized: "Analyzer 输入: 16 kHz / mono / Int16 PCM"),
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
            return String(localized: "无法读取麦克风输入")
        case .analyzerUnavailable:
            return String(localized: "语音分析器不可用")
        case .unsupportedLanguage:
            return String(localized: "当前语言暂不支持")
        case .stereoCaptureUnavailable:
            return String(localized: "当前麦克风不支持 AVCapture stereo 采集")
        }
    }
}
