import AVFoundation
import Combine
import Foundation
import TranscriberCore
import TranscriberDomain

@MainActor
final class MacRecordingPlayer: ObservableObject {
    @Published private(set) var currentSessionID: RecordingSession.ID?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?

    private var player: AVPlayer?
    private var periodicTimeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?

    deinit {
        if let periodicTimeObserver {
            player?.removeTimeObserver(periodicTimeObserver)
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
        }
    }

    func toggle(
        session: RecordingSession,
        library: any RecordingLibraryReading
    ) async {
        if currentSessionID == session.id, player != nil {
            if isPlaying {
                pause()
            } else {
                play()
            }
            return
        }

        await loadAndPlay(session: session, library: library)
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func play() {
        guard let player else {
            return
        }
        if duration > 0, currentTime >= duration - 0.05 {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.play()
        isPlaying = true
    }

    func seek(to seconds: Double) {
        guard let player else {
            return
        }
        let clampedTime = min(max(seconds, 0), max(duration, 0))
        player.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = clampedTime
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        currentTime = 0
        isPlaying = false
    }

    private func loadAndPlay(
        session: RecordingSession,
        library: any RecordingLibraryReading
    ) async {
        guard let asset = preferredPlaybackAsset(in: session) else {
            errorMessage = "This recording has no playable audio or video asset."
            return
        }

        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        do {
            let url = try await library.recordingAssetURL(
                sessionID: session.id,
                assetID: asset.id
            )
            let playerItem = AVPlayerItem(url: url)
            replacePlayer(with: AVPlayer(playerItem: playerItem), item: playerItem)
            currentSessionID = session.id
            currentTime = 0
            duration = max(session.durationSeconds, 0)

            if let loadedDuration = try? await playerItem.asset.load(.duration),
               loadedDuration.isNumeric {
                duration = max(loadedDuration.seconds, 0)
            }
            play()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
            isPlaying = false
        }
    }

    private func preferredPlaybackAsset(in session: RecordingSession) -> RecordingAsset? {
        if let primaryAsset = session.primaryAsset,
           primaryAsset.kind.isAudio || primaryAsset.kind.isVideo {
            return primaryAsset
        }
        return session.assets.first(where: { $0.kind.isAudio })
            ?? session.assets.first(where: { $0.kind.isVideo })
    }

    private func replacePlayer(with newPlayer: AVPlayer, item: AVPlayerItem) {
        if let periodicTimeObserver {
            player?.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        player?.pause()
        player = newPlayer
        periodicTimeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = max(time.seconds, 0)
        }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.currentTime = self?.duration ?? 0
        }
    }
}
