import AVFoundation
import CoreMedia
import Foundation

final class SharedAudioChunkProducer: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.broadcast-audio-producer",
        qos: .userInitiated
    )
    private let directory: SharedAudioChunkDirectory
    private let normalizer = SystemAudioPCMNormalizer()

    private var metadata: SharedAudioSessionMetadata?
    private var nextSequence: UInt64 = 0
    private var didReceiveAudio = false

    init(directory: SharedAudioChunkDirectory? = nil) throws {
        self.directory = try directory ?? SharedAudioChunkDirectory()
    }

    func start() throws {
        try queue.sync {
            try directory.cleanupExpiredSessions()
            metadata = try directory.beginSession()
            nextSequence = 0
            didReceiveAudio = false
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.appendOnQueue(sampleBuffer)
        }
    }

    func pause() {
        updateState(.paused)
    }

    func resume() {
        updateState(didReceiveAudio ? .capturing : .waitingForAudio)
    }

    func finish() {
        updateState(.finished)
    }

    func fail(_ error: Error) {
        queue.sync {
            guard var metadata else { return }
            metadata.state = .failed
            metadata.errorMessage = error.localizedDescription
            metadata.heartbeat = Date()
            try? directory.writeMetadata(metadata)
            self.metadata = metadata
        }
    }

    private func appendOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard var metadata else { return }

        do {
            let normalizedBuffer = try normalizer.normalize(sampleBuffer)
            let data = try SystemAudioPCMNormalizer.data(from: normalizedBuffer)
            let sequence = nextSequence
            let committed = try directory.commitChunk(
                data,
                sessionID: metadata.sessionID,
                sequence: sequence
            )
            if committed {
                nextSequence &+= 1
                didReceiveAudio = true
                metadata.state = .capturing
                metadata.latestSequence = sequence
            } else {
                metadata.overrunCount &+= 1
                metadata.droppedChunkCount &+= 1
            }
            metadata.heartbeat = Date()
            try directory.writeMetadata(metadata)
            self.metadata = metadata
        } catch {
            metadata.droppedChunkCount &+= 1
            metadata.errorMessage = error.localizedDescription
            metadata.heartbeat = Date()
            try? directory.writeMetadata(metadata)
            self.metadata = metadata
        }
    }

    private func updateState(_ state: SharedAudioTransportState) {
        queue.sync {
            guard var metadata else { return }
            metadata.state = state
            metadata.heartbeat = Date()
            try? directory.writeMetadata(metadata)
            self.metadata = metadata
        }
    }
}
