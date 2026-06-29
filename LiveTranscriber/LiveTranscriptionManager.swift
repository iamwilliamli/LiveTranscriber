import AVFoundation
import Combine
import CoreMedia
import Foundation
import Speech

@MainActor
final class LiveTranscriptionManager: ObservableObject {
    @Published private(set) var transcriptLines: [TranscriptionLine] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isPreparing = false
    @Published private(set) var statusText = String(localized: "准备就绪")
    @Published private(set) var errorText: String?
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var supportedLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @Published var selectedAudioFormat: RecordingAudioFormat {
        didSet {
            UserDefaults.standard.set(selectedAudioFormat.rawValue, forKey: Self.audioFormatDefaultsKey)
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

    private static let languageDefaultsKey = "transcription.language"
    private static let audioFormatDefaultsKey = "recording.audioFormat"

    private let audioEngine = AVAudioEngine()
    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcription.audio-session", qos: .userInitiated)
    private var analyzer: SpeechAnalyzer?
    private var speechTranscriber: SpeechTranscriber?
    private var analyzerPipeline: AnalyzerInputPipeline?
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
    private var finalizedLines: [TranscriptionLine] = []
    private var interimLine: TranscriptionLine?
    private var lastLiveActivitySnapshot: LiveActivitySnapshot?

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

    init() {
        selectedLanguageID = UserDefaults.standard.string(forKey: Self.languageDefaultsKey) ?? TranscriptionLanguage.defaultLanguageID
        if let rawFormat = UserDefaults.standard.string(forKey: Self.audioFormatDefaultsKey),
           let storedFormat = RecordingAudioFormat(rawValue: rawFormat) {
            selectedAudioFormat = storedFormat
        } else {
            selectedAudioFormat = .defaultFormat
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
        resetTranscriptStorage()
        statusText = String(localized: "正在请求权限")

        guard await requestPermissions() else {
            isPreparing = false
            return
        }

        do {
            try await configureAudioSession()

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                throw LiveTranscriptionError.invalidAudioInput
            }

            let language = selectedLanguage
            let audioFormat = selectedAudioFormat
            let prepared = try await prepareSpeechPipeline(language: language, inputFormat: recordingFormat)
            let recordingURL = try Self.makeTemporaryRecordingURL(format: audioFormat)
            let writer = try AudioFileWriter(url: recordingURL, inputFormat: recordingFormat, outputFormat: audioFormat)

            analyzer = prepared.analyzer
            speechTranscriber = prepared.transcriber
            analyzerPipeline = prepared.pipeline
            audioWriter = writer
            currentAudioURL = recordingURL
            currentRecordingFormat = recordingFormat
            currentAudioOutputFormat = audioFormat

            startResultReader(for: prepared.transcriber)
            startAnalyzer(prepared.analyzer, stream: prepared.stream)
            try startAudioEngine(format: recordingFormat, writer: writer, pipeline: prepared.pipeline)
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

    func pauseRecording() async {
        guard isRecording, !isPaused else {
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
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
        guard let writer = audioWriter,
              let pipeline = analyzerPipeline,
              let format = currentRecordingFormat else {
            fail(with: String(localized: "录音恢复失败"))
            return
        }

        do {
            try await configureAudioSession()
            try startAudioEngine(format: format, writer: writer, pipeline: pipeline)
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
        guard isRecording || isPreparing || audioEngine.isRunning || currentAudioURL != nil else {
            return nil
        }

        isPreparing = false
        isRecording = false
        isPaused = false

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

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

        statusText = String(localized: "正在增强录音音量")
        let audioNormalizedAt: Date?
        do {
            try await RecordingFileNormalizer.normalize(url: recordingURL, outputFormat: audioOutputFormat)
            audioNormalizedAt = Date()
        } catch {
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
            accumulatedRecordingSeconds = 0
            recordingStartedAt = nil
            activeSegmentStartedAt = nil
        }
    }

    private func prepareSpeechPipeline(
        language: TranscriptionLanguage,
        inputFormat: AVAudioFormat
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

        let options = SpeechAnalyzer.Options(
            priority: .userInitiated,
            modelRetention: .whileInUse,
            ignoresResourceLimits: true
        )
        let analyzer = SpeechAnalyzer(modules: modules, options: options)
        try await analyzer.prepareToAnalyze(in: inputFormat)
        let converter = try await AnalyzerInputConverter.converter(compatibleWith: modules)

        var continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        let stream = AsyncThrowingStream<AnalyzerInput, Error> { createdContinuation in
            continuation = createdContinuation
        }

        guard let continuation else {
            throw LiveTranscriptionError.analyzerUnavailable
        }

        return PreparedSpeechPipeline(
            analyzer: analyzer,
            transcriber: transcriber,
            stream: stream,
            pipeline: AnalyzerInputPipeline(converter: converter, continuation: continuation)
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
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP, .defaultToSpeaker, .duckOthers])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
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

    private func startAudioEngine(
        format: AVAudioFormat,
        writer: AudioFileWriter,
        pipeline: AnalyzerInputPipeline
    ) throws {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        try inputNode.installAudioTap(onBus: 0, bufferSize: 1024, format: format) { [writer, pipeline] readOnlyBuffer, _ in
            let recordingBuffer = AVAudioPCMBuffer(copying: readOnlyBuffer)
            writer.write(recordingBuffer)

            let buffer = AVAudioPCMBuffer(copying: readOnlyBuffer)
            pipeline.process(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
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

private final class AnalyzerInputPipeline: @unchecked Sendable {
    private let converter: AnalyzerInputConverter
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let lock = NSLock()
    private var didFinish = false

    init(
        converter: AnalyzerInputConverter,
        continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    ) {
        self.converter = converter
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else {
            return
        }

        do {
            let inputs = try converter.convert(buffer, at: nil)
            for input in inputs {
                continuation.yield(input)
            }
        } catch {
            didFinish = true
            continuation.finish(throwing: error)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else {
            return
        }

        do {
            let inputs = try converter.flush()
            for input in inputs {
                continuation.yield(input)
            }
            didFinish = true
            continuation.finish()
        } catch {
            didFinish = true
            continuation.finish(throwing: error)
        }
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

private enum LiveTranscriptionError: LocalizedError {
    case invalidAudioInput
    case analyzerUnavailable
    case unsupportedLanguage

    var errorDescription: String? {
        switch self {
        case .invalidAudioInput:
            return String(localized: "无法读取麦克风输入")
        case .analyzerUnavailable:
            return String(localized: "语音分析器不可用")
        case .unsupportedLanguage:
            return String(localized: "当前语言暂不支持")
        }
    }
}
