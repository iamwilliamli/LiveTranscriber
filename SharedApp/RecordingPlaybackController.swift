import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog
import SwiftUI
import TranscriberDomain
#if canImport(UIKit)
import UIKit
#endif

struct RecordingPlaybackHistoryEntry: Codable, Hashable, Sendable {
    let position: TimeInterval
    let duration: TimeInterval
    let lastPlayedAt: Date

    func resumePosition(for actualDuration: TimeInterval) -> TimeInterval? {
        let resolvedDuration = max(actualDuration, duration)
        guard resolvedDuration.isFinite, resolvedDuration > 0 else {
            return nil
        }

        let clampedPosition = min(max(position, 0), resolvedDuration)
        let progress = clampedPosition / resolvedDuration
        guard clampedPosition >= 5,
              resolvedDuration - clampedPosition >= 5,
              progress < 0.95 else {
            return nil
        }
        return clampedPosition
    }
}

enum RecordingPlaybackHistoryStore {
    static let defaultsKey = "RecordingPlayback.historyV1JSON"
    private static let maximumEntryCount = 200

    static func entries(from json: String) -> [RecordingItem.ID: RecordingPlaybackHistoryEntry] {
        guard let data = json.data(using: .utf8),
              let stored = try? JSONDecoder().decode(
                  [String: RecordingPlaybackHistoryEntry].self,
                  from: data
              ) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, entry in
            UUID(uuidString: key).map { ($0, entry) }
        })
    }

    static func entry(for recordingID: RecordingItem.ID) -> RecordingPlaybackHistoryEntry? {
        entries(from: UserDefaults.standard.string(forKey: defaultsKey) ?? "{}")[recordingID]
    }

    static func save(
        recordingID: RecordingItem.ID,
        position: TimeInterval,
        duration: TimeInterval,
        lastPlayedAt: Date = Date()
    ) {
        guard position.isFinite,
              duration.isFinite,
              duration > 0 else {
            return
        }

        var entries = entries(from: UserDefaults.standard.string(forKey: defaultsKey) ?? "{}")
        entries[recordingID] = RecordingPlaybackHistoryEntry(
            position: min(max(position, 0), duration),
            duration: duration,
            lastPlayedAt: lastPlayedAt
        )

        if entries.count > maximumEntryCount {
            let retainedIDs = Set(
                entries
                    .sorted { $0.value.lastPlayedAt > $1.value.lastPlayedAt }
                    .prefix(maximumEntryCount)
                    .map(\.key)
            )
            entries = entries.filter { retainedIDs.contains($0.key) }
        }

        let stored = Dictionary(uniqueKeysWithValues: entries.map { id, entry in
            (id.uuidString, entry)
        })
        guard let data = try? JSONEncoder().encode(stored),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: defaultsKey)
    }

    static func remove(recordingID: RecordingItem.ID) {
        var entries = entries(from: UserDefaults.standard.string(forKey: defaultsKey) ?? "{}")
        guard entries.removeValue(forKey: recordingID) != nil else {
            return
        }
        let stored = Dictionary(uniqueKeysWithValues: entries.map { id, entry in
            (id.uuidString, entry)
        })
        guard let data = try? JSONEncoder().encode(stored),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: defaultsKey)
    }
}

