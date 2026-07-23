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

@MainActor
final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var currentItem: RecordingItem?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorText: String?
    @Published private(set) var playbackRate: Float = 1

    private static let playbackGainDecibels: Float = 3
    private static let playbackUITickMilliseconds = 250
    private static let playbackPreparationDuration: TimeInterval = 0.2
    private static let logger = Logger(subsystem: "com.reddownloader.LiveTranscriber", category: "RecordingPlayback")
    static let availablePlaybackRates: [Float] = [0.75, 1, 1.25, 1.5, 2]

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
    private var connectedFileFormat: AVAudioFormat?
    private var playbackTimerTask: Task<Void, Never>?
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
            sampleRate = file.fileFormat.sampleRate
            duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            currentTime = 0
            isLoaded = true
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
        currentItem = nil
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
                self.currentTime = playbackTime
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
        ZStack {
            Color(red: 0.018, green: 0.020, blue: 0.022)

            RetroDotMatrixGrid()
                .accessibilityHidden(true)

            VStack(spacing: 8) {
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

                    VStack(spacing: 8) {
                        RetroPixelWaveform(
                            samples: waveformSamples,
                            progress: playbackProgress(for: currentTime),
                            playheadColor: displayRed,
                            isActive: player.isPlaying
                        )
                        .frame(height: 106)
                        .accessibilityHidden(true)

                        RetroDotMatrixTime(
                            text: Self.displayTimestamp(currentTime),
                            accessibilityText: "\(TranscriptionLine.formatTimestamp(currentTime)) / \(TranscriptionLine.formatTimestamp(effectiveDuration))"
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(Color.black.opacity(0.88), lineWidth: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .padding(3)
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
    static let gridPitch: CGFloat = 4.6
    static let backgroundDotSize: CGFloat = 2.15
    static let activeDotSize: CGFloat = 2.7
}

private struct RetroDotMatrixGrid: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let pitch = RetroDisplayMetrics.gridPitch
            let dotSize = RetroDisplayMetrics.backgroundDotSize
            var y: CGFloat = 1.4

            while y < size.height {
                var x: CGFloat = 1.4
                while x < size.width {
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 0.45),
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
    let text: String
    let accessibilityText: String

    private static let glyphRows: [Character: [String]] = [
        "0": ["0111110", "1100011", "1000001", "1000001", "1000001", "1000001", "1000001", "1000001", "1000001", "1100011", "0111110"],
        "1": ["0011000", "0111000", "1011000", "0011000", "0011000", "0011000", "0011000", "0011000", "0011000", "0011000", "1111111"],
        "2": ["0111110", "1100011", "0000001", "0000001", "0000010", "0001100", "0110000", "1000000", "1000000", "1000000", "1111111"],
        "3": ["1111110", "0000011", "0000001", "0000001", "0000010", "0011110", "0000010", "0000001", "0000001", "1100011", "0111110"],
        "4": ["0000110", "0001110", "0010110", "0100110", "1000110", "1000110", "1111111", "0000110", "0000110", "0000110", "0000110"],
        "5": ["1111111", "1000000", "1000000", "1000000", "1111110", "0000011", "0000001", "0000001", "0000001", "1100011", "0111110"],
        "6": ["0011110", "0110000", "1100000", "1000000", "1111110", "1100011", "1000001", "1000001", "1000001", "1100011", "0111110"],
        "7": ["1111111", "0000011", "0000010", "0000100", "0001000", "0010000", "0010000", "0100000", "0100000", "1000000", "1000000"],
        "8": ["0111110", "1100011", "1000001", "1000001", "1100011", "0111110", "1100011", "1000001", "1000001", "1100011", "0111110"],
        "9": ["0111110", "1100011", "1000001", "1000001", "1100011", "0111111", "0000001", "0000001", "0000011", "0000110", "0111100"],
        ":": ["00", "00", "11", "11", "00", "00", "00", "11", "11", "00", "00"]
    ]

    var body: some View {
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

            let horizontalPitch = max((size.width - 4) / CGFloat(totalColumns), 1)
            let verticalPitch = max((size.height - 2) / CGFloat(rowCount), 1)
            let pitch = min(horizontalPitch, verticalPitch)
            let dotSize = max(pitch * 0.66, 1.35)
            let contentWidth = CGFloat(totalColumns - 1) * pitch + dotSize
            let contentHeight = CGFloat(rowCount - 1) * pitch + dotSize
            let originX = (size.width - contentWidth) / 2
            let originY = (size.height - contentHeight) / 2
            var glyphColumn = 0

            for (glyphIndex, rows) in glyphs.enumerated() {
                let width = glyphWidths[glyphIndex]

                for (row, pattern) in rows.enumerated() {
                    for (column, value) in pattern.enumerated() where value == "1" {
                        let rect = CGRect(
                            x: originX + CGFloat(glyphColumn + column) * pitch,
                            y: originY + CGFloat(row) * pitch,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: dotSize * 0.12),
                            with: .color(Color.white.opacity(0.96))
                        )
                    }
                }

                glyphColumn += width + 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }
}


struct RetroPixelWaveform: View {
    let samples: [CGFloat]
    let progress: CGFloat
    let playheadColor: Color
    let isActive: Bool

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let centerY = size.height / 2
            let pitch = RetroDisplayMetrics.gridPitch
            let pixelSize = RetroDisplayMetrics.activeDotSize
            let maximumHalfRows = max(Int((size.height / 2 - pitch) / pitch), 1)
            let drawableWidth = max(size.width - pixelSize, 0)
            let columnCount = max(Int((drawableWidth / pitch).rounded(.down)) + 1, 2)
            let columnPitch = drawableWidth / CGFloat(columnCount - 1)
            let rawPlayheadX = min(max(progress, 0), 1) * size.width
            let lineX = min(
                max(rawPlayheadX, pixelSize / 2),
                max(size.width - pixelSize / 2, pixelSize / 2)
            )

            for index in 0..<columnCount {
                let x = pixelSize / 2 + CGFloat(index) * columnPitch
                let sample = interpolatedSample(at: index, columnCount: columnCount)
                let halfRows = max(
                    Int((min(max(sample, 0), 1) * CGFloat(maximumHalfRows)).rounded()),
                    0
                )
                let waveformOpacity = x <= rawPlayheadX ? 0.94 : 0.34

                for row in -halfRows...halfRows {
                    let y = centerY + CGFloat(row) * pitch
                    let rect = CGRect(
                        x: x - pixelSize / 2,
                        y: y - pixelSize / 2,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                        with: .color(Color.white.opacity(waveformOpacity))
                    )
                }
            }

            var playheadY = pixelSize / 2 + pitch * 2
            while playheadY <= size.height - pixelSize / 2 {
                let rect = CGRect(
                    x: lineX - pixelSize / 2,
                    y: playheadY - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                    with: .color(playheadColor.opacity(isActive ? 1 : 0.74))
                )
                playheadY += pitch
            }

            for row in 0..<2 {
                for column in 0..<2 {
                    let horizontalOffset = (CGFloat(column) - 0.5) * pitch
                    let center = CGPoint(
                        x: rawPlayheadX + horizontalOffset,
                        y: pixelSize / 2 + CGFloat(row) * pitch
                    )
                    let rect = CGRect(
                        x: center.x - pixelSize / 2,
                        y: center.y - pixelSize / 2,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                        with: .color(playheadColor.opacity(isActive ? 1 : 0.74))
                    )
                }
            }
        }
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
