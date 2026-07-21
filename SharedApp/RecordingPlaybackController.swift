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
    private static let logger = Logger(subsystem: "com.reddownloader.LiveTranscriber", category: "RecordingPlayback")
    static let availablePlaybackRates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private let audioSessionOwner = UUID()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchUnit: AVAudioUnitTimePitch?
    private var gainUnit: AVAudioUnitEQ?
    private var audioFile: AVAudioFile?
    private var playbackTimerTask: Task<Void, Never>?
    private var sampleRate: Double = 44_100
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackScheduleID = 0
    private var playbackCommandID = 0
    private var hasScheduledPlayback = false
    private var needsPlaybackReschedule = true
    private var nowPlayingTranscriptRecordingID: UUID?
    private var nowPlayingTranscriptCues: [NowPlayingTranscriptCue] = []
    private var lastPublishedNowPlayingTitle: String?
    private var remoteCommandTargets: [RemoteCommandTarget] = []
    private var isReceivingRemoteControlEvents = false

    init() {
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

        load(url: url)
        currentItem = item
        updateNowPlayingInfo()
        updateRemoteCommandAvailability(isEnabled: isLoaded)
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

    func load(url: URL) {
        unload()
        errorText = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorText = localized(L10n.Recordings.recordingFileMissing)
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            try configurePlaybackEngine(format: file.processingFormat)
            currentTime = 0
            isLoaded = true
            updateNowPlayingInfo()
            updateRemoteCommandAvailability(isEnabled: true)
        } catch {
            errorText = localizedFormat(L10n.Recordings.playbackFailedFormat, error.localizedDescription)
            updateRemoteCommandAvailability(isEnabled: false)
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
        guard isLoaded, let playerNode else {
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
                try await configurePlaybackSession()
                guard commandID == playbackCommandID, isLoaded else {
                    await deactivatePlaybackSession()
                    return
                }

                beginReceivingRemoteControlEventsIfNeeded()
                try startPlaybackEngineIfNeeded()
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                if currentTime >= duration {
                    currentTime = 0
                    needsPlaybackReschedule = true
                }
                if !hasScheduledPlayback || needsPlaybackReschedule {
                    schedulePlayback(from: currentTime)
                }
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                playerNode.play()
                isPlaying = true
                startTimer()
                updateNowPlayingInfo()
            } catch {
                errorText = localizedFormat(L10n.Recordings.playbackStartFailedFormat, error.localizedDescription)
            }
        }
    }

    func pause() {
        playbackCommandID += 1
        let pausedTime = currentPlaybackTime()
        isPlaying = false
        playerNode?.pause()
        audioEngine?.pause()
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
            schedulePlayback(from: clampedTime)
            if commandID == playbackCommandID {
                playerNode?.play()
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
        timePitchUnit?.rate = clampedRate
        updateNowPlayingInfo()
    }

    func presentationTime() -> TimeInterval {
        min(max(currentPlaybackTime(), 0), duration)
    }

    func unload() {
        playbackCommandID += 1
        playbackScheduleID += 1
        playerNode?.stop()
        playerNode?.reset()
        audioEngine?.stop()
        playerNode = nil
        timePitchUnit = nil
        gainUnit = nil
        audioEngine = nil
        audioFile = nil
        currentItem = nil
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        nowPlayingTranscriptRecordingID = nil
        nowPlayingTranscriptCues = []
        lastPublishedNowPlayingTitle = nil
        isLoaded = false
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimer()
        clearNowPlayingInfo()
        updateRemoteCommandAvailability(isEnabled: false)
        endReceivingRemoteControlEventsIfNeeded()
        Task {
            await deactivatePlaybackSession()
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

    private func configurePlaybackEngine(format: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = playbackRate
        let equalizer = AVAudioUnitEQ(numberOfBands: 1)
        if let band = equalizer.bands.first {
            band.filterType = .parametric
            band.frequency = 1_000
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        equalizer.globalGain = Self.playbackGainDecibels

        engine.attach(node)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        engine.prepare()

        audioEngine = engine
        playerNode = node
        timePitchUnit = timePitch
        gainUnit = equalizer
    }

    private func startPlaybackEngineIfNeeded() throws {
        guard let audioEngine, !audioEngine.isRunning else {
            return
        }
        try audioEngine.start()
    }

    private func schedulePlayback(from time: TimeInterval) {
        guard let audioFile, let playerNode else {
            return
        }

        playbackScheduleID += 1
        let completionID = playbackScheduleID
        playerNode.stop()
        hasScheduledPlayback = false

        let startFrame = framePosition(for: time)
        let remainingFrames = max(audioFile.length - startFrame, 0)
        guard remainingFrames > 0 else {
            finishPlayback()
            return
        }

        scheduledStartFrame = startFrame
        currentTime = Double(startFrame) / sampleRate
        needsPlaybackReschedule = false
        hasScheduledPlayback = true
        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(AVAudioFrameCount.max)))
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] callbackType in
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
              sampleRate > 0,
              let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTime
        }

        let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
        let frame = min(max(scheduledStartFrame + playedFrames, 0), audioFile?.length ?? scheduledStartFrame)
        return min(Double(frame) / sampleRate, duration)
    }

    private func finishPlayback() {
        playbackCommandID += 1
        playbackScheduleID += 1
        playerNode?.stop()
        playerNode?.reset()
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        currentTime = duration
        isPlaying = false
        stopTimer()
        updateNowPlayingInfo()
        Task {
            await deactivatePlaybackSession()
        }
    }

    private func configurePlaybackSession() async throws {
        try await AppAudioSessionCoordinator.shared.activatePlayback(owner: audioSessionOwner)
    }

    private func deactivatePlaybackSession() async {
        await AppAudioSessionCoordinator.shared.deactivatePlayback(owner: audioSessionOwner)
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

private struct NowPlayingTranscriptCue {
    let startTime: TimeInterval
    let text: String
}

private struct RemoteCommandTarget {
    let command: MPRemoteCommand
    let token: Any
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

    private func playbackProgress(for currentTime: TimeInterval) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        return CGFloat(min(max(currentTime / duration, 0), 1))
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
                        duration
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
                            accessibilityText: "\(TranscriptionLine.formatTimestamp(currentTime)) / \(TranscriptionLine.formatTimestamp(duration))"
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