@MainActor
final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var currentItem: RecordingItem?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorText: String?
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var isSilenceSkippingEnabled = false
    @Published private(set) var isPreparingSilenceAnalysis = false

    private static let playbackGainDecibels: Float = 3
    private static let playbackUITickMilliseconds = 250
    private static let playbackPreparationDuration: TimeInterval = 0.2
    private static let logger = Logger(subsystem: "com.reddownloader.LiveTranscriber", category: "RecordingPlayback")
    static let availablePlaybackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    /// Local recordings are decoded by AVAudioFile/AVAudioPlayerNode, which is
    /// Apple's file-playback path and supports the Float32 WAV files already
    /// in the library. Keep the graph alive for the controller's lifetime;
    /// rebuilding and deallocating an engine for every detail transition was
    /// the source of the earlier main-thread stalls.
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sourceMixerNode = AVAudioMixerNode()
    private let timePitchUnit = AVAudioUnitTimePitch()
    private let gainUnit = AVAudioUnitEQ(numberOfBands: 1)
    private let audioCommandExecutor = RecordingPlaybackAudioCommandExecutor()
    private let audioSessionQueue = DispatchQueue(
        label: "com.reddownloader.live-transcriber.playback-session",
        qos: .userInitiated
    )
    private var audioFile: AVAudioFile?
    private var loadedAudioURL: URL?
    private var connectedFileFormat: AVAudioFormat?
    private var playbackTimerTask: Task<Void, Never>?
    private var silenceAnalysisTask: Task<Void, Never>?
    private var silenceIntervals: [RecordingSilenceInterval] = []
    private var silenceAnalysisGeneration = 0
    private var hasAnalyzedSilence = false
    private var sampleRate: Double = 44_100
    private var scheduledStartTime: TimeInterval = 0
    private var playbackScheduleID = 0
    private var playbackCommandID = 0
    private var hasScheduledPlayback = false
    private var needsPlaybackReschedule = true
    private var nowPlayingTranscriptRecordingID: UUID?
    private var nowPlayingTranscriptCues: [NowPlayingTranscriptCue] = []
    private var lastPublishedNowPlayingTitle: String?
    private var remoteCommandTargets: [RemoteCommandTarget] = []
    private var isReceivingRemoteControlEvents = false
    private var isPlaybackSessionActive = false
    private var playbackSessionActivationTask: Task<Void, Error>?
    private var playbackSessionGeneration = 0
    private var transportCleanupTask: Task<Void, Never>?
    private var transportCleanupGeneration = 0
    private var transportLoadCommandID: Int?
    private var isTransportReconfiguring = false
    private var playbackHistoryTrackingID: RecordingItem.ID?
    private var lastPlaybackHistoryWriteAt = Date.distantPast

    init() {
        configurePersistentPlaybackGraph()
        configureRemoteCommands()
        updateRemoteCommandAvailability(isEnabled: false)
    }

    deinit {
        let targets = remoteCommandTargets
        Task { @MainActor in
            for target in targets {
                target.command.removeTarget(target.token)
            }
        }
    }

    func load(item: RecordingItem, url: URL) {
        guard currentItem?.id != item.id || currentItem?.audioFileName != item.audioFileName || !isLoaded else {
            currentItem = item
            updateNowPlayingInfo()
            return
        }

        Task { [weak self] in
            await self?.loadPrepared(item: item, url: url)
        }
    }

    func loadPrepared(item: RecordingItem, url: URL) async {
        guard currentItem?.id != item.id
                || currentItem?.audioFileName != item.audioFileName
                || !isLoaded else {
            currentItem = item
            updateNowPlayingInfo()
            return
        }

        await waitForPendingTransportCleanup()
        guard !Task.isCancelled else {
            return
        }

        if currentItem != nil || audioFile != nil || isLoaded {
            if let resetTask = resetPlaybackState(deactivateSession: false) {
                await resetTask.value
            }
            guard !Task.isCancelled else {
                return
            }
        }

        playbackCommandID += 1
        let commandID = playbackCommandID
        currentItem = item
        await loadAudioFile(at: url, commandID: commandID)
    }

    func setNowPlayingTranscript(
        for recordingID: UUID,
        cues: [(startTime: TimeInterval, text: String)]
    ) {
        guard currentItem?.id == recordingID else {
            return
        }

        nowPlayingTranscriptRecordingID = recordingID
        nowPlayingTranscriptCues = cues.compactMap { cue in
            let text = cue.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard cue.startTime.isFinite, cue.startTime >= 0, !text.isEmpty else {
                return nil
            }
            return NowPlayingTranscriptCue(startTime: cue.startTime, text: text)
        }
        .sorted { lhs, rhs in
            lhs.startTime < rhs.startTime
        }
        updateNowPlayingInfo()
    }

    func load(url: URL) async {
        await waitForPendingTransportCleanup()
        guard !Task.isCancelled else {
            return
        }

        if currentItem != nil || audioFile != nil || isLoaded {
            if let resetTask = resetPlaybackState(deactivateSession: false) {
                await resetTask.value
            }
            guard !Task.isCancelled else {
                return
            }
        }

        playbackCommandID += 1
        let commandID = playbackCommandID
        await loadAudioFile(at: url, commandID: commandID)
    }

    private func loadAudioFile(at url: URL, commandID: Int) async {
        errorText = nil
        transportLoadCommandID = commandID

        let engine = audioEngine
        let node = playerNode
        let sourceMixer = sourceMixerNode
        let previousFormat = connectedFileFormat
        let command = RecordingPlaybackAudioCommand<RecordingPlaybackPreparedAudioFile> {
            guard FileManager.default.fileExists(atPath: url.path),
                  FileManager.default.isReadableFile(atPath: url.path) else {
                throw RecordingPlaybackAudioLoadError.fileUnavailable
            }

            let file = try AVAudioFile(forReading: url)
            guard file.length > 0, file.fileFormat.sampleRate > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let processingFormat = file.processingFormat
            let shouldReconnect = previousFormat != processingFormat
            node.stop()
            node.reset()
            if shouldReconnect {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: sourceMixer, format: processingFormat)
            }
            engine.prepare()

            return RecordingPlaybackPreparedAudioFile(
                file: file,
                processingFormat: processingFormat,
                didReconnect: shouldReconnect,
                fileFormatDescription: String(describing: file.fileFormat),
                processingFormatDescription: String(describing: processingFormat)
            )
        }

        do {
            let preparedFile = try await audioCommandExecutor.execute(command)
            if transportLoadCommandID == commandID {
                transportLoadCommandID = nil
            }
            if preparedFile.didReconnect {
                connectedFileFormat = preparedFile.processingFormat
            }
            guard !Task.isCancelled, commandID == playbackCommandID else {
                return
            }

            let file = preparedFile.file
            audioFile = file
            loadedAudioURL = url
            sampleRate = file.fileFormat.sampleRate
            duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            currentTime = currentItem
                .flatMap { item in
                    RecordingPlaybackHistoryStore
                        .entry(for: item.id)?
                        .resumePosition(for: duration)
                }
                ?? 0
            playbackHistoryTrackingID = nil
            lastPlaybackHistoryWriteAt = .distantPast
            isLoaded = true
            if isSilenceSkippingEnabled {
                startSilenceAnalysis(at: url)
            }
            updateNowPlayingInfo()
            updateRemoteCommandAvailability(isEnabled: true)
            Self.logger.info(
                "[RecordingPlayback] load.ready file=\(url.lastPathComponent, privacy: .public) frames=\(file.length, privacy: .public) duration=\(self.duration, privacy: .public) fileFormat=\(preparedFile.fileFormatDescription, privacy: .public) processingFormat=\(preparedFile.processingFormatDescription, privacy: .public)"
            )
        } catch RecordingPlaybackAudioLoadError.fileUnavailable {
            if transportLoadCommandID == commandID {
                transportLoadCommandID = nil
            }
            guard commandID == playbackCommandID else {
                return
            }
            errorText = localized(L10n.Recordings.recordingFileMissing)
            updateRemoteCommandAvailability(isEnabled: false)
            Self.logger.error(
                "[RecordingPlayback] load.file-unavailable file=\(url.lastPathComponent, privacy: .public)"
            )
        } catch {
            if transportLoadCommandID == commandID {
                transportLoadCommandID = nil
            }
            guard commandID == playbackCommandID else {
                return
            }
            errorText = localizedFormat(L10n.Recordings.playbackFailedFormat, error.localizedDescription)
            updateRemoteCommandAvailability(isEnabled: false)
            Self.logger.error(
                "[RecordingPlayback] load.failed file=\(url.lastPathComponent, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    static func playbackRateLabel(_ rate: Float) -> String {
        if rate == floor(rate) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }

    func play() {
        guard isLoaded, audioFile != nil else {
            Self.logger.error("[RecordingPlayback] play.rejected reason=not-loaded")
            return
        }

        guard !isPlaying else {
            updateNowPlayingInfo()
            return
        }

        playbackCommandID += 1
        let commandID = playbackCommandID
        Task {
            do {
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }
                try await configurePlaybackSessionIfNeeded()
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                beginReceivingRemoteControlEventsIfNeeded()
                try await startPlaybackEngineIfNeeded()
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                if currentTime >= duration {
                    currentTime = 0
                    needsPlaybackReschedule = true
                }
                if !hasScheduledPlayback || needsPlaybackReschedule {
                    await schedulePlayback(from: currentTime)
                }
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                let node = playerNode
                try await performAudioCommand {
                    node.play()
                }
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }
                isPlaying = true
                playbackHistoryTrackingID = currentItem?.id
                persistPlaybackHistory(force: true)
                startTimer()
                updateNowPlayingInfo()
                Self.logger.info(
                    "[RecordingPlayback] play.started command=\(commandID, privacy: .public) time=\(self.currentTime, privacy: .public)"
                )
            } catch is CancellationError {
                return
            } catch {
                errorText = localizedFormat(L10n.Recordings.playbackStartFailedFormat, error.localizedDescription)
                Self.logger.error(
                    "[RecordingPlayback] play.failed command=\(commandID, privacy: .public) domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func pause() {
        playbackCommandID += 1
        let pausedTime = currentPlaybackTime()
        isPlaying = false
        playerNode.pause()
        currentTime = pausedTime
        persistPlaybackHistory(position: pausedTime, force: true)
        stopTimer()
        updateNowPlayingInfo()
        Self.logger.debug("[RecordingPlayback] Paused at \(pausedTime, privacy: .public)")
    }

    func seek(to time: TimeInterval) {
        guard isLoaded else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        currentTime = clampedTime
        persistPlaybackHistory(position: clampedTime, force: true)
        needsPlaybackReschedule = true
        if isPlaying {
            playbackCommandID += 1
            let commandID = playbackCommandID
            isTransportReconfiguring = true
            Task { [weak self] in
                guard let self,
                      commandID == self.playbackCommandID,
                      self.isLoaded else {
                    return
                }
                await self.schedulePlayback(from: clampedTime)
                guard commandID == self.playbackCommandID,
                      self.isLoaded,
                      self.isPlaying else {
                    return
                }
                do {
                    let node = self.playerNode
                    try await self.performAudioCommand {
                        node.play()
                    }
                    guard commandID == self.playbackCommandID else {
                        return
                    }
                    self.isTransportReconfiguring = false
                } catch {
                    guard commandID == self.playbackCommandID else {
                        return
                    }
                    self.isTransportReconfiguring = false
                    self.errorText = localizedFormat(
                        L10n.Recordings.playbackStartFailedFormat,
                        error.localizedDescription
                    )
                }
            }
        }
        updateNowPlayingInfo()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentPlaybackTime() + seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        let clampedRate = min(max(rate, 0.5), 3)
        guard playbackRate != clampedRate else {
            return
        }

        currentTime = currentPlaybackTime()
        playbackRate = clampedRate
        timePitchUnit.rate = clampedRate
        updateNowPlayingInfo()
    }

    func toggleSilenceSkipping() {
        guard isLoaded else {
            return
        }
        isSilenceSkippingEnabled.toggle()
        if isSilenceSkippingEnabled {
            if !hasAnalyzedSilence,
               !isPreparingSilenceAnalysis,
               let loadedAudioURL {
                startSilenceAnalysis(at: loadedAudioURL)
            }
        } else if isPreparingSilenceAnalysis {
            silenceAnalysisGeneration += 1
            silenceAnalysisTask?.cancel()
            silenceAnalysisTask = nil
            silenceIntervals = []
            isPreparingSilenceAnalysis = false
            hasAnalyzedSilence = false
        }
    }

    func presentationTime() -> TimeInterval {
        min(max(currentPlaybackTime(), 0), duration)
    }

    func unload() {
        guard currentItem != nil || audioFile != nil || isLoaded || isPlaying else {
            return
        }
        _ = resetPlaybackState(deactivateSession: true)
    }

    @discardableResult
    private func resetPlaybackState(deactivateSession: Bool) -> Task<Void, Never>? {
        persistPlaybackHistory(force: true)
        playbackHistoryTrackingID = nil
        lastPlaybackHistoryWriteAt = .distantPast
        playbackCommandID += 1
        playbackScheduleID += 1
        transportCleanupGeneration += 1
        let cleanupGeneration = transportCleanupGeneration
        let retainedAudioFile = audioFile
        let shouldResetTransport = retainedAudioFile != nil
            || isLoaded
            || hasScheduledPlayback
            || transportLoadCommandID != nil
        let engine = audioEngine
        let node = playerNode

        audioFile = nil
        loadedAudioURL = nil
        currentItem = nil
        silenceAnalysisGeneration += 1
        silenceAnalysisTask?.cancel()
        silenceAnalysisTask = nil
        silenceIntervals = []
        isPreparingSilenceAnalysis = false
        hasAnalyzedSilence = false
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        isTransportReconfiguring = false
        nowPlayingTranscriptRecordingID = nil
        nowPlayingTranscriptCues = []
        lastPublishedNowPlayingTitle = nil
        isLoaded = false
        isPlaying = false
        currentTime = 0
        scheduledStartTime = 0
        duration = 0
        stopTimer()
        clearNowPlayingInfo()
        updateRemoteCommandAvailability(isEnabled: false)
        endReceivingRemoteControlEventsIfNeeded()

        if deactivateSession {
            // The graph stays allocated for reuse. Its hardware stop runs in
            // the serialized command below, outside the navigation update.
            playbackSessionGeneration += 1
            playbackSessionActivationTask?.cancel()
            playbackSessionActivationTask = nil
            isPlaybackSessionActive = false
        }

        guard shouldResetTransport else {
            if deactivateSession {
                requestPlaybackSessionDeactivation()
            }
            return nil
        }

        let command = RecordingPlaybackAudioCommand<Void> {
            // Keep the file alive until AVAudioPlayerNode has released its
            // scheduled secondary reader. These calls can synchronously wait
            // on AVAudioSession/XPC on iOS, so they must not run on MainActor.
            _ = retainedAudioFile
            if deactivateSession {
                engine.pause()
            }
            node.stop()
            node.reset()
        }
        let executor = audioCommandExecutor
        let cleanupTask = Task { [weak self] in
            try? await executor.execute(command)
            guard let self,
                  cleanupGeneration == self.transportCleanupGeneration else {
                return
            }
            self.transportCleanupTask = nil
            if deactivateSession {
                self.requestPlaybackSessionDeactivation()
            }
        }
        transportCleanupTask = cleanupTask
        return cleanupTask
    }

    private func waitForPendingTransportCleanup() async {
        if let transportCleanupTask {
            await transportCleanupTask.value
        }
    }

    /// Warm the session and persistent graph while the detail transition is
    /// completing so the first play tap only starts the already-scheduled
    /// player node.
    func prewarmPlaybackSession() {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.configurePlaybackSessionIfNeeded()
                guard self.isLoaded else {
                    return
                }
                try await self.startPlaybackEngineIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error(
                    "[RecordingPlayback] prewarm.failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    func prepareForBackgroundPlayback() {
        guard isLoaded else {
            return
        }

        beginReceivingRemoteControlEventsIfNeeded()
        updateRemoteCommandAvailability(isEnabled: true)
        updateNowPlayingInfo()
        Self.logger.debug("[RecordingPlayback] Prepared for background playback playing=\(self.isPlaying, privacy: .public)")
    }

    private func startTimer() {
        stopTimer()
        playbackTimerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard self.isPlaying else {
                    do {
                        try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                    } catch {
                        break
                    }
                    continue
                }

                let playbackTime = min(self.currentPlaybackTime(), self.duration)
                if let skipDestination = self.silenceSkipDestination(
                    at: playbackTime
                ) {
                    self.seek(to: skipDestination)
                    continue
                }
                self.currentTime = playbackTime
                self.persistPlaybackHistory(force: false)
                self.refreshNowPlayingTitleIfNeeded(at: playbackTime)

                do {
                    try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func persistPlaybackHistory(
        position: TimeInterval? = nil,
        force: Bool
    ) {
        guard let currentItem,
              playbackHistoryTrackingID == currentItem.id,
              duration.isFinite,
              duration > 0 else {
            return
        }

        let now = Date()
        guard force || now.timeIntervalSince(lastPlaybackHistoryWriteAt) >= 5 else {
            return
        }

        RecordingPlaybackHistoryStore.save(
            recordingID: currentItem.id,
            position: position ?? presentationTime(),
            duration: duration,
            lastPlayedAt: now
        )
        lastPlaybackHistoryWriteAt = now
    }

    private func startSilenceAnalysis(at url: URL) {
        silenceAnalysisGeneration += 1
        let generation = silenceAnalysisGeneration
        silenceAnalysisTask?.cancel()
        silenceIntervals = []
        isPreparingSilenceAnalysis = true
        hasAnalyzedSilence = false

        let task = Task { [weak self] in
            let intervals = await RecordingSilenceDetector.intervals(from: url)
            guard !Task.isCancelled,
                  let self,
                  generation == self.silenceAnalysisGeneration,
                  self.isLoaded else {
                return
            }
            self.silenceIntervals = intervals
            self.isPreparingSilenceAnalysis = false
            self.hasAnalyzedSilence = true
            self.silenceAnalysisTask = nil
        }
        silenceAnalysisTask = task
    }

    private func silenceSkipDestination(
        at playbackTime: TimeInterval
    ) -> TimeInterval? {
        guard isSilenceSkippingEnabled,
              isPlaying,
              !isTransportReconfiguring,
              !silenceIntervals.isEmpty else {
            return nil
        }

        var lowerBound = silenceIntervals.startIndex
        var upperBound = silenceIntervals.endIndex
        while lowerBound < upperBound {
            let midIndex = lowerBound + (upperBound - lowerBound) / 2
            let interval = silenceIntervals[midIndex]
            if playbackTime < interval.startTime {
                upperBound = midIndex
            } else if playbackTime >= interval.endTime {
                lowerBound = midIndex + 1
            } else {
                let destination = min(interval.endTime, duration)
                return destination > playbackTime + 0.05
                    ? destination
                    : nil
            }
        }
        return nil
    }

    private func configurePersistentPlaybackGraph() {
        timePitchUnit.rate = playbackRate
        if let band = gainUnit.bands.first {
            band.filterType = .parametric
            band.frequency = 1_000
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        gainUnit.globalGain = Self.playbackGainDecibels

        audioEngine.attach(playerNode)
        audioEngine.attach(sourceMixerNode)
        audioEngine.attach(timePitchUnit)
        audioEngine.attach(gainUnit)

        // The source mixer is the stable format boundary. Only the upstream
        // player connection changes when a recording has a different channel
        // count/sample rate; the expensive output/effect graph stays intact.
        audioEngine.connect(sourceMixerNode, to: timePitchUnit, format: nil)
        audioEngine.connect(timePitchUnit, to: gainUnit, format: nil)
        audioEngine.connect(gainUnit, to: audioEngine.mainMixerNode, format: nil)
    }

    private func startPlaybackEngineIfNeeded() async throws {
        let engine = audioEngine
        try await performAudioCommand {
            guard !engine.isRunning else {
                return
            }
            try engine.start()
        }
    }

    private func schedulePlayback(from time: TimeInterval) async {
        guard let audioFile else {
            return
        }

        playbackScheduleID += 1
        let completionID = playbackScheduleID
        hasScheduledPlayback = false

        let startFrame = framePosition(for: time)
        let remainingFrames = max(audioFile.length - startFrame, 0)
        guard remainingFrames > 0 else {
            finishPlayback()
            return
        }

        // Audio must be scheduled on an integer frame, but transcript
        // timestamps are logical times that may fall between frames. Keep the
        // requested time as the UI timeline origin so converting the floored
        // frame back to seconds cannot momentarily select the previous line.
        scheduledStartTime = min(max(time, 0), duration)
        currentTime = scheduledStartTime
        needsPlaybackReschedule = false
        hasScheduledPlayback = true
        let scheduledFrameCount = AVAudioFrameCount(
            min(remainingFrames, AVAudioFramePosition(AVAudioFrameCount.max))
        )
        let preparationFrameCount = Self.playbackPreparationFrameCount(
            remainingFrames: remainingFrames,
            sampleRate: sampleRate
        )
        let completionHandler: (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] callbackType in
            Task { @MainActor in
                guard let self,
                      callbackType == .dataPlayedBack,
                      self.playbackScheduleID == completionID,
                      self.isPlaying else {
                    return
                }
                self.finishPlayback()
            }
        }
        let node = playerNode
        try? await performAudioCommand {
            node.stop()
            node.reset()
            node.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: scheduledFrameCount,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { callbackType in
                completionHandler(callbackType)
            }
            // scheduleSegment streams the complete remaining segment.
            // Preparing only a short fixed window avoids reserving buffers
            // for millions of frames on long recordings.
            if preparationFrameCount > 0 {
                node.prepare(withFrameCount: preparationFrameCount)
            }
        }
    }

    private func performAudioCommand(
        _ operation: @escaping () throws -> Void
    ) async throws {
        let command = RecordingPlaybackAudioCommand<Void>(operation: operation)
        try await audioCommandExecutor.execute(command)
    }

    static func playbackPreparationFrameCount(
        remainingFrames: AVAudioFramePosition,
        sampleRate: Double
    ) -> AVAudioFrameCount {
        guard remainingFrames > 0, sampleRate.isFinite, sampleRate > 0 else {
            return 0
        }

        let maximumFrameCount = AVAudioFramePosition(AVAudioFrameCount.max)
        let targetFrameCount = AVAudioFramePosition(
            min(
                max((sampleRate * playbackPreparationDuration).rounded(.up), 1),
                Double(AVAudioFrameCount.max)
            )
        )
        return AVAudioFrameCount(min(min(remainingFrames, targetFrameCount), maximumFrameCount))
    }

    private func framePosition(for time: TimeInterval) -> AVAudioFramePosition {
        guard sampleRate > 0 else {
            return 0
        }
        let clampedTime = min(max(time, 0), duration)
        let frame = AVAudioFramePosition((clampedTime * sampleRate).rounded(.down))
        return min(max(frame, 0), audioFile?.length ?? frame)
    }

    private func currentPlaybackTime() -> TimeInterval {
        guard isPlaying,
              !isTransportReconfiguring,
              sampleRate > 0,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTime
        }

        // A newly started player node can briefly report a negative sample
        // time before its scheduled segment reaches the render timeline. That
        // is preroll, not an actual seek backwards, so keep the requested UI
        // time until the node begins reporting samples from the new segment.
        guard playerTime.sampleTime >= 0 else {
            return currentTime
        }

        let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
        return min(
            scheduledStartTime + Double(playedFrames) / sampleRate,
            duration
        )
    }

    private func finishPlayback() {
        playbackCommandID += 1
        playbackScheduleID += 1
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        isTransportReconfiguring = false
        currentTime = duration
        isPlaying = false
        persistPlaybackHistory(position: duration, force: true)
        stopTimer()
        updateNowPlayingInfo()
    }

    private func configurePlaybackSessionIfNeeded() async throws {
        guard !isPlaybackSessionActive else {
            return
        }

        let generation = playbackSessionGeneration
        let activationTask: Task<Void, Error>
        if let playbackSessionActivationTask {
            activationTask = playbackSessionActivationTask
        } else {
            let task = Task { [weak self] in
                guard let self else {
                    throw CancellationError()
                }
                try await self.activatePlaybackSession()
            }
            playbackSessionActivationTask = task
            activationTask = task
        }

        do {
            try await activationTask.value
            guard generation == playbackSessionGeneration else {
                throw CancellationError()
            }
            playbackSessionActivationTask = nil
            isPlaybackSessionActive = true
        } catch {
            if generation == playbackSessionGeneration {
                playbackSessionActivationTask = nil
            }
            throw error
        }
    }

    private func activatePlaybackSession() async throws {
        #if os(iOS)
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #endif
    }

    private func requestPlaybackSessionDeactivation() {
        #if os(iOS)
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        #endif
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [5]
        commandCenter.skipBackwardCommand.preferredIntervals = [5]
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = Self.availablePlaybackRates.map { NSNumber(value: $0) }

        remoteCommandTargets = [
            RemoteCommandTarget(command: commandCenter.playCommand, token: commandCenter.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.play()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.pauseCommand, token: commandCenter.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.pause()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.togglePlayPauseCommand, token: commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.togglePlayback()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.stopCommand, token: commandCenter.stopCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.pause()
                    self.seek(to: 0)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.skipForwardCommand, token: commandCenter.skipForwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
                Task { @MainActor in
                    self?.skip(by: interval)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.skipBackwardCommand, token: commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
                Task { @MainActor in
                    self?.skip(by: -interval)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.changePlaybackPositionCommand, token: commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    self?.seek(to: event.positionTime)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.changePlaybackRateCommand, token: commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackRateCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    self?.setPlaybackRate(event.playbackRate)
                }
                return .success
            })
        ]
    }

    private func updateRemoteCommandAvailability(isEnabled: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = isEnabled
        commandCenter.pauseCommand.isEnabled = isEnabled
        commandCenter.togglePlayPauseCommand.isEnabled = isEnabled
        commandCenter.stopCommand.isEnabled = isEnabled
        commandCenter.skipForwardCommand.isEnabled = isEnabled
        commandCenter.skipBackwardCommand.isEnabled = isEnabled
        commandCenter.changePlaybackPositionCommand.isEnabled = isEnabled
        commandCenter.changePlaybackRateCommand.isEnabled = isEnabled
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo(elapsedTime providedElapsedTime: TimeInterval? = nil) {
        guard isLoaded else {
            clearNowPlayingInfo()
            return
        }

        let elapsedTime = min(max(providedElapsedTime ?? currentPlaybackTime(), 0), duration)
        let title = nowPlayingTitle(at: elapsedTime)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPMediaItemPropertyAlbumTitle: nowPlayingSubtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate
        ]

        if #available(iOS 10.0, *) {
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        lastPublishedNowPlayingTitle = title
        Self.logger.debug(
            "[RecordingPlayback] NowPlaying updated title=\(title, privacy: .private) artist=\(self.nowPlayingArtist, privacy: .private) elapsed=\(elapsedTime, privacy: .public) duration=\(self.duration, privacy: .public) rate=\(self.playbackRate, privacy: .public) playing=\(self.isPlaying, privacy: .public)"
        )
    }

    private func clearNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        lastPublishedNowPlayingTitle = nil
        Self.logger.debug("[RecordingPlayback] NowPlaying cleared")
    }

    private func beginReceivingRemoteControlEventsIfNeeded() {
        guard !isReceivingRemoteControlEvents else {
            return
        }

        #if os(iOS)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
        isReceivingRemoteControlEvents = true
        Self.logger.debug("[RecordingPlayback] Began receiving remote control events")
    }

    private func endReceivingRemoteControlEventsIfNeeded() {
        guard isReceivingRemoteControlEvents else {
            return
        }

        #if os(iOS)
        UIApplication.shared.endReceivingRemoteControlEvents()
        #endif
        isReceivingRemoteControlEvents = false
        Self.logger.debug("[RecordingPlayback] Ended receiving remote control events")
    }

    private var fallbackNowPlayingTitle: String {
        currentItem?.displayName ?? localized(L10n.Recordings.recordingFallback)
    }

    private var nowPlayingArtist: String {
        fallbackNowPlayingTitle
    }

    private func nowPlayingTitle(at time: TimeInterval) -> String {
        guard nowPlayingTranscriptRecordingID == currentItem?.id,
              !nowPlayingTranscriptCues.isEmpty else {
            return fallbackNowPlayingTitle
        }

        var lowerBound = 0
        var upperBound = nowPlayingTranscriptCues.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if nowPlayingTranscriptCues[middle].startTime <= time {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let index = lowerBound - 1
        guard nowPlayingTranscriptCues.indices.contains(index) else {
            return fallbackNowPlayingTitle
        }
        return nowPlayingTranscriptCues[index].text
    }

    private func refreshNowPlayingTitleIfNeeded(at time: TimeInterval) {
        guard nowPlayingTitle(at: time) != lastPublishedNowPlayingTitle else {
            return
        }
        updateNowPlayingInfo(elapsedTime: time)
    }

    private var nowPlayingSubtitle: String {
        guard let item = currentItem else {
            return localized(L10n.Recordings.recordingPlayback)
        }

        let formattedDate = item.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(item.localizedLanguageName) · \(formattedDate)"
    }
}

private enum RecordingPlaybackAudioLoadError: Error {
    case fileUnavailable
}

private struct RecordingPlaybackPreparedAudioFile: @unchecked Sendable {
    let file: AVAudioFile
    let processingFormat: AVAudioFormat
    let didReconnect: Bool
    let fileFormatDescription: String
    let processingFormatDescription: String
}

private final class RecordingPlaybackAudioCommand<Output: Sendable>: @unchecked Sendable {
    private let operation: () throws -> Output

    init(operation: @escaping () throws -> Output) {
        self.operation = operation
    }

    func execute() throws -> Output {
        try operation()
    }
}

private final class RecordingPlaybackAudioCommandExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.reddownloader.live-transcriber.playback-transport",
        qos: .userInitiated
    )

    func execute<Output: Sendable>(
        _ command: RecordingPlaybackAudioCommand<Output>
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try command.execute())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct NowPlayingTranscriptCue {
    let startTime: TimeInterval
    let text: String
}

private struct RemoteCommandTarget {
    let command: MPRemoteCommand
    let token: Any
}

private struct RecordingSummaryWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct RecordingSummaryMarquee: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .caption2) private var lineHeight: CGFloat = 14
    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var animationStart = Date()

    let text: String

    private let gap: CGFloat = 28
    private let speed: CGFloat = 22
    private let initialPause: TimeInterval = 1.0
    private let endPause: TimeInterval = 0.9
    private let fadeWidth: CGFloat = 9

    private var hasOverflow: Bool {
        containerWidth > 0 && textWidth > containerWidth + 1
    }

    private var shouldAnimate: Bool {
        hasOverflow && !accessibilityReduceMotion
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if shouldAnimate {
                    TimelineView(
                        .animation(
                            minimumInterval: 1.0 / 30.0,
                            paused: scenePhase != .active
                        )
                    ) { timeline in
                        let offset = marqueeOffset(at: timeline.date)

                        ZStack(alignment: .leading) {
                            HStack(spacing: gap) {
                                fixedSummaryText
                                fixedSummaryText
                                    .accessibilityHidden(true)
                            }
                            .offset(x: -offset)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                } else if hasOverflow {
                    Text(text)
                        .font(.redditSans(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(text)
                        .font(.redditSans(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: hasOverflow ? .leading : .center
            )
            .clipped()
            .mask {
                Group {
                    if hasOverflow {
                        edgeMask
                    } else {
                        Rectangle()
                            .fill(.black)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .onAppear {
                updateContainerWidth(geometry.size.width)
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                updateContainerWidth(newWidth)
            }
        }
        .frame(height: lineHeight)
        .background {
            fixedSummaryText
                .hidden()
                .accessibilityHidden(true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: RecordingSummaryWidthPreferenceKey.self,
                            value: geometry.size.width
                        )
                    }
                }
        }
        .onPreferenceChange(RecordingSummaryWidthPreferenceKey.self) { newWidth in
            guard abs(textWidth - newWidth) > 0.5 else {
                return
            }
            textWidth = newWidth
            animationStart = Date()
        }
        .onChange(of: text) {
            animationStart = Date()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private var fixedSummaryText: some View {
        Text(text)
            .font(.redditSans(.caption2))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func marqueeOffset(at date: Date) -> CGFloat {
        let distance = textWidth + gap
        guard distance > 0 else {
            return 0
        }

        let elapsed = max(date.timeIntervalSince(animationStart), 0)
        guard elapsed > initialPause else {
            return 0
        }

        let travelDuration = TimeInterval(distance / speed)
        let cycleDuration = travelDuration + endPause
        let phase = (elapsed - initialPause).truncatingRemainder(dividingBy: cycleDuration)
        guard phase < travelDuration else {
            return distance
        }
        return CGFloat(phase) * speed
    }

    private func updateContainerWidth(_ newWidth: CGFloat) {
        guard abs(containerWidth - newWidth) > 0.5 else {
            return
        }
        containerWidth = newWidth
        animationStart = Date()
    }

    private var edgeMask: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let fadeFraction = min(fadeWidth / width, 0.5)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fadeFraction),
                    .init(color: .black, location: 1 - fadeFraction),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct RetroRecordingDisplay: View {
    @State private var waveformSamples: [CGFloat] = []

    let statusText: String
    let title: String
    let audioURL: URL
    @ObservedObject var player: RecordingPlaybackController
    let scrubbedTime: TimeInterval?
    let duration: TimeInterval

    private let displayRed = Color(red: 0.94, green: 0.08, blue: 0.13)

    private var effectiveDuration: TimeInterval {
        player.duration > 0 ? player.duration : duration
    }

    private func playbackProgress(for currentTime: TimeInterval) -> CGFloat {
        guard effectiveDuration > 0 else {
            return 0
        }
        return CGFloat(min(max(currentTime / effectiveDuration, 0), 1))
    }

    var body: some View {
        let displayShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        ZStack {
            Color(red: 0.018, green: 0.020, blue: 0.022)

            RetroDotMatrixGrid()
                .padding(RetroDisplayMetrics.edgePixelInset)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    RetroPlaybackStatusMark(color: displayRed, isActive: player.isPlaying)
                        .accessibilityHidden(true)

                    Text(statusText)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.56))

                    Spacer(minLength: 8)

                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .minimumScaleFactor(0.72)

                TimelineView(
                    .animation(
                        minimumInterval: 1.0 / 60.0,
                        paused: !player.isPlaying || scrubbedTime != nil
                    )
                ) { _ in
                    let currentTime = min(
                        max(scrubbedTime ?? player.presentationTime(), 0),
                        effectiveDuration
                    )

                    VStack(spacing: 4) {
                        RetroPixelWaveform(
                            samples: waveformSamples,
                            progress: playbackProgress(for: currentTime),
                            playheadColor: displayRed,
                            isActive: player.isPlaying
                        )
                        .frame(height: 106)
                        .padding(
                            .horizontal,
                            -(
                                RetroDisplayMetrics.contentHorizontalInset
                                    - RetroDisplayMetrics.edgePixelInset
                            )
                        )
                        .accessibilityHidden(true)

                        RetroDotMatrixTime(
                            text: Self.displayTimestamp(currentTime),
                            accessibilityText: "\(TranscriptionLine.formatTimestamp(currentTime)) / \(TranscriptionLine.formatTimestamp(effectiveDuration))"
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 35)
                    }
                }
            }
            .padding(.horizontal, RetroDisplayMetrics.contentHorizontalInset)
            .padding(.vertical, 10)
        }
        .coordinateSpace(name: RetroDisplayMetrics.coordinateSpaceName)
        .frame(height: 184)
        .clipShape(displayShape)
        .overlay {
            displayShape
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task(id: audioURL) {
            waveformSamples = []
            let samples = await RecordingDisplayWaveformSampler.samples(
                from: audioURL,
                sampleCount: 96
            )
            guard !Task.isCancelled else {
                return
            }
            waveformSamples = samples
        }
    }

    private static func displayTimestamp(_ time: TimeInterval) -> String {
        let safeSeconds = max(Int(time.rounded(.down)), 0)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

enum RetroDisplayMetrics {
    static let coordinateSpaceName = "retroRecordingDisplayGrid"
    static let contentHorizontalInset: CGFloat = 16
    static let gridPitch: CGFloat = 4.6
    static let edgePixelInset: CGFloat = gridPitch
    static let backgroundDotSize: CGFloat = 2.15
    static let activeDotSize: CGFloat = 2.7
    static let gridOrigin: CGFloat = 1.4

    static func pixelAligned(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        let safeScale = max(displayScale, 1)
        return (value * safeScale).rounded() / safeScale
    }
}

private struct RetroDotMatrixGrid: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let pitch = RetroDisplayMetrics.gridPitch
            let dotSize = RetroDisplayMetrics.pixelAligned(
                RetroDisplayMetrics.backgroundDotSize,
                displayScale: displayScale
            )
            let cornerRadius = 1 / max(displayScale, 1)
            var y = RetroDisplayMetrics.gridOrigin

            while y < size.height {
                var x = RetroDisplayMetrics.gridOrigin
                while x < size.width {
                    let rect = CGRect(
                        x: RetroDisplayMetrics.pixelAligned(x, displayScale: displayScale),
                        y: RetroDisplayMetrics.pixelAligned(y, displayScale: displayScale),
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: cornerRadius),
                        with: .color(Color.white.opacity(0.065))
                    )
                    x += pitch
                }
                y += pitch
            }
        }
    }
}

private struct RetroPlaybackStatusMark: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let squareSize: CGFloat = 3.8
            let gap: CGFloat = 1.5

            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(
                        x: CGFloat(column) * (squareSize + gap),
                        y: CGFloat(row) * (squareSize + gap),
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 0.55),
                        with: .color(color.opacity(isActive ? 1 : 0.52))
                    )
                }
            }
        }
        .frame(width: 9.1, height: 9.1)
    }
}

