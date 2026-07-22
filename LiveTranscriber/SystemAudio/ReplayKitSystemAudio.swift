import AVFoundation
import Foundation
import ReplayKit
import SwiftUI

struct ReplayKitBroadcastPicker: UIViewRepresentable {
    static let extensionBundleIdentifier = "com.iamwilliamli.LiveTranscriber.BroadcastUpload"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.tintColor = UIColor(AppTheme.brand)
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.tintColor = UIColor(AppTheme.brand)
    }
}

final class ReplayKitSystemAudioSource: SystemAudioSource, @unchecked Sendable {
    let backend: SystemAudioBackend = .replayKitCompatibility
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)?
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)?

    private let consumer: SharedAudioChunkConsumer

    init(directory: SharedAudioChunkDirectory? = nil) throws {
        consumer = SharedAudioChunkConsumer(directory: try directory ?? SharedAudioChunkDirectory())
    }

    func start() async throws {
        consumer.frameHandler = { [weak self] frame in
            self?.frameHandler?(frame)
        }
        consumer.eventHandler = { [weak self] event in
            self?.eventHandler?(event)
        }
        try consumer.start()
        eventHandler?(.awaitingUserApproval)
    }

    func stop() async {
        consumer.stop()
    }
}

final class SharedAudioChunkConsumer: @unchecked Sendable {
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)?
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)?

    private let directory: SharedAudioChunkDirectory
    private let queue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.screen-audio-consumer",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var activeSessionID: UUID?
    private var lastState: SharedAudioTransportState?
    private var expectedSequence: UInt64?
    private var consumedFrameCount: UInt64 = 0
    private var diagnostics = SystemAudioDiagnostics()
    private var isRunning = false
    private var didEmitFinished = false

    init(directory: SharedAudioChunkDirectory) {
        self.directory = directory
    }

    func start() throws {
        try directory.prepare()
        try directory.cleanupExpiredSessions()
        queue.sync {
            guard !isRunning else { return }
            isRunning = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            isRunning = false
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
        }
    }

    private func poll() {
        guard isRunning else { return }

        let metadata: SharedAudioSessionMetadata
        do {
            guard let loadedMetadata = try directory.loadActiveMetadata() else {
                return
            }
            metadata = loadedMetadata
        } catch {
            recordError(error.localizedDescription, corruptedChunk: false)
            return
        }

        if activeSessionID != metadata.sessionID {
            activeSessionID = metadata.sessionID
            lastState = nil
            expectedSequence = nil
            consumedFrameCount = 0
            diagnostics = SystemAudioDiagnostics()
            didEmitFinished = false
            eventHandler?(.started)
        }

        eventHandler?(.heartbeat(metadata.heartbeat))
        diagnostics.overruns = metadata.overrunCount
        diagnostics.droppedFrames = max(diagnostics.droppedFrames, metadata.droppedChunkCount)
        emitStateChangeIfNeeded(metadata)
        consumeReadyChunks(sessionID: metadata.sessionID)

        if metadata.state == .finished,
           (try? directory.readyChunkURLs(sessionID: metadata.sessionID).isEmpty) == true,
           !didEmitFinished {
            didEmitFinished = true
            eventHandler?(.diagnostics(diagnostics))
            eventHandler?(.finished)
            try? directory.removeSession(metadata.sessionID)
        }
    }

    private func emitStateChangeIfNeeded(_ metadata: SharedAudioSessionMetadata) {
        guard metadata.state != lastState else { return }
        lastState = metadata.state
        switch metadata.state {
        case .waitingForAudio:
            eventHandler?(.waitingForAudio)
        case .capturing:
            eventHandler?(.resumed)
        case .paused:
            eventHandler?(.paused)
        case .finished:
            break
        case .failed:
            eventHandler?(.failed(metadata.errorMessage ?? String(localized: L10n.ScreenAudio.captureFailed)))
        }
    }

    private func consumeReadyChunks(sessionID: UUID) {
        let urls: [URL]
        do {
            urls = try directory.readyChunkURLs(sessionID: sessionID)
        } catch {
            recordError(error.localizedDescription, corruptedChunk: false)
            return
        }

        for url in urls {
            guard isRunning else { return }
            guard let sequence = SharedAudioChunkDirectory.sequence(from: url) else {
                diagnostics.corruptedChunks &+= 1
                try? directory.removeChunk(at: url)
                continue
            }

            if let expectedSequence, sequence > expectedSequence {
                diagnostics.droppedFrames &+= sequence - expectedSequence
            }

            do {
                let data = try directory.readChunk(at: url)
                let buffer = try SystemAudioPCMNormalizer.buffer(from: data)
                let presentationTime = Double(consumedFrameCount)
                    / Double(SharedAudioChunkConstants.sampleRate)
                let frame = SystemAudioPCMFrame(
                    buffer: buffer,
                    sequence: sequence,
                    presentationTime: presentationTime
                )
                frameHandler?(frame)
                consumedFrameCount &+= UInt64(buffer.frameLength)
                expectedSequence = sequence &+ 1
                try directory.removeChunk(at: url)
            } catch {
                recordError(error.localizedDescription, corruptedChunk: true)
                try? directory.removeChunk(at: url)
                expectedSequence = sequence &+ 1
            }
        }

        eventHandler?(.diagnostics(diagnostics))
    }

    private func recordError(_ message: String, corruptedChunk: Bool) {
        diagnostics.lastError = message
        if corruptedChunk {
            diagnostics.corruptedChunks &+= 1
        }
        eventHandler?(.diagnostics(diagnostics))
    }
}