private struct RetroDotMatrixTime: View {
    @Environment(\.displayScale) private var displayScale

    let text: String
    let accessibilityText: String

    private static let glyphRows: [Character: [String]] = [
        "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
        "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
        ":": ["0", "1", "1", "0", "1", "1", "0"]
    ]

    var body: some View {
        GeometryReader { proxy in
            let displayFrame = proxy.frame(
                in: .named(RetroDisplayMetrics.coordinateSpaceName)
            )

            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                let glyphs = text.compactMap { Self.glyphRows[$0] }
                guard !glyphs.isEmpty else {
                    return
                }

                let glyphWidths = glyphs.map { $0.first?.count ?? 0 }
                let totalColumns = glyphWidths.reduce(0, +) + max(glyphs.count - 1, 0)
                let rowCount = glyphs.map(\.count).max() ?? 0
                guard totalColumns > 0, rowCount > 0 else {
                    return
                }

                let pitch = RetroDisplayMetrics.gridPitch
                let dotSize = RetroDisplayMetrics.pixelAligned(
                    RetroDisplayMetrics.backgroundDotSize,
                    displayScale: displayScale
                )
                let contentWidth = CGFloat(totalColumns - 1) * pitch + dotSize
                let contentHeight = CGFloat(rowCount - 1) * pitch + dotSize
                let horizontalPhase = gridPhase(for: displayFrame.minX)
                let verticalPhase = gridPhase(for: displayFrame.minY)
                let originX = alignedOrigin(
                    centeredIn: size.width,
                    contentLength: contentWidth,
                    phase: horizontalPhase
                )
                let originY = alignedOrigin(
                    centeredIn: size.height,
                    contentLength: contentHeight,
                    phase: verticalPhase
                )
                var glyphColumn = 0

                for (glyphIndex, rows) in glyphs.enumerated() {
                    let width = glyphWidths[glyphIndex]

                    for (row, pattern) in rows.enumerated() {
                        for (column, value) in pattern.enumerated() where value == "1" {
                            let localX = originX + CGFloat(glyphColumn + column) * pitch
                            let localY = originY + CGFloat(row) * pitch
                            let rect = CGRect(
                                x: pixelAligned(
                                    localX,
                                    displayOffset: displayFrame.minX
                                ),
                                y: pixelAligned(
                                    localY,
                                    displayOffset: displayFrame.minY
                                ),
                                width: dotSize,
                                height: dotSize
                            )
                            context.fill(
                                Path(
                                    roundedRect: rect,
                                    cornerRadius: 1 / max(displayScale, 1)
                                ),
                                with: .color(Color.white.opacity(0.96))
                            )
                        }
                    }

                    glyphColumn += width + 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private func gridPhase(for displayOffset: CGFloat) -> CGFloat {
        let pitch = RetroDisplayMetrics.gridPitch
        let alignedGridOrigin = RetroDisplayMetrics.pixelAligned(
            RetroDisplayMetrics.gridOrigin,
            displayScale: displayScale
        )
        let unwrappedPhase = alignedGridOrigin - displayOffset
        return ((unwrappedPhase.truncatingRemainder(dividingBy: pitch)) + pitch)
            .truncatingRemainder(dividingBy: pitch)
    }

    private func pixelAligned(
        _ localValue: CGFloat,
        displayOffset: CGFloat
    ) -> CGFloat {
        RetroDisplayMetrics.pixelAligned(
            localValue + displayOffset,
            displayScale: displayScale
        ) - displayOffset
    }

    private func alignedOrigin(
        centeredIn availableLength: CGFloat,
        contentLength: CGFloat,
        phase: CGFloat
    ) -> CGFloat {
        let pitch = RetroDisplayMetrics.gridPitch
        let maximumOrigin = max(availableLength - contentLength, 0)
        let desiredOrigin = (availableLength - contentLength) / 2
        let firstVisibleStep = Int(ceil((0 - phase) / pitch))
        let lastVisibleStep = Int(floor((maximumOrigin - phase) / pitch))

        guard firstVisibleStep <= lastVisibleStep else {
            return min(max(desiredOrigin, 0), maximumOrigin)
        }

        let centeredStep = Int(round((desiredOrigin - phase) / pitch))
        let visibleStep = min(max(centeredStep, firstVisibleStep), lastVisibleStep)
        return phase + CGFloat(visibleStep) * pitch
    }
}


struct RetroPixelWaveform: View {
    @Environment(\.displayScale) private var displayScale

    let samples: [CGFloat]
    let progress: CGFloat
    let playheadColor: Color
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let displayFrame = proxy.frame(
                in: .named(RetroDisplayMetrics.coordinateSpaceName)
            )

            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                let pitch = RetroDisplayMetrics.gridPitch
                let cellSize = RetroDisplayMetrics.pixelAligned(
                    RetroDisplayMetrics.backgroundDotSize,
                    displayScale: displayScale
                )
                let cornerRadius = 1 / max(displayScale, 1)
                let columns = gridOrigins(
                    phase: gridPhase(for: displayFrame.minX),
                    length: size.width,
                    pitch: pitch,
                    cellSize: cellSize,
                    displayOffset: displayFrame.minX
                )
                let rows = gridOrigins(
                    phase: gridPhase(for: displayFrame.minY),
                    length: size.height,
                    pitch: pitch,
                    cellSize: cellSize,
                    displayOffset: displayFrame.minY
                )
                guard columns.count > 2, rows.count > 2 else {
                    return
                }

                let firstWaveformColumn = columns.index(after: columns.startIndex)
                let lastWaveformColumn = columns.index(columns.endIndex, offsetBy: -2)
                let waveformColumnIndices = firstWaveformColumn...lastWaveformColumn
                let firstWaveformCenter = columns[firstWaveformColumn] + cellSize / 2
                let lastWaveformCenter = columns[lastWaveformColumn] + cellSize / 2
                let rawPlayheadX = firstWaveformCenter
                    + min(max(progress, 0), 1)
                    * (lastWaveformCenter - firstWaveformCenter)
                let playheadColumn = nearestIndex(
                    to: rawPlayheadX,
                    in: columns,
                    cellSize: cellSize
                )
                let centerRow = nearestIndex(
                    to: size.height / 2,
                    in: rows,
                    cellSize: cellSize
                )
                let maximumHalfRows = max(
                    min(centerRow, rows.count - centerRow - 1),
                    0
                )

                for index in waveformColumnIndices {
                    let sample = interpolatedSample(
                        at: index - firstWaveformColumn,
                        columnCount: waveformColumnIndices.count
                    )
                    let halfRows = max(
                        Int(
                            (
                                min(max(sample, 0), 1)
                                    * CGFloat(maximumHalfRows)
                            ).rounded()
                        ),
                        0
                    )
                    let waveformOpacity = index <= playheadColumn ? 0.94 : 0.34
                    let lowerRow = max(centerRow - halfRows, rows.startIndex)
                    let upperRow = min(centerRow + halfRows, rows.index(before: rows.endIndex))

                    for rowIndex in lowerRow...upperRow {
                        let rect = CGRect(
                            x: pixelAligned(
                                columns[index],
                                displayOffset: displayFrame.minX
                            ),
                            y: pixelAligned(
                                rows[rowIndex],
                                displayOffset: displayFrame.minY
                            ),
                            width: cellSize,
                            height: cellSize
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cornerRadius),
                            with: .color(Color.white.opacity(waveformOpacity))
                        )
                    }
                }

                let playheadOpacity = isActive ? 1.0 : 0.74
                let playheadX = pixelAligned(
                    columns[playheadColumn],
                    displayOffset: displayFrame.minX
                )

                for rowIndex in rows.indices.dropFirst(2) {
                    let rect = CGRect(
                        x: playheadX,
                        y: pixelAligned(
                            rows[rowIndex],
                            displayOffset: displayFrame.minY
                        ),
                        width: cellSize,
                        height: cellSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: cornerRadius),
                        with: .color(playheadColor.opacity(playheadOpacity))
                    )
                }

                let capStartColumn = columns.index(before: playheadColumn)
                let capEndColumn = columns.index(after: playheadColumn)
                for columnIndex in capStartColumn...capEndColumn {
                    for rowIndex in rows.indices.prefix(2) {
                        let rect = CGRect(
                            x: pixelAligned(
                                columns[columnIndex],
                                displayOffset: displayFrame.minX
                            ),
                            y: pixelAligned(
                                rows[rowIndex],
                                displayOffset: displayFrame.minY
                            ),
                            width: cellSize,
                            height: cellSize
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cornerRadius),
                            with: .color(playheadColor.opacity(playheadOpacity))
                        )
                    }
                }
            }
        }
    }

    private func gridPhase(for displayOffset: CGFloat) -> CGFloat {
        let pitch = RetroDisplayMetrics.gridPitch
        let alignedGridOrigin = RetroDisplayMetrics.pixelAligned(
            RetroDisplayMetrics.gridOrigin,
            displayScale: displayScale
        )
        let unwrappedPhase = alignedGridOrigin - displayOffset
        return ((unwrappedPhase.truncatingRemainder(dividingBy: pitch)) + pitch)
            .truncatingRemainder(dividingBy: pitch)
    }

    private func gridOrigins(
        phase: CGFloat,
        length: CGFloat,
        pitch: CGFloat,
        cellSize: CGFloat,
        displayOffset: CGFloat
    ) -> [CGFloat] {
        var origins: [CGFloat] = []
        var origin = phase

        while origin < length {
            let alignedOrigin = pixelAligned(
                origin,
                displayOffset: displayOffset
            )
            if alignedOrigin >= 0, alignedOrigin + cellSize <= length {
                origins.append(alignedOrigin)
            }
            origin += pitch
        }

        return origins
    }

    private func nearestIndex(
        to position: CGFloat,
        in origins: [CGFloat],
        cellSize: CGFloat
    ) -> Int {
        origins.indices.min { lhs, rhs in
            abs(origins[lhs] + cellSize / 2 - position)
                < abs(origins[rhs] + cellSize / 2 - position)
        } ?? origins.startIndex
    }

    private func pixelAligned(
        _ localValue: CGFloat,
        displayOffset: CGFloat
    ) -> CGFloat {
        RetroDisplayMetrics.pixelAligned(
            localValue + displayOffset,
            displayScale: displayScale
        ) - displayOffset
    }

    private func interpolatedSample(at column: Int, columnCount: Int) -> CGFloat {
        guard let firstSample = samples.first else {
            return 0
        }
        guard samples.count > 1, columnCount > 1 else {
            return firstSample
        }

        let position = CGFloat(column) / CGFloat(columnCount - 1) * CGFloat(samples.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, samples.count - 1)
        let fraction = position - CGFloat(lowerIndex)
        return samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
    }
}
